import XCTest
@testable import SequencerAI

final class ChordsTests: XCTestCase {
    func test_chord_id_has_16_cases() {
        XCTAssertEqual(ChordID.allCases.count, 16)
    }

    func test_every_chord_id_has_a_chord() {
        for id in ChordID.allCases {
            XCTAssertNotNil(ChordDefinition.for(id: id), "Missing chord for \(id)")
        }
    }

    func test_spot_check_intervals() {
        XCTAssertEqual(ChordDefinition.for(id: .majorTriad)?.intervals, [0, 4, 7])
        XCTAssertEqual(ChordDefinition.for(id: .dominant7th)?.intervals, [0, 4, 7, 10])
    }

    func test_chord_intervals_are_valid() {
        for id in ChordID.allCases {
            guard let chord = ChordDefinition.for(id: id) else {
                XCTFail("Missing chord for \(id)")
                continue
            }

            XCTAssertEqual(chord.intervals.first, 0, "Chord \(id) should start at 0")
            XCTAssertEqual(chord.intervals, chord.intervals.sorted(), "Chord \(id) should be ascending")
            XCTAssertEqual(chord.intervals.count, Set(chord.intervals).count, "Chord \(id) should not repeat intervals")
        }
    }
}
