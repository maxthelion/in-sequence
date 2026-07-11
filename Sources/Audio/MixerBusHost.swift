import AVFoundation
import Foundation

final class MixerBusHost {
    struct Readout {
        let busID: UUID
        let inputMixer: AVAudioMixerNode
        let insertNodes: [AVAudioNode]
        let outputVolume: Float
        let pan: Float
        let isEffectivelyMuted: Bool
        let terminalSourceNode: AVAudioNode?
        let terminalOutputNode: AVAudioNode?
        let topologyRebuildCount: Int
        let parameterApplyCount: Int
    }

    private struct GraphShape: Equatable {
        let inserts: [InsertShape]
    }

    private struct InsertShape: Equatable {
        let id: UUID
        let kind: InsertKindShape
    }

    private struct CachedAUEffect {
        let componentID: AudioComponentID
        let stateBlob: Data?
        let unit: AVAudioUnit
    }

    let id: UUID

    private let factory: AUAudioUnitFactory
    private weak var audioGraph: MainAudioGraph?
    private var latestBus: MixerBus?
    private var inputMixer: AVAudioMixerNode?
    private var insertNodes: [AVAudioNode] = []
    private var terminalSourceNode: AVAudioNode?
    private var terminalOutputNode: AVAudioNode?
    private var nodesByInsertID: [UUID: AVAudioNode] = [:]
    private var cachedAUEffects: [UUID: CachedAUEffect] = [:]
    private var pendingAUEffectIDs: Set<UUID> = []
    private var installedShape: GraphShape?
    private var effectiveMute = false
    private(set) var topologyRebuildCount = 0
    private(set) var parameterApplyCount = 0

    init(id: UUID, factory: AUAudioUnitFactory = AUAudioUnitFactory()) {
        self.id = id
        self.factory = factory
    }

    @MainActor
    func install(
        bus: MixerBus,
        in audioGraph: MainAudioGraph,
        effectiveMute: Bool,
        holdOutputAtSilence: Bool = false
    ) {
        latestBus = bus.normalized(fallbackName: bus.name)
        self.audioGraph = audioGraph
        let nextShape = Self.graphShape(for: bus)
        if inputMixer == nil || installedShape != nextShape {
            rebuild(
                bus: bus,
                in: audioGraph,
                effectiveMute: effectiveMute,
                holdOutputAtSilence: holdOutputAtSilence
            )
        } else {
            configureInstalledNodes(for: bus)
            applyMix(
                bus.mix,
                effectiveMute: effectiveMute,
                outputLevelOverride: holdOutputAtSilence ? 0 : nil
            )
        }
    }

    func needsTopologyChange(for bus: MixerBus) -> Bool {
        inputMixer == nil || installedShape != Self.graphShape(for: bus)
    }

    @MainActor
    func applyMix(
        _ mix: BusMixSettings,
        effectiveMute: Bool,
        outputLevelOverride: Float? = nil
    ) {
        guard let inputMixer else { return }
        let normalized = mix.normalized()
        self.effectiveMute = effectiveMute
        inputMixer.outputVolume = outputLevelOverride ?? (effectiveMute ? 0 : Float(normalized.level))
        inputMixer.pan = Float(normalized.pan)
        parameterApplyCount += 1
    }

    @MainActor
    func applyParameters(bus: MixerBus, effectiveMute: Bool) {
        let normalized = bus.normalized(fallbackName: bus.name)
        latestBus = normalized
        guard inputMixer != nil,
              installedShape == Self.graphShape(for: normalized)
        else {
            return
        }
        configureInstalledNodes(for: normalized)
        applyMix(normalized.mix, effectiveMute: effectiveMute)
    }

    @MainActor
    func prepareAUEffect(insertID: UUID) {
        guard let insert = latestBus?.inserts.first(where: { $0.id == insertID }),
              case let .auEffect(componentID, stateBlob) = insert.kind
        else { return }
        _ = cachedAUEffectNode(insertID: insertID, componentID: componentID, stateBlob: stateBlob)
    }

