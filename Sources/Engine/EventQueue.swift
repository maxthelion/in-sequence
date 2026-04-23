import Foundation

/// NSLock-backed FIFO queue for timer-driven prepare/dispatch callers.
/// Safe for the current scheduling queue; not intended for the audio render thread.
final class EventQueue {
    private var events: [ScheduledEvent] = []
    private let lock = NSLock()

    func enqueue(_ event: ScheduledEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    func enqueue(_ newEvents: [ScheduledEvent]) {
        guard !newEvents.isEmpty else {
            return
        }

        lock.lock()
        events.append(contentsOf: newEvents)
        lock.unlock()
    }

    func drain() -> [ScheduledEvent] {
        lock.lock()
        defer { lock.unlock() }

        let drained = events
        events.removeAll(keepingCapacity: true)
        return drained
    }

    func clear() {
        lock.lock()
        events.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return events.count
    }

    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return events.isEmpty
    }
}
