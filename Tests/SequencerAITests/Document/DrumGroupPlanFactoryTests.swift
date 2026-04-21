import Foundation
import XCTest
@testable import SequencerAI

final class DrumGroupPlanFactoryTests: XCTestCase {
    func test_blankDefault_has_four_members_with_expected_tags() {
        let plan = DrumGroupPlan.blankDefault

        XCTAssertEqual(plan.members.map(\.tag), ["kick", "snare", "hat-closed", "clap"])
        XCTAssertEqual(plan.members.map(\.trackName), ["Kick", "Snare", "Hat", "Clap"])
    }

    func test_blankDefault_members_have_all_false_seed_patterns_of_length_16() {
        let plan = DrumGroupPlan.blankDefault

        for member in plan.members {
            XCTAssertEqual(member.seedPattern.count, 16)
            XCTAssertTrue(member.seedPattern.allSatisfy { $0 == false })
        }
    }

    func test_blankDefault_has_no_shared_destination_and_prepopulate_off() {
        let plan = DrumGroupPlan.blankDefault

        XCTAssertNil(plan.sharedDestination)
        XCTAssertFalse(plan.prepopulateClips)
        XCTAssertEqual(plan.name, "Drum Group")
        XCTAssertEqual(plan.color, "#8AA")
    }

    func test_blankDefault_members_routeToShared_true_by_default() {
        let plan = DrumGroupPlan.blankDefault

        XCTAssertTrue(plan.members.allSatisfy(\.routesToShared))
    }

    func test_templated_from_kit808_mirrors_preset_members() {
        let plan = DrumGroupPlan.templated(from: .kit808)
        let presetMembers = DrumKitPreset.kit808.members

        XCTAssertEqual(plan.members.count, presetMembers.count)
        for (planMember, presetMember) in zip(plan.members, presetMembers) {
            XCTAssertEqual(planMember.tag, presetMember.tag)
            XCTAssertEqual(planMember.trackName, presetMember.trackName)
            XCTAssertEqual(planMember.seedPattern, presetMember.seedPattern)
            XCTAssertTrue(planMember.routesToShared)
        }
    }

    func test_templated_from_preset_inherits_name_and_color_and_defaults_prepopulate_on() {
        let plan = DrumGroupPlan.templated(from: .kit808)

        XCTAssertEqual(plan.name, DrumKitPreset.kit808.displayName)
        XCTAssertEqual(plan.color, DrumKitPreset.kit808.suggestedGroupColor)
        XCTAssertTrue(plan.prepopulateClips)
        XCTAssertNil(plan.sharedDestination)
    }

    func test_templated_from_each_preset_has_nonempty_members() {
        for preset in DrumKitPreset.allCases {
            let plan = DrumGroupPlan.templated(from: preset)
            XCTAssertFalse(plan.members.isEmpty, "preset=\(preset.rawValue)")
        }
    }
}