    @MainActor
    func currentAUEffect(insertID: UUID) -> AVAudioUnit? {
        guard let insert = latestBus?.inserts.first(where: { $0.id == insertID }),
              case let .auEffect(componentID, stateBlob) = insert.kind,
              let cached = cachedAUEffects[insertID],
              cached.componentID == componentID,
              cached.stateBlob == stateBlob
        else {
            return nil
        }
        return cached.unit
    }

    @MainActor
    func auEffectParameterReadout(insertID: UUID) -> [AUParameterDescriptor]? {
        guard let unit = currentAUEffect(insertID: insertID),
              let tree = unit.auAudioUnit.parameterTree
        else {
            return nil
        }
        return AudioInstrumentHost.parameterDescriptors(from: tree)
    }

    @MainActor
    func teardown(from audioGraph: MainAudioGraph) {
        if let inputMixer {
            audioGraph.disconnectOutput(inputMixer)
            audioGraph.detach(inputMixer)
        }
        for node in insertNodes {
            audioGraph.disconnectOutput(node)
            audioGraph.detach(node)
        }
        inputMixer = nil
        insertNodes = []
        terminalSourceNode = nil
        terminalOutputNode = nil
        nodesByInsertID = [:]
        installedShape = nil
    }

    @MainActor
    func destinationNode() -> AVAudioNode? {
        inputMixer
    }

    @MainActor
    func readout() -> Readout? {
        guard let inputMixer else { return nil }
        return Readout(
            busID: id,
            inputMixer: inputMixer,
            insertNodes: insertNodes,
            outputVolume: inputMixer.outputVolume,
            pan: inputMixer.pan,
            isEffectivelyMuted: effectiveMute,
            terminalSourceNode: terminalSourceNode,
            terminalOutputNode: terminalOutputNode,
            topologyRebuildCount: topologyRebuildCount,
            parameterApplyCount: parameterApplyCount
        )
    }

    @MainActor
    private func rebuild(
        bus: MixerBus,
        in audioGraph: MainAudioGraph,
        effectiveMute: Bool,
        holdOutputAtSilence: Bool
    ) {
        let mixer = inputMixer ?? AVAudioMixerNode()
        if inputMixer == nil {
            inputMixer = mixer
            audioGraph.attach(mixer)
        }

        audioGraph.disconnectOutput(mixer)
        for node in insertNodes {
            audioGraph.disconnectOutput(node)
            audioGraph.detach(node)
        }

        var nextNodes: [AVAudioNode] = []
        var nextNodesByInsertID: [UUID: AVAudioNode] = [:]
        for insert in bus.inserts {
            guard let node = node(for: insert) else { continue }
            if node.engine == nil {
                audioGraph.attach(node)
            }
            configure(node, for: insert)
            nextNodes.append(node)
            nextNodesByInsertID[insert.id] = node
        }

        if let first = nextNodes.first {
            audioGraph.connect(mixer, to: first)
            for (source, destination) in zip(nextNodes, nextNodes.dropFirst()) {
                audioGraph.connect(source, to: destination)
            }
            audioGraph.connect(nextNodes.last ?? first, to: audioGraph.preMasterMixer)
        } else {
            audioGraph.connect(mixer, to: audioGraph.preMasterMixer)
        }

        insertNodes = nextNodes
        terminalSourceNode = nextNodes.last ?? mixer
        terminalOutputNode = audioGraph.preMasterMixer
        nodesByInsertID = nextNodesByInsertID
        // Record the shape of what was ACTUALLY installed: an AU effect that
        // is still instantiating produced no node, so it must not be part of
        // the installed shape — otherwise the post-load reinstall compares
        // equal, takes the configure-in-place path, and the AU never wires in.
        installedShape = Self.graphShape(for: bus, includingOnly: Set(nextNodesByInsertID.keys))
        topologyRebuildCount += 1
        applyMix(
            bus.mix,
            effectiveMute: effectiveMute,
            outputLevelOverride: holdOutputAtSilence ? 0 : nil
        )
    }

