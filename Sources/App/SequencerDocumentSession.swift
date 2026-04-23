import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class SequencerDocumentSession {
    @ObservationIgnored
    private let document: Binding<SeqAIDocument>
    @ObservationIgnored
    private var flushTask: Task<Void, Never>?
    /// Set to `true` during `flushToDocument()` so that `ingestExternalDocumentChange`
    /// can detect the self-originated change and skip a redundant engine apply.
    @ObservationIgnored
    private var selfOriginatedFlushInFlight: Bool = false

    let store: LiveSequencerStore
    let engineController: EngineController
    private(set) var revision: UInt64 = 0

    /// Production initializer. Creates and owns a new EngineController.
    init(document: Binding<SeqAIDocument>) {
        self.document = document
        self.engineController = EngineController(
            audioOutput: AudioInstrumentHost(),
            audioOutputFactory: { AudioInstrumentHost() }
        )
        self.store = LiveSequencerStore(project: document.wrappedValue.project)
        self.revision = store.revision
        SequencerDocumentSessionRegistry.register(self)
    }

    /// Test-only initializer that accepts an injected EngineController.
    /// Allows unit tests to provide stub engines without requiring CoreAudio access.
    init(document: Binding<SeqAIDocument>, engineController: EngineController) {
        self.document = document
        self.engineController = engineController
        self.store = LiveSequencerStore(project: document.wrappedValue.project)
        self.revision = store.revision
        SequencerDocumentSessionRegistry.register(self)
    }

    deinit {
        let identifier = ObjectIdentifier(self)
        Task { @MainActor in
            SequencerDocumentSessionRegistry.unregister(identifier: identifier)
        }
    }

    var project: Project {
        store.exportToProject()
    }

    func activate() {
        engineController.apply(documentModel: store.exportToProject())
        publishSnapshot()
    }

    func publishSnapshot() {
        engineController.apply(playbackSnapshot: SequencerSnapshotCompiler.compile(state: store.compileInput()))
        revision = store.revision
    }

    func scheduleFlushToDocument() {
        flushTask?.cancel()
        flushTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(150))
            guard let self else {
                return
            }
            flushToDocument()
        }
    }

    func flushToDocument() {
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
        engineController.apply(documentModel: store.exportToProject())
        publishSnapshot()
    }

    func mutateProject(
        impact: LiveMutationImpact = .snapshotOnly,
        _ update: (inout Project) -> Void
    ) {
        guard store.mutate(impact: impact, update) else {
            return
        }

        revision = store.revision

        switch impact {
        case .snapshotOnly:
            publishSnapshot()
        case .fullEngineApply:
            /// Calls engineController.apply(documentModel:) which installs a fresh
            /// snapshot internally. Do NOT also call publishSnapshot() here — that
            /// would compile the snapshot a second time.
            engineController.apply(documentModel: store.exportToProject())
        case .scopedRuntime(let update):
            dispatchScopedRuntimeUpdate(update)
            publishSnapshot()
        }

        scheduleFlushToDocument()
    }

    /// Dispatch a scoped runtime update directly to the engine. This updates a single
    /// domain in the live engine without rebuilding the full document-model pipeline.
    private func dispatchScopedRuntimeUpdate(_ update: ScopedRuntimeUpdate) {
        switch update {
        case let .filter(trackID, settings):
            engineController.sampleEngineSink.applyFilter(settings, trackID: trackID)
        case let .auState(trackID, blob):
            // The state blob is already written into the store by the mutation closure.
            // Write it into the live AU host if one exists.
            engineController.writeStateBlob(blob, for: trackID)
        case let .mix(trackID, mix):
            engineController.setMix(trackID: trackID, mix: mix)
        }
    }

    func setTrackMix(trackID: UUID, mix: TrackMixSettings) {
        let changed = store.mutateTrack(id: trackID) { track in
            track.mix = mix
        }

        guard changed else {
            return
        }

        revision = store.revision
        engineController.setMix(trackID: trackID, mix: mix)
        publishSnapshot()
        scheduleFlushToDocument()
    }
}
