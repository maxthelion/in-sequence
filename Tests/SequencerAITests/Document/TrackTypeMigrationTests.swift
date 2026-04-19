import XCTest
@testable import SequencerAI

final class TrackTypeMigrationTests: XCTestCase {
    func test_track_type_has_three_cases() {
        XCTAssertEqual(TrackType.allCases.count, 3)
        XCTAssertEqual(Set(TrackType.allCases), [.monoMelodic, .polyMelodic, .slice])
    }

    func test_legacy_instrument_decodes_to_mono_melodic() throws {
        XCTAssertEqual(try decode("\"instrument\""), .monoMelodic)
    }

    func test_legacy_drum_rack_decodes_to_mono_melodic() throws {
        XCTAssertEqual(try decode("\"drumRack\""), .monoMelodic)
    }

    func test_legacy_slice_loop_decodes_to_slice() throws {
        XCTAssertEqual(try decode("\"sliceLoop\""), .slice)
    }

    func test_new_values_round_trip() throws {
        for trackType in TrackType.allCases {
            let data = try JSONEncoder().encode(trackType)
            let decoded = try JSONDecoder().decode(TrackType.self, from: data)
            XCTAssertEqual(decoded, trackType)
        }
    }

    func test_unknown_value_throws() {
        XCTAssertThrowsError(try decode("\"wat\""))
    }

    private func decode(_ json: String) throws -> TrackType {
        try JSONDecoder().decode(TrackType.self, from: Data(json.utf8))
    }
}
