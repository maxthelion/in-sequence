import AVFoundation
import Foundation

protocol MasterBusHosting: AnyObject {
    var appliedState: MasterBusState { get }
    var applyCallCount: Int { get }
    func attach(to audioGraph: MainAudioGraph)
    func apply(_ state: MasterBusState)
}

final class MasterBusHost: MasterBusHosting {
    private let lock = NSLock()
    private let factory: AUAudioUnitFactory
    private var state: MasterBusState = .default
    private var count: Int = 0
    private weak var audioGraph: MainAudioGraph?
    private var cachedAUEffects: [UUID: CachedAUEffect] = [:]
    private var pendingAUEffectIDs: Set<UUID> = []

    private struct CachedAUEffect {
        let componentID: AudioComponentID
        let stateBlob: Data?
        let unit: AVAudioUnit
    }

    init(factory: AUAudioUnitFactory = AUAudioUnitFactory()) {
        self.factory = factory
    }

    var appliedState: MasterBusState {
        lock.withLock { state }
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
            self.count += 1
        }
        rebuildAudioGraph()
    }

    var activeScene: MasterBusScene {
        appliedState.liveScene
    }

    var abCrossfadeGains: (a: Double, b: Double)? {
        guard let selection = appliedState.abSelection else { return nil }
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
            (self.state, self.audioGraph)
        }
        guard let audioGraph else { return }

        performOnMain {
            let chains = self.chains(for: state)
            audioGraph.installMasterChains(chains)
        }
    }

    @MainActor
    private func chains(for state: MasterBusState) -> [MainAudioGraph.MasterChain] {
        let chains: [MainAudioGraph.MasterChain]
        if let selection = state.abSelection,
           let sceneA = state.scene(id: selection.sceneAID),
           let sceneB = state.scene(id: selection.sceneBID)
        {
            let gains = Self.equalPowerGains(crossfader: selection.crossfader)
            chains = [
                chain(for: sceneA, gain: sceneA.outputGain * gains.a),
                chain(for: sceneB, gain: sceneB.outputGain * gains.b),
            ]
        } else {
            let scene = state.liveScene
            chains = [chain(for: scene, gain: scene.outputGain)]
        }
        return chains
    }

    @MainActor
    private func chain(for scene: MasterBusScene, gain: Double) -> MainAudioGraph.MasterChain {
        let nodes = scene.inserts.compactMap { insert -> AVAudioNode? in
            guard insert.isEnabled, insert.wetDry > 0 else { return nil }
            return node(for: insert)
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
        let normalized = settings.normalized()
        let eq = AVAudioUnitEQ(numberOfBands: 1)
        let band = eq.bands[0]
        band.bypass = wetDry <= 0
        band.filterType = normalized.mode == .lowPass ? .lowPass : .highPass
        band.frequency = Float(normalized.cutoffHz)
        band.bandwidth = Float(2 - (normalized.resonance * 1.9))
        return eq
    }

    @MainActor
    private func makeLoFiNode(settings: MasterBitcrusherSettings, wetDry: Double) -> AVAudioNode {
        let normalized = settings.normalized()
        let distortion = AVAudioUnitDistortion()
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
        return distortion
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