    @MainActor
    private func configureInstalledNodes(for bus: MixerBus) {
        for insert in bus.inserts {
            guard let node = nodesByInsertID[insert.id] else { continue }
            configure(node, for: insert)
        }
    }

    @MainActor
    private func node(for insert: MixerBusInsert) -> AVAudioNode? {
        switch insert.kind {
        case .nativeFilter:
            return nodesByInsertID[insert.id] ?? AVAudioUnitEQ(numberOfBands: 1)
        case .nativeBitcrusher:
            return nodesByInsertID[insert.id] ?? AVAudioUnitDistortion()
        case let .auEffect(componentID, stateBlob):
            return cachedAUEffectNode(insertID: insert.id, componentID: componentID, stateBlob: stateBlob)
        }
    }

    @MainActor
    private func configure(_ node: AVAudioNode, for insert: MixerBusInsert) {
        switch (node, insert.kind) {
        case let (eq as AVAudioUnitEQ, .nativeFilter(settings)):
            configureFilterNode(eq, settings: settings, wetDry: insert.isEnabled ? insert.wetDry : 0)
        case let (distortion as AVAudioUnitDistortion, .nativeBitcrusher(settings)):
            configureLoFiNode(distortion, settings: settings, wetDry: insert.isEnabled ? insert.wetDry : 0)
        case let (unit as AVAudioUnit, .auEffect):
            unit.auAudioUnit.shouldBypassEffect = !insert.isEnabled
        default:
            return
        }
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

    @MainActor
    private func cachedAUEffectNode(insertID: UUID, componentID: AudioComponentID, stateBlob: Data?) -> AVAudioNode? {
        if let cached = cachedAUEffects[insertID],
           cached.componentID == componentID,
           cached.stateBlob == stateBlob
        {
            return cached.unit
        }
        startLoadingAUEffect(insertID: insertID, componentID: componentID, stateBlob: stateBlob)
        return nil
    }

    private func startLoadingAUEffect(insertID: UUID, componentID: AudioComponentID, stateBlob: Data?) {
        guard !pendingAUEffectIDs.contains(insertID) else { return }
        pendingAUEffectIDs.insert(insertID)
        factory.instantiate(componentID, stateBlob: stateBlob) { [weak self] result in
            guard let self else { return }
            self.pendingAUEffectIDs.remove(insertID)
            guard case let .success(unit) = result else { return }
            self.cachedAUEffects[insertID] = CachedAUEffect(
                componentID: componentID,
                stateBlob: stateBlob,
                unit: unit
            )
            // ALWAYS re-enter the graph asynchronously. AU instantiation can
            // complete inline on the main thread, i.e. while the caller that
            // triggered this load (installMixerBuses) still holds the graph
            // lock — re-entering the install machinery inline from here is
            // the send-bus self-deadlock class (sampled live 2026-06-11).
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                MainActor.assumeIsolated {
                    guard let audioGraph = self.audioGraph, let latestBus = self.latestBus else { return }
                    audioGraph.setMixerBusParameters(
                        bus: latestBus,
                        effectiveMute: self.effectiveMute
                    )
                }
            }
        }
    }

    private static func graphShape(for bus: MixerBus, includingOnly insertIDs: Set<UUID>? = nil) -> GraphShape {
        GraphShape(
            inserts: bus.inserts.compactMap { insert in
                if let insertIDs, !insertIDs.contains(insert.id) {
                    return nil
                }
                return InsertShape(id: insert.id, kind: InsertKindShape.make(for: insert.kind))
            }
        )
    }

}

final class SendBusHost {
    struct Readout {
        let busID: SendBusID
        let inputMixer: AVAudioMixerNode
        let insertNodes: [AVAudioNode]
        let terminalSourceNode: AVAudioNode?
        let terminalOutputNode: AVAudioNode?
        let topologyRebuildCount: Int
        let parameterApplyCount: Int
    }

    private struct GraphShape: Equatable {
        let inserts: [InsertShape]
    }

    private struct InsertShape: Equatable {
        let id: UUID
        let kind: InsertKindShape
    }

