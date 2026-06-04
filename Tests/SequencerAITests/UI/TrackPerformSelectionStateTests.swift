import SwiftUI
import XCTest
@testable import SequencerAI

@MainActor
final class TrackPerformSelectionStateTests: XCTestCase {
    private final class DocumentBox {
        var document: SeqAIDocument

        init(document: SeqAIDocument) {
            self.document = document
        }
    }

    private func makeSession(project: Project) -> SequencerDocumentSession {
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
        return session
    }

    private func makeThreeTrackProject() -> Project {
        var project = makeLiveStoreProject().0
        project.appendTrack(trackType: .monoMelodic)
        project.appendTrack(trackType: .monoMelodic)
        return project
    }

    func test_selectedSet_addRemoveToggleClearAndReconcile() {
        let trackA = UUID()
        let trackB = UUID()
        let trackC = UUID()
        let removedTrack = UUID()
        var selection = TrackPerformSelectionState()

        selection.add(trackA)
        selection.add(trackB)
        XCTAssertEqual(selection.selectedTrackIDs, [trackA, trackB])
        XCTAssertTrue(selection.contains(trackA))

        selection.remove(trackA)
        XCTAssertEqual(selection.selectedTrackIDs, [trackB])

        selection.toggle(trackB)
        XCTAssertTrue(selection.isEmpty)

        selection.toggle(trackC)
        selection.add(removedTrack)
        selection.reconcile(availableTrackIDs: [trackA, trackB, trackC])
        XCTAssertEqual(selection.selectedTrackIDs, [trackC])

        selection.clear()
        XCTAssertTrue(selection.isEmpty)
    }

    func test_authoredEditFromSelectedSourceFansOutToSelectedTracksOnly() throws {
        let project = makeThreeTrackProject()
        let session = makeSession(project: project)
        defer { SequencerDocumentSessionRegistry.unregister(session) }

        let tracks = session.store.tracks.map(\.id)
        let sourceTrackID = tracks[0]
        let untouchedTrackID = tracks[1]
        let linkedTrackID = tracks[2]
        let muteLayerID = try XCTUnwrap(session.store.layers.first(where: { $0.target == .mute })?.id)
        var selection = TrackPerformSelectionState()
        selection.add(sourceTrackID)
        selection.add(linkedTrackID)

        let recipients = TrackPerformAuthoredEdit.recipientTrackIDs(
            sourceTrackID: sourceTrackID,
            orderedTrackIDs: tracks,
            selection: selection
        )
        session.setPhraseCell(
            .single(.bool(true)),
            layerID: muteLayerID,
            trackIDs: recipients,
            phraseID: session.store.selectedPhraseID
        )

        let phrase = session.store.selectedPhrase
        XCTAssertEqual(phrase.cell(for: muteLayerID, trackID: sourceTrackID), .single(.bool(true)))
        XCTAssertEqual(phrase.cell(for: muteLayerID, trackID: linkedTrackID), .single(.bool(true)))
        XCTAssertEqual(phrase.cell(for: muteLayerID, trackID: untouchedTrackID), .inheritDefault)
    }

    func test_authoredEditFromUnselectedSourceStaysLocal() throws {
        let project = makeThreeTrackProject()
        let session = makeSession(project: project)
        defer { SequencerDocumentSessionRegistry.unregister(session) }

        let tracks = session.store.tracks.map(\.id)
        let selectedTrackID = tracks[0]
        let sourceTrackID = tracks[1]
        let otherSelectedTrackID = tracks[2]
        let muteLayerID = try XCTUnwrap(session.store.layers.first(where: { $0.target == .mute })?.id)
        let selection = TrackPerformSelectionState(selectedTrackIDs: [selectedTrackID, otherSelectedTrackID])

        let recipients = TrackPerformAuthoredEdit.recipientTrackIDs(
            sourceTrackID: sourceTrackID,
            orderedTrackIDs: tracks,
            selection: selection
        )
        session.setPhraseCell(
            .single(.bool(true)),
            layerID: muteLayerID,
            trackIDs: recipients,
            phraseID: session.store.selectedPhraseID
        )

        let phrase = session.store.selectedPhrase
        XCTAssertEqual(phrase.cell(for: muteLayerID, trackID: sourceTrackID), .single(.bool(true)))
        XCTAssertEqual(phrase.cell(for: muteLayerID, trackID: selectedTrackID), .inheritDefault)
        XCTAssertEqual(phrase.cell(for: muteLayerID, trackID: otherSelectedTrackID), .inheritDefault)
    }

    func test_authoredEditFromSingleSelectedSourceStaysLocal() throws {
        let project = makeThreeTrackProject()
        let session = makeSession(project: project)
        defer { SequencerDocumentSessionRegistry.unregister(session) }

        let tracks = session.store.tracks.map(\.id)
        let sourceTrackID = tracks[0]
        let untouchedTrackID = tracks[1]
        let muteLayerID = try XCTUnwrap(session.store.layers.first(where: { $0.target == .mute })?.id)
        let selection = TrackPerformSelectionState(selectedTrackIDs: [sourceTrackID])

        let recipients = TrackPerformAuthoredEdit.recipientTrackIDs(
            sourceTrackID: sourceTrackID,
            orderedTrackIDs: tracks,
            selection: selection
        )
        session.setPhraseCell(
            .single(.bool(true)),
            layerID: muteLayerID,
            trackIDs: recipients,
            phraseID: session.store.selectedPhraseID
        )

        let phrase = session.store.selectedPhrase
        XCTAssertEqual(phrase.cell(for: muteLayerID, trackID: sourceTrackID), .single(.bool(true)))
        XCTAssertEqual(phrase.cell(for: muteLayerID, trackID: untouchedTrackID), .inheritDefault)
    }
}
