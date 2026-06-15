import XCTest
import SwiftUI
@testable import SequencerAI

// MARK: - Slice 6a: drum tracks default to the kit matrix view
//
// A drum-group/kit track now lands on the kit matrix (all parts together) by
// default; the per-part editor is the dive-in, reached by selecting a part.
// Non-drum tracks (mono/poly/slice/audio-in) are unaffected.
//
// `TrackWorkspaceView` derives the view it shows from
// `DrumKitWorkspaceNavigationState.defaultForOpening(headerModel:)` plus a
// dive-in flag. These tests cover that pure default-view decision and the
// dive-in / dive-out transitions over the same header model.

@MainActor
final class DrumTrackKitFirstRoutingTests: XCTestCase {

    private final class DocumentBox {
        var document: SeqAIDocument

        init(document: SeqAIDocument) {
            self.document = document
        }

        var binding: Binding<SeqAIDocument> {
            Binding(
                get: { self.document },
                set: { self.document = $0 }
            )
        }
    }

    private func makeSession() -> (SequencerDocumentSession, DocumentBox) {
        let (project, _, _) = makeLiveStoreProject()
        let box = DocumentBox(document: SeqAIDocument(project: project))
        let engine = EngineController(client: nil, endpoint: nil)
        let session = SequencerDocumentSession(
            document: box.binding,
            engineController: engine,
            debounceInterval: .seconds(100)
        )
        session.activate()
        return (session, box)
    }

    @discardableResult
    private func makeDrumGroup(in session: SequencerDocumentSession) -> TrackGroupID {
        let plan = DrumGroupPlan(
            name: "Kit-First Kit",
            color: "#C06030",
            members: [
                DrumGroupPlan.Member(tag: "kick", trackName: "Kick"),
                DrumGroupPlan.Member(tag: "snare", trackName: "Snare"),
                DrumGroupPlan.Member(tag: "hat-closed", trackName: "Hat"),
            ],
            templateID: nil
        )
        guard let groupID = session.addDrumGroup(plan: plan) else {
            XCTFail("addDrumGroup failed")
            return TrackGroupID()
        }
        return groupID
    }

    private func headerModel(
        for session: SequencerDocumentSession
    ) -> DrumPartWorkspaceHeaderModel? {
        DrumPartWorkspaceHeaderModel(
            selectedTrack: session.store.selectedTrack,
            tracks: session.store.tracks,
            trackGroups: session.store.trackGroups
        )
    }

    // MARK: - Default view for a drum-group track is the kit matrix

    func test_openingDrumGroupTrack_defaultsToKitMatrix() {
        let (session, _) = makeSession()
        let groupID = makeDrumGroup(in: session)
        let memberIDs = session.store.trackGroups.first { $0.id == groupID }!.memberIDs
        session.setSelectedTrackID(memberIDs[1]) // Snare

        let model = headerModel(for: session)
        XCTAssertNotNil(model, "a drum-group member is a drum part")

        let navState = DrumKitWorkspaceNavigationState.defaultForOpening(headerModel: model)
        XCTAssertNotNil(navState, "drum track defaults into the kit matrix")
        XCTAssertEqual(navState?.groupID, groupID)
        XCTAssertEqual(navState?.originatingPartID, memberIDs[1])
    }

    // MARK: - Non-drum tracks are unaffected (no header model -> no matrix)

    func test_openingNonDrumTrack_neverDefaultsToKitMatrix() {
        let (session, _) = makeSession()
        // The base project already has standalone (non-grouped) tracks.
        guard let ungrouped = session.store.tracks.first(where: { $0.groupID == nil }) else {
            return XCTFail("expected a non-grouped track in the base project")
        }
        session.setSelectedTrackID(ungrouped.id)

        let model = headerModel(for: session)
        XCTAssertNil(model, "a non-grouped track is not a drum part")
        XCTAssertNil(
            DrumKitWorkspaceNavigationState.defaultForOpening(headerModel: model),
            "non-drum tracks keep their single-source editor"
        )
    }

    // MARK: - Dive-in / dive-out transitions

    /// Mirrors `TrackWorkspaceView`'s `kitNavigationState` derivation: a drum
    /// track shows the matrix unless the user has dived into the selected part.
    private func resolvedNavState(
        headerModel model: DrumPartWorkspaceHeaderModel?,
        divedInPartID: UUID?
    ) -> DrumKitWorkspaceNavigationState? {
        guard let model else { return nil }
        if divedInPartID == model.currentPartID { return nil }
        return DrumKitWorkspaceNavigationState.defaultForOpening(headerModel: model)
    }

    func test_diveIntoPart_showsPartEditor_thenDiveOutReturnsToMatrix() {
        let (session, _) = makeSession()
        let groupID = makeDrumGroup(in: session)
        let memberIDs = session.store.trackGroups.first { $0.id == groupID }!.memberIDs
        session.setSelectedTrackID(memberIDs[0]) // Kick
        let model = headerModel(for: session)
        XCTAssertNotNil(model)

        // Default: matrix is shown (no dive-in).
        XCTAssertNotNil(
            resolvedNavState(headerModel: model, divedInPartID: nil),
            "drum track lands on the kit matrix by default"
        )

        // Dive into the selected part: part editor shows (no matrix nav state).
        XCTAssertNil(
            resolvedNavState(headerModel: model, divedInPartID: model?.currentPartID),
            "diving into the selected part shows the per-part editor"
        )

        // Dive back out (clear the dived-in part): matrix returns.
        XCTAssertNotNil(
            resolvedNavState(headerModel: model, divedInPartID: nil),
            "diving back out returns to the kit matrix"
        )
    }

    func test_diveInForOnePart_doesNotLeakToAnotherSelectedPart() {
        let (session, _) = makeSession()
        let groupID = makeDrumGroup(in: session)
        let memberIDs = session.store.trackGroups.first { $0.id == groupID }!.memberIDs

        // Dive into Kick.
        session.setSelectedTrackID(memberIDs[0])
        let kickModel = headerModel(for: session)
        XCTAssertNil(
            resolvedNavState(headerModel: kickModel, divedInPartID: memberIDs[0]),
            "Kick dive-in shows the Kick part editor"
        )

        // A different part selected with the SAME dived-in id must NOT be
        // treated as dived-in: it falls back to the matrix default.
        session.setSelectedTrackID(memberIDs[2])
        let hatModel = headerModel(for: session)
        XCTAssertNotNil(
            resolvedNavState(headerModel: hatModel, divedInPartID: memberIDs[0]),
            "selecting a different part shows the kit matrix, not a stale dive-in"
        )
    }
}
