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
        _ = client.inputEndpoints
        _ = client.outputEndpoints
    }

    func test_endpoint_has_non_empty_display_name_when_present() throws {
        let client = try MIDIClient(name: "SequencerAITest")
        for endpoint in client.inputEndpoints + client.outputEndpoints {
            XCTAssertFalse(endpoint.displayName.isEmpty)
        }
    }
}
