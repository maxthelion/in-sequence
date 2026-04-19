import Foundation
import XCTest
@testable import SequencerAI

final class TrackGroupTests: XCTestCase {
    func test_minimal_track_group_round_trips() throws {
        let id = UUID()
        let group = TrackGroup(id: id, name: "Drums")

        let data = try JSONEncoder().encode(group)
        let decoded = try JSONDecoder().decode(TrackGroup.self, from: data)

        XCTAssertEqual(decoded, group)
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.memberIDs, [])
        XCTAssertNil(decoded.sharedDestination)
        XCTAssertEqual(decoded.noteMapping, [:])
        XCTAssertFalse(decoded.mute)
        XCTAssertFalse(decoded.solo)
        XCTAssertNil(decoded.busSink)
    }

    func test_full_track_group_round_trips() throws {
        let memberA = UUID()
        let memberB = UUID()
        let id = UUID()
        let group = TrackGroup(
            id: id,
            name: "Kit A",
            color: "#123456",
            memberIDs: [memberA, memberB],
            sharedDestination: .midi(port: .sequencerAIOut, channel: 9, noteOffset: -12),
            noteMapping: [memberA: 36, memberB: 38],
            mute: true,
            solo: true,
            busSink: BusRef(id: "main-kit-bus")
        )

        let data = try JSONEncoder().encode(group)
        let decoded = try JSONDecoder().decode(TrackGroup.self, from: data)

        XCTAssertEqual(decoded, group)
        XCTAssertEqual(decoded.id, id)
    }

    func test_missing_optional_fields_decode_to_defaults() throws {
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "name": "Drums"
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(TrackGroup.self, from: json)

        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.name, "Drums")
        XCTAssertEqual(decoded.color, "#8AA")
        XCTAssertEqual(decoded.memberIDs, [])
        XCTAssertNil(decoded.sharedDestination)
        XCTAssertEqual(decoded.noteMapping, [:])
        XCTAssertFalse(decoded.mute)
        XCTAssertFalse(decoded.solo)
        XCTAssertNil(decoded.busSink)
    }
}
