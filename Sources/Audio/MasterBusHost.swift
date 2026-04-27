import AVFoundation
import Foundation

protocol MasterBusHosting: AnyObject {
    var appliedState: MasterBusState { get }
    var resolvedState: MasterBusState { get }
    var performanceOverlayState: MasterBusPerformanceOverlayState { get }
    var applyCallCount: Int { get }
    func attach(to audioGraph: MainAudioGraph)
    func apply(_ state: MasterBusState)
    func setPerformanceOverlay(_ overlay: MasterBusPerformanceOverlayState)
    func setSceneMacroOverride(sceneID: UUID, macroID: UUID, value: Double)
    func clearSceneMacroOverrides(sceneID: UUID)
    func setLiveCrossfaderOverride(_ value: Double?)
    func clearPerformanceOverlay()
}

final class MasterBusHost: MasterBusHosting {
    private let lock = NSLock()
    private let factory: AUAudioUnitFactory
    private var state: MasterBusState = .default
    private var performanceOverlay: MasterBusPerformanceOverlayState = MasterBusPerformanceOverlayState()
    private var count: Int = 0
    private weak var audioGraph: MainAudioGraph?
    private var cachedAUEffects: [UUID: CachedAUEffect] = [:]
    private var pendingAUEffectIDs: Set<UUID> = []
    private var installedShape: MasterBusGraphShape?
    private var installedNodesByInsertID: [UUID: AVAudioNode] = [:]

    private struct CachedAUEffect {
        let componentID: AudioComponentID
        let stateBlob: Data?
        let unit: AVAudioUnit
    }

    private struct MasterBusGraphShape: Equatable {
        let branches: [MasterBusBranchShape]
    }

    private struct MasterBusBranchShape: Equatable {
        let sceneID: UUID
        let inserts: [MasterBusInsertShape]
    }

    private struct MasterBusInsertShape: Equatable {
        let id: UUID
        let kind: MasterBusInsertKindShape
    }

    private enum MasterBusInsertKindShape: Equatable {
        case nativeFilter
        case nativeBitcrusher
        case auEffect(componentID: AudioComponentID, stateBlob: Data?)
    }

    private struct BuiltMasterChains {
        let chains: [MainAudioGraph.MasterChain]
        let nodesByInsertID: [UUID: AVAudioNode]
        let shape: MasterBusGraphShape
    }

    private struct MasterBusBranch {
        let scene: MasterBusScene
        let gain: Double
    }

    init(factory: AUAudioUnitFactory = AUAudioUnitFactory()) {
        self.factory = factory
    }

    var appliedState: MasterBusState {
        lock.withLock { state }
    }

    var resolvedState: MasterBusState {
        lock.withLock { state.applyingPerformanceOverlay(performanceOverlay.normalized(for: state)) }
    }

    var performanceOverlayState: MasterBusPerformanceOverlayState {
        lock.withLock { performanceOverlay }
    }

    var applyCallCount: Int {
        lock.withLock { count }
    }

    func attach(to audioGraph: MainAudioGraph) {
        lock.withLock {
            self.audioGraph = audioGraph
        }
        rebuildAudioGraph()
    }

    func apply(_ state: MasterBusState) {
        lock.withLock {
            self.state = state.normalized()
            self.performanceOverlay = self.performanceOverlay.normalized(for: self.state)
            self.count += 1
        }
        rebuildAudioGraph()
    }

    func setPerformanceOverlay(_ overlay: MasterBusPerformanceOverlayState) {
        lock.withLock {
            self.performanceOverlay = overlay.normalized(for: state)
        }
        refreshAudioGraphForPerformanceChange()
    }

    func setSceneMacroOverride(sceneID: UUID, macroID: UUID, value: Double) {
        lock.withLock {
            performanceOverlay.setMacroOverride(sceneID: sceneID, macroID: macroID, value: value)
            performanceOverlay = performanceOverlay.normalized(for: state)
        }
        refreshAudioGraphForPerformanceChange()
    }

    func clearSceneMacroOverrides(sceneID: UUID) {
        lock.withLock {
            performanceOverlay.clearMacroOverrides(sceneID: sceneID)
        }
        refreshAudioGraphForPerformanceChange()
    }

    func setLiveCrossfaderOverride(_ value: Double?) {
        lock.withLock {
            performanceOverlay.crossfaderOverride = value?.clamped(to: 0...1)
            performanceOverlay = performanceOverlay.normalized(for: state)
        }
        refreshAudioGraphForPerformanceChange()
    }