    private struct CachedAUEffect {
        let componentID: AudioComponentID
        let stateBlob: Data?
        let unit: AVAudioUnit
    }

    let id: SendBusID

    private let factory: AUAudioUnitFactory
    private weak var audioGraph: MainAudioGraph?
    private(set) var appliedStateForTesting: SendBusState
    private var inputMixer: AVAudioMixerNode?
    private var insertNodes: [AVAudioNode] = []
    private var terminalSourceNode: AVAudioNode?
    private var terminalOutputNode: AVAudioNode?
    private var nodesByInsertID: [UUID: AVAudioNode] = [:]
    private var cachedAUEffects: [UUID: CachedAUEffect] = [:]
    private var pendingAUEffectIDs: Set<UUID> = []
    private var installedShape: GraphShape?
    private(set) var topologyRebuildCount = 0
    private(set) var parameterApplyCount = 0

    init(id: SendBusID, factory: AUAudioUnitFactory = AUAudioUnitFactory()) {
        self.id = id
        self.factory = factory
        self.appliedStateForTesting = SendBusState(id: id)
    }

    @MainActor
    func install(sendBus: SendBusState, in audioGraph: MainAudioGraph) {
        let normalized = sendBus.normalized(expectedID: id)
        appliedStateForTesting = normalized
        self.audioGraph = audioGraph
        if needsTopologyChange(for: normalized) {
            rebuild(sendBus: normalized, in: audioGraph)
        } else {
            configureInstalledNodes(for: normalized)
            parameterApplyCount += 1
        }
    }

    /// True when installing `sendBus` would change the node topology (as
    /// opposed to a value/parameter-only update on the already-installed
    /// shape). `installSendBuses` uses this to keep the engine running for
    /// value-only changes.
    @MainActor
    func needsTopologyChange(for sendBus: SendBusState) -> Bool {
        let normalized = sendBus.normalized(expectedID: id)
        return inputMixer == nil || installedShape != Self.graphShape(for: normalized)
    }

    @MainActor
    func destinationNode() -> AVAudioNode? {
        inputMixer
    }

    @MainActor
    func readout() -> Readout? {
        guard let inputMixer else { return nil }
        return Readout(
            busID: id,
            inputMixer: inputMixer,
            insertNodes: insertNodes,
            terminalSourceNode: terminalSourceNode,
            terminalOutputNode: terminalOutputNode,
            topologyRebuildCount: topologyRebuildCount,
            parameterApplyCount: parameterApplyCount
        )
    }

    @MainActor
    private func rebuild(sendBus: SendBusState, in audioGraph: MainAudioGraph) {
        let mixer = inputMixer ?? AVAudioMixerNode()
        if inputMixer == nil {
            inputMixer = mixer
            audioGraph.attach(mixer)
        }

        audioGraph.disconnectOutput(mixer)
        for node in insertNodes {
            audioGraph.disconnectOutput(node)
            audioGraph.detach(node)
        }

        var nextNodes: [AVAudioNode] = []
        var nextNodesByInsertID: [UUID: AVAudioNode] = [:]
        for insert in sendBus.inserts {
            guard let node = node(for: insert) else { continue }
            if node.engine == nil {
                audioGraph.attach(node)
            }
            configure(node, for: insert)
            nextNodes.append(node)
            nextNodesByInsertID[insert.id] = node
        }

        let returnDestination = audioGraph.sendReturnDestinationForTesting
        if let first = nextNodes.first {
            audioGraph.connect(mixer, to: first)
            for (source, destination) in zip(nextNodes, nextNodes.dropFirst()) {
                audioGraph.connect(source, to: destination)
            }
            audioGraph.connect(nextNodes.last ?? first, to: returnDestination)
        } else {
            audioGraph.connect(mixer, to: returnDestination)
        }

        insertNodes = nextNodes
        terminalSourceNode = nextNodes.last ?? mixer
        terminalOutputNode = returnDestination
        nodesByInsertID = nextNodesByInsertID
        // Record the shape of what was ACTUALLY installed: an AU effect that
        // is still instantiating produced no node, so it must not be part of
        // the installed shape — otherwise the post-load reinstall compares
        // equal, takes the configure-in-place path, and the AU never wires in.
        installedShape = Self.graphShape(for: sendBus, includingOnly: Set(nextNodesByInsertID.keys))
        topologyRebuildCount += 1
        parameterApplyCount += 1
    }

