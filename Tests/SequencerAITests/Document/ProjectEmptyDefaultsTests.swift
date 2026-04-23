import Foundation
import XCTest
@testable import SequencerAI

final class ProjectEmptyDefaultsTests: XCTestCase {
    func test_empty_project_bank_has_no_attached_generator() {
        let project = Project.empty
        let bank = project.patternBank(for: project.selectedTrack.id)
        XCTAssertNil(bank.attachedGeneratorID, "Project.empty must start with no generator attached")
    }

    func test_empty_project_bank_slots_all_in_clip_mode() {
        let project = Project.empty
        let bank = project.patternBank(for: project.selectedTrack.id)
        for slot in bank.slots {
            XCTAssertEqual(
                slot.sourceRef.mode, .clip,
                "slot \(slot.slotIndex) must be in clip mode in Project.empty"
            )
        }
    }

    func test_empty_project_has_an_owned_clip_in_the_pool() {
        let project = Project.empty
        XCTAssertFalse(project.clipPool.isEmpty, "Project.empty must seed at least one clip in clipPool")
        let defaultTrack = project.selectedTrack
        let compatibleClips = project.clipPool.filter { $0.trackType == defaultTrack.trackType }
        XCTAssertFalse(compatibleClips.isEmpty, "Project.empty must have a compatible clip for the default track type")
    }

    func test_empty_project_bank_seeds_only_the_first_slot_with_a_clip() {
        let project = Project.empty
        let bank = project.patternBank(for: project.selectedTrack.id)
        XCTAssertNotNil(bank.slot(at: 0).sourceRef.clipID)
        for slot in bank.slots.dropFirst() {
            XCTAssertNil(slot.sourceRef.clipID, "slot \(slot.slotIndex) should stay empty until edited")
        }
    }
}
