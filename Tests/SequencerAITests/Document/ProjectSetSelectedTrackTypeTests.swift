import Foundation
import XCTest
@testable import SequencerAI

final class ProjectSetSelectedTrackTypeTests: XCTestCase {
    func test_setSelectedTrackType_does_not_reuse_another_tracks_clip() {
        var project = Project.empty
        // Track A is the initial default track (monoMelodic)
        let trackA = project.selectedTrack

        // Append track B with polyMelodic - it gets its own clip
        project.appendTrack(trackType: .polyMelodic)
        let trackBClipID = project.clipPool.last!.id

        // Select track A and change its type to polyMelodic
        project.selectTrack(id: trackA.id)
        project.setSelectedTrackType(.polyMelodic)

        let bankA = project.patternBank(for: trackA.id)
        let slotClipIDs = bankA.slots.map { $0.sourceRef.clipID }
        for (index, clipID) in slotClipIDs.enumerated() {
            XCTAssertNotEqual(
                clipID, trackBClipID,
                "slot \(index) must not reuse track B's clip — it must own its own clip"
            )
        }
    }

    func test_setSelectedTrackType_appends_new_clip_to_pool() {
        var project = Project.empty
        project.appendTrack(trackType: .polyMelodic)
        let trackBClipID = project.clipPool.last!.id
        _ = trackBClipID

        let initialClipCount = project.clipPool.count
        let trackA = project.tracks.first!
        project.selectTrack(id: trackA.id)

        project.setSelectedTrackType(.polyMelodic)

        XCTAssertEqual(
            project.clipPool.count, initialClipCount + 1,
            "setSelectedTrackType must append exactly one new clip to the pool"
        )
    }

    func test_setSelectedTrackType_bank_has_no_attached_generator() {
        var project = Project.empty
        let trackA = project.selectedTrack

        project.setSelectedTrackType(.polyMelodic)

        let bank = project.patternBank(for: trackA.id)
        XCTAssertNil(bank.attachedGeneratorID, "bank must have no attached generator after type change")
    }

    func test_setSelectedTrackType_slots_point_to_new_owned_clip() {
        var project = Project.empty
        let trackA = project.selectedTrack

        project.setSelectedTrackType(.polyMelodic)

        let bank = project.patternBank(for: trackA.id)
        let newClip = project.clipPool.last!
        for slot in bank.slots {
            XCTAssertEqual(slot.sourceRef.mode, .clip, "slot \(slot.slotIndex) must be in clip mode")
            XCTAssertEqual(slot.sourceRef.clipID, newClip.id, "slot \(slot.slotIndex) must point to the new owned clip")
        }
    }
}
