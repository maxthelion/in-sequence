import XCTest
@testable import SequencerAI

private typealias EngineStream = SequencerAI.Stream

final class NoteGeneratorTests: XCTestCase {
    func test_default_config_emits_note_every_tick_and_cycles_pitches() {
        let generator = NoteGenerator(id: "gen")

        let events = (0..<16).flatMap { tick in
            notes(from: generator.tick(context: makeContext(tick: UInt64(tick))))
        }

        XCTAssertEqual(events.count, 16)
        XCTAssertEqual(events.map(\.pitch), [60, 62, 64, 65, 67, 69, 71, 72, 60, 62, 64, 65, 67, 69, 71, 72])
        XCTAssertTrue(events.allSatisfy { $0.velocity == 100 && $0.length == 4 && $0.gate })
    }

    func test_step_pattern_disables_every_other_note() {
        let generator = NoteGenerator(id: "gen", params: [
            "stepPattern": .integers([1, 0, 1, 0])
        ])

        let outputs = (0..<8).map { tick in
            notes(from: generator.tick(context: makeContext(tick: UInt64(tick))))
        }

        XCTAssertEqual(outputs.filter { !$0.isEmpty }.count, 4)
    }

    func test_all_false_step_pattern_never_emits_notes() {
        let generator = NoteGenerator(id: "gen", params: [
            "stepPattern": .integers([0])
        ])

        for tick in 0..<8 {
            XCTAssertTrue(notes(from: generator.tick(context: makeContext(tick: UInt64(tick)))).isEmpty)
        }
    }

    func test_accent_pattern_boosts_step_velocity() {
        let generator = NoteGenerator(id: "gen", params: [
            "stepPattern": .integers([1, 1]),
            "accentPattern": .integers([0, 1]),
            "velocity": .number(90)
        ])

        let first = notes(from: generator.tick(context: makeContext(tick: 0)))
        let second = notes(from: generator.tick(context: makeContext(tick: 1)))

        XCTAssertEqual(first.first?.velocity, 90)
        XCTAssertEqual(second.first?.velocity, 110)
    }

    func test_registers_in_block_registry_under_note_generator() throws {
        let registry = BlockRegistry()

        try registerCoreBlocks(registry)
        let block = registry.make(kindID: "note-generator", blockID: "gen")

        XCTAssertTrue(block is NoteGenerator)
    }

    private func makeContext(tick: UInt64) -> TickContext {
        TickContext(tickIndex: tick, bpm: 120, inputs: [:], now: 0)
    }

    private func notes(from outputs: [PortID: EngineStream]) -> [NoteEvent] {
        guard case let .notes(events)? = outputs["notes"] else {
            return []
        }
        return events
    }
}
