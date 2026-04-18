import Dispatch

final class CommandQueue {
    private let capacity: Int
    private let queue = DispatchQueue(label: "ai.sequencer.engine.command-queue")
    private var commands: [Command] = []
    private var dropped: UInt64 = 0

    init(capacity: Int = 1024) {
        self.capacity = capacity
    }

    @discardableResult
    func enqueue(_ command: Command) -> Bool {
        queue.sync {
            guard commands.count < capacity else {
                dropped += 1
                return false
            }
            commands.append(command)
            return true
        }
    }

    func drainAll() -> [Command] {
        queue.sync {
            let drained = commands
            commands.removeAll(keepingCapacity: true)
            return drained
        }
    }

    var droppedCount: UInt64 {
        queue.sync { dropped }
    }
}