    func clearPerformanceOverlay() {
        lock.withLock {
            performanceOverlay.clearAll()
        }
        refreshAudioGraphForPerformanceChange()
    }

    var activeScene: MasterBusScene {
        resolvedState.activeScene
    }

    var abCrossfadeGains: (a: Double, b: Double)? {
        guard let selection = resolvedState.abSelection else { return nil }
        return Self.equalPowerGains(crossfader: selection.crossfader)
    }

    static func equalPowerGains(crossfader: Double) -> (a: Double, b: Double) {
        let clamped = min(max(crossfader, 0), 1)
        return (
            a: cos(clamped * .pi / 2),
            b: sin(clamped * .pi / 2)
        )
    }

    private func rebuildAudioGraph() {
        let (state, audioGraph) = lock.withLock {
            (self.state.applyingPerformanceOverlay(self.performanceOverlay.normalized(for: self.state)), self.audioGraph)
        }
        guard let audioGraph else { return }

        performOnMain {
            let built = self.buildMasterChains(for: state)
            audioGraph.installMasterChains(built.chains)
            self.lock.withLock {
                self.installedShape = built.shape
                self.installedNodesByInsertID = built.nodesByInsertID
            }
        }
    }

    @MainActor
    private func buildMasterChains(for state: MasterBusState) -> BuiltMasterChains {
        var nodesByInsertID: [UUID: AVAudioNode] = [:]
        let branches = Self.branches(for: state)
        let chains = branches.map { branch in
            chain(for: branch.scene, gain: branch.gain, nodesByInsertID: &nodesByInsertID)
        }
        return BuiltMasterChains(
            chains: chains,
            nodesByInsertID: nodesByInsertID,
            shape: Self.graphShape(for: state)
        )
    }

    @MainActor
    private func chain(
        for scene: MasterBusScene,
        gain: Double,
        nodesByInsertID: inout [UUID: AVAudioNode]
    ) -> MainAudioGraph.MasterChain {
        let nodes = scene.inserts.compactMap { insert -> AVAudioNode? in
            guard insert.isEnabled else { return nil }
            let node = node(for: insert)
            if let node {
                nodesByInsertID[insert.id] = node
            }
            return node
        }
        return MainAudioGraph.MasterChain(nodes: nodes, gain: gain)
    }

    @MainActor
    private func node(for insert: MasterBusInsert) -> AVAudioNode? {
        switch insert.kind {
        case let .nativeFilter(settings):
            return makeFilterNode(settings: settings, wetDry: insert.wetDry)
        case let .nativeBitcrusher(settings):
            return makeLoFiNode(settings: settings, wetDry: insert.wetDry)
        case let .auEffect(componentID, stateBlob):
            return cachedAUEffectNode(insertID: insert.id, componentID: componentID, stateBlob: stateBlob)
        }
    }

    @MainActor
    private func makeFilterNode(settings: MasterFilterSettings, wetDry: Double) -> AVAudioNode {
        let eq = AVAudioUnitEQ(numberOfBands: 1)
        configureFilterNode(eq, settings: settings, wetDry: wetDry)
        return eq
    }

    @MainActor
    private func configureFilterNode(_ eq: AVAudioUnitEQ, settings: MasterFilterSettings, wetDry: Double) {
        let normalized = settings.normalized()
        let band = eq.bands[0]
        band.bypass = wetDry <= 0
        band.filterType = normalized.mode == .lowPass ? .lowPass : .highPass
        band.frequency = Float(normalized.cutoffHz)
        band.bandwidth = Float(2 - (normalized.resonance * 1.9))
    }

    @MainActor
    private func makeLoFiNode(settings: MasterBitcrusherSettings, wetDry: Double) -> AVAudioNode {
        let distortion = AVAudioUnitDistortion()
        configureLoFiNode(distortion, settings: settings, wetDry: wetDry)
        return distortion
    }

    @MainActor
    private func configureLoFiNode(_ distortion: AVAudioUnitDistortion, settings: MasterBitcrusherSettings, wetDry: Double) {
        let normalized = settings.normalized()
        let crushAmount = ((16 - Double(normalized.bitDepth)) / 12 * 0.4)
            + ((1 - normalized.sampleRateScale) * 0.6)
        let preset: AVAudioUnitDistortionPreset
        switch crushAmount {
        case ..<0.25:
            preset = .multiDecimated1
        case ..<0.5:
            preset = .multiDecimated2
        case ..<0.75:
            preset = .multiDecimated3
        default:
            preset = .multiDecimated4
        }
        distortion.loadFactoryPreset(preset)
        distortion.wetDryMix = Float(wetDry.clamped(to: 0...1) * 100)
        distortion.preGain = Float(normalized.drive * 36)
    }

