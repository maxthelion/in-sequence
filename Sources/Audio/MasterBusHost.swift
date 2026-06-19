import AVFoundation
import Foundation

extension MasterFilterSettings.Mode {
    /// Maps each filter mode to a concrete AVAudioUnitEQ filter type. Low/high
    /// pass and band pass/notch (band stop) have native DSP; Peak uses the
    /// parametric band with a resonance-driven gain bump.
    var avFilterType: AVAudioUnitEQFilterType {
        switch self {
        case .lowPass: return .lowPass
        case .highPass: return .highPass
        case .bandPass: return .bandPass
        case .notch: return .bandStop
        case .peak: return .parametric
        }
    }
}

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
    func setLiveMasterOutputGain(_ value: Double)
    func clearLiveMasterOutputGain()
    func clearPerformanceOverlay()
    func prepareAUEffect(insertID: UUID)
    func currentAUEffect(insertID: UUID) -> AVAudioUnit?
    func auEffectParameterReadout(insertID: UUID) -> [AUParameterDescriptor]?
}

final class MasterBusHost: MasterBusHosting {
    private let lock = NSLock()
    private let factory: AUAudioUnitFactory
    private let parameterObserverToken = AUParameterObserverToken(bitPattern: Int.random(in: 1...Int.max))!
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
        let masterInserts: [MasterBusInsertShape]
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
        let postBlendMasterNodes: [AVAudioNode]
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

    func setLiveMasterOutputGain(_ value: Double) {
        guard let audioGraph = lock.withLock({ self.audioGraph }) else { return }
        audioGraph.setMasterOutputGain(value)
    }

    func clearLiveMasterOutputGain() {
        let (gain, audioGraph) = lock.withLock {
            (self.state.masterOutputGain, self.audioGraph)
        }
        audioGraph?.setMasterOutputGain(gain)
    }

    func clearPerformanceOverlay() {
        lock.withLock {
            performanceOverlay.clearAll()
        }
        refreshAudioGraphForPerformanceChange()
    }

    func prepareAUEffect(insertID: UUID) {
        guard let spec = lock.withLock({ auEffectSpec(insertID: insertID, in: state) }) else {
            return
        }
        if let cached = lock.withLock({ cachedAUEffects[insertID] }),
           cached.componentID == spec.componentID,
           cached.stateBlob == spec.stateBlob
        {
            return
        }
        startLoadingAUEffect(insertID: insertID, componentID: spec.componentID, stateBlob: spec.stateBlob)
    }

    func currentAUEffect(insertID: UUID) -> AVAudioUnit? {
        lock.withLock {
            guard let spec = auEffectSpec(insertID: insertID, in: state),
                  let cached = cachedAUEffects[insertID],
                  cached.componentID == spec.componentID,
                  cached.stateBlob == spec.stateBlob
            else {
                return nil
            }
            return cached.unit
        }
    }

