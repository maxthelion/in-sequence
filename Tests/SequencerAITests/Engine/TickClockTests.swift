import XCTest
@testable import SequencerAI

final class TickClockTests: XCTestCase {
    func test_tick_intervals_match_expected_bpm() {
        let clock = TickClock(stepsPerBar: 16)
        clock.bpm = 240

        let ticks = expectation(description: "clock ticks")
        ticks.expectedFulfillmentCount = 11

        let timestamps = LockedTimestamps()
        clock.start { _, now in
            timestamps.append(now)
            ticks.fulfill()
        }

        wait(for: [ticks], timeout: 2.0)
        clock.stop()

        let deltas = timestamps.deltas()
        XCTAssertEqual(deltas.count, 10)
        for delta in deltas {
            XCTAssertEqual(delta, 0.0625, accuracy: 0.008)
        }
    }

    func test_stop_inside_handler_prevents_future_ticks() {
        let clock = TickClock(stepsPerBar: 16)
        let stopped = expectation(description: "clock stopped")
        let sawTickAfterStop = LockedFlag()

        clock.start { tickIndex, _ in
            if tickIndex == 0 {
                clock.stop()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    stopped.fulfill()
                }
            } else {
                sawTickAfterStop.setTrue()
            }
        }

        wait(for: [stopped], timeout: 1.0)
        XCTAssertFalse(sawTickAfterStop.value)
    }

    func test_bpm_change_affects_next_tick_interval() {
        let clock = TickClock(stepsPerBar: 16)
        clock.bpm = 240

        let ticks = expectation(description: "bpm changed")
        ticks.expectedFulfillmentCount = 4

        let timestamps = LockedTimestamps()
        clock.start { tickIndex, now in
            timestamps.append(now)
            if tickIndex == 1 {
                clock.bpm = 120
            }
            ticks.fulfill()
        }

        wait(for: [ticks], timeout: 2.0)
        clock.stop()

        let deltas = timestamps.deltas()
        XCTAssertGreaterThanOrEqual(deltas.count, 3)
        XCTAssertEqual(deltas[0], 0.0625, accuracy: 0.008)
        XCTAssertEqual(deltas[1], 0.125, accuracy: 0.008)
    }

    func test_tick_index_starts_at_zero_and_increments_without_gaps() {
        let clock = TickClock(stepsPerBar: 16)
        let ticks = expectation(description: "index sequence")
        ticks.expectedFulfillmentCount = 5
        let indexes = LockedIndexes()

        clock.start { tickIndex, _ in
            indexes.append(tickIndex)
            ticks.fulfill()
        }

        wait(for: [ticks], timeout: 1.0)
        clock.stop()

        XCTAssertEqual(indexes.values, [0, 1, 2, 3, 4])
    }
}

private final class LockedTimestamps: @unchecked Sendable {
    private var values: [TimeInterval] = []
    private let lock = NSLock()

    func append(_ value: TimeInterval) {
        lock.lock()
        values.append(value)
        lock.unlock()
    }

    func deltas() -> [TimeInterval] {
        lock.lock()
        let snapshot = values
        lock.unlock()

        guard snapshot.count > 1 else {
            return []
        }

        return zip(snapshot, snapshot.dropFirst()).map { $1 - $0 }
    }
}

private final class LockedIndexes: @unchecked Sendable {
    private var storage: [UInt64] = []
    private let lock = NSLock()

    func append(_ value: UInt64) {
        lock.lock()
        storage.append(value)
        lock.unlock()
    }

    var values: [UInt64] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var storage = false

    func setTrue() {
        lock.lock()
        storage = true
        lock.unlock()
    }

    var value: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}
