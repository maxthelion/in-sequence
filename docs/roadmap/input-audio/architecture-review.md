---
feature: input-audio
created: 2026-06-03
reviewed_architecture: docs/roadmap/input-audio/architecture.md
verdict: accepted
gate: architecture
spec_unblocked: true
---

# Input Audio Architecture Review

## Verdict

Accepted.

The architecture is fit for v1 PM progression. It preserves the project's
document/runtime boundary, keeps live capture and monitoring in
`EngineController`/audio runtime state, avoids persisting capture buffers or arm
state, uses optional document fields for compatibility, and scopes engine work
as additive branches rather than broad rewrites.

This review closes the architecture gate required by `architecture.md`.
`spec.md` is now unblocked from the architecture side, provided the spec carries
the constraints and exclusions below.

## Gate Criteria

| Criterion | Result | Notes |
|---|---|---|
| Product intent alignment | Pass | Supports preferences-based input setup, live input into the mixer, quantized recording, live/loop monitoring, and waveform feedback. |
| Document/runtime separation | Pass | Persisted fields are limited to authored track choices; capture buffers, arm state, monitor mode, pending ticks, and waveform scan data remain transient. |
| Compatibility | Pass | New `StepSequenceTrack` fields must use `decodeIfPresent` / `encodeIfPresent`. |
| Engine ownership | Pass | `EngineController` owns per-track audio-input runtime keyed by track ID. |
| Mixer/routing fit | Pass | Live input and loop playback are routed to the existing pre-master path without replacing current AU/sample sync paths. |
| Thread discipline | Pass with spec constraint | Tap work must use preallocated buffers and atomic/snapshot handoff; SwiftUI must never read tap-owned buffers directly. |
| v1 scope control | Pass | One audio input track, destructive replace, no step grid, no sample-rate/buffer controls, and no BPM-change time-stretching are accepted v1 constraints. |

## Review Question Rulings

### A. Single vs. shared input tap

Use a direct `engine.inputNode` tap for v1.

`decisions.md` limits v1 to one audio input track per session, so a shared input
distribution layer would add abstraction before there is a product need. The
spec must enforce the one-track limit in the UI and runtime. A shared tap or
input distributor can be introduced when multiple audio input tracks become a
real v2 requirement.

### B. CommandQueue vs. direct runtime mutation

Use explicit command-queue mutations for ARM, cancel ARM, monitor-mode changes,
and input-channel rerouting.

The architecture is correct that `EngineController` owns the runtime state, but
the spec should avoid ad hoc direct UI mutation of engine internals. Commands
keep UI-to-engine communication coherent with existing `setParam` / `setBPM`
style boundaries and make quantized state changes easier to test.

### C. Loop playback timing

Loop playback is bar-locked for v1.

`decisions.md` resolves this: after recording, switching to Loop mode starts
playback on the next bar boundary rather than immediately. Best-effort immediate
playback is rejected for v1 because it would weaken the user-story promise that
captured loops play back in time with the session.

### D. Waveform bucket publishing

Publish UI waveform data through main-thread snapshots only.

The tap may update preallocated running bucket state, but SwiftUI must consume a
copied bucket array published from an observable view model on the main thread,
driven by a display-link or periodic timer. The final waveform should be
published from the completed loop buffer after capture finalization.

## Required Spec Constraints

- Explicitly exclude sample-rate and buffer-size controls from v1.
- Explicitly exclude BPM-change time-stretching and pitch-shifting from v1.
- Enforce one audio input track per session in v1.
- Use destructive replace when a new recording completes; no overdub in v1.
- Keep `monitorMode` as transient runtime state unless a later PM decision says
  the selected monitoring mode should survive save/load.
- Lock bar length and input-channel changes while armed or recording, unless
  the spec defines a safe cancel/re-arm flow.
- Define failed device-switch behavior: restore the previous successful UID,
  persist only after success, and show a non-blocking error state.
- Define missing-device-at-launch behavior: fall back to system default and show
  a Preferences banner.
- Require an implementation spike or first implementation step to validate
  CoreAudio/AUHAL device switching before broad UI polish work.
- Audit every `TrackType` switch in `Sources/` when `.audioInput` is added.

## Residual Risks

The architecture is accepted, but several implementation risks remain and should
be carried into `spec.md` and `plan.md`:

- CoreAudio device switching through AUHAL property setting may require fallback
  to a fuller graph rebuild if validation fails.
- Exact bar-locked loop playback may require careful scheduling between
  `TickClock`, `AVAudioPlayerNode`, and engine sample time.
- Tap completion signaling and waveform bucket publication are correctness
  risks if implemented with non-atomic shared state or direct UI reads.
- The accepted prototype does not yet have a separate `prototype-approval.md`
  artifact, although `ux-review.md` accepted the selected prototype.

## Product-Owner Attention

No product-owner attention is needed for the architecture gate. The current
roadmap artifacts resolve the relevant product questions for v1.
