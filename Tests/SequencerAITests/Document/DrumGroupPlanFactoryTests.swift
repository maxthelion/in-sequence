import Foundation
import XCTest
@testable import SequencerAI

final class DrumGroupPlanFactoryTests: XCTestCase {
    func test_blankDefault_has_four_members_with_expected_tags() {
        let plan = DrumGroupPlan.blankDefault

        XCTAssertEqual(plan.members.map(\.tag), ["kick", "snare", "hat-closed", "clap"])
        XCTAssertEqual(plan.members.map(\.trackName), ["Kick", "Snare", "Hat", "Clap"])
    }

    func test_blankDefault_members_have_no_preferred_sample() {
        let plan = DrumGroupPlan.blankDefault

        XCTAssertTrue(plan.members.allSatisfy { $0.sampleID == nil })
    }

    func test_blankDefault_has_no_shared_destination_and_no_template() {
        let plan = DrumGroupPlan.blankDefault

        XCTAssertNil(plan.sharedDestination)
        XCTAssertNil(plan.templateID)
        XCTAssertEqual(plan.name, "Drum Group")
        XCTAssertEqual(plan.color, "#8AA")
    }

    func test_blankDefault_members_routeToShared_true_by_default() {
        let plan = DrumGroupPlan.blankDefault

        XCTAssertTrue(plan.members.allSatisfy(\.routesToShared))
    }

    func test_blankDefault_routes_to_dedicatedBus_by_default() {
        // AC3.4: new drum groups are self-contained mixable units on their own
        // bus, not straight onto master.
        XCTAssertEqual(DrumGroupPlan.blankDefault.busRouting, .dedicatedBus)
    }

    func test_from_kit_routes_to_dedicatedBus_by_default() throws {
        let kit = try XCTUnwrap(DrumAssetLibrary.factoryKits.first(where: { $0.name == "808" }))

        XCTAssertEqual(DrumGroupPlan.from(kit: kit).busRouting, .dedicatedBus)
    }

    func test_from_kit_mirrors_kit_parts() throws {
        let kit = try XCTUnwrap(DrumAssetLibrary.factoryKits.first(where: { $0.name == "808" }))

        let plan = DrumGroupPlan.from(kit: kit)

        XCTAssertEqual(plan.members.count, kit.parts.count)
        for (member, part) in zip(plan.members, kit.parts) {
            XCTAssertEqual(member.tag, part.tag)
            XCTAssertEqual(member.trackName, part.trackName)
            XCTAssertEqual(member.sampleID, part.sampleID)
            XCTAssertTrue(member.routesToShared)
        }
    }

    func test_from_kit_inherits_kit_name_and_defaults_to_no_template() throws {
        let kit = try XCTUnwrap(DrumAssetLibrary.factoryKits.first(where: { $0.name == "808" }))

        let plan = DrumGroupPlan.from(kit: kit)

        XCTAssertEqual(plan.name, kit.name)
        XCTAssertNil(plan.templateID)
        XCTAssertNil(plan.sharedDestination)
    }

    func test_from_kit_carries_explicit_templateID() throws {
        let kit = try XCTUnwrap(DrumAssetLibrary.factoryKits.first)
        let templateID = try XCTUnwrap(DrumAssetLibrary.factoryTemplates.first?.id)

        let plan = DrumGroupPlan.from(kit: kit, templateID: templateID)

        XCTAssertEqual(plan.templateID, templateID)
    }

    func test_from_kit_carries_part_sampleIDs_into_members() {
        let sampleID = UUID()
        let kit = DrumKit(
            id: UUID(),
            name: "Custom",
            parts: [
                DrumKit.Part(tag: "kick", trackName: "Kick", sampleID: sampleID),
                DrumKit.Part(tag: "snare", trackName: "Snare"),
            ]
        )

        let plan = DrumGroupPlan.from(kit: kit)

        XCTAssertEqual(plan.members.map(\.sampleID), [sampleID, nil])
    }

    func test_from_each_factory_kit_has_nonempty_members() {
        for kit in DrumAssetLibrary.factoryKits {
            let plan = DrumGroupPlan.from(kit: kit)
            XCTAssertFalse(plan.members.isEmpty, "kit=\(kit.name)")
        }
    }
}
