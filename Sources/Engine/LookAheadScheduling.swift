import AVFoundation
import Foundation

// MARK: - Phase 3 look-ahead scheduling contract (RAIL STUB — builder implements)
//
// This file is the COMPILE-TIME CONTRACT for Phase 3 of
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
// The DECLARATIONS below are intentionally a NO-OP / knife-edge (lead == 0, the
// pre-Phase-3 behaviour described at `AudioMasterClock.swift:227-235`: "No
// `now()` / lookahead-pump read is exposed ... the ~100–200 ms lookahead pump
// described in the plan is a later step"). They make the frozen rail
// (`Tests/SequencerAITests/Audio/LookAheadSchedulingTests.swift`) COMPILE and run
// RED on the current code (the feature is not built yet).
//
// FROZEN-RAIL DISCIPLINE: the BUILDER implements the bodies here (and may extend
// / re-home these declarations as long as the rail keeps compiling and passes
// HONESTLY). The builder MUST NOT edit the rail test file. The public surface
// (member names, signatures, the `lookAheadLeadSeconds` value contract) is what
// the frozen rail asserts against — it must stay stable.
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
    /// STUB: `0` — no look-ahead built yet (knife-edge dispatch, the pre-Phase-3
    /// behaviour). The builder replaces this with the locked lead and wires it
    /// into the prepare/dispatch split so events are handed to the schedulers
    /// early.
    var lookAheadLeadSeconds: TimeInterval {
        // BUILDER: return the locked look-ahead lead (>= 0.100 s) once the
        // dispatch pump runs ahead of the musical due time.
        0
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
    /// STUB: returns the knife-edge stamp (the event's musical due host time, no
    /// lead) — so a dispatch at or after the due time is past-due and the rail is
    /// RED. The builder makes the dispatch run `lookAheadLeadSeconds` ahead.
    func leadStampedAudioTime(
        forMusicalSeconds musicalSeconds: TimeInterval,
        dispatchNow: TimeInterval
    ) -> AVAudioTime? {
        // BUILDER: stamp the event so the dispatch pump hands it to the
        // scheduler `lookAheadLeadSeconds` ahead of its musical due time, keeping
        // the sounding stamp anchored to `AudioMasterClock` (Rule 1). The no-op
        // below stamps at the knife-edge (no lead) → RED.
        _ = dispatchNow
        return audioMasterClock.audioTime(atMusicalSeconds: max(0, musicalSeconds))
    }
}
