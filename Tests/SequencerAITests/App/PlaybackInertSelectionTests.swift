import SwiftUI
import XCTest
@testable import SequencerAI

@MainActor
final class PlaybackInertSelectionTests: XCTestCase {

    private final class DocumentBox {
        var document: SeqAIDocument

        init(document: SeqAIDocument) {
            self.document = document
        }
    }

    func test_selectedTrackChange_doesNotInstallPlaybackSnapshot() {
        let (baseProject, _, _) = makeLiveStoreProject()
        var project = baseProject
        project.appendTrack(trackType: .monoMelodic)
        let documentBox = DocumentBox(document: SeqAIDocument(project: project))
        let engine = EngineController(client: nil, endpoint: nil)
        let session = SequencerDocumentSession(
            document: Binding(
                get: { documentBox.document },
                set: { documentBox.document = $0 }
            ),
            engineController: engine,
            debounceInterval: .seconds(100)
        )
        session.activate()

        let snapshotsBefore = engine.applyPlaybackSnapshotCallCount
        let snapshotBefore = session.snapshotPublisher.snapshot
        let secondTrackID = project.tracks[1].id

        session.setSelectedTrackID(secondTrackID)

        XCTAssertEqual(engine.applyPlaybackSnapshotCallCount, snapshotsBefore)
        XCTAssertEqual(session.snapshotPublisher.snapshot, snapshotBefore)
        XCTAssertEqual(session.store.selectedTrackID, secondTrackID)
        XCTAssertEqual(documentBox.document.project.selectedTrackID, project.selectedTrackID)

        SequencerDocumentSessionRegistry.unregister(session)
    }
}
