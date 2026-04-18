import XCTest
@testable import SequencerAI

private typealias EngineStream = SequencerAI.Stream

final class ExecutorTests: XCTestCase {
    func test_single_block_graph_returns_output() throws {
        let queue = CommandQueue()
        let source = ConstantSourceBlock(id: "source", value: .scalar(0.5))
        let executor = try Executor(blocks: ["source": source], wiring: [:], commandQueue: queue)

        let outputs = executor.tick(now: 1.0)

        XCTAssertEqual(outputs["source"]?["value"], SequencerAI.Stream.scalar(0.5))
    }

    func test_two_block_chain_passes_outputs_downstream() throws {
        let queue = CommandQueue()
        let source = ConstantSourceBlock(id: "source", value: .scalar(0.5))
        let transform = ForwardingBlock(id: "transform")
        let executor = try Executor(
            blocks: ["source": source, "transform": transform],
            wiring: ["transform": ["input": ("source", "value")]],
            commandQueue: queue
        )

        let outputs = executor.tick(now: 1.0)

        XCTAssertEqual(outputs["transform"]?["output"], SequencerAI.Stream.scalar(0.5))
    }

    func test_cycle_detection_throws_at_init() {
        let queue = CommandQueue()
        let a = ForwardingBlock(id: "a")
        let b = ForwardingBlock(id: "b")

        XCTAssertThrowsError(try Executor(
            blocks: ["a": a, "b": b],
            wiring: [
                "a": ["input": ("b", "output")],
                "b": ["input": ("a", "output")]
            ],
            commandQueue: queue
        )) { error in
            guard case let Executor.Error.cycleDetected(path) = error else {
                XCTFail("Expected cycleDetected, got \(error)")
                return
            }
            XCTAssertTrue(path.contains("a"))
            XCTAssertTrue(path.contains("b"))
        }
    }

    func test_missing_upstream_throws_at_init() {
        let queue = CommandQueue()
        let block = ForwardingBlock(id: "transform")

        XCTAssertThrowsError(try Executor(
            blocks: ["transform": block],
            wiring: [:],
            commandQueue: queue
        )) { error in
            XCTAssertEqual(
                error as? Executor.Error,
                .missingUpstream(blockID: "transform", portID: "input")
            )
        }
    }

    func test_stream_kind_mismatch_throws_at_init() {
        let queue = CommandQueue()
        let source = ConstantSourceBlock(id: "source", value: SequencerAI.Stream.scalar(0.5))
        let sink = GateInputBlock(id: "sink")

        XCTAssertThrowsError(try Executor(
            blocks: ["source": source, "sink": sink],
            wiring: ["sink": ["gate": ("source", "value")]],
            commandQueue: queue
        )) { error in
            XCTAssertEqual(
                error as? Executor.Error,
                .streamKindMismatch(blockID: "sink", portID: "gate", expected: .gate, got: .scalar)
            )
        }
    }

    func test_tick_index_increments_on_each_tick() throws {
        let queue = CommandQueue()
        let source = TickRecordingBlock(id: "source")
        let executor = try Executor(blocks: ["source": source], wiring: [:], commandQueue: queue)

        _ = executor.tick(now: 1.0)
        _ = executor.tick(now: 2.0)

        XCTAssertEqual(source.observedTickIndexes, [0, 1])
    }

    func test_command_drain_applies_param_before_tick() throws {
        let queue = CommandQueue()
        let block = AdjustableScalarBlock(id: "b")
        let executor = try Executor(blocks: ["b": block], wiring: [:], commandQueue: queue)
        XCTAssertTrue(queue.enqueue(.setParam(blockID: "b", paramKey: "level", value: .number(0.8))))

        let outputs = executor.tick(now: 1.0)

        XCTAssertEqual(block.appliedParams, ["level"])
        XCTAssertEqual(outputs["b"]?["value"], SequencerAI.Stream.scalar(0.8))
    }

    func test_command_drain_updates_bpm() throws {
        let queue = CommandQueue()
        let block = TickRecordingBlock(id: "source")
        let executor = try Executor(blocks: ["source": block], wiring: [:], commandQueue: queue)
        XCTAssertTrue(queue.enqueue(.setBPM(240)))

        _ = executor.tick(now: 1.0)

        XCTAssertEqual(executor.currentBPM, 240)
        XCTAssertEqual(block.observedBPMs, [240])
    }

    func test_command_for_unknown_block_is_ignored() throws {
        let queue = CommandQueue()
        let block = AdjustableScalarBlock(id: "existing")
        let executor = try Executor(blocks: ["existing": block], wiring: [:], commandQueue: queue)
        XCTAssertTrue(queue.enqueue(.setParam(blockID: "missing", paramKey: "level", value: .number(0.8))))

        let outputs = executor.tick(now: 1.0)

        XCTAssertTrue(block.appliedParams.isEmpty)
        XCTAssertEqual(outputs["existing"]?["value"], SequencerAI.Stream.scalar(0.5))
    }
}

private final class ConstantSourceBlock: Block {
    static let inputs: [PortSpec] = []
    static let outputs: [PortSpec] = [PortSpec(id: "value", streamKind: .scalar)]

    let id: BlockID
    private let value: EngineStream

    init(id: BlockID, value: EngineStream) {
        self.id = id
        self.value = value
    }

    func tick(context: TickContext) -> [PortID: EngineStream] {
        ["value": value]
    }

    func apply(paramKey: String, value: ParamValue) {}
}

private final class ForwardingBlock: Block {
    static let inputs: [PortSpec] = [PortSpec(id: "input", streamKind: .scalar)]
    static let outputs: [PortSpec] = [PortSpec(id: "output", streamKind: .scalar)]

    let id: BlockID

    init(id: BlockID) {
        self.id = id
    }

    func tick(context: TickContext) -> [PortID: EngineStream] {
        ["output": context.inputs["input"] ?? EngineStream.scalar(0)]
    }

    func apply(paramKey: String, value: ParamValue) {}
}

private final class GateInputBlock: Block {
    static let inputs: [PortSpec] = [PortSpec(id: "gate", streamKind: .gate)]
    static let outputs: [PortSpec] = []

    let id: BlockID

    init(id: BlockID) {
        self.id = id
    }

    func tick(context: TickContext) -> [PortID: EngineStream] { [:] }
    func apply(paramKey: String, value: ParamValue) {}
}

private final class TickRecordingBlock: Block {
    static let inputs: [PortSpec] = []
    static let outputs: [PortSpec] = [PortSpec(id: "value", streamKind: .scalar)]

    let id: BlockID
    private(set) var observedTickIndexes: [UInt64] = []
    private(set) var observedBPMs: [Double] = []

    init(id: BlockID) {
        self.id = id
    }

    func tick(context: TickContext) -> [PortID: EngineStream] {
        observedTickIndexes.append(context.tickIndex)
        observedBPMs.append(context.bpm)
        return ["value": EngineStream.scalar(Double(context.tickIndex))]
    }

    func apply(paramKey: String, value: ParamValue) {}
}

private final class AdjustableScalarBlock: Block {
    static let inputs: [PortSpec] = []
    static let outputs: [PortSpec] = [PortSpec(id: "value", streamKind: .scalar)]

    let id: BlockID
    private var level: Double = 0.5
    private(set) var appliedParams: [String] = []

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
        appliedParams.append(paramKey)
        level = nextLevel
    }
}
