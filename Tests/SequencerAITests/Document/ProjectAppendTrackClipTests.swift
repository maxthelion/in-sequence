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
        for slot in bank.slots {
            XCTAssertEqual(slot.sourceRef.mode, .clip)
            XCTAssertEqual(slot.sourceRef.clipID, expectedClipID)
        }
    }

    func test_appendTrack_slice_picks_slice_template() {
        var project = Project.empty

        project.appendTrack(trackType: .slice)

        let addedClip = project.clipPool.last!
        XCTAssertEqual(addedClip.trackType, .slice)
    }
}
