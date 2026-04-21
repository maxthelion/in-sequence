import Foundation
import XCTest
@testable import SequencerAI

final class TrackPatternBankDefaultConstructorTests: XCTestCase {
    func test_default_points_all_slots_at_initialClipID() {
        let track = StepSequenceTrack.default
        let clipID = UUID()

        let bank = TrackPatternBank.default(for: track, initialClipID: clipID)

        XCTAssertEqual(bank.slots.count, TrackPatternBank.slotCount)
        XCTAssertNil(bank.attachedGeneratorID)
        for slot in bank.slots {
            XCTAssertEqual(slot.sourceRef.mode, .clip)
            XCTAssertEqual(slot.sourceRef.clipID, clipID)
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
