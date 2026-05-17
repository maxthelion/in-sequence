import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class SequencerDocumentSession {
    @ObservationIgnored
    private let document: Binding<SeqAIDocument>
    /// Weak reference to the owned document so the registry can perform
    /// document-identity lookup for the save pre-hook.
    @ObservationIgnored
    weak var owningDocument: SeqAIDocument?
    @ObservationIgnored
    private var flushTask: Task<Void, Never>?
    /// Set to `true` during `flushToDocumentSync()` so that
    /// `ingestExternalDocumentChange` can detect the self-originated change
    /// and skip a redundant engine apply.
    @ObservationIgnored
    private var selfOriginatedFlushInFlight: Bool = false

    /// Set to `true` while `batch(impact:changed:_:)` is running so that individual
    /// typed-session methods skip their per-call impact dispatch and let `batch`
    /// publish once at the end.
    @ObservationIgnored
    var isInBatch: Bool = false
    @ObservationIgnored
    var pendingBatchChange: SnapshotChange = .none

    let store: LiveSequencerStore
    let engineController: EngineController
    let snapshotPublisher: SessionSnapshotPublisher
    var revision: UInt64 = 0

    /// Debounce interval used for `scheduleFlushToDocument`.
    /// Injectable for tests to avoid real-time waits.
    let debounceInterval: Duration

    /// Production initializer. Creates and owns a new EngineController.
    init(
        document: Binding<SeqAIDocument>,
        debounceInterval: Duration = .milliseconds(150)
    ) {
        self.document = document
        self.owningDocument = document.wrappedValue
        self.debounceInterval = debounceInterval
        let audioGraph = MainAudioGraph()
        let audioOutputFactory = {
            AudioInstrumentHost(audioGraph: audioGraph)
        }
        self.engineController = EngineController(
            audioOutput: audioOutputFactory(),
            audioOutputFactory: audioOutputFactory,
            mainAudioGraph: audioGraph,
            sampleEngine: SamplePlaybackEngine(audioGraph: audioGraph)
        )
        let initialStore = LiveSequencerStore(project: document.wrappedValue.project)
        self.store = initialStore
        self.snapshotPublisher = SessionSnapshotPublisher(
            initial: SequencerSnapshotCompiler.compile(state: initialStore.compileInput())
        )
        self.revision = store.revision
        SequencerDocumentSessionRegistry.register(self)
    }

    /// Test-only initializer that accepts an injected EngineController.
    /// Allows unit tests to provide stub engines without requiring CoreAudio access.
    init(
        document: Binding<SeqAIDocument>,
        engineController: EngineController,
        debounceInterval: Duration = .milliseconds(150)
    ) {
        self.document = document
        self.owningDocument = document.wrappedValue
        self.debounceInterval = debounceInterval
        self.engineController = engineController
        let initialStore = LiveSequencerStore(project: document.wrappedValue.project)
        self.store = initialStore
        self.snapshotPublisher = SessionSnapshotPublisher(
            initial: SequencerSnapshotCompiler.compile(state: initialStore.compileInput())
        )
        self.revision = store.revision
        SequencerDocumentSessionRegistry.register(self)
    }

    deinit {
        let identifier = ObjectIdentifier(self)
        Task { @MainActor in
            SequencerDocumentSessionRegistry.unregister(identifier: identifier)
        }
    }

    func activate() {
        // apply(documentModel:) compiles and installs a fresh snapshot internally.
        // We also update the publisher to the same compiled value so UI visualisers
        // are in sync. We read currentPlaybackSnapshotForTesting to avoid a second
        // compile call; the cost is one stateLock read on the main thread.
        engineController.apply(documentModel: store.exportToProject())
        snapshotPublisher.replace(engineController.currentPlaybackSnapshotForTesting)
    }

    func publishSnapshot(changed change: SnapshotChange? = nil) {
        let newSnapshot: PlaybackSnapshot
        if let change {
            newSnapshot = SequencerSnapshotCompiler.compile(
                changed: change,
                previous: snapshotPublisher.snapshot,
                state: store.compileInput()
            )
        } else {
            newSnapshot = SequencerSnapshotCompiler.compile(state: store.compileInput())
        }
        engineController.apply(playbackSnapshot: newSnapshot)
        snapshotPublisher.replace(newSnapshot)
        revision = store.revision
    }

    func scheduleFlushToDocument() {
        flushTask?.cancel()
        let interval = debounceInterval
        flushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: interval)
            self?.flushToDocumentSync()
        }
    }

    /// Synchronous flush: writes the live-store state into `document.project`
    /// immediately, cancelling any pending debounce task so it cannot double-write.
    /// Called from the save pre-hook, terminate, and resign-active handlers.
    func flushToDocumentSync() {
        flushTask?.cancel()
        flushTask = nil
        let exported = store.exportToProject()
        guard document.wrappedValue.project != exported else {
            return
        }
        selfOriginatedFlushInFlight = true
        document.wrappedValue.project = exported
        selfOriginatedFlushInFlight = false
    }

    /// Async-context alias for `flushToDocumentSync()`. Kept for call sites that
    /// already name it `flushToDocument()`.
    func flushToDocument() {
        flushToDocumentSync()
    }

    func ingestExternalDocumentChange(_ project: Project) {
        // Guard: if this change was written by our own flush, skip it — applying
        // our own exported state back into the engine would be a no-op and risks
        // re-triggering a broad apply() during high-frequency editing.
        guard !selfOriginatedFlushInFlight else {
            return
        }
        guard store.replaceProject(project) else {
            return
        }
        revision = store.revision
        // apply(documentModel:) compiles and installs a fresh snapshot internally.
        // We also update the publisher so UI visualisers see the new state immediately.
        // We read currentPlaybackSnapshotForTesting to avoid a second compile call.
        engineController.apply(documentModel: store.exportToProject())
        snapshotPublisher.replace(engineController.currentPlaybackSnapshotForTesting)
    }

    /// Dispatch a scoped runtime update directly to the engine. This updates a single
    /// domain in the live engine without rebuilding the full document-model pipeline.
    func dispatchScopedRuntimeUpdate(_ update: ScopedRuntimeUpdate) {
        switch update {
        case let .filter(trackID, settings):
            engineController.sampleEngineSink.applyFilter(settings, trackID: trackID)
        case let .auState(trackID, blob):
            // The state blob is already written into the store by the mutation closure.
            // Write it into the live AU host if one exists.
            engineController.writeStateBlob(blob, for: trackID)
        case let .mix(trackID, mix):
            engineController.setMix(trackID: trackID, mix: mix)
        case let .mixerBusMix(busID, mix):
            engineController.setMixerBusMix(busID: busID, mix: mix)
        case let .sendBus(sendBus):
            engineController.apply(sendBus: sendBus)
        case let .masterBus(masterBus):
            engineController.apply(masterBus: masterBus)
        }
    }

    func setTrackMix(trackID: UUID, mix: TrackMixSettings) {
        let normalizedMix = mix.normalized()
        let changed = store.mutateTrack(id: trackID) { track in
            track.mix = normalizedMix
        }

        guard changed else {
            return
        }

        revision = store.revision
        engineController.setMix(trackID: trackID, mix: normalizedMix)
        publishSnapshot(changed: .track(trackID))
        scheduleFlushToDocument()
    }

    func setTrackSends(trackID: UUID, sendA: Double, sendB: Double) {
        guard let track = store.tracks.first(where: { $0.id == trackID }) else {
            return
        }
        var mix = track.mix
        mix.sendA = sendA
        mix.sendB = sendB
        setTrackMix(trackID: trackID, mix: mix)
    }

    func setTrackSendA(_ value: Double, trackID: UUID) {
        guard let track = store.tracks.first(where: { $0.id == trackID }) else {
            return
        }
        setTrackSends(trackID: trackID, sendA: value, sendB: track.mix.sendB)
    }

    func setTrackSendB(_ value: Double, trackID: UUID) {
        guard let track = store.tracks.first(where: { $0.id == trackID }) else {
            return
        }
        setTrackSends(trackID: trackID, sendA: track.mix.sendA, sendB: value)
    }

    @discardableResult
    func addMixerBus(name: String? = nil, color: String? = nil) -> UUID {
        let busID = store.appendMixerBus(name: name, color: color)
        applyDocumentModelMutation()
        return busID
    }

    func renameMixerBus(_ busID: UUID, name: String) {
        let changed = store.mutateMixerBus(id: busID) { bus in
            bus.name = name
        }
        guard changed else { return }
        applyDocumentModelMutation()
    }

    func setMixerBusColor(_ color: String?, busID: UUID) {
        let changed = store.mutateMixerBus(id: busID) { bus in
            bus.color = MixerBus.normalizedColor(color)
        }
        guard changed else { return }
        applyDocumentModelMutation()
    }

    func setMixerBusMix(busID: UUID, mix: BusMixSettings) {
        let changed = store.mutateMixerBus(id: busID) { bus in
            bus.mix = mix
        }
        guard changed else { return }
        applyMixerBusMixPerformanceMutation(busID: busID)
    }

    func setMixerBusLevel(_ level: Double, busID: UUID) {
        updateMixerBusMix(busID: busID) { $0.level = level }
    }

    func setMixerBusPan(_ pan: Double, busID: UUID) {
        updateMixerBusMix(busID: busID) { $0.pan = pan }
    }

    func setMixerBusMuted(_ muted: Bool, busID: UUID) {
        updateMixerBusMix(busID: busID) { $0.isMuted = muted }
    }

    func setMixerBusSoloed(_ soloed: Bool, busID: UUID) {
        updateMixerBusMix(busID: busID) { $0.isSoloed = soloed }
    }

    func setTrackOutputBus(trackID: UUID, busID: UUID?) {
        guard busID == nil || store.buses.contains(where: { $0.id == busID }) else {
            return
        }
        let changed = store.mutateTrack(id: trackID) { track in
            track.outputBusID = busID
        }
        guard changed else { return }
        applyDocumentModelMutation()
    }

    func setTrackSoloed(_ soloed: Bool, trackID: UUID) {
        let changed = store.mutateTrack(id: trackID) { track in
            track.mix.isSoloed = soloed
        }
        guard changed else { return }
        applyTrackMixPerformanceMutation(trackID: trackID)
    }

    func clearAllSolo() {
        let soloedTrackIDs = store.tracks.filter { $0.mix.isSoloed }.map(\.id)
        let soloedBusIDs = store.buses.filter { $0.mix.isSoloed }.map(\.id)
        guard store.clearAllSolo() else { return }
        applySoloClearPerformanceMutation(trackIDs: soloedTrackIDs, busIDs: soloedBusIDs)
    }

    @discardableResult
    func deleteMixerBus(id: UUID) -> [UUID] {
        let existed = store.buses.contains { $0.id == id }
        let affectedTrackIDs = store.deleteMixerBus(id: id)
        guard existed else { return [] }
        applyDocumentModelMutation()
        return affectedTrackIDs
    }

    private func updateMixerBusMix(busID: UUID, _ update: (inout BusMixSettings) -> Void) {
        let changed = store.mutateMixerBus(id: busID) { bus in
            update(&bus.mix)
        }
        guard changed else { return }
        applyMixerBusMixPerformanceMutation(busID: busID)
    }

    private func applyMixerBusMixPerformanceMutation(busID: UUID) {
        guard let bus = store.buses.first(where: { $0.id == busID }) else { return }
        revision = store.revision
        dispatchScopedRuntimeUpdate(.mixerBusMix(busID: busID, mix: bus.mix))
        scheduleFlushToDocument()
    }

    private func applyTrackMixPerformanceMutation(trackID: UUID) {
        guard let track = store.tracks.first(where: { $0.id == trackID }) else { return }
        revision = store.revision
        engineController.setMix(trackID: trackID, mix: track.mix)
        publishSnapshot(changed: .track(trackID))
        scheduleFlushToDocument()
    }

    private func applySoloClearPerformanceMutation(trackIDs: [UUID], busIDs: [UUID]) {
        revision = store.revision

        var snapshotChange = SnapshotChange.none
        for trackID in trackIDs {
            guard let track = store.tracks.first(where: { $0.id == trackID }) else { continue }
            engineController.setMix(trackID: trackID, mix: track.mix)
            snapshotChange.formUnion(.track(trackID))
        }

        for busID in busIDs {
            guard let bus = store.buses.first(where: { $0.id == busID }) else { continue }
            dispatchScopedRuntimeUpdate(.mixerBusMix(busID: busID, mix: bus.mix))
        }

        if snapshotChange.requiresPlaybackSnapshotInstall {
            publishSnapshot(changed: snapshotChange)
        }
        scheduleFlushToDocument()
    }

    private func applyDocumentModelMutation() {
        revision = store.revision
        engineController.apply(documentModel: store.exportToProject())
        snapshotPublisher.replace(engineController.currentPlaybackSnapshotForTesting)
        scheduleFlushToDocument()
    }
}
