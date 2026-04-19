import XCTest
@testable import SequencerAI

final class TransportModeTests: XCTestCase {
    func test_all_cases_are_song_and_free() {
        XCTAssertEqual(TransportMode.allCases, [.song, .free])
    }

    func test_codable_roundtrip_preserves_mode() throws {
        for mode in TransportMode.allCases {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(TransportMode.self, from: data)
            XCTAssertEqual(decoded, mode)
        }
    }

    func test_labels_and_details_are_non_empty_and_distinct() {
        let labels = Set(TransportMode.allCases.map(\.label))
        let details = Set(TransportMode.allCases.map(\.detail))

        XCTAssertEqual(labels.count, TransportMode.allCases.count)
        XCTAssertEqual(details.count, TransportMode.allCases.count)
        XCTAssertTrue(labels.allSatisfy { !$0.isEmpty })
        XCTAssertTrue(details.allSatisfy { !$0.isEmpty })
    }
}
