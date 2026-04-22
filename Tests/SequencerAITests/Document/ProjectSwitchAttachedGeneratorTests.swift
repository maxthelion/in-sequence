import Foundation
import XCTest
@testable import SequencerAI

final class ProjectSwitchAttachedGeneratorTests: XCTestCase {
    private func projectWithTwoGenerators() throws -> (project: Project, trackID: UUID, gen1ID: UUID, gen2ID: UUID) {
        var project = Project.empty
        project.appendTrack(trackType: .monoMelodic)
        let track = project.selectedTrack
        let gen1 = try XCTUnwrap(project.attachNewGenerator(to: track.id))
        let gen2 = try XCTUnwrap(project.attachNewGenerator(to: track.id))
        return (project, track.id, gen1.id, gen2.id)
    }

    func test_switchAttachedGenerator_updates_attachedGeneratorID() throws {
        var (project, trackID, gen1ID, gen2ID) = try projectWithTwoGenerators()
        project.switchAttachedGenerator(to: gen1ID, for: trackID)

        XCTAssertEqual(
            project.patternBank(for: trackID).attachedGeneratorID, gen1ID,
            "switchAttachedGenerator must set attachedGeneratorID to the new generator"
        )
        _ = gen2ID
    }

    func test_switchAttachedGenerator_updates_all_slot_generatorIDs() throws {
        var (project, trackID, gen1ID, _) = try projectWithTwoGenerators()
        project.switchAttachedGenerator(to: gen1ID, for: trackID)

        let bank = project.patternBank(for: trackID)
        for slot in bank.slots {
            XCTAssertEqual(
                slot.sourceRef.generatorID, gen1ID,
                "slot \(slot.slotIndex) generatorID must be updated to gen1"
            )
        }
    }

    func test_switchAttachedGenerator_preserves_clipID() throws {
        var (project, trackID, gen1ID, _) = try projectWithTwoGenerators()
        let slot0ClipID = project.patternBank(for: trackID).slot(at: 0).sourceRef.clipID

        project.switchAttachedGenerator(to: gen1ID, for: trackID)

        let bank = project.patternBank(for: trackID)
        XCTAssertEqual(bank.slots.first?.sourceRef.clipID, slot0ClipID, "slot 0 clipID preserved")
        for slot in bank.slots.dropFirst() {
            XCTAssertNil(slot.sourceRef.clipID, "slot \(slot.slotIndex) lazily-allocated clipID is nil")
        }
    }

    func test_switchAttachedGenerator_preserves_per_slot_bypass_mode() throws {
        var (project, trackID, gen1ID, gen2ID) = try projectWithTwoGenerators()
        project.setSlotBypassed(true, trackID: trackID, slotIndex: 5)
        XCTAssertEqual(project.patternBank(for: trackID).slot(at: 5).sourceRef.mode, .clip)

        project.switchAttachedGenerator(to: gen1ID, for: trackID)

        let slot5 = project.patternBank(for: trackID).slot(at: 5)
        XCTAssertEqual(slot5.sourceRef.mode, .clip, "bypassed slot must remain bypassed after switching generators")
        XCTAssertEqual(slot5.sourceRef.generatorID, gen1ID, "bypassed slot generatorID must update to new generator")
        _ = gen2ID
    }
}
