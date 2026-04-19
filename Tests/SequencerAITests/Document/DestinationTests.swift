import Foundation
import XCTest
@testable import SequencerAI

final class DestinationTests: XCTestCase {
    func test_destination_round_trips_each_variant() throws {
        let cases: [Destination] = [
            .midi(port: .sequencerAIOut, channel: 9, noteOffset: -12),
            .auInstrument(
                componentID: AudioComponentID(type: "aumu", subtype: "DLS ", manufacturer: "appl", version: 1),
                stateBlob: Data(repeating: 0xAB, count: 64)
            ),
            .internalSampler(bankID: .drumKitDefault, preset: "kick-909"),
            .none,
        ]

        for destination in cases {
            let data = try JSONEncoder().encode(destination)
            let decoded = try JSONDecoder().decode(Destination.self, from: data)
            XCTAssertEqual(decoded, destination)
        }
    }

    func test_none_uses_em_dash_kind_label() {
        XCTAssertEqual(Destination.none.kindLabel, "—")
    }

    func test_audio_component_display_key_uses_manufacturer_type_and_subtype() {
        let id = AudioComponentID(type: "aumu", subtype: "Sero", manufacturer: "XfnZ", version: 12)
        XCTAssertEqual(id.displayKey, "XfnZ.aumu.Sero")
    }

    func test_midi_endpoint_name_equality_is_value_based() {
        XCTAssertEqual(
            MIDIEndpointName(displayName: "SequencerAI Out", isVirtual: true),
            MIDIEndpointName(displayName: "SequencerAI Out", isVirtual: true)
        )
    }
}
