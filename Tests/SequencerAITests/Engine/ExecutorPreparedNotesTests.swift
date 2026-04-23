import XCTest
@testable import SequencerAI

final class ExecutorPreparedNotesTests: XCTestCase {
    func test_prepared_notes_reach_note_generator_without_json_param() throws {
        let queue = CommandQueue()
        let generator = NoteGenerator(id: "gen")
        let executor = try Executor(
            blocks: ["gen": generator],
            wiring: [:],
            commandQueue: queue
        )

        let prepared = [
            NoteEvent(pitch: 72, velocity: 100, length: 4, gate: true, voiceTag: "prepared")
        ]
        let outputs = executor.tick(now: 0, preparedNotesByBlockID: ["gen": prepared])

        guard case let .notes(events)? = outputs["gen"]?["notes"] else {
            return XCTFail("Expected prepared note output")
        }
        XCTAssertEqual(events, prepared)
    }
}
