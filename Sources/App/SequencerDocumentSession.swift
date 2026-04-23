import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class SequencerDocumentSession {
    @ObservationIgnored
    private let document: Binding<SeqAIDocument>
    @ObservationIgnored
    private unowned let engineController: EngineController
    @ObservationIgnored
    private var flushTask: Task<Void, Never>?

    let store: LiveSequencerStore
    private(set) var revision: UInt64 = 0

    init(
        document: Binding<SeqAIDocument>,
        engineController: EngineController
    ) {
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
        document.wrappedValue.project = exported
    }

    func ingestExternalDocumentChange(_ project: Project) {
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
            engineController.apply(documentModel: store.exportToProject())
            publishSnapshot()
        case .documentOnly:
            break
        }

        scheduleFlushToDocument()
    }

    func setTrackMix(trackID: UUID, mix: TrackMixSettings) {
        let changed = store.mutate { project in
            guard let index = project.tracks.firstIndex(where: { $0.id == trackID }) else {
                return
            }
            project.tracks[index].mix = mix
        }

        guard changed else {
            return
        }

        revision = store.revision
        engineController.setMix(trackID: trackID, mix: mix)
        scheduleFlushToDocument()
    }
}
