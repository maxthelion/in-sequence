import Foundation
import XCTest
@testable import SequencerAI

final class TrackPatternBankDefaultConstructorTests: XCTestCase {
    func test_default_seeds_only_the_first_slot_with_initialClipID() {
        let track = StepSequenceTrack.default
        let clipID = UUID()

        let bank = TrackPatternBank.default(for: track, initialClipID: clipID)

        XCTAssertEqual(bank.slots.count, TrackPatternBank.slotCount)
        XCTAssertNil(bank.attachedGeneratorID)
        // Lazy allocation model: only slot 0 is pre-seeded; rest are empty clip refs.
        XCTAssertEqual(bank.slots.first?.sourceRef.mode, .clip)
        XCTAssertEqual(bank.slots.first?.sourceRef.clipID, clipID)
        XCTAssertNil(bank.slots.first?.sourceRef.generatorID)
        for slot in bank.slots.dropFirst() {
            XCTAssertEqual(slot.sourceRef.mode, .clip)
            XCTAssertNil(slot.sourceRef.clipID, "non-zero slots lazily allocated")
            XCTAssertNil(slot.sourceRef.generatorID)
        }
    }

    func test_default_accepts_nil_initialClipID() {
        let track = StepSequenceTrack.default

        let bank = TrackPatternBank.default(for: track, initialClipID: nil)

        XCTAssertEqual(bank.slots.count, TrackPatternBank.slotCount)
        XCTAssertNil(bank.attachedGeneratorID)
        for slot in bank.slots {
            XCTAssertEqual(slot.sourceRef.mode, .clip)
            XCTAssertNil(slot.sourceRef.clipID)
        }
    }
}
