import Foundation

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

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return events.count
    }

    var isEmpty: Bool {
        count == 0
    }
}
