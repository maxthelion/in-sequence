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
        let group = DispatchGroup()

        for index in 0..<100 {
            DispatchQueue.global().async(group: group) {
                queue.enqueue(
                    ScheduledEvent(
                        scheduledHostTime: Double(index),
                        payload: .chordContextBroadcast(lane: "\(index)", chord: chord)
                    )
                )
            }
        }

        group.wait()

        XCTAssertEqual(queue.count, 100)
        XCTAssertEqual(queue.drain().count, 100)
        XCTAssertTrue(queue.isEmpty)
    }
}
