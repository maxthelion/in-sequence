import AVFoundation
import Foundation

// MARK: - Phase 3 look-ahead scheduling contract (IMPLEMENTED — early dispatch)
//
// This file defines the look-ahead lead contract for Phase 3 of
// `docs/plans/2026-06-30-precompute-lookahead-recording.md`:
//
//   "with a warm origin (P1) + a precomputed bar (P2), stamp events with a fixed
//    lead (~100 ms) ahead of dispatch and hand them to the sample/AU schedulers
//    early, so `effectivePlaybackTime` never sees a past-due `when`."
//
//   Gate-1 LOCKED decision (the spec): "Look-ahead lead: 100 ms."
//
//   Executable gate (headline): "zero \"immediate\"-mode triggers in the timing
//    probe under normal load" — i.e. `effectivePlaybackTime` never clamps to
//    immediate (nil) when a dispatch arrives within the lead.
//
// # How the lead is realised (implemented; see LookAheadEarlyDispatch.swift)
//
// The lead is NOT a master-clock origin shift. `TickClock` fires tick 0
// immediately and then reschedules its repeating timer so every subsequent
// wake runs `lookAheadLeadSeconds` ahead of the step grid (`TickClock.swift`,
// the `tickIndex == 0` reschedule in the timer's event handler). Each wake
// drives `EngineController.processLiveLookAheadPumpMarked`, which dispatches
// every step whose musical due time falls within `pumpMusicalSeconds +
// lookAheadLeadSeconds`, with the `nextLivePumpStep` cursor preventing
// duplicate dispatch — so sinks receive events up to `lookAheadLeadSeconds`
// before they are musically due. `AudioMasterClock.captureOrigin` is called
// with the default `leadSeconds: 0` on the live transport-start path
// (`EngineController.start`); the origin itself never moves, only the
// dispatch wake does.
//
// FROZEN-RAIL DISCIPLINE: `Tests/SequencerAITests/Audio/LookAheadSchedulingTests.swift`
// asserts against the public surface below (member names, signatures, the
// `lookAheadLeadSeconds` value contract). Do not edit the rail test file; the
// surface here must stay stable.
//
// # Why the lead is the contract, and why it is anchored to the musical origin
//
// Rule 1 (AGENTS.md): the frame an event sounds on comes from the tempo map +
// the render origin, NEVER from a wall clock. So the look-ahead lead is realised
// by dispatching EARLY (the pump prepares/hands an event to the scheduler up to
// `lookAheadLeadSeconds` before its musical due time), NOT by adding the lead to
// the sounding stamp. The event's stamp stays anchored to the unified clock
// (`AudioMasterClock.audioTime(atMusicalSeconds:)`); the LEAD is the gap between
// the pump's dispatch `now` and that musical due time. Consequence: when a
// dispatch arrives up to `lookAheadLeadSeconds` late (the pump woke late), the
// stamp is still in the FUTURE relative to `now`, so
// `SamplePlaybackEngine.effectivePlaybackTime(for:now:)` returns the future
// `when` instead of clamping it to immediate (nil) — eliminating the
// stale→immediate flam at the source.

extension EngineController {

    /// The fixed look-ahead lead (seconds) the dispatch pump runs ahead of an
    /// event's musical due time. Gate-1 LOCKED at 100 ms
    /// (`docs/plans/2026-06-30-precompute-lookahead-recording.md`).
    ///
    /// Contract (what the frozen rail asserts): `>= 0.100` seconds. Live
    /// performance controls still apply at dispatch ON TOP of the lead, so the
    /// lead does not hurt responsiveness (spec, "Look-ahead lead: 100 ms").
    ///
    /// Implemented: forwards `AudioMasterClock.lookAheadLeadSeconds` (0.100 s).
    /// `TickClock.start(lookAheadLeadSeconds:)` uses this value to reschedule
    /// its wakes ~100 ms ahead of the step grid, and
    /// `EngineController.processLiveLookAheadPumpMarked` uses it as the
    /// dispatch horizon (`pumpMusicalSeconds + lookAheadLeadSeconds`) for
    /// which due-soon steps to dispatch on each wake.
    var lookAheadLeadSeconds: TimeInterval {
        // Phase 3 — this is the pump's look-ahead horizon. It must not be paid
        // as a master-clock origin delay. The event stamp remains the true
        // musical due time; the pump must hand it to sinks before that due time.
        AudioMasterClock.lookAheadLeadSeconds
    }

    /// The future `AVAudioTime` an event at musical position `musicalSeconds`
    /// should be stamped with when the dispatch pump hands it to the sample/AU
    /// scheduler at wall-clock `dispatchNow`, WITH the look-ahead lead applied.
    ///
    /// Contract (what the frozen rail asserts):
    /// - The returned stamp is anchored to the unified clock's musical position
    ///   (`AudioMasterClock.audioTime(atMusicalSeconds:)`) — Rule 1 — NOT to
    ///   `dispatchNow`. `dispatchNow` only models WHEN the pump dispatched.
    /// - Because the pump dispatches up to `lookAheadLeadSeconds` EARLY, a
    ///   dispatch that arrives late by any `lateness` in
    ///   `[0, lookAheadLeadSeconds)` still yields a stamp whose host time is in
    ///   the FUTURE relative to `dispatchNow`. Equivalently:
    ///   `SamplePlaybackEngine.effectivePlaybackTime(for: result, now: dispatchNow)`
    ///   is non-nil (never clamped to immediate) for such a dispatch.
    /// - Returns nil only when there is genuinely no sample-accurate stamp yet
    ///   (no render origin), mirroring `scheduledAUNoteSampleTime`'s contract.
    ///
    /// Implemented: intentionally returns the musical-due-time stamp (no lead
    /// added to the stamp itself) — the lead is realised upstream, by the pump
    /// calling this EARLY (see the file header), not by shifting the stamp this
    /// function returns. `dispatchNow` is accepted for the contract's
    /// documentation/testing value (it lets callers/tests state WHEN the pump
    /// dispatched relative to the due time) but is not read here: Rule 1
    /// requires the stamp to be anchored purely to the unified clock's musical
    /// due time, never to the wall-clock dispatch moment, so folding
    /// `dispatchNow` into the returned stamp would be wrong even if it were
    /// convenient.
    func leadStampedAudioTime(
        forMusicalSeconds musicalSeconds: TimeInterval,
        dispatchNow: TimeInterval
    ) -> AVAudioTime? {
        // Route the conversion through `scheduledAudioTime(for:)` so the stamp
        // flows through the SAME `scheduledAudioTimeOverrideForTesting` seam the
        // mandate names and the offline / look-ahead rails install — the
        // integration is then genuinely exercised, not bypassed. Production has no
        // override installed, so this is the identical `AudioMasterClock`
        // conversion the previous direct call made.
        _ = dispatchNow
        return scheduledAudioTime(for: max(0, musicalSeconds))
    }
}
