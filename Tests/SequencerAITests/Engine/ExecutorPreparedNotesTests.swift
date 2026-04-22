import XCTest
@testable import SequencerAI

final class ExecutorPreparedNotesTests: XCTestCase {
    func test_preparedNotes_override_generator_output_for_one_tick() throws {
        let generator = NoteGenerator(id: "gen")
        let executor = try Executor(
            blocks: ["gen": generator],
            wiring: [:],
            commandQueue: CommandQueue(capacity: 8)
        )

        let firstOutputs = executor.tick(
            now: 0,
            preparedNotesByBlockID: [
                "gen": [NoteEvent(pitch: 72, velocity: 88, length: 6, gate: true, voiceTag: "lead")]
            ]
        )
        let secondOutputs = executor.tick(now: 0.25)

        XCTAssertEqual(notes(from: firstOutputs).map(\.pitch), [72])
        XCTAssertEqual(notes(from: firstOutputs).map(\.velocity), [88])
        XCTAssertEqual(notes(from: firstOutputs).map(\.voiceTag), ["lead"])
        XCTAssertEqual(notes(from: secondOutputs).map(\.pitch), [62], "next tick should fall back to the generator program")
    }

    private func notes(from outputs: [BlockID: [PortID: Stream]]) -> [NoteEvent] {
        guard case let .notes(events)? = outputs["gen"]?["notes"] else {
            return []
        }
        return events
    }
}
