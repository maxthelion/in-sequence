import XCTest
@testable import SequencerAI

private typealias EngineStream = SequencerAI.Stream

final class BlockRegistryTests: XCTestCase {
    func test_register_and_make_kind_by_identifier() throws {
        let registry = BlockRegistry()
        let kind = testKind(id: "test-kind")

        try registry.register(kind)
        let block = registry.make(kindID: "test-kind", blockID: "instance", params: ["label": .text("hello")])

        XCTAssertEqual((block as? RegistryTestBlock)?.id, "instance")
        XCTAssertEqual((block as? RegistryTestBlock)?.label, "hello")
    }

    func test_unknown_kind_returns_nil() {
        let registry = BlockRegistry()

        XCTAssertNil(registry.make(kindID: "missing", blockID: "instance"))
    }

    func test_kinds_reflect_registrations() throws {
        let registry = BlockRegistry()
        try registry.register(testKind(id: "a"))
        try registry.register(testKind(id: "b"))

        XCTAssertEqual(Set(registry.kinds().map(\.id)), ["a", "b"])
    }

    func test_duplicate_registration_throws() throws {
        let registry = BlockRegistry()
        let kind = testKind(id: "duplicate")
        try registry.register(kind)

        XCTAssertThrowsError(try registry.register(kind)) { error in
            XCTAssertEqual(error as? BlockRegistry.RegistryError, .duplicate("duplicate"))
        }
    }

    private func testKind(id: String) -> BlockKind {
        BlockKind(
            id: id,
            inputs: [],
            outputs: [PortSpec(id: "value", streamKind: .scalar)]
        ) { blockID, params in
            RegistryTestBlock(
                id: blockID,
                label: params["label"].flatMap {
                    if case let .text(value) = $0 { return value }
                    return nil
                } ?? "default"
            )
        }
    }
}

private final class RegistryTestBlock: Block {
    static let inputs: [PortSpec] = []
    static let outputs: [PortSpec] = [PortSpec(id: "value", streamKind: .scalar)]

    let id: BlockID
    let label: String

    init(id: BlockID, label: String) {
        self.id = id
        self.label = label
    }

    func tick(context: TickContext) -> [PortID: EngineStream] {
        ["value": EngineStream.scalar(1.0)]
    }

    func apply(paramKey: String, value: ParamValue) {}
}
