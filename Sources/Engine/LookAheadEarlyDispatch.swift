import AVFoundation
import Foundation

// MARK: - P3 EARLY-DISPATCH contract (IMPLEMENTED — round-2 correction)
//
// This file defines the test-observation surface for the ROUND-2 correction of
// Phase 3 (`docs/plans/2026-07-01-round2-integration-spec.md`, "P3 — real early
// dispatch, not an origin delay"):
//
//   "stamp events with the 100 ms lead and hand them to the schedulers EARLY
//    (ahead of the dispatch wake) so `effectivePlaybackTime` never sees a
//    past-due `when`; `leadStampedAudioTime` must be the live path. Do NOT
//    globally delay the master-clock origin."
//
// # What round-1 shipped WRONG (this contract was written to correct it)
//
// Round-1 realised the lead as a FIXED ~100 ms forward shift of the captured
// master-clock origin (`EngineController.start()` calling
// `AudioMasterClock.captureOrigin(..., leadSeconds: lookAheadLeadSeconds)`).
// Net effect: musical second 0 SOUNDED ~100 ms after the transport-start
// render position — ~100 ms of ABSOLUTE first-play latency, which DEFEATED the
// Gate-1 ≤ 10 ms first-play criterion. And the early-dispatch surface
// `leadStampedAudioTime(forMusicalSeconds:dispatchNow:)`
// (`Sources/Engine/LookAheadScheduling.swift`) was DEAD in production — the
// live dispatch loop stamped via `dispatchSampleAudioTime` /
// `scheduledAUNoteSampleTime` and never called `leadStampedAudioTime`.
//
// # Current state: both invariants are implemented and live
//
// 1. FIRST-PLAY ABSOLUTE LATENCY ≤ 10 ms. `EngineController.start()` calls
//    `audioMasterClock.captureOrigin(fallbackHostSeconds:)` with the default
//    `leadSeconds: 0` (EngineController.swift ~1223, ~1337) — the master-clock
//    origin is never shifted forward by the lead. The lead is instead realised
//    by dispatching EARLY: `TickClock` reschedules its wakes to run
//    `lookAheadLeadSeconds` ahead of the step grid after tick 0
//    (`TickClock.swift:71-78`), so each wake hands due-soon events to the
//    schedulers ahead of the wake, not by moving the sounding origin.
//
// 2. `leadStampedAudioTime` IS THE LIVE DISPATCH PATH, invoked with the
//    configured lead. `EngineController.dispatchTick` routes each sample/AU
//    event's stamp through `leadStampedSampleAudioTime` /
//    `leadStampedAUNoteSampleTime` (EngineController.swift ~692-762), which
//    call `leadStampedAudioTime(forMusicalSeconds:dispatchNow:)` and report the
//    invocation through `noteLeadStampedDispatchForTesting(...)` below, so the
//    rail can machine-verify the live invocation + the lead applied.
//
// FROZEN-RAIL DISCIPLINE: `Tests/SequencerAITests/Audio/LookAheadEarlyDispatchTests.swift`
// asserts against the public surface below (member names / signatures). Do not
// edit the rail test file; the surface here must stay stable.

extension EngineController {

    /// Test observation hook fired by the LIVE `dispatchTick` loop each time it
    /// stamps a sample/AU event through `leadStampedAudioTime(forMusicalSeconds:
    /// dispatchNow:)`. Parameters:
    ///   - `musicalSeconds`: the event's musical due position (the value handed
    ///     to `leadStampedAudioTime`).
    ///   - `dispatchNow`: the wall-clock wake at which the pump dispatched
    ///     (models WHEN the pump woke; must NOT move the stamp — Rule 1).
    ///   - `lead`: the look-ahead lead the dispatch applied (the gap between the
    ///     pump's early dispatch and the event's musical due time).
    ///
    /// Implemented: `EngineController.dispatchTick` calls
    /// `noteLeadStampedDispatchForTesting(...)` below for every sample/AU event
    /// it routes through `leadStampedAudioTime` (via `leadStampedSampleAudioTime`
    /// / `leadStampedAUNoteSampleTime`), reporting the configured lead. The probe
    /// stays nil in production (no test has installed one), so this fires the
    /// no-op default and adds nothing to the realtime path.
    var leadStampedAudioTimeDispatchProbeForTesting: ((_ musicalSeconds: TimeInterval, _ dispatchNow: TimeInterval, _ lead: TimeInterval) -> Void)? {
        get { EngineControllerEarlyDispatchProbeStore.shared.probe(for: self) }
        set { EngineControllerEarlyDispatchProbeStore.shared.setProbe(newValue, for: self) }
    }

    /// Report one live-dispatch invocation of `leadStampedAudioTime` to the probe.
    /// Called from `leadStampedSampleAudioTime` / `leadStampedAUNoteSampleTime`
    /// (`EngineController.swift`, the `dispatchTick` helpers that route a
    /// sample/AU event's stamp through `leadStampedAudioTime(forMusicalSeconds:
    /// dispatchNow:)`), passing the SAME `musicalSeconds` / `dispatchNow` handed
    /// to the stamp call and the `lead` applied. No-op when no probe is
    /// installed (production), so this adds nothing to the realtime path in the
    /// steady state.
    func noteLeadStampedDispatchForTesting(
        musicalSeconds: TimeInterval,
        dispatchNow: TimeInterval,
        lead: TimeInterval
    ) {
        leadStampedAudioTimeDispatchProbeForTesting?(musicalSeconds, dispatchNow, lead)
    }
}

/// Backing store for `leadStampedAudioTimeDispatchProbeForTesting` (an
/// extension cannot add stored properties to `EngineController`). Keyed by object
/// identity; entries are cleared when a probe is set to nil. Test-only surface —
/// production never installs a probe.
final class EngineControllerEarlyDispatchProbeStore {
    static let shared = EngineControllerEarlyDispatchProbeStore()

    private var probes: [ObjectIdentifier: (TimeInterval, TimeInterval, TimeInterval) -> Void] = [:]

    func probe(for controller: EngineController) -> ((TimeInterval, TimeInterval, TimeInterval) -> Void)? {
        probes[ObjectIdentifier(controller)]
    }

    func setProbe(
        _ probe: ((TimeInterval, TimeInterval, TimeInterval) -> Void)?,
        for controller: EngineController
    ) {
        let key = ObjectIdentifier(controller)
        if let probe {
            probes[key] = probe
        } else {
            probes.removeValue(forKey: key)
        }
    }
}
