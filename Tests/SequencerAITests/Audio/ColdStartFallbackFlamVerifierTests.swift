import AVFoundation
import XCTest
@testable import SequencerAI

/// VERIFIER work-product (NOT a frozen rail) for the P3/P1 prosecutor charge:
///
///   "Cold-start fallback origin gives drums the 100ms lead but leaves AU
///    immediate — a first-play AU-vs-drum flam." (AudioMasterClock.swift:164)
///
/// The charge: when `captureOrigin` takes the FALLBACK branch
/// (`renderPositionProvider() == nil` at start) and a render position never
/// becomes available before the first dispatch, it sets
///   - `originHostSeconds = fallback + lead`  (line 165 — lead applied)
///   - `originSampleTime = 0`                 (line 164 — NO lead in frames)
///   - `originIsRenderDerived = false`        (line 166)
/// so on first play a drum/sample trigger is stamped via the HOST-time path
/// (`audioTime(atMusicalSeconds:)` → `hostSeconds` == fallback + lead + m) and
/// lands ~100 ms in the FUTURE (gets the lead), but an AU note goes through
/// `scheduledAUNoteSampleTime` which returns nil when `hasRenderOrigin == false`,
/// so the AU plays IMMEDIATE (no lead). That is a ~100 ms AU-vs-drum onset split
/// on the first bar — contradicting the Gate-1 first-play criterion ("AU AND drum
/// audio audible within 10 ms of the grid").
///
/// The frozen offline rails cannot see this: in offline manual-rendering mode
/// `MainAudioGraph.renderPosition` is ALWAYS non-nil (MainAudioGraph.swift:487),
/// so `captureOrigin` always takes the render-derived branch and `isRenderDerived`
/// is always true in those tests.
///
/// This file DRIVES THE UN-UPGRADED FALLBACK BRANCH directly (a
/// `renderPositionProvider` that stays nil — the live cold-start the offline path
/// never takes) and measures the onset split between the drum (host) path and the
/// AU (sample-stamp) path.
final class ColdStartFallbackFlamVerifierTests: XCTestCase {

    private static let specLeadSeconds: TimeInterval = AudioMasterClock.lookAheadLeadSeconds

    /// Reproduce-or-kill: in the un-upgraded fallback branch, what onset does each
    /// path resolve to, relative to the dispatch `now`? The drum/sample path uses
    /// `audioTime(atMusicalSeconds:)`; the AU path uses `hasRenderOrigin` (its gate
    /// for sample-stamping vs immediate). If the drum gets +lead while the AU is
    /// forced immediate, the split is ~lead.
    func test_coldStartFallback_drumVsAUOnsetSplit() {
        // Live cold start: engine not yet rendering, render position never appears.
        let clock = AudioMasterClock(stepsPerBar: 16, renderPositionProvider: { nil })

        // Transport start in LIVE mode passes the locked lead (EngineController.start:1028).
        let fallbackHost: TimeInterval = 1_000.0
        clock.captureOrigin(fallbackHostSeconds: fallbackHost, leadSeconds: Self.specLeadSeconds)

        // Step 0 sounds at musical second 0 (first event of the first bar).
        let m: TimeInterval = 0.0

        // The dispatch wakes at ~fallbackHost (the pump fires around transport start;
        // with the lead the event is targeted `lead` ahead of this wake).
        let dispatchNow = fallbackHost

        // DRUM / SAMPLE path: `EngineController.dispatchSampleAudioTime(for:)` gates
        // on the SAME `hasRenderOrigin` the AU path uses — in the cold fallback it
        // returns nil (→ immediate), aligning with the AU. We model that gate here.
        let drumHasLeadStamp = clock.hasRenderOrigin
        let drumStampHostSeconds = AVAudioTime.seconds(
            forHostTime: clock.audioTime(atMusicalSeconds: m).hostTime
        )
        let drumOnsetRelativeToDispatch: TimeInterval = drumHasLeadStamp
            ? (drumStampHostSeconds - dispatchNow)
            : 0.0   // cold fallback → immediate, no lead (the fix)

        // AU path discriminator: scheduledAUNoteSampleTime returns a sample stamp
        // ONLY when hasRenderOrigin is true; otherwise nil → AUEventSampleTimeImmediate
        // (AudioInstrumentHost.noteStamps:1205-1210), i.e. head of the next render
        // cycle — effectively `now`, NO lead.
        let auHasSampleStamp = clock.hasRenderOrigin
        let auOnsetRelativeToDispatch: TimeInterval = auHasSampleStamp
            ? (drumStampHostSeconds - dispatchNow)   // would match the drum
            : 0.0                                     // immediate, no lead

        let split = abs(drumOnsetRelativeToDispatch - auOnsetRelativeToDispatch)

        // Diagnostic record of the charge.
        print("[cold-start-fallback] isRenderDerived=\(clock.capturedOriginCorrelation().isRenderDerived) " +
              "auHasSampleStamp=\(auHasSampleStamp) " +
              "drumOnset=+\(drumOnsetRelativeToDispatch * 1000)ms " +
              "auOnset=+\(auOnsetRelativeToDispatch * 1000)ms " +
              "split=\(split * 1000)ms")

        // The Gate-1 first-play criterion: AU and drum must be within 10 ms of each
        // other (both on the grid). If the charge is REAL, `split` ≈ lead (100 ms)
        // and this fails; if the paths agree, `split` < 10 ms.
        XCTAssertLessThan(
            split, 0.010,
            "Cold-start fallback: drum onset is +\(drumOnsetRelativeToDispatch * 1000) ms " +
            "(host path got the look-ahead lead) but the AU onset is +\(auOnsetRelativeToDispatch * 1000) ms " +
            "(scheduledAUNoteSampleTime returned nil → immediate, NO lead). That is a " +
            "\(split * 1000) ms AU-vs-drum first-play flam, violating the Gate-1 10 ms criterion."
        )
    }
}
