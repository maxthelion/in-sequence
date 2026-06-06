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

    @discardableResult
    func cancelRepeatOwnedEvents(for trackIDs: Set<UUID>) -> Int {
        guard !trackIDs.isEmpty else {
            return 0
        }

        lock.lock()
        defer { lock.unlock() }

        let originalCount = events.count
        events.removeAll { event in
            guard let owner = event.repeatOwnerTrackID else {
                return false
            }
            return trackIDs.contains(owner)
        }
        return originalCount - events.count
    }

    func repeatOwnedEventCount(for trackID: UUID) -> Int {
        lock.lock()
        defer { lock.unlock() }
        return events.filter { $0.repeatOwnerTrackID == trackID }.count
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
