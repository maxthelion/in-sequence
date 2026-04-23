import Foundation
import XCTest
@testable import SequencerAI

final class ProjectAttachNewGeneratorTests: XCTestCase {
    func test_attachNewGenerator_appends_one_pool_entry_of_matching_track_type() throws {
        var project = Project.empty
        project.appendTrack(trackType: .monoMelodic)
        let track = project.selectedTrack
        let priorCount = project.generatorPool.count

        let added = try XCTUnwrap(project.attachNewGenerator(to: track.id))

        XCTAssertEqual(project.generatorPool.count, priorCount + 1)
        XCTAssertEqual(added.trackType, .monoMelodic)
        XCTAssertTrue(project.generatorPool.contains(where: { $0.id == added.id }))
    }

    func test_attachNewGenerator_sets_attachedGeneratorID_on_bank() throws {
        var project = Project.empty
        project.appendTrack(trackType: .polyMelodic)
        let track = project.selectedTrack

        let added = try XCTUnwrap(project.attachNewGenerator(to: track.id))

        let bank = project.patternBank(for: track.id)
        XCTAssertEqual(bank.attachedGeneratorID, added.id)
    }

    func test_attachNewGenerator_preserves_slot_modes_while_wiring_generator_ids() throws {
        var project = Project.empty
        project.appendTrack(trackType: .monoMelodic)
        let track = project.selectedTrack
        let priorClipID = project.patternBank(for: track.id).slot(at: 0).sourceRef.clipID

        let added = try XCTUnwrap(project.attachNewGenerator(to: track.id))

        let bank = project.patternBank(for: track.id)
        for slot in bank.slots {
            XCTAssertEqual(slot.sourceRef.mode, .clip)
            XCTAssertEqual(slot.sourceRef.generatorID, added.id)
        }
        XCTAssertEqual(bank.slot(at: 0).sourceRef.clipID, priorClipID, "seeded clipID must survive attach")
        XCTAssertTrue(bank.slots.dropFirst().allSatisfy { $0.sourceRef.clipID == nil })
    }

    func test_attachNewGenerator_returns_nil_for_unknown_track() {
        var project = Project.empty
        let added = project.attachNewGenerator(to: UUID())
        XCTAssertNil(added)
    }
}
