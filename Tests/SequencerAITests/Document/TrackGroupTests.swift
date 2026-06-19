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
        XCTAssertEqual(decoded.triggerMappingMode, .perNote)
        XCTAssertEqual(decoded.noteMapping, [:])
        XCTAssertEqual(decoded.channelMapping, [:])
        XCTAssertFalse(decoded.mute)
        XCTAssertFalse(decoded.solo)
        XCTAssertTrue(decoded.isPatternLinked)
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
            triggerMappingMode: .perChannel,
            noteMapping: [memberA: 0, memberB: 2],
            channelMapping: [memberA: 0, memberB: 1],
            mute: true,
            solo: true,
            isPatternLinked: false
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
        XCTAssertEqual(decoded.triggerMappingMode, .perNote)
        XCTAssertEqual(decoded.noteMapping, [:])
        XCTAssertEqual(decoded.channelMapping, [:])
        XCTAssertFalse(decoded.mute)
        XCTAssertFalse(decoded.solo)
        XCTAssertTrue(decoded.isPatternLinked, "Older documents default to linked")
    }

    func test_older_track_group_documents_decode_mapping_contract_defaults() throws {
        let memberA = UUID()
        let memberB = UUID()
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "name": "Legacy Drums",
          "memberIDs": ["\(memberA.uuidString)", "\(memberB.uuidString)"],
          "noteMapping": ["\(memberA.uuidString)", 0, "\(memberB.uuidString)", 2]
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(TrackGroup.self, from: json)

        XCTAssertEqual(decoded.triggerMappingMode, .perNote)
        XCTAssertEqual(decoded.noteMapping, [memberA: 0, memberB: 2])
        XCTAssertEqual(decoded.channelMapping, [:])
    }
}
