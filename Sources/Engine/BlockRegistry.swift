struct BlockKind: Sendable {
    let id: String
    let inputs: [PortSpec]
    let outputs: [PortSpec]
    let make: @Sendable (BlockID, [String: ParamValue]) -> Block
}

extension BlockKind: Equatable {
    static func == (lhs: BlockKind, rhs: BlockKind) -> Bool {
        lhs.id == rhs.id &&
        lhs.inputs == rhs.inputs &&
        lhs.outputs == rhs.outputs
    }
}

func registerCoreBlocks(_ registry: BlockRegistry) throws {
    try registry.register(
        BlockKind(
            id: "note-generator",
            inputs: NoteGenerator.inputs,
            outputs: NoteGenerator.outputs
        ) { blockID, params in
            NoteGenerator(id: blockID, params: params)
        }
    )
    try registry.register(
        BlockKind(
            id: "midi-out",
            inputs: MidiOut.inputs,
            outputs: MidiOut.outputs
        ) { blockID, params in
            MidiOut(id: blockID, params: params)
        }
    )
    try registry.register(
        BlockKind(
            id: "chord-context-sink",
            inputs: ChordContextSink.inputs,
            outputs: ChordContextSink.outputs
        ) { blockID, _ in
            ChordContextSink(id: blockID) { _ in }
        }
    )
}

final class BlockRegistry {
    enum RegistryError: Swift.Error, Equatable {
        case duplicate(String)
    }

    private var storage: [String: BlockKind] = [:]

    func register(_ kind: BlockKind) throws {
        guard storage[kind.id] == nil else {
            throw RegistryError.duplicate(kind.id)
        }
        storage[kind.id] = kind
    }

    func kinds() -> [BlockKind] {
        Array(storage.values)
    }

    func make(kindID: String, blockID: BlockID, params: [String: ParamValue] = [:]) -> Block? {
        storage[kindID]?.make(blockID, params)
    }
}
