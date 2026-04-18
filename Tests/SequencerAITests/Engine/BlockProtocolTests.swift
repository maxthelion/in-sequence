import XCTest
@testable import SequencerAI

private typealias EngineStream = SequencerAI.Stream

final class BlockProtocolTests: XCTestCase {
    func test_trivial_block_ticks_and_applies_param_updates() {
        let block = LevelBlock(id: "level")

        XCTAssertEqual(
            block.tick(context: makeContext()).valueOutput,
            SequencerAI.Stream.scalar(0.5)
        )

        block.apply(paramKey: "level", value: .number(0.8))

        XCTAssertEqual(
            block.tick(context: makeContext()).valueOutput,
            SequencerAI.Stream.scalar(0.8)
        )
    }

    func test_unknown_param_key_is_ignored_without_crashing() {
        let block = LevelBlock(id: "level")

        block.apply(paramKey: "unknown", value: .number(0.2))

        XCTAssertEqual(
            block.tick(context: makeContext()).valueOutput,
            SequencerAI.Stream.scalar(0.5)
        )
    }

    private func makeContext() -> TickContext {
        TickContext(tickIndex: 0, bpm: 120, inputs: [:], now: 0)
    }
}

private final class LevelBlock: Block {
    static let inputs: [PortSpec] = []
    static let outputs: [PortSpec] = [
        PortSpec(id: "value", streamKind: .scalar)
    ]

    let id: BlockID
    private var level: Double = 0.5

    init(id: BlockID) {
        self.id = id
    }

    func tick(context: TickContext) -> [PortID: EngineStream] {
        ["value": EngineStream.scalar(level)]
    }

    func apply(paramKey: String, value: ParamValue) {
        guard case let ("level", .number(nextLevel)) = (paramKey, value) else {
            return
        }
        level = nextLevel
    }
}

private extension Dictionary where Key == PortID, Value == EngineStream {
    var valueOutput: EngineStream? {
        self["value"]
    }
}