    func auEffectParameterReadout(insertID: UUID) -> [AUParameterDescriptor]? {
        guard let unit = currentAUEffect(insertID: insertID),
              let tree = unit.auAudioUnit.parameterTree
        else {
            return nil
        }
        return AudioInstrumentHost.parameterDescriptors(from: tree)
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
        let (state, audioGraph, installedShape) = lock.withLock {
            (
                self.state.applyingPerformanceOverlay(self.performanceOverlay.normalized(for: self.state)),
                self.audioGraph,
                self.installedShape
            )
        }
        guard let audioGraph else { return }

        let nextShape = Self.graphShape(for: state)

        // Gain and crossfade are VALUE updates — they must never reinstall
        // master chains (installMasterChains stops/starts the engine, an
        // audible dropout mid-gesture; mixer-latency cause for the master
        // fader release and the first crossfader tick).
        //
        // Fast path 1: nothing installed and nothing needs installing (no
        // enabled inserts anywhere). The default pass-through wiring already
        // carries audio; master gain rides finalOutputMixer.outputVolume and
        // a crossfade between two insert-less scenes is audibly a no-op.
        if installedShape == nil, Self.hasNoEnabledInserts(nextShape) {
            audioGraph.setMasterOutputGain(state.masterOutputGain)
            return
        }

        // Fast path 2: identical topology — update gains and node
        // parameters in place on the running engine.
        if let installedShape, installedShape == nextShape {
            let nodesByInsertID = lock.withLock { installedNodesByInsertID }
            performOnMain {
                audioGraph.setMasterOutputGain(state.masterOutputGain)
                audioGraph.setMasterBranchGains(Self.branches(for: state).map(\.gain))
                self.configureInstalledNodes(for: state, nodesByInsertID: nodesByInsertID)
            }
            return
        }

        performOnMain {
            let built = self.buildMasterChains(for: state)
            audioGraph.installMasterChains(
                built.chains,
                postBlendMasterNodes: built.postBlendMasterNodes,
                masterOutputGain: state.masterOutputGain
            )
            self.configureInstalledNodes(for: state, nodesByInsertID: built.nodesByInsertID)
            self.lock.withLock {
                self.installedShape = built.shape
                self.installedNodesByInsertID = built.nodesByInsertID
            }
        }
    }

    private static func hasNoEnabledInserts(_ shape: MasterBusGraphShape) -> Bool {
        shape.masterInserts.isEmpty && shape.branches.allSatisfy { $0.inserts.isEmpty }
    }

