import Foundation
import XCTest
@testable import SequencerAI

final class ProjectRemoveAttachedGeneratorTests: XCTestCase {
    func test_remove_clears_attachedGeneratorID() throws {
        var project = Project.empty
        project.appendTrack(trackType: .monoMelodic)
        let track = project.selectedTrack
        _ = try XCTUnwrap(project.attachNewGenerator(to: track.id))

        project.removeAttachedGenerator(from: track.id)

        let bank = project.patternBank(for: track.id)
        XCTAssertNil(bank.attachedGeneratorID)
    }

    func test_remove_flips_slots_to_clip_mode_preserving_clipID_and_generatorID() throws {
        var project = Project.empty
        project.appendTrack(trackType: .monoMelodic)
        let track = project.selectedTrack
        let ownedClipID = project.patternBank(for: track.id).slot(at: 0).sourceRef.clipID
        let added = try XCTUnwrap(project.attachNewGenerator(to: track.id))

        project.removeAttachedGenerator(from: track.id)

        let bank = project.patternBank(for: track.id)
        for slot in bank.slots {
            XCTAssertEqual(slot.sourceRef.mode, .clip)
            XCTAssertEqual(slot.sourceRef.clipID, ownedClipID, "remove must fall back to the slot's clipID")
            XCTAssertEqual(slot.sourceRef.generatorID, added.id, "generatorID is retained so un-attach could re-engage")
        }
    }

    func test_remove_does_not_delete_pool_entry() throws {
        var project = Project.empty
        project.appendTrack(trackType: .monoMelodic)
        let track = project.selectedTrack
        let added = try XCTUnwrap(project.attachNewGenerator(to: track.id))
        let priorCount = project.generatorPool.count

        project.removeAttachedGenerator(from: track.id)

        XCTAssertEqual(project.generatorPool.count, priorCount, "remove-from-track must not prune the pool")
        XCTAssertTrue(project.generatorPool.contains(where: { $0.id == added.id }))
    }

    func test_remove_is_noop_when_no_generator_attached() {
        var project = Project.empty
        project.appendTrack(trackType: .monoMelodic)
        let track = project.selectedTrack
        let priorBank = project.patternBank(for: track.id)

        project.removeAttachedGenerator(from: track.id)

        let bank = project.patternBank(for: track.id)
        XCTAssertEqual(bank, priorBank)
    }
}
