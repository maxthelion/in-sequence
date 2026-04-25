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

    private func makeSession(project: Project) -> (SequencerDocumentSession, EngineController, DocumentBox) {
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
        return (session, engine, documentBox)
    }

    func test_selectedTrackChange_doesNotInstallPlaybackSnapshot() {
        let (baseProject, _, _) = makeLiveStoreProject()
        var project = baseProject
        project.appendTrack(trackType: .monoMelodic)
        let (session, engine, documentBox) = makeSession(project: project)

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

    func test_combinedSelection_trackOnlyChange_doesNotInstallPlaybackSnapshot() {
        let (baseProject, _, _) = makeLiveStoreProject()
        var project = baseProject
        project.appendTrack(trackType: .monoMelodic)
        let (session, engine, _) = makeSession(project: project)
        let snapshotsBefore = engine.applyPlaybackSnapshotCallCount
        let secondTrackID = project.tracks[1].id

        session.setSelectedPhraseAndTrackID(
            phraseID: project.selectedPhraseID,
            trackID: secondTrackID
        )

        XCTAssertEqual(engine.applyPlaybackSnapshotCallCount, snapshotsBefore)
        XCTAssertEqual(session.store.selectedTrackID, secondTrackID)
        XCTAssertEqual(session.store.selectedPhraseID, project.selectedPhraseID)

        SequencerDocumentSessionRegistry.unregister(session)
    }

    func test_combinedSelection_phraseChange_installsExactlyOneSnapshot() {
        let (baseProject, _, _) = makeLiveStoreProject()
        var project = baseProject
        let firstPhraseID = project.selectedPhraseID
        project.duplicatePhrase(id: firstPhraseID)
        project.selectedPhraseID = firstPhraseID
        let secondPhraseID = project.phrases[1].id
        let (session, engine, _) = makeSession(project: project)
        let snapshotsBefore = engine.applyPlaybackSnapshotCallCount

        session.setSelectedPhraseAndTrackID(
            phraseID: secondPhraseID,
            trackID: project.selectedTrackID
        )

        XCTAssertEqual(engine.applyPlaybackSnapshotCallCount, snapshotsBefore + 1)
        XCTAssertEqual(session.snapshotPublisher.snapshot.selectedPhraseID, secondPhraseID)

        SequencerDocumentSessionRegistry.unregister(session)
    }

    func test_booleanCellTap_afterTrackOnlySelection_installsOnlyCellSnapshot() throws {
        let (baseProject, _, _) = makeLiveStoreProject()
        var project = baseProject
        project.appendTrack(trackType: .monoMelodic)
        let secondTrackID = project.tracks[1].id
        let muteLayerID = try XCTUnwrap(project.layers.first(where: { $0.target == .mute })?.id)
        let (session, engine, _) = makeSession(project: project)
        let snapshotsBefore = engine.applyPlaybackSnapshotCallCount

        session.setSelectedPhraseAndTrackID(
            phraseID: project.selectedPhraseID,
            trackID: secondTrackID
        )
        session.setPhraseCell(
            .single(.bool(true)),
            layerID: muteLayerID,
            trackIDs: [secondTrackID],
            phraseID: project.selectedPhraseID
        )

        XCTAssertEqual(
            engine.applyPlaybackSnapshotCallCount,
            snapshotsBefore + 1,
            "track-only selection must be playback-inert; only the phrase-cell mutation should publish"
        )

        SequencerDocumentSessionRegistry.unregister(session)
    }
}
