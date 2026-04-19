import XCTest
@testable import SequencerAI

final class RouteTests: XCTestCase {
    func test_route_round_trips_through_codable() throws {
        let trackID = UUID(uuidString: "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE") ?? UUID()
        let route = Route(
            id: UUID(uuidString: "11111111-2222-3333-4444-555555555555") ?? UUID(),
            source: .track(trackID),
            filter: .noteRange(lo: 60, hi: 72),
            destination: .midi(port: .sequencerAIOut, channel: 5, noteOffset: -12),
            enabled: false
        )

        let data = try JSONEncoder().encode(route)
        let decoded = try JSONDecoder().decode(Route.self, from: data)

        XCTAssertEqual(decoded, route)
        XCTAssertEqual(decoded.id, route.id)
    }

    func test_route_equality_considers_enabled_state() {
        let trackID = UUID(uuidString: "12121212-3434-5656-7878-909090909090") ?? UUID()
        let lhs = Route(source: .track(trackID), destination: .voicing(trackID), enabled: true)
        let rhs = Route(id: lhs.id, source: .track(trackID), destination: .voicing(trackID), enabled: false)

        XCTAssertNotEqual(lhs, rhs)
    }

    func test_chord_generator_route_round_trips() throws {
        let trackID = UUID(uuidString: "ABABABAB-CDCD-EFEF-0101-234523452345") ?? UUID()
        let route = Route(
            source: .chordGenerator(trackID),
            destination: .chordContext(broadcastTag: "verse")
        )

        let data = try JSONEncoder().encode(route)
        let decoded = try JSONDecoder().decode(Route.self, from: data)

        XCTAssertEqual(decoded, route)
    }

    func test_target_track_id_is_exposed_for_track_destinations() {
        let targetID = UUID(uuidString: "99999999-8888-7777-6666-555555555555") ?? UUID()

        XCTAssertEqual(RouteDestination.voicing(targetID).targetTrackID, targetID)
        XCTAssertEqual(RouteDestination.trackInput(targetID, tag: "kick").targetTrackID, targetID)
        XCTAssertNil(RouteDestination.midi(port: .sequencerAIOut, channel: 0, noteOffset: 0).targetTrackID)
    }
}
