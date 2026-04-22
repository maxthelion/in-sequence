import Foundation
import XCTest
@testable import SequencerAI

final class ProjectAddDrumKitClipTests: XCTestCase {
    func test_addDrumKit_808_appends_four_seeded_clips_to_pool() throws {
        var project = Project.empty
        let priorClipCount = project.clipPool.count
        let priorGeneratorCount = project.generatorPool.count

        let groupID = try XCTUnwrap(project.addDrumKit(.kit808))

        XCTAssertEqual(project.clipPool.count, priorClipCount + 4)
        XCTAssertEqual(project.generatorPool.count, priorGeneratorCount, "drum-kit creation must not add generator pool entries")

        let memberIDs = try XCTUnwrap(project.trackGroups.first(where: { $0.id == groupID })?.memberIDs)
        XCTAssertEqual(memberIDs.count, 4)

        let presetMembers = DrumKitPreset.kit808.members
        for (memberID, presetMember) in zip(memberIDs, presetMembers) {
            let bank = project.patternBank(for: memberID)
            XCTAssertNil(bank.attachedGeneratorID, "drum part must have no generator attached")

            let clipID = try XCTUnwrap(bank.slots.first?.sourceRef.clipID)
            let clip = try XCTUnwrap(project.clipEntry(id: clipID))

            XCTAssertEqual(clip.trackType, .monoMelodic)
            XCTAssertEqual(clip.name, presetMember.trackName)
            XCTAssertEqual(noteGridMainStepPattern(clip.content), presetMember.seedPattern)
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

    func test_addDrumKit_techno_appends_four_seeded_clips() throws {
        var project = Project.empty
        let priorCount = project.clipPool.count

        _ = try XCTUnwrap(project.addDrumKit(.techno))

        XCTAssertEqual(project.clipPool.count, priorCount + 4)
    }

    func test_addDrumKit_acoustic_appends_three_seeded_clips() throws {
        var project = Project.empty
        let priorCount = project.clipPool.count

        _ = try XCTUnwrap(project.addDrumKit(.acousticBasic))

        XCTAssertEqual(project.clipPool.count, priorCount + 3)
    }
}
