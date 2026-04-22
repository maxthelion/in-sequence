import struct Foundation.TimeInterval
import OSLog

final class Executor {
    enum Error: Swift.Error, Equatable {
        case cycleDetected(path: [BlockID])
        case missingUpstream(blockID: BlockID, portID: PortID)
        case streamKindMismatch(blockID: BlockID, portID: PortID, expected: StreamKind, got: StreamKind)
        case unknownBlockID(BlockID)
    }

    private static let logger = Logger(subsystem: "ai.sequencer.SequencerAI", category: "Engine")

    private let blocks: [BlockID: Block]
    private let wiring: [BlockID: [PortID: (BlockID, PortID)]]
    private let commandQueue: CommandQueue
    private let orderedBlockIDs: [BlockID]
    private var tickCounter: UInt64 = 0

    private(set) var currentBPM: Double = 120

    init(
        blocks: [BlockID: Block],
        wiring: [BlockID: [PortID: (BlockID, PortID)]],
        commandQueue: CommandQueue
    ) throws {
        self.blocks = blocks
        self.wiring = wiring
        self.commandQueue = commandQueue

        try Self.validateGraph(blocks: blocks, wiring: wiring)
        self.orderedBlockIDs = try Self.topologicalOrder(blocks: blocks, wiring: wiring)
    }

    func tick(
        now: TimeInterval,
        preparedNotesByBlockID: [BlockID: [NoteEvent]] = [:]
    ) -> [BlockID: [PortID: Stream]] {
        drainCommands()

        var allOutputs: [BlockID: [PortID: Stream]] = [:]

        for blockID in orderedBlockIDs {
            guard let block = blocks[blockID] else {
                continue
            }

            let inputs = resolveInputs(for: blockID, availableOutputs: allOutputs)
            let context = TickContext(
                tickIndex: tickCounter,
                bpm: currentBPM,
                inputs: inputs,
                now: now,
                preparedNotesByBlockID: preparedNotesByBlockID
            )
            allOutputs[blockID] = block.tick(context: context)
        }

        tickCounter += 1
        return allOutputs
    }

    private func resolveInputs(
        for blockID: BlockID,
        availableOutputs: [BlockID: [PortID: Stream]]
    ) -> [PortID: Stream] {
        guard let blockInputs = wiring[blockID] else {
            return [:]
        }

        var resolved: [PortID: Stream] = [:]
        for (inputPortID, upstream) in blockInputs {
            resolved[inputPortID] = availableOutputs[upstream.0]?[upstream.1]
        }
        return resolved
    }

    private func drainCommands() {
        for command in commandQueue.drainAll() {
            switch command {
            case let .setParam(blockID, paramKey, value):
                guard let block = blocks[blockID] else {
                    Self.logger.debug("Dropped setParam for unknown block '\(blockID, privacy: .public)'")
                    continue
                }
                block.apply(paramKey: paramKey, value: value)

            case let .setBPM(bpm):
                currentBPM = bpm
            }
        }
    }

    private static func validateGraph(
        blocks: [BlockID: Block],
        wiring: [BlockID: [PortID: (BlockID, PortID)]]
    ) throws {
        for (blockID, block) in blocks {
            let inputSpecs = Dictionary(uniqueKeysWithValues: type(of: block).inputs.map { ($0.id, $0) })
            let connectedInputs = wiring[blockID] ?? [:]

            for input in inputSpecs.values where input.required && connectedInputs[input.id] == nil {
                throw Error.missingUpstream(blockID: blockID, portID: input.id)
            }

            for (inputPortID, upstream) in connectedInputs {
                guard let inputSpec = inputSpecs[inputPortID] else {
                    throw Error.missingUpstream(blockID: blockID, portID: inputPortID)
                }

                guard let upstreamBlock = blocks[upstream.0] else {
                    throw Error.unknownBlockID(upstream.0)
                }

                let outputSpecs = Dictionary(uniqueKeysWithValues: type(of: upstreamBlock).outputs.map { ($0.id, $0) })
                guard let outputSpec = outputSpecs[upstream.1] else {
                    throw Error.missingUpstream(blockID: blockID, portID: inputPortID)
                }

                guard outputSpec.streamKind == inputSpec.streamKind else {
                    throw Error.streamKindMismatch(
                        blockID: blockID,
                        portID: inputPortID,
                        expected: inputSpec.streamKind,
                        got: outputSpec.streamKind
                    )
                }
            }
        }
    }

    private static func topologicalOrder(
        blocks: [BlockID: Block],
        wiring: [BlockID: [PortID: (BlockID, PortID)]]
    ) throws -> [BlockID] {
        let dependencies = dependencyMap(from: blocks, wiring: wiring)
        var visiting: [BlockID] = []
        var visited = Set<BlockID>()
        var ordered: [BlockID] = []

        func dfs(_ blockID: BlockID) throws {
            if let cycleStart = visiting.firstIndex(of: blockID) {
                let cycle = Array(visiting[cycleStart...]) + [blockID]
                throw Error.cycleDetected(path: cycle)
            }
            guard !visited.contains(blockID) else {
                return
            }

            visiting.append(blockID)
            for dependency in dependencies[blockID, default: []].sorted() {
                try dfs(dependency)
            }
            _ = visiting.popLast()
            visited.insert(blockID)
            ordered.append(blockID)
        }

        for blockID in blocks.keys.sorted() {
            try dfs(blockID)
        }

        return ordered
    }

    private static func dependencyMap(
        from blocks: [BlockID: Block],
        wiring: [BlockID: [PortID: (BlockID, PortID)]]
    ) -> [BlockID: Set<BlockID>] {
        var dependencies = Dictionary(uniqueKeysWithValues: blocks.keys.map { ($0, Set<BlockID>()) })

        for (blockID, blockWiring) in wiring {
            for (_, upstream) in blockWiring {
                dependencies[blockID, default: []].insert(upstream.0)
            }
        }

        return dependencies
    }
}
