import AVFoundation
import Foundation

// MARK: - P3 EARLY-DISPATCH contract (RAIL STUB — builder implements)
//
// This file is the COMPILE-TIME CONTRACT for the ROUND-2 correction of Phase 3
// (`docs/plans/2026-07-01-round2-integration-spec.md`, "P3 — real early
// dispatch, not an origin delay"):
//
//   "stamp events with the 100 ms lead and hand them to the schedulers EARLY
//    (ahead of the dispatch wake) so `effectivePlaybackTime` never sees a
//    past-due `when`; `leadStampedAudioTime` must be the live path. Do NOT
//    globally delay the master-clock origin."
//
// # What round-1 shipped WRONG (this contract exists to correct it)
//
// Round-1 realised the lead as a FIXED ~100 ms forward shift of the captured
// master-clock origin (`EngineController.start()` →
// `AudioMasterClock.captureOrigin(..., leadSeconds: lookAheadLeadSeconds)`; the
// origin shift in `AudioMasterClock.captureOrigin` /
// `refreshOriginIfAvailable`). Net effect: musical second 0 SOUNDS ~100 ms
// after the transport-start render position — ~100 ms of ABSOLUTE first-play
// latency, which DEFEATS the Gate-1 ≤ 10 ms first-play criterion. And the real
// early-dispatch surface `leadStampedAudioTime(forMusicalSeconds:dispatchNow:)`
// (`Sources/Engine/LookAheadScheduling.swift`) is DEAD in production — the live
// `dispatchTick` loop stamps via `dispatchSampleAudioTime` /
// `scheduledAUNoteSampleTime` and never calls `leadStampedAudioTime`.
//
// # The two invariants the frozen rail asserts (make it GREEN honestly)
//
// 1. FIRST-PLAY ABSOLUTE LATENCY ≤ 10 ms. The first event (musical second 0)
//    must be stamped within 10 ms of the transport-start render origin — i.e.
//    the master-clock origin must NOT be shifted forward by the lead. The lead
//    is realised by dispatching EARLY (handing events to the schedulers ahead
//    of the wake), NOT by moving the sounding origin.
//
// 2. `leadStampedAudioTime` IS THE LIVE DISPATCH PATH, invoked with the
//    configured lead. The `dispatchTick` loop must route each sample/AU event's
//    stamp through `leadStampedAudioTime(forMusicalSeconds:dispatchNow:)` and
//    report it through `noteLeadStampedDispatchForTesting(...)` so the rail can
//    machine-verify the live invocation + the lead applied.
//
// FROZEN-RAIL DISCIPLINE: the BUILDER wires the production dispatch path to call
// `leadStampedAudioTime` and to report each call through the probe below, and
// removes the origin shift so first-play latency is ≤ 10 ms. The builder MUST
// NOT edit the rail test file
// (`Tests/SequencerAITests/Audio/LookAheadEarlyDispatchTests.swift`). The public
// surface here (member names / signatures) is what the frozen rail asserts
// against — it must stay stable.

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
    /// STUB: never invoked — the production dispatch path does not call
    /// `leadStampedAudioTime` yet (round-1 shipped the origin-shift mechanism
    /// instead), so the probe stays silent and the frozen rail's live-path
    /// invariant is RED. The builder makes `dispatchTick` route every sample/AU
    /// stamp through `leadStampedAudioTime` and CALL this probe with the lead
    /// applied.
    var leadStampedAudioTimeDispatchProbeForTesting: ((_ musicalSeconds: TimeInterval, _ dispatchNow: TimeInterval, _ lead: TimeInterval) -> Void)? {
        get { EngineControllerEarlyDispatchProbeStore.shared.probe(for: self) }
        set { EngineControllerEarlyDispatchProbeStore.shared.setProbe(newValue, for: self) }
    }

    /// Report one live-dispatch invocation of `leadStampedAudioTime` to the probe.
    /// The BUILDER calls this from `dispatchTick` at the site where it routes a
    /// sample/AU event's stamp through `leadStampedAudioTime(forMusicalSeconds:
    /// dispatchNow:)`, passing the SAME `musicalSeconds` / `dispatchNow` it
    /// handed the stamp call and the `lead` it applied. No-op when no probe is
    /// installed (production), so this adds nothing to the realtime path in the
    /// steady state.
    ///
    /// STUB present so the rail + the wiring compile now; the round-1 dispatch
    /// path never calls it, which is why the rail is RED.
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
