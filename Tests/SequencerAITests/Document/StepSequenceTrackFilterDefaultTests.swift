import XCTest
@testable import SequencerAI

/// Tests that StepSequenceTrack.filter exists, has bypass-transparent defaults,
/// and decodes gracefully from legacy JSON without a "filter" key.
final class StepSequenceTrackFilterDefaultTests: XCTestCase {

    // MARK: - Defaults

    func test_newTrack_hasDefaultFilterSettings() {
        let track = StepSequenceTrack(
            name: "Test",
            pitches: [60],
            stepPattern: [true],
            velocity: 100,
            gateLength: 4
        )
        XCTAssertEqual(track.filter.type, .lowpass)
        XCTAssertEqual(track.filter.poles, .two)
        XCTAssertEqual(track.filter.cutoffHz, 20_000, accuracy: 0.001)
        XCTAssertEqual(track.filter.resonance, 0, accuracy: 0.001)
        XCTAssertEqual(track.filter.drive, 0, accuracy: 0.001)
    }

    func test_defaultStaticTrack_hasDefaultFilterSettings() {
        let track = StepSequenceTrack.default
        XCTAssertEqual(track.filter.type, .lowpass)
        XCTAssertEqual(track.filter.poles, .two)
        XCTAssertEqual(track.filter.cutoffHz, 20_000, accuracy: 0.001)
    }

    // MARK: - Round-trip coding

    func test_filter_roundTrip() throws {
        var track = StepSequenceTrack(
            name: "Test",
            pitches: [60],
            stepPattern: [true],
            velocity: 100,
            gateLength: 4
        )
        track.filter.type = .highpass
        track.filter.poles = .four
        track.filter.cutoffHz = 3000
        track.filter.resonance = 0.5
        track.filter.drive = 0.25

        let data = try JSONEncoder().encode(track)
        let decoded = try JSONDecoder().decode(StepSequenceTrack.self, from: data)

        XCTAssertEqual(decoded.filter.type, .highpass)
        XCTAssertEqual(decoded.filter.poles, .four)
        XCTAssertEqual(decoded.filter.cutoffHz, 3000, accuracy: 0.001)
        XCTAssertEqual(decoded.filter.resonance, 0.5, accuracy: 0.001)
        XCTAssertEqual(decoded.filter.drive, 0.25, accuracy: 0.001)
    }

    // MARK: - Legacy decode (no filter key)

    func test_legacyDecode_noFilterKey_usesDefaults() throws {
        // Build a JSON dict without the "filter" key, simulating a legacy document.
        let legacyJSON: [String: Any] = [
            "id": UUID().uuidString,
            "name": "Legacy Track",
            "trackType": "monoMelodic",
            "pitches": [60],
            "stepPattern": [true],
            "stepAccents": [false],
            "destination": ["kind": "none"],
            "mix": ["level": 0.8, "pan": 0.0, "isMuted": false, "isSolo": false],
            "velocity": 100,
            "gateLength": 4,
            "macros": []
        ]
        let data = try JSONSerialization.data(withJSONObject: legacyJSON)
        let decoded = try JSONDecoder().decode(StepSequenceTrack.self, from: data)
        XCTAssertEqual(decoded.filter.type, .lowpass)
        XCTAssertEqual(decoded.filter.cutoffHz, 20_000, accuracy: 0.001)
        XCTAssertEqual(decoded.filter.resonance, 0, accuracy: 0.001)
    }

    // MARK: - Filter is independent of Destination

    func test_filter_survivesDestinationChange() {
        var track = StepSequenceTrack(
            name: "Test",
            pitches: [60],
            stepPattern: [true],
            destination: .sample(sampleID: UUID(), settings: .default),
            velocity: 100,
            gateLength: 4
        )
        track.filter.cutoffHz = 1200
        track.filter.resonance = 0.8

        // Change destination — filter should be unchanged.
        track.destination = .internalSampler(bankID: .sliceDefault, preset: "other")

        XCTAssertEqual(track.filter.cutoffHz, 1200, accuracy: 0.001)
        XCTAssertEqual(track.filter.resonance, 0.8, accuracy: 0.001)
    }
}
