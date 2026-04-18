import XCTest
@testable import SequencerAI

final class MIDIClientTests: XCTestCase {
    func test_client_initializes_without_error() throws {
        let client = try MIDIClient(name: "SequencerAITest")
        XCTAssertEqual(client.name, "SequencerAITest")
    }

    func test_endpoints_are_enumerable() throws {
        let client = try MIDIClient(name: "SequencerAITest")
        // May be empty if no MIDI hardware is connected — the call must not crash.
        _ = client.sources
        _ = client.destinations
    }

    func test_endpoint_has_non_empty_display_name_when_present() throws {
        let client = try MIDIClient(name: "SequencerAITest")
        for endpoint in client.sources + client.destinations {
            XCTAssertFalse(endpoint.displayName.isEmpty)
        }
    }
}

extension MIDIClientTests {
    func test_can_create_virtual_output_endpoint() throws {
        let client = try MIDIClient(name: "SequencerAITest")
        let endpoint = try client.createVirtualOutput(name: "SequencerAI Out")
        XCTAssertEqual(endpoint.displayName, "SequencerAI Out")
        XCTAssertEqual(endpoint.role, .source)
    }

    func test_can_create_virtual_input_endpoint() throws {
        let client = try MIDIClient(name: "SequencerAITest")
        let endpoint = try client.createVirtualInput(name: "SequencerAI In") { _ in }
        XCTAssertEqual(endpoint.displayName, "SequencerAI In")
        XCTAssertEqual(endpoint.role, .destination)
    }

    func test_created_virtual_output_appears_in_sources() throws {
        let client = try MIDIClient(name: "SequencerAITest")
        let endpoint = try client.createVirtualOutput(name: "SequencerAI Probe Out")
        let found = client.sources.contains { $0.id == endpoint.id }
        XCTAssertTrue(found, "Created virtual source should be listed in client.sources")
    }
}
