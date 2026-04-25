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
        // Start from a real encoded track, then drop the filter key to simulate
        // a pre-filter document while preserving the current enum coding shapes.
        let legacyTrack = StepSequenceTrack(
            name: "Legacy Track",
            pitches: [60],
            stepPattern: [true],
            destination: Destination.none,
            mix: TrackMixSettings(level: 0.8, pan: 0, isMuted: false),
            velocity: 100,
            gateLength: 4
        )
        let encoded = try JSONEncoder().encode(legacyTrack)
        var legacyJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        legacyJSON.removeValue(forKey: "filter")
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

    func test_legacyMacroBindings_withoutSlotIndices_areAssignedSequentialSlots() throws {
        let first = TrackMacroDescriptor(
            id: UUID(),
            displayName: "Cutoff",
            minValue: 0,
            maxValue: 1,
            defaultValue: 0.5,
            valueType: .scalar,
            source: .auParameter(address: 1, identifier: "cutoff")
        )
        let second = TrackMacroDescriptor(
            id: UUID(),
            displayName: "Resonance",
            minValue: 0,
            maxValue: 1,
            defaultValue: 0.2,
            valueType: .scalar,
            source: .auParameter(address: 2, identifier: "resonance")
        )

        let track = StepSequenceTrack(
            name: "Legacy Track",
            pitches: [60],
            stepPattern: [true],
            velocity: 100,
            gateLength: 4,
            macros: [
                TrackMacroBinding(descriptor: first, slotIndex: 0),
                TrackMacroBinding(descriptor: second, slotIndex: 1)
            ]
        )
        let encoded = try JSONEncoder().encode(track)
        var legacyJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        let legacyMacros = [
            ["descriptor": try XCTUnwrap(JSONSerialization.jsonObject(with: try JSONEncoder().encode(first)) as? [String: Any])],
            ["descriptor": try XCTUnwrap(JSONSerialization.jsonObject(with: try JSONEncoder().encode(second)) as? [String: Any])]
        ]
        legacyJSON["macros"] = legacyMacros

        let data = try JSONSerialization.data(withJSONObject: legacyJSON)
        let decoded = try JSONDecoder().decode(StepSequenceTrack.self, from: data)

        XCTAssertEqual(decoded.macros.map(\.slotIndex), [0, 1])
        XCTAssertEqual(decoded.macros.map(\.id), [first.id, second.id])
    }
}
