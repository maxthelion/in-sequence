import AVFoundation
import XCTest
@testable import SequencerAI

/// Regression for the swing-map SIGSEGV (evidence
/// .meta/hang-evidence/20260702-1903-swing-advance-dict-segfault.ips):
/// `AudioMasterClock.advance(toStep:bpm:swing:)` :329 → `Dictionary.subscript.getter`
/// → `objc_msgSend` EXC_BAD_ACCESS at 0x10 — the classic signature of Swift
/// `Dictionary` storage freed/reallocated by a concurrent mutation while another
/// thread reads it.
///
/// The crash reproduced under `EngineControllerSampleTriggerTests.test_orphanSampleID_noCrash`:
/// `controller.start()` spins the live look-ahead pump (background queue) which
/// calls `advance()`, while the test thread ALSO calls `controller.processTick`
/// → `advance()`. Both mutate `cumulativeMusicalSecondsByStep` (and its >8-entry
/// prune, which REALLOCATES the storage) concurrently, corrupting the buffer.
///
/// The clock documents "Mutated only on the tick/pump queue", but nothing
/// enforces it, so any two-thread overlap (pump + manual tick / MIDI clock)
/// crashes. This test drives the exact overlap and must complete without a
/// segfault (RED — process dies — before the tempo-map lock; GREEN after).
final class AudioMasterClockSwingConcurrencyTests: XCTestCase {
    func test_advance_concurrentPumpAndManualTick_doesNotCorruptTempoMap() {
        let clock = AudioMasterClock(stepsPerBar: 16, defaultSampleRate: 48_000) { nil }
        clock.captureOrigin(fallbackHostSeconds: 0)

        let iterations = 20_000
        let group = DispatchGroup()

        // "Pump" thread: advances the tempo map forward with swing set — this is
        // the background look-ahead pump's advance() call site.
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            for step in 1...iterations {
                _ = clock.advance(toStep: UInt64(step), bpm: 128, swing: 0.5)
            }
            group.leave()
        }

        // "Manual tick" thread: advances the SAME overlapping steps and reads the
        // map back — the direct processTick() call site racing the pump.
        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            for step in 1...iterations {
                _ = clock.advance(toStep: UInt64(step), bpm: 128, swing: 0.5)
                _ = clock.musicalSeconds(forStep: UInt64(step))
            }
            group.leave()
        }

        let outcome = group.wait(timeout: .now() + 60)
        XCTAssertEqual(
            outcome, .success,
            "concurrent advance()/musicalSeconds() must complete without corrupting the tempo map"
        )
    }
}
