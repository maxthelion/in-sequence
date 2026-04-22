import Foundation
import XCTest
@testable import SequencerAI

final class ProjectAppendTrackClipTests: XCTestCase {
    func test_appendTrack_appends_a_matching_template_clip_to_pool() {
        var project = Project.empty
        let priorClipCount = project.clipPool.count
        let priorGeneratorCount = project.generatorPool.count

        project.appendTrack(trackType: .monoMelodic)

        XCTAssertEqual(project.clipPool.count, priorClipCount + 1, "appendTrack should add exactly one clip to the pool")
        XCTAssertEqual(project.generatorPool.count, priorGeneratorCount, "appendTrack must not mutate the generator pool")

        let addedClip = project.clipPool.last!
        XCTAssertEqual(addedClip.trackType, .monoMelodic)
    }

    func test_appendTrack_bank_points_at_the_new_clip_with_no_generator_attached() {
        var project = Project.empty

        project.appendTrack(trackType: .polyMelodic)

        let newTrack = project.selectedTrack
        let bank = project.patternBank(for: newTrack.id)
        let expectedClipID = project.clipPool.last!.id

        XCTAssertNil(bank.attachedGeneratorID, "new track should have no generator attached")
        // Lazy allocation: only slot 0 is pre-seeded; others are empty clip refs.
        XCTAssertEqual(bank.slots.first?.sourceRef.mode, .clip)
        XCTAssertEqual(bank.slots.first?.sourceRef.clipID, expectedClipID)
        for slot in bank.slots.dropFirst() {
            XCTAssertEqual(slot.sourceRef.mode, .clip)
            XCTAssertNil(slot.sourceRef.clipID, "slot \(slot.slotIndex) lazily allocated")
        }
    }

    func test_appendTrack_slice_picks_slice_template() {
        var project = Project.empty

        project.appendTrack(trackType: .slice)

        let addedClip = project.clipPool.last!
        XCTAssertEqual(addedClip.trackType, .slice)
    }
}
