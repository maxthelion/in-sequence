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
        XCTAssertEqual(bank.slot(at: 0).sourceRef.mode, .clip)
        XCTAssertEqual(bank.slot(at: 0).sourceRef.clipID, clipID)
        XCTAssertNil(bank.slot(at: 0).sourceRef.generatorID)
        for slot in bank.slots.dropFirst() {
            XCTAssertEqual(slot.sourceRef.mode, .clip)
            XCTAssertNil(slot.sourceRef.clipID)
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
