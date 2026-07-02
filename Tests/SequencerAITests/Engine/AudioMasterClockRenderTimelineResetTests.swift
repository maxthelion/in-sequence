import AVFoundation
import XCTest
@testable import SequencerAI

/// Regression coverage for the scene-FX AU-attenuation bug
/// (docs/bugs/20260702-143000-scene-fx-attenuates-au-track-until-restart).
///
/// Adding a master-bus scene FX insert while the transport runs rebuilds the
/// master chain via `MainAudioGraph.installMasterChains`, which stop()/start()s
/// the LIVE engine. Measured live-HAL physics (2026-07-02 probe): that restart
/// RESETS the output node's render `sampleTime` timeline (pre-stop frame
/// 48128 → post-restart frame 24576 after +0.55 s of wall time), while host
/// time and the AU node's own render counter CONTINUE.
///
/// The unified master clock's FRAME origin (`sampleTime(atMusicalSeconds:)`)
/// was captured on the pre-restart timeline, so after the reset every AU note
/// stamp sat the whole pre-restart elapsed time in the NEW timeline's future —
/// AU notes stopped landing (audibly the AU track drops way down; drums are
/// untouched because sample sinks schedule against HOST time). The state was
/// sticky (removing the FX restarts the engine again — same dead origin) and
/// healed only on transport Stop→Play (`captureOrigin` re-anchors).
///
/// The fix: `AudioMasterClock` detects the render-timeline reset (a large
/// regression of the render `sampleTime` against the highest frame observed on
/// the current timeline) and REBASES the frame origin onto the new timeline
/// through the still-valid host-seconds origin correlation. These tests drive
/// the clock with an injected render-position provider that reproduces the
/// measured timeline reset deterministically (offline manual rendering cannot
/// reproduce it: `manualRenderingSampleTime` is continuous across
/// stop()/start(), also measured).
final class AudioMasterClockRenderTimelineResetTests: XCTestCase {
    private typealias RenderPosition = (sampleTime: AVAudioFramePosition, hostTime: UInt64, sampleRate: Double)

    private static let rate: Double = 48_000

    private func hostTime(forSeconds seconds: TimeInterval) -> UInt64 {
        AVAudioTime.hostTime(forSeconds: seconds)
    }

    /// THE bug: after a live-engine restart resets the output render timeline,
    /// AU note frame stamps must track the NEW timeline (schedulable ~lead
    /// ahead of the live render position), not sit the whole pre-restart
    /// session duration in its future.
    func test_frameStamps_staySchedulable_afterRenderTimelineReset() {
        // Warm engine: the graph has been rendering for 20 s when the
        // transport starts (frame 960_000 at host second 100).
        var position: RenderPosition? = (
            sampleTime: 960_000,
            hostTime: hostTime(forSeconds: 100),
            sampleRate: Self.rate
        )
        let clock = AudioMasterClock(stepsPerBar: 16, renderPositionProvider: { position })
        clock.captureOrigin(
            fallbackHostSeconds: 100,
            startupAnchorLeadSeconds: AudioMasterClock.startupAnchorLeadSeconds
        )

        // Transport runs ~10 s; the render position advances in lockstep.
        position = (
            sampleTime: 960_000 + 480_000,
            hostTime: hostTime(forSeconds: 110),
            sampleRate: Self.rate
        )

        // Sanity (pre-mutation): a note due at musical 10.1 s is stamped
        // anchor(0.05) + 0.1 s ahead of the current render frame.
        let preStamp = clock.sampleTime(atMusicalSeconds: 10.1)
        XCTAssertEqual(
            Double(preStamp - 1_440_000) / Self.rate, 0.15, accuracy: 0.001,
            "pre-mutation stamps must sit just ahead of the live render position"
        )

        // Scene-FX mutation: installMasterChains stop()/start() resets the
        // output timeline — the new render position restarts near zero while
        // host time continues (the measured live-HAL behaviour).
        position = (
            sampleTime: 4_096,
            hostTime: hostTime(forSeconds: 110.1),
            sampleRate: Self.rate
        )

        let postStamp = clock.sampleTime(atMusicalSeconds: 10.2)
        let aheadOfRenderSeconds = Double(postStamp - 4_096) / Self.rate

        // Without the rebase the stamp is origin(962_400) + 10.2 s ≈ 30 s in
        // the new timeline's future — the AU falls silent/chopped until
        // transport restart. With the rebase it must sit just ahead of the
        // new render position: musical 10.2 is due at host 110.25, i.e.
        // 0.15 s after the reset position's host second 110.1.
        XCTAssertLessThan(
            aheadOfRenderSeconds, 1.0,
            "AU frame stamps must be rebased onto the new render timeline after a live engine restart " +
            "(scene-FX insert add/remove); a stamp \(aheadOfRenderSeconds) s in the future is unplayable " +
            "until the AU's own counter catches up — the sticky attenuation the owner heard"
        )
        XCTAssertEqual(
            aheadOfRenderSeconds, 0.15, accuracy: 0.001,
            "the rebased stamp must preserve the musical timeline exactly (host anchor unchanged)"
        )
    }

