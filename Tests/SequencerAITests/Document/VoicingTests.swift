import XCTest
@testable import SequencerAI

final class VoicingTests: XCTestCase {
    func test_single_sets_default_destination() {
        let destination = Destination.midi(port: .sequencerAIOut, channel: 0, noteOffset: 0)
        XCTAssertEqual(Voicing.single(destination).defaultDestination, destination)
    }

    func test_missing_tag_defaults_to_none() {
        let voicing = Voicing(destinations: [
            "kick": .internalSampler(bankID: .drumKitDefault, preset: "kick-909"),
            "snare": .internalSampler(bankID: .drumKitDefault, preset: "snare-909"),
        ])

        XCTAssertEqual(voicing.destination(for: "cowbell"), .none)
    }

    func test_voicing_round_trips_through_codable() throws {
        let original = Voicing(destinations: [
            Voicing.defaultTag: .auInstrument(
                componentID: AudioComponentID(type: "aumu", subtype: "DLS ", manufacturer: "appl", version: 1),
                stateBlob: nil
            ),
            "kick": .internalSampler(bankID: .drumKitDefault, preset: "kick-909"),
        ])

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Voicing.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func test_set_default_replaces_default_destination() {
        var voicing = Voicing.single(.none)
        let next = Destination.midi(port: .sequencerAIOut, channel: 3, noteOffset: 2)

        voicing.setDefault(next)

        XCTAssertEqual(voicing.defaultDestination, next)
    }

    func test_defaults_for_melodic_tracks_start_unassigned() {
        XCTAssertEqual(Voicing.defaults(forType: .monoMelodic).defaultDestination, .none)
        XCTAssertEqual(Voicing.defaults(forType: .polyMelodic).defaultDestination, .none)
    }

    func test_defaults_for_slice_tracks_seed_internal_sampler_default() {
        XCTAssertEqual(
            Voicing.defaults(forType: .slice).defaultDestination,
            .internalSampler(bankID: .sliceDefault, preset: "empty-slice")
        )
    }
}