    @MainActor
    private func buildMasterChains(for state: MasterBusState) -> BuiltMasterChains {
        var nodesByInsertID: [UUID: AVAudioNode] = [:]
        let branches = Self.branches(for: state)
        let chains = branches.map { branch in
            chain(for: branch.scene, gain: branch.gain, nodesByInsertID: &nodesByInsertID)
        }
        let postBlendMasterNodes = masterInsertNodes(for: state.masterInserts, nodesByInsertID: &nodesByInsertID)
        return BuiltMasterChains(
            chains: chains,
            postBlendMasterNodes: postBlendMasterNodes,
            nodesByInsertID: nodesByInsertID,
            // Record only what was ACTUALLY installed: an AU effect still
            // instantiating produced no node, so it must not be part of the
            // installed shape — otherwise the post-load rebuild compares
            // shape-equal, takes the in-place path, and the AU never wires in.
            shape: Self.graphShape(for: state, includingOnly: Set(nodesByInsertID.keys))
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
                configureExistingNode(node, for: insert, in: scene)
            }
            return node
        }
        return MainAudioGraph.MasterChain(nodes: nodes, gain: gain)
    }

    @MainActor
    private func masterInsertNodes(
        for inserts: [MasterBusInsert],
        nodesByInsertID: inout [UUID: AVAudioNode]
    ) -> [AVAudioNode] {
        inserts.compactMap { insert -> AVAudioNode? in
            guard insert.isEnabled else { return nil }
            let node = node(for: insert)
            if let node {
                nodesByInsertID[insert.id] = node
                configureExistingMasterNode(node, for: insert)
            }
            return node
        }
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
        band.filterType = normalized.mode.avFilterType
        band.frequency = Float(normalized.cutoffHz)
        band.bandwidth = Float(2 - (normalized.resonance * 1.9))
        if normalized.mode == .peak {
            band.gain = Float(6 + normalized.resonance * 18)
        }
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
                    self.configureExistingNode(node, for: insert, in: branch.scene)
                }
            }
            for insert in state.masterInserts where insert.isEnabled {
                guard let node = nodesByInsertID[insert.id] else { continue }
                self.configureExistingMasterNode(node, for: insert)
            }
        }
    }

    @MainActor
    private func configureExistingNode(_ node: AVAudioNode, for insert: MasterBusInsert, in scene: MasterBusScene) {
        switch (node, insert.kind) {
        case let (eq as AVAudioUnitEQ, .nativeFilter(settings)):
            configureFilterNode(eq, settings: settings, wetDry: insert.wetDry)
        case let (distortion as AVAudioUnitDistortion, .nativeBitcrusher(settings)):
            configureLoFiNode(distortion, settings: settings, wetDry: insert.wetDry)
        case let (unit as AVAudioUnit, .auEffect):
            applyAUMacroValues(to: unit, insertID: insert.id, scene: scene)
        default:
            return
        }
    }

    @MainActor
    private func configureExistingMasterNode(_ node: AVAudioNode, for insert: MasterBusInsert) {
        switch (node, insert.kind) {
        case let (eq as AVAudioUnitEQ, .nativeFilter(settings)):
            configureFilterNode(eq, settings: settings, wetDry: insert.wetDry)
        case let (distortion as AVAudioUnitDistortion, .nativeBitcrusher(settings)):
            configureLoFiNode(distortion, settings: settings, wetDry: insert.wetDry)
        default:
            return
        }
    }

    @MainActor
    private func configureInstalledNodes(for state: MasterBusState, nodesByInsertID: [UUID: AVAudioNode]) {
        for branch in Self.branches(for: state) {
            for insert in branch.scene.inserts where insert.isEnabled {
                guard let node = nodesByInsertID[insert.id] else { continue }
                configureExistingNode(node, for: insert, in: branch.scene)
            }
        }
        for insert in state.masterInserts where insert.isEnabled {
            guard let node = nodesByInsertID[insert.id] else { continue }
            configureExistingMasterNode(node, for: insert)
        }
    }

    @MainActor
    private func applyAUMacroValues(to unit: AVAudioUnit, insertID: UUID, scene: MasterBusScene) {
        guard let tree = unit.auAudioUnit.parameterTree else { return }
        for macro in scene.macroBindings {
            guard case let .auParameter(targetInsertID, address, identifier, _, _, _, _, _) = macro.target,
                  targetInsertID == insertID,
                  let value = macro.value(in: scene)
            else {
                continue
            }
            setAUParameterValue(value, address: address, identifier: identifier, tree: tree)
        }
    }

    @MainActor
    private func setAUParameterValue(
        _ value: Double,
        address: UInt64,
        identifier: String,
        tree: AUParameterTree
    ) {
        if let param = tree.parameter(withAddress: address) {
            param.setValue(AUValue(value), originator: parameterObserverToken)
            return
        }

        if let param = tree.value(forKeyPath: identifier) as? AUParameter {
            param.setValue(AUValue(value), originator: parameterObserverToken)
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

    private static func graphShape(
        for state: MasterBusState,
        includingOnly insertIDs: Set<UUID>? = nil
    ) -> MasterBusGraphShape {
        func shape(for insert: MasterBusInsert) -> MasterBusInsertShape? {
            guard insert.isEnabled else { return nil }
            if let insertIDs, !insertIDs.contains(insert.id) {
                return nil
            }
            return MasterBusInsertShape(id: insert.id, kind: insertKindShape(for: insert.kind))
        }
        return MasterBusGraphShape(
            branches: branches(for: state).map { branch in
                MasterBusBranchShape(
                    sceneID: branch.scene.id,
                    inserts: branch.scene.inserts.compactMap(shape(for:))
                )
            },
            masterInserts: state.masterInserts.compactMap(shape(for:))
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

    private func auEffectSpec(
        insertID: UUID,
        in state: MasterBusState
    ) -> (componentID: AudioComponentID, stateBlob: Data?)? {
        if let insert = state.masterInserts.first(where: { $0.id == insertID }),
           case let .auEffect(componentID, stateBlob) = insert.kind
        {
            return (componentID, stateBlob)
        }
        for scene in state.scenes {
            guard let insert = scene.inserts.first(where: { $0.id == insertID }),
                  case let .auEffect(componentID, stateBlob) = insert.kind
            else {
                continue
            }
            return (componentID, stateBlob)
        }
        return nil
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

        TickPathMainSyncGuard.assertNotSyncingToMainFromTickPath("MasterBusHost.performOnMain")
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
