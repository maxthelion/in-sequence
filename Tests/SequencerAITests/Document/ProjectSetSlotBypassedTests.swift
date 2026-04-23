import Foundation
import XCTest
@testable import SequencerAI

final class ProjectSetSlotBypassedTests: XCTestCase {
    private func projectWithAttachedGenerator() throws -> (Project, UUID) {
        var project = Project.empty
        project.appendTrack(trackType: .monoMelodic)
        let track = project.selectedTrack
        _ = try XCTUnwrap(project.attachNewGenerator(to: track.id))
        return (project, track.id)
    }

    func test_bypass_true_flips_only_the_named_slot_to_clip_mode() throws {
        var (project, trackID) = try projectWithAttachedGenerator()
        for index in 0..<TrackPatternBank.slotCount where index != 3 {
            project.setSlotBypassed(false, trackID: trackID, slotIndex: index)
        }

        project.setSlotBypassed(true, trackID: trackID, slotIndex: 3)

        let bank = project.patternBank(for: trackID)
        XCTAssertEqual(bank.slot(at: 3).sourceRef.mode, .clip)
        for index in 0..<TrackPatternBank.slotCount where index != 3 {
            XCTAssertEqual(bank.slot(at: index).sourceRef.mode, .generator, "slot \(index) must stay engaged")
        }
    }

    func test_bypass_false_re_engages_the_slot() throws {
        var (project, trackID) = try projectWithAttachedGenerator()
        project.setSlotBypassed(true, trackID: trackID, slotIndex: 7)

        project.setSlotBypassed(false, trackID: trackID, slotIndex: 7)

        XCTAssertEqual(project.patternBank(for: trackID).slot(at: 7).sourceRef.mode, .generator)
    }

    func test_bypass_preserves_generatorID_and_clipID() throws {
        var (project, trackID) = try projectWithAttachedGenerator()
        let priorSlot = project.patternBank(for: trackID).slot(at: 5)

        project.setSlotBypassed(true, trackID: trackID, slotIndex: 5)

        let bypassed = project.patternBank(for: trackID).slot(at: 5)
        XCTAssertEqual(bypassed.sourceRef.generatorID, priorSlot.sourceRef.generatorID)
        XCTAssertEqual(bypassed.sourceRef.clipID, priorSlot.sourceRef.clipID)
    }

    func test_bypass_is_noop_when_no_generator_attached() {
        var project = Project.empty
        project.appendTrack(trackType: .monoMelodic)
        let trackID = project.selectedTrack.id
        let priorBank = project.patternBank(for: trackID)

        project.setSlotBypassed(true, trackID: trackID, slotIndex: 3)

        XCTAssertEqual(project.patternBank(for: trackID), priorBank)
    }

    func test_bypass_clamps_slotIndex_out_of_range() throws {
        var (project, trackID) = try projectWithAttachedGenerator()

        project.setSlotBypassed(true, trackID: trackID, slotIndex: 999)

        // The last slot (index 15) should be the clamped target.
        XCTAssertEqual(project.patternBank(for: trackID).slot(at: 15).sourceRef.mode, .clip)
    }
}
