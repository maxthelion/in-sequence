import Foundation
import XCTest
@testable import SequencerAI

final class ProjectSetPatternClipIDTests: XCTestCase {
    // Helper: project with a track + attached generator + slot 3 bypassed.
    private func projectWithBypassedSlot() throws -> (project: Project, trackID: UUID, generatorID: UUID) {
        var project = Project.empty
        project.appendTrack(trackType: .monoMelodic)
        let track = project.selectedTrack
        let entry = try XCTUnwrap(project.attachNewGenerator(to: track.id))
        project.setSlotBypassed(true, trackID: track.id, slotIndex: 3)
        return (project, track.id, entry.id)
    }

    func test_setPatternClipID_on_bypassed_slot_preserves_generatorID() throws {
        var (project, trackID, generatorID) = try projectWithBypassedSlot()
        // Create a second clip to switch to
        let otherClip = ClipPoolEntry(
            id: UUID(),
            name: "Other Clip",
            trackType: .monoMelodic,
            content: .stepSequence(stepPattern: Array(repeating: false, count: 16), pitches: [60])
        )
        project.clipPool.append(otherClip)

        project.setPatternClipID(otherClip.id, for: trackID, slotIndex: 3)

        let slot = project.patternBank(for: trackID).slot(at: 3)
        XCTAssertEqual(
            slot.sourceRef.generatorID, generatorID,
            "setPatternClipID must preserve the slot's retained generatorID"
        )
        XCTAssertEqual(slot.sourceRef.clipID, otherClip.id, "clipID must be updated to the new clip")
        XCTAssertEqual(slot.sourceRef.mode, .clip, "bypassed slot must remain in clip mode")
    }

    func test_unbypass_after_clip_change_re_engages_attached_generator() throws {
        var (project, trackID, generatorID) = try projectWithBypassedSlot()
        let otherClip = ClipPoolEntry(
            id: UUID(),
            name: "Other Clip",
            trackType: .monoMelodic,
            content: .stepSequence(stepPattern: Array(repeating: false, count: 16), pitches: [60])
        )
        project.clipPool.append(otherClip)
        project.setPatternClipID(otherClip.id, for: trackID, slotIndex: 3)

        // Un-bypass: re-engage the generator
        project.setSlotBypassed(false, trackID: trackID, slotIndex: 3)

        let slot = project.patternBank(for: trackID).slot(at: 3)
        XCTAssertEqual(slot.sourceRef.mode, .generator, "un-bypassing must flip mode back to generator")
        XCTAssertEqual(slot.sourceRef.generatorID, generatorID, "generatorID must still be the attached generator")
    }
}
