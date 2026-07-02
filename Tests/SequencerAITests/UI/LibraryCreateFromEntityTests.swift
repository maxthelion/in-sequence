import SwiftUI
import XCTest
@testable import SequencerAI

/// Tests for the Library page's create-track-from-entity affordances
/// (docs/roadmap/library-pools "2026-07 owner refinement"). The AU-instrument
/// and generator compositions themselves are covered by
/// CreateTrackWithSoundTests; here we pin the one-click drum-kit contract
/// (plan defaults, no customization sheet) at the session level.
@MainActor
final class LibraryCreateFromEntityTests: XCTestCase {

    private final class DocumentBox {
        var document: SeqAIDocument
        init(document: SeqAIDocument) { self.document = document }
    }

    private func makeSession(project: Project = .empty) -> (SequencerDocumentSession, DocumentBox) {
        let box = DocumentBox(document: SeqAIDocument(project: project))
        let session = SequencerDocumentSession(
            document: Binding(
                get: { box.document },
                set: { box.document = $0 }
            ),
            engineController: EngineController(client: nil, endpoint: nil)
        )
        // Test-isolation teardown (bug 20260702-135500): every controller this
        // suite creates is fully shut down inside the test that created it, so
        // no TickClock timer or host-queue work leaks into later suites.
        addTeardownBlock {
            session.engineController.shutdown()
            XCTAssertFalse(session.engineController.clock.isRunning,
                "no TickClock may survive test teardown")
            SequencerDocumentSessionRegistry.unregister(session)
        }
        return (session, box)
    }

    /// The Library kit row creates one-click with the plan DEFAULTS: dedicated
    /// bus, no template, no shared destination, members mirroring the kit's
    /// parts. If these defaults drift, the one-click create silently changes
    /// routing behaviour — pin them.
    func test_oneClickKitPlan_usesCreationDefaults() {
        let kit = DrumAssetLibrary.factoryKits[0]
        let plan = DrumGroupPlan.from(kit: kit)

        XCTAssertEqual(plan.name, kit.name)
        XCTAssertEqual(plan.busRouting, .dedicatedBus,
            "One-click kit create must keep the dedicated-bus default")
        XCTAssertNil(plan.templateID, "No template is applied without the builder")
        XCTAssertNil(plan.sharedDestination, "No shared destination without the builder")
        XCTAssertEqual(plan.members.map(\.tag), kit.parts.map(\.tag))
        XCTAssertEqual(plan.members.map(\.sampleID), kit.parts.map(\.sampleID),
            "The kit's per-part sound picks must carry into the plan")
    }

    /// One-click create from a kit row must add the group and select a member
    /// track so onOpenTrack lands inside the new kit.
    func test_createFromKitRow_addsGroupAndSelectsMember() throws {
        let (session, _) = makeSession()
        let kit = DrumAssetLibrary.factoryKits[0]

        let groupID = session.addDrumGroup(plan: .from(kit: kit))

        let live = session.store.exportToProject()
        let createdGroupID = try XCTUnwrap(groupID)
        let group = try XCTUnwrap(live.trackGroups.first(where: { $0.id == createdGroupID }))
        XCTAssertEqual(group.memberIDs.count, kit.parts.count,
            "Every kit part must become a member track")
        XCTAssertTrue(group.memberIDs.contains(live.selectedTrackID),
            "A member of the new kit must be selected for navigation")

        SequencerDocumentSessionRegistry.unregister(session)
    }
}
