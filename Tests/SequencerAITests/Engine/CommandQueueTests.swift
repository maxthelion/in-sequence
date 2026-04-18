import XCTest
@testable import SequencerAI

final class CommandQueueTests: XCTestCase {
    func test_drain_returns_fifo_order() {
        let queue = CommandQueue(capacity: 4)
        let commands: [Command] = [
            .setBPM(120),
            .setBPM(140),
            .setParam(blockID: "gen", paramKey: "level", value: .number(0.8))
        ]

        commands.forEach { XCTAssertTrue(queue.enqueue($0)) }

        XCTAssertEqual(queue.drainAll(), commands)
    }

    func test_enqueue_past_capacity_drops_commands() {
        let queue = CommandQueue(capacity: 2)

        XCTAssertTrue(queue.enqueue(.setBPM(120)))
        XCTAssertTrue(queue.enqueue(.setBPM(140)))
        XCTAssertFalse(queue.enqueue(.setBPM(160)))

        XCTAssertEqual(queue.droppedCount, 1)
        XCTAssertEqual(queue.drainAll(), [.setBPM(120), .setBPM(140)])
    }

    func test_enqueue_from_background_queue_and_drain_on_main() {
        let queue = CommandQueue(capacity: 8)
        let expectation = expectation(description: "background enqueue")

        DispatchQueue.global().async {
            XCTAssertTrue(queue.enqueue(.setBPM(120)))
            XCTAssertTrue(queue.enqueue(.setBPM(240)))
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
        XCTAssertEqual(queue.drainAll(), [.setBPM(120), .setBPM(240)])
    }

    func test_stress_accounts_for_all_commands() {
        let queue = CommandQueue(capacity: 1200)
        let producerExpectation = expectation(description: "producer finished")

        DispatchQueue.global().async {
            for index in 0..<1000 {
                _ = queue.enqueue(.setBPM(Double(index)))
            }
            producerExpectation.fulfill()
        }

        var drainedCount = 0
        for _ in 0..<10 {
            drainedCount += queue.drainAll().count
        }

        wait(for: [producerExpectation], timeout: 2.0)
        drainedCount += queue.drainAll().count

        XCTAssertEqual(drainedCount + Int(queue.droppedCount), 1000)
    }
}
