import AVFoundation
import Foundation

/// Per-track FX insert chain host.
///
/// MIRRORS `MixerBusHost` / `SendBusHost`: it owns an ordered series of insert
/// nodes (native EQ / distortion / instantiated AU effects) and configures
/// them from the document's `TrackFXInsert` chain. The difference is splice
/// geometry: a bus host always runs `inputMixer -> [inserts] -> preMaster`,
/// whereas a track insert chain is spliced between an arbitrary track output
/// `source` node and whatever dry destination + sends `reconnectTrackOutput`
/// has chosen. So this host only owns the inserts and their INTERNAL series
/// wiring (`inputNode -> ... -> terminalNode`); `MainAudioGraph` owns the two
/// boundary connections (`source -> inputNode` and `terminalNode -> dry`).
///
/// graphLock discipline: every method here is `@MainActor` and is only ever
/// called from inside `MainAudioGraph`'s `performOnMain` closures while the
/// caller holds graphLock — identical to how the bus hosts are driven. The AU
/// instantiation callback NEVER re-enters the install machinery inline; it
/// re-enters via `DispatchQueue.main.async` (the send-bus Add-FX deadlock
/// class, sampled live 2026-06-11) and calls back through a closure that hops
/// onto the graph queue itself.
final class TrackInsertChainHost {
    private struct InsertShape: Equatable {
        let id: UUID
        let kind: InsertKindShape
    }

    private struct CachedAUEffect {
        let componentID: AudioComponentID
        let stateBlob: Data?
        let unit: AVAudioUnit
    }

    let trackID: UUID

    private let factory: AUAudioUnitFactory
    /// Re-entry seam: invoked (asynchronously, on main) when an AU effect
    /// finishes instantiating so the owning graph can re-splice the chain.
    private let requestRebuild: (UUID) -> Void

    private var insertNodes: [AVAudioNode] = []
    private var nodesByInsertID: [UUID: AVAudioNode] = [:]
    private var cachedAUEffects: [UUID: CachedAUEffect] = [:]
    private var pendingAUEffectIDs: Set<UUID> = []
    private var installedShape: [InsertShape]?
    private(set) var topologyRebuildCount = 0
    private(set) var parameterApplyCount = 0

    init(
        trackID: UUID,
        factory: AUAudioUnitFactory = AUAudioUnitFactory(),
        requestRebuild: @escaping (UUID) -> Void
    ) {
        self.trackID = trackID
        self.factory = factory
        self.requestRebuild = requestRebuild
    }

    /// The first node in the chain — `source` should feed into this. Nil when
    /// the chain is empty (every insert bypassed/removed or still loading), in
    /// which case the caller routes `source` straight to its dry destination.
    var inputNode: AVAudioNode? { insertNodes.first }

    /// The last node in the chain — this feeds the dry destination + sends.
    /// Nil when the chain is empty.
    var terminalNode: AVAudioNode? { insertNodes.last }

    /// Count of insert nodes actually INSTALLED in the live graph (not the
    /// authored document array). Engine-truth for the routing-stress gate: a
    /// command that merely parsed but failed to install would leave this at the
    /// old value. AU-backed inserts only appear here once instantiated.
    var installedInsertNodeCountForTesting: Int { insertNodes.count }

    /// True when applying `inserts` would change the node topology (insert
    /// added/removed/reordered or an AU still loading) as opposed to a
    /// value/parameter-only update on the already-installed chain. The graph
    /// uses this to skip a full output rewire for value-only changes.
    @MainActor
    func needsTopologyChange(for inserts: [TrackFXInsert]) -> Bool {
        installedShape != Self.graphShape(for: inserts)
    }

    /// Build (or reconfigure) the insert nodes for `inserts`, attaching new
    /// nodes and wiring them in series. Does NOT connect the chain to `source`
    /// or any destination — the caller (`MainAudioGraph.reconnectTrackOutput`)
    /// owns the boundary connections. After this returns, `inputNode` /
    /// `terminalNode` describe the chain to splice.
    @MainActor
    func rebuild(inserts: [TrackFXInsert], in audioGraph: MainAudioGraph) {
        for node in insertNodes {
            audioGraph.disconnectOutput(node)
            audioGraph.disconnectInput(node)
        }

        var nextNodes: [AVAudioNode] = []
        var nextNodesByInsertID: [UUID: AVAudioNode] = [:]
        for insert in inserts {
            guard let node = node(for: insert) else { continue }
            if node.engine == nil {
                audioGraph.attach(node)
            }
            configure(node, for: insert)
            nextNodes.append(node)
            nextNodesByInsertID[insert.id] = node
        }

        // Tear down nodes that dropped out of the chain (removed inserts, or
        // an AU effect whose component/state changed and is reloading).
        let survivingIDs = Set(nextNodesByInsertID.keys)
        for (id, node) in nodesByInsertID where !survivingIDs.contains(id) {
            audioGraph.disconnectOutput(node)
            audioGraph.disconnectInput(node)
            audioGraph.detach(node)
            cachedAUEffects.removeValue(forKey: id)
        }

        for (source, destination) in zip(nextNodes, nextNodes.dropFirst()) {
            audioGraph.connect(source, to: destination)
        }

        insertNodes = nextNodes
        nodesByInsertID = nextNodesByInsertID
        // Record the shape of what was ACTUALLY installed: an AU effect still
        // instantiating produced no node, so it must NOT be part of the
        // installed shape — otherwise the post-load rebuild compares equal,
        // takes the configure-in-place path, and the AU never wires in (the
        // send-bus post-load class, mirrored).
        installedShape = Self.graphShape(for: inserts, includingOnly: survivingIDs)
        topologyRebuildCount += 1
        parameterApplyCount += 1
    }

