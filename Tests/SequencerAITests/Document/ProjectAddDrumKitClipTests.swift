import Foundation
import XCTest
@testable import SequencerAI

final class ProjectAddDrumKitClipTests: XCTestCase {
    func test_addDrumGroup_808_with_template_assigns_seeded_clips_to_slot_zero() throws {
        var project = Project.empty
        let priorGeneratorCount = project.generatorPool.count
        let plan = DrumKitFixtures.templatedPlan(named: "808")
        let template = DrumKitFixtures.factoryTemplate(named: "808")

        let groupID = try XCTUnwrap(
            project.addDrumGroup(plan: plan, templateLookup: DrumKitFixtures.factoryTemplateLookup)
        )

        XCTAssertEqual(project.generatorPool.count, priorGeneratorCount, "drum-kit creation must not add generator pool entries")

        let memberIDs = try XCTUnwrap(project.trackGroups.first(where: { $0.id == groupID })?.memberIDs)
        XCTAssertEqual(memberIDs.count, 4)

        for (memberID, member) in zip(memberIDs, plan.members) {
            let bank = project.patternBank(for: memberID)
            XCTAssertNil(bank.attachedGeneratorID, "drum part must have no generator attached")

            let clipID = try XCTUnwrap(bank.slots.first?.sourceRef.clipID)
            let clip = try XCTUnwrap(project.clipEntry(id: clipID))

            XCTAssertEqual(clip.trackType, .monoMelodic)
            XCTAssertEqual(clip.name, member.trackName)
            XCTAssertEqual(noteGridMainStepPattern(clip.content), template.patterns[member.tag])
            XCTAssertEqual(noteGridPitches(clip.content), [DrumKitNoteMap.baselineNote])

            // Under the lazy-allocation model, only slot 0 is pre-seeded;
            // remaining slots are empty clip refs until edited.
            XCTAssertEqual(bank.slots.first?.sourceRef.mode, .clip)
            XCTAssertEqual(bank.slots.first?.sourceRef.clipID, clipID)
            for slot in bank.slots.dropFirst() {
                XCTAssertEqual(slot.sourceRef.mode, .clip)
                XCTAssertNil(slot.sourceRef.clipID, "non-zero slots are lazily allocated — should be empty")
            }
        }
    }

    func test_addDrumGroup_without_template_appends_one_empty_clip_per_member() throws {
        var project = Project.empty
        let priorCount = project.clipPool.count

        _ = try XCTUnwrap(
            project.addDrumGroup(
                plan: .from(kit: DrumKitFixtures.factoryKit(named: "808")),
                templateLookup: DrumKitFixtures.factoryTemplateLookup
            )
        )

        XCTAssertEqual(project.clipPool.count, priorCount + 4)
        for clip in project.clipPool.suffix(4) {
            XCTAssertTrue(noteGridMainStepPattern(clip.content).allSatisfy { $0 == false })
        }
    }

    func test_addDrumGroup_techno_with_template_seeds_four_members() throws {
        var project = Project.empty
        let plan = DrumKitFixtures.templatedPlan(named: "Techno")
        let template = DrumKitFixtures.factoryTemplate(named: "Techno")

        let groupID = try XCTUnwrap(
            project.addDrumGroup(plan: plan, templateLookup: DrumKitFixtures.factoryTemplateLookup)
        )

        let memberIDs = try XCTUnwrap(project.trackGroups.first(where: { $0.id == groupID })?.memberIDs)
        XCTAssertEqual(memberIDs.count, 4)
        for (memberID, member) in zip(memberIDs, plan.members) {
            let clipID = try XCTUnwrap(project.patternBank(for: memberID).slots.first?.sourceRef.clipID)
            let clip = try XCTUnwrap(project.clipEntry(id: clipID))
            XCTAssertEqual(noteGridMainStepPattern(clip.content), template.patterns[member.tag])
        }
    }

    func test_addDrumGroup_acoustic_with_template_seeds_three_members() throws {
        var project = Project.empty
        let plan = DrumKitFixtures.templatedPlan(named: "Acoustic")
        let template = DrumKitFixtures.factoryTemplate(named: "Acoustic")

        let groupID = try XCTUnwrap(
            project.addDrumGroup(plan: plan, templateLookup: DrumKitFixtures.factoryTemplateLookup)
        )

        let memberIDs = try XCTUnwrap(project.trackGroups.first(where: { $0.id == groupID })?.memberIDs)
        XCTAssertEqual(memberIDs.count, 3)
        for (memberID, member) in zip(memberIDs, plan.members) {
            let clipID = try XCTUnwrap(project.patternBank(for: memberID).slots.first?.sourceRef.clipID)
            let clip = try XCTUnwrap(project.clipEntry(id: clipID))
            XCTAssertEqual(noteGridMainStepPattern(clip.content), template.patterns[member.tag])
        }
    }
}