    private func refreshAudioGraphForPerformanceChange() {
        let (state, audioGraph, installedShape, nodesByInsertID) = lock.withLock {
            (
                self.state.applyingPerformanceOverlay(self.performanceOverlay.normalized(for: self.state)),
                self.audioGraph,
                self.installedShape,
                self.installedNodesByInsertID
            )
        }

        guard let audioGraph else { return }
        let nextShape = Self.graphShape(for: state)
        guard installedShape == nextShape else {
            rebuildAudioGraph()
            return
        }

        performOnMain {
            let branches = Self.branches(for: state)
            audioGraph.setMasterBranchGains(branches.map(\.gain))
            for branch in branches {
                for insert in branch.scene.inserts where insert.isEnabled {
                    guard let node = nodesByInsertID[insert.id] else { continue }
                    self.configureExistingNode(node, for: insert)
                }
            }
        }
    }

    @MainActor
    private func configureExistingNode(_ node: AVAudioNode, for insert: MasterBusInsert) {
        switch (node, insert.kind) {
        case let (eq as AVAudioUnitEQ, .nativeFilter(settings)):
            configureFilterNode(eq, settings: settings, wetDry: insert.wetDry)
        case let (distortion as AVAudioUnitDistortion, .nativeBitcrusher(settings)):
            configureLoFiNode(distortion, settings: settings, wetDry: insert.wetDry)
        default:
            return
        }
    }

    private static func branches(for state: MasterBusState) -> [MasterBusBranch] {
        if let selection = state.abSelection,
           let sceneA = state.scene(id: selection.sceneAID),
           let sceneB = state.scene(id: selection.sceneBID)
        {
            let gains = equalPowerGains(crossfader: selection.crossfader)
            return [
                MasterBusBranch(scene: sceneA, gain: gains.a),
                MasterBusBranch(scene: sceneB, gain: gains.b),
            ]
        }
        let scene = state.activeScene
        return [MasterBusBranch(scene: scene, gain: 1)]
    }

    private static func graphShape(for state: MasterBusState) -> MasterBusGraphShape {
        MasterBusGraphShape(
            branches: branches(for: state).map { branch in
                MasterBusBranchShape(
                    sceneID: branch.scene.id,
                    inserts: branch.scene.inserts.compactMap { insert in
                        guard insert.isEnabled else { return nil }
                        return MasterBusInsertShape(id: insert.id, kind: insertKindShape(for: insert.kind))
                    }
                )
            }
        )
    }

    private static func insertKindShape(for kind: MasterBusInsertKind) -> MasterBusInsertKindShape {
        switch kind {
        case .nativeFilter:
            return .nativeFilter
        case .nativeBitcrusher:
            return .nativeBitcrusher
        case let .auEffect(componentID, stateBlob):
            return .auEffect(componentID: componentID, stateBlob: stateBlob)
        }
    }

    @MainActor
    private func cachedAUEffectNode(insertID: UUID, componentID: AudioComponentID, stateBlob: Data?) -> AVAudioNode? {
        if let cached = lock.withLock({ cachedAUEffects[insertID] }),
           cached.componentID == componentID,
           cached.stateBlob == stateBlob
        {
            return cached.unit
        }

        startLoadingAUEffect(insertID: insertID, componentID: componentID, stateBlob: stateBlob)
        return nil
    }

    private func startLoadingAUEffect(insertID: UUID, componentID: AudioComponentID, stateBlob: Data?) {
        let shouldStart = lock.withLock { () -> Bool in
            guard !pendingAUEffectIDs.contains(insertID) else { return false }
            pendingAUEffectIDs.insert(insertID)
            return true
        }
        guard shouldStart else { return }

        factory.instantiate(componentID, stateBlob: stateBlob) { [weak self] result in
            guard let self else { return }

            var shouldRebuild = false
            self.lock.withLock {
                self.pendingAUEffectIDs.remove(insertID)
                if case let .success(unit) = result {
                    self.cachedAUEffects[insertID] = CachedAUEffect(
                        componentID: componentID,
                        stateBlob: stateBlob,
                        unit: unit
                    )
                    shouldRebuild = true
                }
            }

            if shouldRebuild {
                self.rebuildAudioGraph()
            }
        }
    }

    private func performOnMain(_ work: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                work()
            }
            return
        }

        DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                work()
            }
        }
    }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
