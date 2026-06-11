import Foundation
import XCTest
@testable import SequencerAI

final class ProjectApplyPatternTemplateTests: XCTestCase {
    private var libraryRoot: URL!

    override func setUpWithError() throws {
        libraryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try ["kick", "snare", "hatClosed", "clap"].forEach(makeCategory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: libraryRoot)
    }

    private var testLibrary: AudioSampleLibrary {
        AudioSampleLibrary(libraryRoot: libraryRoot)
    }

    private func makeCategory(_ name: String) throws {
        let directory = libraryRoot.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: directory.appendingPathComponent("\(name)-default.wav"))
    }

    private let kickPattern = (0..<16).map { $0 % 4 == 0 }
    private let snarePattern = (0..<16).map { $0 % 8 == 4 }

    private func makeTemplate(patterns: [VoiceTag: [Bool]]? = nil) -> PatternTemplate {
        PatternTemplate(
            id: UUID(),
            name: "Test Groove",
            patterns: patterns ?? ["kick": kickPattern, "snare": snarePattern]
        )
    }

    private func makeGroup(
        in project: inout Project,
        members: [DrumGroupPlan.Member] = [
            DrumGroupPlan.Member(tag: "kick", trackName: "Kick"),
            DrumGroupPlan.Member(tag: "snare", trackName: "Snare"),
            DrumGroupPlan.Member(tag: "clap", trackName: "Clap"),
        ]
    ) throws -> TrackGroupID {
        let plan = DrumGroupPlan(name: "Test Group", color: "#8AA", members: members)
        return try XCTUnwrap(project.addDrumGroup(plan: plan, library: testLibrary))
    }

    private func slotClip(_ project: Project, memberID: UUID, slotIndex: Int = 0) throws -> ClipPoolEntry {
        let clipID = try XCTUnwrap(project.patternBank(for: memberID).slot(at: slotIndex).sourceRef.clipID)
        return try XCTUnwrap(project.clipEntry(id: clipID))
    }

    func test_matched_members_get_fresh_clips_assigned_to_target_slot() throws {
        var project = Project.empty
        let groupID = try makeGroup(in: &project)
        let memberIDs = try XCTUnwrap(project.trackGroups.first(where: { $0.id == groupID })?.memberIDs)
        let priorSlotClipIDs = try memberIDs.map { try slotClip(project, memberID: $0).id }
        let priorClipCount = project.clipPool.count

        project.applyPatternTemplate(makeTemplate(), toGroup: groupID, slotIndex: 0)

        // kick + snare matched — two fresh clip pool entries.
        XCTAssertEqual(project.clipPool.count, priorClipCount + 2)

        let kickClip = try slotClip(project, memberID: memberIDs[0])
        XCTAssertFalse(priorSlotClipIDs.contains(kickClip.id), "matched member must get a fresh clip")
        XCTAssertEqual(kickClip.name, "Kick")
        XCTAssertEqual(kickClip.trackType, .monoMelodic)
        XCTAssertEqual(noteGridMainStepPattern(kickClip.content), kickPattern)
        XCTAssertEqual(noteGridPitches(kickClip.content), [DrumKitNoteMap.baselineNote])

        let snareClip = try slotClip(project, memberID: memberIDs[1])
        XCTAssertEqual(noteGridMainStepPattern(snareClip.content), snarePattern)
    }

    func test_members_without_template_entry_are_untouched() throws {
        var project = Project.empty
        let groupID = try makeGroup(in: &project)
        let memberIDs = try XCTUnwrap(project.trackGroups.first(where: { $0.id == groupID })?.memberIDs)
        let clapSlotBefore = project.patternBank(for: memberIDs[2]).slot(at: 0)

        project.applyPatternTemplate(makeTemplate(), toGroup: groupID, slotIndex: 0)

        XCTAssertEqual(project.patternBank(for: memberIDs[2]).slot(at: 0), clapSlotBefore, "clap has no template entry — must be untouched")
    }

    func test_template_tags_absent_from_group_are_ignored() throws {
        var project = Project.empty
        let groupID = try makeGroup(in: &project, members: [DrumGroupPlan.Member(tag: "kick", trackName: "Kick")])
        let priorClipCount = project.clipPool.count
        let template = makeTemplate(patterns: ["kick": kickPattern, "shaker": Array(repeating: true, count: 16)])

        project.applyPatternTemplate(template, toGroup: groupID, slotIndex: 0)

        XCTAssertEqual(project.clipPool.count, priorClipCount + 1, "no member carries the shaker tag — only kick fills")
    }

    func test_member_whose_target_slot_holds_a_generator_is_skipped() throws {
        var project = Project.empty
        let groupID = try makeGroup(in: &project)
        let memberIDs = try XCTUnwrap(project.trackGroups.first(where: { $0.id == groupID })?.memberIDs)
        _ = try XCTUnwrap(project.createBlankGeneratorSource(trackID: memberIDs[0], slotIndex: 0))
        let kickSlotBefore = project.patternBank(for: memberIDs[0]).slot(at: 0)
        XCTAssertEqual(kickSlotBefore.sourceRef.mode, .generator)

        project.applyPatternTemplate(makeTemplate(), toGroup: groupID, slotIndex: 0)

        XCTAssertEqual(project.patternBank(for: memberIDs[0]).slot(at: 0), kickSlotBefore, "generator-backed slot must be skipped")
        let snareClip = try slotClip(project, memberID: memberIDs[1])
        XCTAssertEqual(noteGridMainStepPattern(snareClip.content), snarePattern, "other members still fill")
    }

    func test_duplicate_tags_fill_first_occurrence_only() throws {
        var project = Project.empty
        let groupID = try makeGroup(in: &project, members: [
            DrumGroupPlan.Member(tag: "kick", trackName: "Kick A"),
            DrumGroupPlan.Member(tag: "kick", trackName: "Kick B"),
        ])
        let memberIDs = try XCTUnwrap(project.trackGroups.first(where: { $0.id == groupID })?.memberIDs)
        let secondSlotBefore = project.patternBank(for: memberIDs[1]).slot(at: 0)

        project.applyPatternTemplate(makeTemplate(), toGroup: groupID, slotIndex: 0)

        let firstClip = try slotClip(project, memberID: memberIDs[0])
        XCTAssertEqual(noteGridMainStepPattern(firstClip.content), kickPattern)
        XCTAssertEqual(project.patternBank(for: memberIDs[1]).slot(at: 0), secondSlotBefore, "second occurrence of a duplicate tag must be untouched")
    }

    func test_apply_into_nonzero_slot_leaves_slot_zero_untouched() throws {
        var project = Project.empty
        let groupID = try makeGroup(in: &project)
        let memberIDs = try XCTUnwrap(project.trackGroups.first(where: { $0.id == groupID })?.memberIDs)
        let kickSlotZeroBefore = project.patternBank(for: memberIDs[0]).slot(at: 0)

        project.applyPatternTemplate(makeTemplate(), toGroup: groupID, slotIndex: 3)

        XCTAssertEqual(project.patternBank(for: memberIDs[0]).slot(at: 0), kickSlotZeroBefore)
        let slotThreeClip = try slotClip(project, memberID: memberIDs[0], slotIndex: 3)
        XCTAssertEqual(noteGridMainStepPattern(slotThreeClip.content), kickPattern)
    }

    func test_unknown_group_is_a_no_op() {
        var project = Project.empty
        let snapshot = project

        project.applyPatternTemplate(makeTemplate(), toGroup: TrackGroupID(), slotIndex: 0)

        XCTAssertEqual(project, snapshot)
    }

    func test_creation_with_template_equals_post_creation_application() throws {
        let kit = DrumKitFixtures.factoryKit(named: "808")
        let template = DrumKitFixtures.factoryTemplate(named: "808")

        var createdWithTemplate = Project.empty
        let groupA = try XCTUnwrap(
            createdWithTemplate.addDrumGroup(
                plan: .from(kit: kit, templateID: template.id),
                library: testLibrary,
                templateLookup: DrumKitFixtures.factoryTemplateLookup
            )
        )

        var appliedAfterCreation = Project.empty
        let groupB = try XCTUnwrap(
            appliedAfterCreation.addDrumGroup(plan: .from(kit: kit), library: testLibrary)
        )
        appliedAfterCreation.applyPatternTemplate(template, toGroup: groupB, slotIndex: 0)

        let membersA = try XCTUnwrap(createdWithTemplate.trackGroups.first(where: { $0.id == groupA })?.memberIDs)
        let membersB = try XCTUnwrap(appliedAfterCreation.trackGroups.first(where: { $0.id == groupB })?.memberIDs)
        XCTAssertEqual(membersA.count, membersB.count)
        XCTAssertEqual(createdWithTemplate.clipPool.count, appliedAfterCreation.clipPool.count)

        for (memberA, memberB) in zip(membersA, membersB) {
            let clipA = try slotClip(createdWithTemplate, memberID: memberA)
            let clipB = try slotClip(appliedAfterCreation, memberID: memberB)
            XCTAssertEqual(clipA.name, clipB.name)
            XCTAssertEqual(clipA.trackType, clipB.trackType)
            XCTAssertEqual(clipA.content, clipB.content)

            let bankA = createdWithTemplate.patternBank(for: memberA)
            let bankB = appliedAfterCreation.patternBank(for: memberB)
            XCTAssertEqual(bankA.slots.map(\.sourceRef.mode), bankB.slots.map(\.sourceRef.mode))
            XCTAssertEqual(
                bankA.slots.map { $0.sourceRef.clipID != nil },
                bankB.slots.map { $0.sourceRef.clipID != nil }
            )
        }
    }
}
