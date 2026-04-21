import XCTest
@testable import SequencerAI

final class EventQueueTests: XCTestCase {
    func test_enqueue_thenDrain_returnsEventsInFIFOOrder() {
        let queue = EventQueue()
        let chord = Chord(root: 60, chordType: "majorTriad", scale: "major")
        let first = ScheduledEvent(
            scheduledHostTime: 1.0,
            payload: .chordContextBroadcast(lane: "a", chord: chord)
        )
        let second = ScheduledEvent(
            scheduledHostTime: 2.0,
            payload: .chordContextBroadcast(lane: "b", chord: chord)
        )

        queue.enqueue(first)
        queue.enqueue(second)

        XCTAssertEqual(queue.count, 2)
        XCTAssertEqual(queue.drain(), [first, second])
        XCTAssertTrue(queue.isEmpty)
    }

    func test_drain_clearsQueue() {
        let queue = EventQueue()
        let chord = Chord(root: 60, chordType: "majorTriad", scale: "major")

        queue.enqueue(
            ScheduledEvent(
                scheduledHostTime: 0,
                payload: .chordContextBroadcast(lane: "x", chord: chord)
            )
        )

        _ = queue.drain()

        XCTAssertTrue(queue.isEmpty)
        XCTAssertEqual(queue.count, 0)
    }

    func test_concurrentEnqueueAndDrain_doesNotCorruptState() {
        let queue = EventQueue()
        let chord = Chord(root: 60, chordType: "majorTriad", scale: "major")
        let producers = DispatchGroup()
        let drainerFinished = DispatchGroup()
        let stopDraining = DispatchSemaphore(value: 0)
        let drainedStore = LockedLaneStore()

        drainerFinished.enter()
        DispatchQueue.global().async {
            while stopDraining.wait(timeout: .now()) == .timedOut {
                drainedStore.append(queue.drain())
            }
            drainedStore.append(queue.drain())
            drainerFinished.leave()
        }

        for index in 0..<100 {
            DispatchQueue.global().async(group: producers) {
                queue.enqueue(
                    ScheduledEvent(
                        scheduledHostTime: Double(index),
                        payload: .chordContextBroadcast(lane: "\(index)", chord: chord)
                    )
                )
            }
        }

        producers.wait()
        stopDraining.signal()
        drainerFinished.wait()

        let drainedLanes = Set(drainedStore.events.compactMap { event -> String? in
            guard case let .chordContextBroadcast(lane, _) = event.payload else {
                return nil
            }
            return lane
        })

        XCTAssertEqual(drainedLanes.count, 100)
        XCTAssertTrue(queue.isEmpty)
    }
    func test_sampleTriggerPayload_equatable() {
        let trackID = UUID()
        let sampleID = UUID()
        let a = ScheduledEvent(
            scheduledHostTime: 1.0,
            payload: .sampleTrigger(trackID: trackID, sampleID: sampleID, settings: .default, scheduledHostTime: 1.0)
        )
        let b = ScheduledEvent(
            scheduledHostTime: 1.0,
            payload: .sampleTrigger(trackID: trackID, sampleID: sampleID, settings: .default, scheduledHostTime: 1.0)
        )
        let c = ScheduledEvent(
            scheduledHostTime: 1.0,
            payload: .sampleTrigger(trackID: trackID, sampleID: UUID(), settings: .default, scheduledHostTime: 1.0)
        )
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}

private final class LockedLaneStore: @unchecked Sendable {
    private let lock = NSLock()
    private(set) var events: [ScheduledEvent] = []

    func append(_ newEvents: [ScheduledEvent]) {
        lock.lock()
        defer { lock.unlock() }
        events.append(contentsOf: newEvents)
    }
}
