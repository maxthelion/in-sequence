import XCTest
@testable import SequencerAI

final class StreamTests: XCTestCase {
    func test_notes_stream_is_equatable_and_sendable() {
        let stream = Stream.notes([
            NoteEvent(pitch: 60, velocity: 100, length: 4, gate: true, voiceTag: "kick")
        ])

        XCTAssertEqual(stream, stream)
        XCTAssertEqual(roundTrip(stream), stream)
    }

    func test_scalar_stream_is_equatable_and_sendable() {
        let stream = Stream.scalar(0.5)

        XCTAssertEqual(stream, stream)
        XCTAssertEqual(roundTrip(stream), stream)
    }

    func test_chord_stream_is_equatable_and_sendable() {
        let stream = Stream.chord(
            Chord(root: 60, chordType: "maj7", scale: "ionian")
        )

        XCTAssertEqual(stream, stream)
        XCTAssertEqual(roundTrip(stream), stream)
    }

    func test_event_stream_is_equatable_and_sendable() {
        let stream = Stream.event(.custom("fill"))

        XCTAssertEqual(stream, stream)
        XCTAssertEqual(roundTrip(stream), stream)
    }

    func test_gate_stream_is_equatable_and_sendable() {
        let stream = Stream.gate(true)

        XCTAssertEqual(stream, stream)
        XCTAssertEqual(roundTrip(stream), stream)
    }

    func test_step_index_stream_is_equatable_and_sendable() {
        let stream = Stream.stepIndex(7)

        XCTAssertEqual(stream, stream)
        XCTAssertEqual(roundTrip(stream), stream)
    }

    private func roundTrip<T: Sendable>(_ value: T) -> T {
        let body: @Sendable (T) -> T = { $0 }
        return body(value)
    }
}
