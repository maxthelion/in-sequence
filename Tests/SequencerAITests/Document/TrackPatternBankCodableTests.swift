import Foundation
import XCTest
@testable import SequencerAI

final class TrackPatternBankCodableTests: XCTestCase {
    func test_bank_round_trips_attachedGeneratorID() throws {
        let trackID = UUID()
        let generatorID = UUID()
        let clipID = UUID()
        let slot = TrackPatternSlot(slotIndex: 0, sourceRef: .clip(clipID))
        let bank = TrackPatternBank(
            trackID: trackID,
            slots: [slot],
            attachedGeneratorID: generatorID
        )

        let data = try JSONEncoder().encode(bank)
        let decoded = try JSONDecoder().decode(TrackPatternBank.self, from: data)

        XCTAssertEqual(decoded.trackID, trackID)
        XCTAssertEqual(decoded.attachedGeneratorID, generatorID)
    }

    func test_bank_round_trips_nil_attachedGeneratorID() throws {
        let trackID = UUID()
        let slot = TrackPatternSlot(slotIndex: 0, sourceRef: .clip(nil))
        let bank = TrackPatternBank(trackID: trackID, slots: [slot], attachedGeneratorID: nil)

        let data = try JSONEncoder().encode(bank)
        let decoded = try JSONDecoder().decode(TrackPatternBank.self, from: data)

        XCTAssertNil(decoded.attachedGeneratorID)
    }

    func test_legacy_document_without_field_decodes_as_nil() throws {
        // JSON produced by the pre-attachedGeneratorID schema — field absent.
        let legacyJSON = """
        {
            "trackID": "11111111-1111-1111-1111-111111111111",
            "slots": [
                { "slotIndex": 0, "sourceRef": { "mode": "clip", "clipID": "22222222-2222-2222-2222-222222222222" } }
            ]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(TrackPatternBank.self, from: legacyJSON)

        XCTAssertNil(decoded.attachedGeneratorID)
        XCTAssertEqual(decoded.trackID, UUID(uuidString: "11111111-1111-1111-1111-111111111111"))
    }
}
