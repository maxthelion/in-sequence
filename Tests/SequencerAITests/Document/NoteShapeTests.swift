import XCTest
@testable import SequencerAI

final class NoteShapeTests: XCTestCase {
    func test_default_round_trips_through_codable() throws {
        let data = try JSONEncoder().encode(NoteShape.default)
        let decoded = try JSONDecoder().decode(NoteShape.self, from: data)

        XCTAssertEqual(decoded, .default)
    }

    func test_equality_reflects_field_changes() {
        let baseline = NoteShape.default
        let matching = NoteShape(velocity: 100, gateLength: 4, accent: false)
        let differentVelocity = NoteShape(velocity: 101, gateLength: 4, accent: false)

        XCTAssertEqual(baseline, matching)
        XCTAssertNotEqual(baseline, differentVelocity)
    }

    func test_default_values_are_valid() {
        XCTAssertGreaterThanOrEqual(NoteShape.default.velocity, 0)
        XCTAssertLessThanOrEqual(NoteShape.default.velocity, 127)
        XCTAssertGreaterThan(NoteShape.default.gateLength, 0)
    }
}