    /// Configure the already-installed nodes in place (value-only update —
    /// no topology change). Mirrors the bus hosts' fast path.
    @MainActor
    func configureInstalledNodes(for inserts: [TrackFXInsert]) {
        for insert in inserts {
            guard let node = nodesByInsertID[insert.id] else { continue }
            configure(node, for: insert)
        }
        parameterApplyCount += 1
    }

    @MainActor
    func prepareAUEffect(insertID: UUID, in inserts: [TrackFXInsert]) {
        guard case let .auEffect(componentID, stateBlob) = inserts.first(where: { $0.id == insertID })?.kind
        else { return }
        _ = cachedAUEffectNode(insertID: insertID, componentID: componentID, stateBlob: stateBlob)
    }

    @MainActor
    func currentAUEffect(insertID: UUID, in inserts: [TrackFXInsert]) -> AVAudioUnit? {
        guard case let .auEffect(componentID, stateBlob) = inserts.first(where: { $0.id == insertID })?.kind,
              let cached = cachedAUEffects[insertID],
              cached.componentID == componentID,
              cached.stateBlob == stateBlob
        else {
            return nil
        }
        return cached.unit
    }

    @MainActor
    func auEffectParameterReadout(insertID: UUID, in inserts: [TrackFXInsert]) -> [AUParameterDescriptor]? {
        guard let unit = currentAUEffect(insertID: insertID, in: inserts),
              let tree = unit.auAudioUnit.parameterTree
        else {
            return nil
        }
        return AudioInstrumentHost.parameterDescriptors(from: tree)
    }

    /// Detach every node from the graph. Called when the track goes away.
    @MainActor
    func teardown(from audioGraph: MainAudioGraph) {
        for node in insertNodes {
            audioGraph.disconnectOutput(node)
            audioGraph.disconnectInput(node)
            audioGraph.detach(node)
        }
        insertNodes = []
        nodesByInsertID = [:]
        cachedAUEffects = [:]
        installedShape = nil
    }

    // MARK: - Node creation / configuration (identical mapping to bus hosts)

    @MainActor
    private func node(for insert: TrackFXInsert) -> AVAudioNode? {
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
    private func configure(_ node: AVAudioNode, for insert: TrackFXInsert) {
        // A bypassed track insert mutes its wet contribution (wetDry 0) /
        // bypasses the AU, matching how `MixerBusInsert.isEnabled` is mapped.
        let enabled = !insert.bypassed
        switch (node, insert.kind) {
        case let (eq as AVAudioUnitEQ, .nativeFilter(settings)):
            configureFilterNode(eq, settings: settings, enabled: enabled)
        case let (distortion as AVAudioUnitDistortion, .nativeBitcrusher(settings)):
            configureLoFiNode(distortion, settings: settings, enabled: enabled)
        case let (unit as AVAudioUnit, .auEffect):
            unit.auAudioUnit.shouldBypassEffect = !enabled
        default:
            return
        }
    }

    @MainActor
    private func configureFilterNode(_ eq: AVAudioUnitEQ, settings: MasterFilterSettings, enabled: Bool) {
        let normalized = settings.normalized()
        let band = eq.bands[0]
        band.bypass = !enabled
        band.filterType = normalized.mode.avFilterType
        band.frequency = Float(normalized.cutoffHz)
        band.bandwidth = Float(2 - (normalized.resonance * 1.9))
        if normalized.mode == .peak {
            band.gain = Float(6 + normalized.resonance * 18)
        }
    }

    @MainActor
    private func configureLoFiNode(_ distortion: AVAudioUnitDistortion, settings: MasterBitcrusherSettings, enabled: Bool) {
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
        distortion.wetDryMix = enabled ? 100 : 0
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
            // ALWAYS re-enter the rebuild asynchronously. AU instantiation can
            // complete inline on the main thread — i.e. while the install pass
            // that triggered this load still holds MainAudioGraph's
            // non-recursive graphLock. Re-entering the install machinery inline
            // from here is the send-bus "+ Add FX" self-deadlock class (sampled
            // live 2026-06-11). The hop and the graphLock re-acquisition both
            // happen inside `requestRebuild`'s `performOnMain` frame.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.requestRebuild(self.trackID)
            }
        }
    }

    private static func graphShape(for inserts: [TrackFXInsert], includingOnly insertIDs: Set<UUID>? = nil) -> [InsertShape] {
        inserts.compactMap { insert in
            if let insertIDs, !insertIDs.contains(insert.id) {
                return nil
            }
            return InsertShape(id: insert.id, kind: InsertKindShape.make(for: insert.kind))
        }
    }
}
