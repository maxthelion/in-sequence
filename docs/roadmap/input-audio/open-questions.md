---
feature: input-audio
created: 2026-06-03
source_questions: docs/roadmap/input-audio/ux-review.md
reconciled_against:
  - docs/roadmap/input-audio/architecture.md
  - docs/roadmap/input-audio/decisions.md
status: reconciled
---

# Input Audio -- Open Question Reconciliation

This reconciles the twelve open questions from `ux-review.md` against the
current architecture and decision artifacts. It records what is closed for v1,
what is explicitly deferred, and what remains open before spec.

## Summary

- Closed for v1: 10
- Deferred beyond v1: 2
- Still open product questions: 0
- Product-owner lock needed now: no

The remaining readiness blocker is not an unresolved product choice from this
list. It is the missing accepted `architecture-review.md` gate called out by
`architecture.md`.

## Reconciled Questions

| # | Question | Status | Reconciled Answer |
|---|---|---|---|
| 1 | Engine restart on device switch | Closed | No full engine teardown is expected for normal device switches. Architecture defines a short rewire phase: stop the engine, set the AUHAL current-device property by UID, then restart. Preferences should show the short disabled/applying state from the prototype. |
| 2 | Independent vs. aggregate device selection | Closed | V1 uses independent input and output device selection. `AudioDevicePreference` stores separate `preferredInputDeviceUID` and `preferredOutputDeviceUID` values. Aggregate-device setup is out of scope. |
| 3 | Sample rate / buffer size controls | Deferred | Device selection ships in v1; explicit sample-rate and buffer-size controls are deferred. The engine uses the selected device defaults. Prototype controls may remain visually subordinated in design evidence, but spec should exclude them from v1 implementation scope. |
| 4 | Missing device at next launch | Closed | Fall back to system default input/output and show a non-blocking Preferences banner that the previous device is unavailable. Do not block launch and do not silently fail with no explanation. |
| 5 | Engine device-switch failure state | Closed | Preferences must show a failed/error state when rewire or restart fails, restore the previous device UID, and update the persisted preference only after a successful switch. |
| 6 | Step-pattern grid on audio input track | Closed | No step-sequencer grid in v1. The audio input workspace stays focused on record/monitor/waveform plus mixer routing. Step-triggering or loop slicing belongs to a later feature. |
| 7 | Live input signal routing in loop mode | Closed | Live input is gated by monitor mode. In live-input mode, the passthrough reaches the mixer and the loop does not. In loop mode, the recorded loop reaches the mixer and live passthrough is disconnected. |
| 8 | Overdub vs. destructive replace | Closed | V1 uses destructive replace. Overdub is not supported. No confirmation dialog is required at arm time; the ARM state communicates pending capture. |
| 9 | Real-time waveform during recording | Closed | V1 should stream waveform fill during recording using lightweight bucket updates. The UI must consume published buckets, not read render-adjacent capture buffers directly. |
| 10 | BPM change after recording | Deferred | No time-stretching or pitch-shifting in v1. The recorded loop keeps its sample length; if BPM changes later, it plays at its original duration and may drift relative to the new tempo. |
| 11 | Per-track hardware channel selector | Closed | In scope. `StepSequenceTrack` carries an `inputChannel` field with mono/stereo choices, and channel changes require engine input re-routing. |
| 12 | Navigation away while recording | Closed | Recording continues when the user navigates away. `EngineController` owns the track runtime state, and the track list/header should show a recording indicator while `armState == .recording`. |

## Deferred Items

The deferred items are intentionally out of v1 scope, not open questions:

- Sample-rate and buffer-size controls.
- BPM-change adaptation through time-stretching or pitch-shifting.

Both should be named as exclusions in `spec.md` so builders do not infer them
from prototype affordances or general DAW expectations.

## Residual Review Risk

Architecture review still needs to accept or revise the implementation-level
details in `architecture.md`, especially direct input tap versus a future shared
input distributor, command queue versus direct runtime mutation, loop playback
bar-locking mechanics, and waveform bucket publishing. Those are architecture
review questions, not current product-owner locks from the UX-review list.