    @MainActor
    private func configureInstalledNodes(for sendBus: SendBusState) {
        for insert in sendBus.inserts {
            guard let node = nodesByInsertID[insert.id] else { continue }
            configure(node, for: insert)
        }
    }

    @MainActor
    private func node(for insert: SendBusInsert) -> AVAudioNode? {
        switch insert.kind {
        case .nativeFilter:
            return nodesByInsertID[insert.id] ?? AVAudioUnitEQ(numberOfBands: 1)
        case .nativeBitcrusher:
            return nodesByInsertID[insert.id] ?? AVAudioUnitDistortion()
        case let .auEffect(componentID, stateBlob):
            return cachedAUEffectNode(insertID: insert.id, componentID: componentID, stateBlob: stateBlob)
        }
    }

    @MainActor
    private func configure(_ node: AVAudioNode, for insert: SendBusInsert) {
        switch (node, insert.kind) {
        case let (eq as AVAudioUnitEQ, .nativeFilter(settings)):
            configureFilterNode(eq, settings: settings, wetDry: insert.isEnabled ? insert.wetDry : 0)
        case let (distortion as AVAudioUnitDistortion, .nativeBitcrusher(settings)):
            configureLoFiNode(distortion, settings: settings, wetDry: insert.isEnabled ? insert.wetDry : 0)
        case let (unit as AVAudioUnit, .auEffect):
            unit.auAudioUnit.shouldBypassEffect = !insert.isEnabled
        default:
            return
        }
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

    @MainActor
    private func cachedAUEffectNode(insertID: UUID, componentID: AudioComponentID, stateBlob: Data?) -> AVAudioNode? {
        if let cached = cachedAUEffects[insertID],
           cached.componentID == componentID,
           cached.stateBlob == stateBlob
        {
            return cached.unit
        }
        startLoadingAUEffect(insertID: insertID, componentID: componentID, stateBlob: stateBlob)
        return nil
    }

    private func startLoadingAUEffect(insertID: UUID, componentID: AudioComponentID, stateBlob: Data?) {
        guard !pendingAUEffectIDs.contains(insertID) else { return }
        pendingAUEffectIDs.insert(insertID)
        factory.instantiate(componentID, stateBlob: stateBlob) { [weak self] result in
            guard let self else { return }
            self.pendingAUEffectIDs.remove(insertID)
            guard case let .success(unit) = result else { return }
            self.cachedAUEffects[insertID] = CachedAUEffect(
                componentID: componentID,
                stateBlob: stateBlob,
                unit: unit
            )
            // ALWAYS re-enter installSendBus asynchronously. AU instantiation
            // can complete inline on the main thread — i.e. while the
            // installSendBuses frame that triggered this load still holds
            // MainAudioGraph's non-recursive graph lock. Re-entering
            // installSendBus inline from here self-deadlocks the main thread
            // on that lock (sampled live 2026-06-11: "+ Add FX" on a send
            // bus wedged the app; tick + instrument-host queues piled up
            // behind main).
            DispatchQueue.main.async { [weak self] in
                guard let self, let audioGraph = self.audioGraph else { return }
                audioGraph.installSendBus(self.appliedStateForTesting)
            }
        }
    }

    private static func graphShape(for sendBus: SendBusState, includingOnly insertIDs: Set<UUID>? = nil) -> GraphShape {
        GraphShape(
            inserts: sendBus.inserts.compactMap { insert in
                if let insertIDs, !insertIDs.contains(insert.id) {
                    return nil
                }
                return InsertShape(id: insert.id, kind: InsertKindShape.make(for: insert.kind))
            }
        )
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
