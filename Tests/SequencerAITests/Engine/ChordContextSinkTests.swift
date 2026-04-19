import XCTest
@testable import SequencerAI

final class ChordContextSinkTests: XCTestCase {
    func test_tick_publishes_chord_input() {
        let expected = Chord(root: 60, chordType: "majorTriad", scale: "major")
        var published: [Chord] = []
        let sink = ChordContextSink(id: "chord-sink") { published.append($0) }

        let outputs = sink.tick(
            context: TickContext(
                tickIndex: 0,
                bpm: 120,
                inputs: ["chord": .chord(expected)],
                now: 0
            )
        )

        XCTAssertEqual(outputs, [:])
        XCTAssertEqual(published, [expected])
    }

    func test_tick_publishes_each_new_chord_value() {
        let cMajor = Chord(root: 60, chordType: "majorTriad", scale: "major")
        let gMinor = Chord(root: 67, chordType: "minorTriad", scale: "dorian")
        var published: [Chord] = []
        let sink = ChordContextSink(id: "chord-sink") { published.append($0) }

        _ = sink.tick(context: TickContext(tickIndex: 0, bpm: 120, inputs: ["chord": .chord(cMajor)], now: 0))
        _ = sink.tick(context: TickContext(tickIndex: 1, bpm: 120, inputs: ["chord": .chord(gMinor)], now: 0.25))

        XCTAssertEqual(published, [cMajor, gMinor])
    }

    func test_tick_ignores_non_chord_streams() {
        var published: [Chord] = []
        let sink = ChordContextSink(id: "chord-sink") { published.append($0) }

        let outputs = sink.tick(
            context: TickContext(
                tickIndex: 0,
                bpm: 120,
                inputs: ["chord": .scalar(0.5)],
                now: 0
            )
        )

        XCTAssertEqual(outputs, [:])
        XCTAssertTrue(published.isEmpty)
    }
}
