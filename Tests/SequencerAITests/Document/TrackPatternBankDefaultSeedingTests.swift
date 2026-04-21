import XCTest
@testable import SequencerAI

final class TrackPatternBankDefaultSeedingTests: XCTestCase {
    func test_default_with_initialClipID_seeds_only_slot_zero() {
        let track = StepSequenceTrack.default
        let clipID = UUID()
        let bank = TrackPatternBank.default(for: track, initialClipID: clipID)

        XCTAssertEqual(bank.slots.count, 16)
        XCTAssertEqual(bank.slots[0].sourceRef.clipID, clipID)
        for index in 1..<16 {
            XCTAssertNil(bank.slots[index].sourceRef.clipID)
        }
    }

    func test_default_with_nil_initialClipID_has_no_seeded_clips() {
        let track = StepSequenceTrack.default
        let bank = TrackPatternBank.default(for: track, initialClipID: nil)

        for slot in bank.slots {
            XCTAssertNil(slot.sourceRef.clipID)
        }
    }

    func test_default_slots_start_in_clip_mode_without_generator() {
        let track = StepSequenceTrack.default
        let bank = TrackPatternBank.default(for: track, initialClipID: UUID())

        for slot in bank.slots {
            XCTAssertEqual(slot.sourceRef.mode, .clip)
            XCTAssertNil(slot.sourceRef.generatorID)
        }
        XCTAssertNil(bank.attachedGeneratorID)
    }
}