    /// The heal must not disturb what already worked: host-time stamps (the
    /// sample/drum sink path) are anchored to the host-seconds origin and must
    /// be IDENTICAL before and after the frame-origin rebase — drums were
    /// unaffected in the owner repro and must stay so.
    func test_hostTimeStamps_unchangedAcrossRenderTimelineReset() {
        var position: RenderPosition? = (
            sampleTime: 960_000,
            hostTime: hostTime(forSeconds: 100),
            sampleRate: Self.rate
        )
        let clock = AudioMasterClock(stepsPerBar: 16, renderPositionProvider: { position })
        clock.captureOrigin(
            fallbackHostSeconds: 100,
            startupAnchorLeadSeconds: AudioMasterClock.startupAnchorLeadSeconds
        )

        position = (
            sampleTime: 960_000 + 480_000,
            hostTime: hostTime(forSeconds: 110),
            sampleRate: Self.rate
        )
        let preHost = AVAudioTime.seconds(forHostTime: clock.audioTime(atMusicalSeconds: 10.2).hostTime)

        // Timeline reset (live engine restart), then the same musical position.
        position = (
            sampleTime: 4_096,
            hostTime: hostTime(forSeconds: 110.1),
            sampleRate: Self.rate
        )
        let postHost = AVAudioTime.seconds(forHostTime: clock.audioTime(atMusicalSeconds: 10.2).hostTime)

        XCTAssertEqual(
            preHost, postHost, accuracy: 1e-6,
            "the frame-origin rebase must not move the host-seconds origin — sample sinks were correct all along"
        )
    }

    /// A STALE frozen render pair (the stopped window hands back the last
    /// pre-stop render time while host time marches on) must NOT trigger a
    /// rebase: the counter freezes, it does not rewind, and the pair is
    /// self-consistent. The origin must stay exactly where transport start
    /// put it.
    func test_frozenStaleRenderPair_doesNotRebaseOrigin() {
        let frozen: RenderPosition = (
            sampleTime: 1_440_000,
            hostTime: hostTime(forSeconds: 110),
            sampleRate: Self.rate
        )
        var position: RenderPosition? = (
            sampleTime: 960_000,
            hostTime: hostTime(forSeconds: 100),
            sampleRate: Self.rate
        )
        let clock = AudioMasterClock(stepsPerBar: 16, renderPositionProvider: { position })
        clock.captureOrigin(
            fallbackHostSeconds: 100,
            startupAnchorLeadSeconds: AudioMasterClock.startupAnchorLeadSeconds
        )

        position = frozen
        let before = clock.sampleTime(atMusicalSeconds: 10.2)

        // The engine is stopped mid-rebuild: repeated reads see the SAME
        // frozen pair while wall time advances. No regression → no rebase.
        for _ in 0..<5 {
            _ = clock.sampleTime(atMusicalSeconds: 10.2)
        }
        let after = clock.sampleTime(atMusicalSeconds: 10.2)
        XCTAssertEqual(before, after, "a frozen stale render pair must never move the frame origin")
    }

    /// Small backwards jitter (well inside the tolerance) must not rebase —
    /// only a genuine timeline reset (a regression far beyond per-quantum
    /// jitter) may move the frame origin.
    func test_smallBackwardsJitter_doesNotRebaseOrigin() {
        var position: RenderPosition? = (
            sampleTime: 960_000,
            hostTime: hostTime(forSeconds: 100),
            sampleRate: Self.rate
        )
        let clock = AudioMasterClock(stepsPerBar: 16, renderPositionProvider: { position })
        clock.captureOrigin(fallbackHostSeconds: 100)

        position = (
            sampleTime: 1_440_000,
            hostTime: hostTime(forSeconds: 110),
            sampleRate: Self.rate
        )
        let before = clock.sampleTime(atMusicalSeconds: 10.2)

        // One render quantum of backwards skew (~512 frames) — jitter, not a reset.
        position = (
            sampleTime: 1_440_000 - 512,
            hostTime: hostTime(forSeconds: 110.01),
            sampleRate: Self.rate
        )
        let after = clock.sampleTime(atMusicalSeconds: 10.2)
        XCTAssertEqual(before, after, "sub-tolerance render jitter must never move the frame origin")
    }

    /// The offline deterministic gate's origin shape is untouched: a clock
    /// whose origin was established purely through `refreshOriginIfAvailable`
    /// (no `captureOrigin`) on a CONTINUOUS, monotonic timeline keeps stamps
    /// exactly `origin + musicalSeconds * sampleRate` forever.
    func test_continuousTimeline_offlineOriginShape_neverRebases() {
        var position: RenderPosition? = (
            sampleTime: 0,
            hostTime: hostTime(forSeconds: 50),
            sampleRate: Self.rate
        )
        let clock = AudioMasterClock(stepsPerBar: 16, renderPositionProvider: { position })

        // Origin established by the first conversion (offline harness shape).
        XCTAssertEqual(clock.sampleTime(atMusicalSeconds: 0), 0)

        // Manual rendering advances monotonically across an engine
        // stop()/start() (measured: 40960 → 49152, no reset).
        position = (
            sampleTime: 49_152,
            hostTime: hostTime(forSeconds: 51),
            sampleRate: Self.rate
        )
        XCTAssertEqual(
            clock.sampleTime(atMusicalSeconds: 2.0),
            AVAudioFramePosition(2.0 * Self.rate),
            "a continuous render timeline must never trigger the reset rebase — the 0-frame gate's stamps stay exact"
        )
    }
}
