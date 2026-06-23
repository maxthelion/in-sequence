import XCTest
import SwiftUI
@testable import SequencerAI

// MARK: - Slice 6a: drum tracks ALWAYS show the kit matrix view
//
// A drum-group/kit track always lands on (and stays on) the kit matrix — all
// parts together. Per-part editing lives inline in the matrix's expanded-row
// accordion, so there is no longer a per-part dive-in. Non-drum tracks
// (mono/poly/slice/audio-in) are unaffected and keep their single-source editor.
//
// `TrackWorkspaceView` derives the view it shows purely from
// `DrumKitWorkspaceNavigationState.defaultForOpening(headerModel:)`: a drum
// track resolves a matrix nav state; a non-drum track resolves nil.

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

    // MARK: - The matrix stays put across part selection (no dive-in)

    func test_selectingDifferentParts_alwaysResolvesTheKitMatrix() {
        let (session, _) = makeSession()
        let groupID = makeDrumGroup(in: session)
        let memberIDs = session.store.trackGroups.first { $0.id == groupID }!.memberIDs

        // Selecting Kick: matrix.
        session.setSelectedTrackID(memberIDs[0])
        XCTAssertNotNil(
            DrumKitWorkspaceNavigationState.defaultForOpening(headerModel: headerModel(for: session)),
            "selecting a drum part keeps the kit matrix on screen"
        )

        // Selecting a different part: still the matrix, scoped to the same group.
        session.setSelectedTrackID(memberIDs[2])
        let hatNav = DrumKitWorkspaceNavigationState.defaultForOpening(headerModel: headerModel(for: session))
        XCTAssertNotNil(hatNav, "selecting another drum part still shows the kit matrix")
        XCTAssertEqual(hatNav?.groupID, groupID)
    }
}
