---
feature: audio-looping
created: 2026-06-04
status: dependency-guardrails-only
sources:
  - docs/roadmap/audio-looping/open-questions.md
  - docs/roadmap/audio-looping/prototype-approval.md
  - docs/roadmap/input-audio/spec.md
  - docs/roadmap/input-audio/architecture.md
---

# Audio Looping Architecture Guardrails

This is not a full implementation architecture. It records dependency and test
guardrails that are already settled by landed Input Audio v1 so future Audio
Looping PM artifacts do not reopen the same boundary.

Full architecture, spec, plan, and handoff must wait until the product-owner
scope lock in `open-questions.md` is answered.

## Runtime Ownership

Audio Looping is a view and command surface over Input Audio runtime state.
It must not define a second model for arm, record, loop, monitor, playback, or
failure state.

Required ownership boundary:

- Authored document state remains limited to Input Audio's track fields such
  as `trackType`, `recordBarLength`, and input channel.
- Runtime state remains owned by `EngineController` /
  `AudioInputTrackRuntime`.
- Captured PCM buffers, waveform buckets, capture progress, pending start tick,
  monitor mode, failure state, and recorded loop buffers remain runtime-only.
- SwiftUI may hold view-only UI state such as hover, selected card focus, or an
  inline clear confirmation.

## V1 Dependency Guardrails

Until the product owner chooses otherwise, builder-facing artifacts must assume
the landed Input Audio v1 constraints:

- maximum one `.audioInput` track per session;
- recording lengths are 1, 2, 4, and 8 bars;
- ARM is bar-quantized and cancelable before recording starts;
- recording auto-stops at the selected length;
- re-recording destructively replaces the previous loop on completion;
- Input and Loop monitor modes are mutually exclusive mixer routes;
- Loop mode with no loop is silent and visibly empty;
- invalid input routes fail locally and non-crashingly.

## Command Semantics

The looping page may expose compact performance controls, but each must map to
canonical Input Audio commands:

| Page command | Runtime command |
| --- | --- |
| Arm / cancel arm | Same arm mutation path as the Input Audio track workspace |
| Record armed track(s) | Same bar-quantized record start path; plural dispatch deferred unless multi-track input is approved |
| Play loop | Set monitor mode to Loop |
| Take loop out | Set monitor mode to Input |
| Clear loop | New explicit runtime buffer reset command for the audio input track |

Do not map loop play/mute to generic mixer mute. Mixer mute remains a mixer
control and must not be hidden behind Audio Looping state.

## Clear Loop Guardrail

Clear loop is not destructive re-record. It must remove the current loop while
preserving the track and setup.

Expected runtime effect:

- stop loop playback if active;
- discard the recorded loop buffer and waveform bucket state;
- clear capture progress and any pending playback scheduling for that loop;
- set arm state back to idle/empty;
- leave selected bar length, input channel, mixer routing, track identity, and
  document state intact.

If this command is not feasible in the first build slice, the spec must name
clear loop as deferred and product-owner-approved, because the accepted story
set currently includes it.

## Test Guardrails

Future implementation must include focused tests or deterministic scenario
evidence for:

- no parallel arm state: arming from the looping page is reflected on the Input
  Audio track workspace and vice versa;
- selected bar length shown on the looping page matches the track field;
- Input/Loop monitor mode changes from the looping page use the same runtime
  path as the track workspace;
- Loop mode with no buffer shows empty/silent state and does not crash;
- clear loop removes the runtime buffer and waveform while preserving track
  configuration;
- invalid input route or recording failure is visible on the looping page
  without creating page-local failure truth;
- one-track v1 behavior, if approved, never implies support for simultaneous
  multi-track record.

## Promotion Boundary

These guardrails are enough to prevent known architecture drift. They are not
enough for build-loop promotion. Promotion still requires the scope lock in
`open-questions.md` to be answered and a complete accepted PM artifact set for
the chosen scope.
