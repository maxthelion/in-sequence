import XCTest
@testable import SequencerAI

/// Unit coverage for the global transport swing parameter
/// (`AudioMasterClock.advance(toStep:bpm:swing:)` + the `.setSwing` command
/// drain). Swing delays every off-beat (odd-index) 16th step by
/// `swing * perStep * AudioMasterClock.swingMaxStepFraction`; the interval
/// into the following even (down-beat) step is shortened by the same amount,
/// so 2-step pairs sum to exactly `2 * perStep` and down-beats never drift.
///
/// The end-to-end stamped-frame gates (setSwing → CommandQueue → Executor
/// drain → advance → captured sink stamp, including a mid-stream swing
/// change) live in `OfflineFrameAccuracyTests` alongside the BPM gates.
final class SwingTimingTests: XCTestCase {

    private let stepsPerBar = 16
    private let bpm = 120.0
    /// 60/120 * 4/16 = 0.125 s per 16th at 120 BPM.
    private var perStep: TimeInterval {
        AudioMasterClock.secondsPerStep(bpm: bpm, stepsPerBar: stepsPerBar)
    }

    private func makeClock() -> AudioMasterClock {
        AudioMasterClock(stepsPerBar: stepsPerBar, renderPositionProvider: { nil })
    }

    // MARK: - AudioMasterClock tempo map

    func test_swingZero_isIdenticalToUnswungAccumulator() {
        let unswung = makeClock()
        let swungZero = makeClock()

        for step in 1...8 {
            let a = unswung.advance(toStep: UInt64(step), bpm: bpm)
            let b = swungZero.advance(toStep: UInt64(step), bpm: bpm, swing: 0)
            XCTAssertEqual(a, b, "step \(step): swing 0 must be byte-identical to the default")
        }
    }

    func test_swing_delaysOddSteps_keepsEvenStepsOnGrid_acrossBars() {
        let clock = makeClock()
        let swing = 0.5
        let offset = swing * perStep * AudioMasterClock.swingMaxStepFraction

        // Cross two full bars step-by-step, the way the live pump advances.
        for step in 1...(stepsPerBar * 2) {
            let seconds = clock.advance(toStep: UInt64(step), bpm: bpm, swing: swing)
            let unswungGrid = Double(step) * perStep
            if step % 2 == 1 {
                XCTAssertEqual(
                    seconds, unswungGrid + offset, accuracy: 1e-9,
                    "off-beat step \(step) must be delayed by exactly the swing offset"
                )
            } else {
                XCTAssertEqual(
                    seconds, unswungGrid, accuracy: 1e-9,
                    "down-beat step \(step) must stay on the unswung grid (no drift)"
                )
            }
        }
    }

    func test_swingMax_isTripletFeel() {
        let clock = makeClock()
        let seconds = clock.advance(toStep: 1, bpm: bpm, swing: 1)
        // At swing = 1 the off-beat lands 1/3 step late: 2:1 pair split.
        XCTAssertEqual(seconds, perStep * (4.0 / 3.0), accuracy: 1e-12)
        let downBeat = clock.advance(toStep: 2, bpm: bpm, swing: 1)
        XCTAssertEqual(downBeat, perStep * 2, accuracy: 1e-12)
    }

    func test_swing_clampsToUnitRange() {
        let over = makeClock()
        let atMax = makeClock()
        XCTAssertEqual(
            over.advance(toStep: 1, bpm: bpm, swing: 2.5),
            atMax.advance(toStep: 1, bpm: bpm, swing: 1)
        )

        let under = makeClock()
        let atZero = makeClock()
        XCTAssertEqual(
            under.advance(toStep: 1, bpm: bpm, swing: -1),
            atZero.advance(toStep: 1, bpm: bpm, swing: 0)
        )
    }

    func test_advance_isIdempotent_laterSwingCannotMoveARecordedStep() {
        let clock = makeClock()
        let recorded = clock.advance(toStep: 2, bpm: bpm, swing: 0)
        // Same-step re-advance with a different swing returns the cached value
        // — the guarantee that lets the resolveNow advance and the post-tick
        // advance share one entry per step.
        XCTAssertEqual(clock.advance(toStep: 2, bpm: bpm, swing: 1), recorded)
        // Step 1 was recorded during the crossing to step 2 (swing 0), so a
        // later swung re-advance cannot move it either.
        XCTAssertEqual(clock.advance(toStep: 1, bpm: bpm, swing: 1), perStep, accuracy: 1e-12)
    }

    func test_multiStepAdvance_swingsByAbsoluteStepParity() {
        // One advance crossing several steps must produce the same grid as
        // stepwise advancing: parity comes from the absolute step index, not
        // from the crossing loop's local iteration count.
        let jump = makeClock()
        let stepwise = makeClock()
        let swing = 0.8

        let jumped = jump.advance(toStep: 5, bpm: bpm, swing: swing)
        var last: TimeInterval = 0
        for step in 1...5 {
            last = stepwise.advance(toStep: UInt64(step), bpm: bpm, swing: swing)
        }
        XCTAssertEqual(jumped, last)
        XCTAssertEqual(
            jump.musicalSeconds(forStep: 4), stepwise.musicalSeconds(forStep: 4),
            "intermediate steps recorded by the jump must match the stepwise grid"
        )
    }

    // MARK: - Executor command drain

    func test_executor_drainsSetSwing_beforeResolveNow_noOneTickLag() throws {
        let queue = CommandQueue()
        let executor = try Executor(blocks: [:], wiring: [:], commandQueue: queue)
        XCTAssertTrue(queue.enqueue(.setSwing(0.4)))

        var observedSwing: Double?
        _ = executor.tick(now: 1.0, resolveNow: { _, swing in
            observedSwing = swing
            return 1.0
        })

        XCTAssertEqual(executor.currentSwing, 0.4)
        XCTAssertEqual(
            observedSwing, 0.4,
            "resolveNow must see the post-drain swing — a mid-step setSwing applies to this step"
        )
    }

    func test_executor_clampsSetSwing() throws {
        let queue = CommandQueue()
        let executor = try Executor(blocks: [:], wiring: [:], commandQueue: queue)

        XCTAssertTrue(queue.enqueue(.setSwing(1.5)))
        _ = executor.tick(now: 1.0)
        XCTAssertEqual(executor.currentSwing, 1)

        XCTAssertTrue(queue.enqueue(.setSwing(-0.5)))
        _ = executor.tick(now: 2.0)
        XCTAssertEqual(executor.currentSwing, 0)
    }

    // MARK: - EngineController surface

    func test_engineController_setSwing_clampsAndUpdatesPublishedValue() {
        let controller = EngineController(client: nil, endpoint: nil)
        XCTAssertEqual(controller.currentSwing, 0, "swing is transient runtime state, defaulting to 0")

        controller.setSwing(0.25)
        XCTAssertEqual(controller.currentSwing, 0.25)

        controller.setSwing(1.4)
        XCTAssertEqual(controller.currentSwing, 1)

        controller.setSwing(-0.2)
        XCTAssertEqual(controller.currentSwing, 0)
    }
}
