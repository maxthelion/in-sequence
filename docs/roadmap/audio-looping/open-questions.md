---
feature: audio-looping
created: 2026-06-04
status: scope-lock-required
sources:
  - README.md
  - docs/roadmap/audio-looping/user-stories.md
  - docs/roadmap/audio-looping/ux-review.md
  - docs/roadmap/audio-looping/notes.md
  - docs/roadmap/input-audio/spec.md
  - docs/roadmap/input-audio/architecture.md
  - docs/multi-pass-coordinator/state/build-loops/input-audio.md
---

# Audio Looping Open Question Reconciliation

Audio Looping remains a macro live-looping performance page, not a second
track-level input-audio model. This pass reconciles the accepted April
prototype with landed Input Audio v1 before any build promotion.

## Summary

- Closed from accepted dependency intent: 4
- Product-owner lock needed: 1
- Ready for build-loop promotion: no

Input Audio v1 has landed with one audio input track per session, canonical
runtime-owned arm state, 1/2/4/8 bar recording lengths, bar-quantized ARM,
destructive replace, mutually exclusive Input versus Loop monitor routing, and
runtime failure states. Audio Looping must consume that model instead of
creating parallel page-local state.

## Product-Owner Lock

### Q1 - First Audio Looping scope

**Locked: product-owner decision required before spec or build promotion.**

The accepted prototype and user stories describe a plural performance page:
multiple loop-capable tracks, per-track arm controls, and a global record
action that starts all armed tracks together. Landed Input Audio v1 deliberately
supports a maximum of one audio input track and defers shared input
distribution.

Recommended default:

**Narrow Audio Looping v1 to a one-capable-track macro page on top of Input
Audio v1, while preserving the plural/global-record prototype as target intent
for the later multi-track expansion.**

Reason:

- It lets the feature proceed after Input Audio without reopening the input
  distribution layer.
- It keeps the macro performance surface valuable as a fast one-track loop
  controller.
- It does not discard the accepted plural prototype; it records that prototype
  as the north-star page once multiple audio input tracks exist.

Alternative:

Wait to promote Audio Looping until multiple audio input tracks and shared
input distribution are explicitly in scope. This preserves the accepted
prototype literally, but blocks the lane behind a larger Input Audio expansion.

Until this choice is answered, no builder-facing `spec.md`, `plan.md`, or
`implementation-handoff.md` should be written.

## Closed Questions

### Q2 - Prototype target versus v1 narrowing

**Closed for PM packaging, pending Q1 for v1 scope.**

`prototypes/looping-page-primary.html` remains accepted target intent for the
macro looping workflow. It should not be treated as a literal v1 builder
contract while Input Audio supports only one audio input track.

If Q1 accepts the recommended default, the v1 narrowing note is:

- show only the single `.audioInput` track when present;
- show the no-loop-capable-track empty state when absent;
- keep global record visually present only if it can honestly act on the one
  canonical armed track, or reduce it to the same ARM/record command exposed in
  the track card;
- defer simultaneous multi-track record, plural armed-track coordination, and
  shared input distribution.

### Q3 - Clear loop behavior

**Closed: clear loop remains first-scope behavior for Audio Looping.**

Destructive re-record/replace is not a substitute for story 5. The accepted
Audio Looping intent asks the performer to discard the current recorded loop
and return the track to empty/ready without deleting or recreating the track.

Builder-facing artifacts must specify an explicit runtime buffer reset command
if the lane is promoted:

- remove the recorded loop buffer and waveform/runtime loop metadata;
- stop loop playback if active;
- return the canonical arm state to idle/empty;
- keep the track, input channel, selected bar length, mixer route, and document
  fields intact.

No modal confirmation is required by current accepted intent. A future spec may
choose a compact inline confirm only if it preserves the performance-surface
interaction budget.

### Q4 - Canonical state ownership

**Closed: Audio Looping reflects Input Audio runtime state.**

The page must not introduce a second arm, monitor, recording, playback, or
failure state machine. It reads and mutates the same `EngineController` /
`AudioInputTrackRuntime` state used by the Input Audio track workspace.

The page state mapping is:

| Page concern | Canonical source |
| --- | --- |
| Loop-capable track list | Tracks whose `trackType == .audioInput` and whose route is valid enough for Input Audio runtime participation |
| Arm / pending record / recording / has-loop | `AudioInputTrackRuntime.armState` |
| Selected recording length | Track `recordBarLength` document field, limited to 1/2/4/8 bars |
| Input versus loop playback | `AudioInputTrackRuntime.monitorMode` |
| Empty loop | `recordedLoopBuffer == nil` plus corresponding waveform-empty state |
| Loop playback availability | `monitorMode == .loop` and recorded loop buffer exists |
| Failure or invalid route | Input Audio runtime/device route failure state exposed locally on the card |

SwiftUI for Audio Looping may keep view-only disclosure state such as an inline
clear confirmation. It must not keep independent musical/runtime truth.

### Q5 - Play/mute assumption

**Closed: replace the old play/mute assumption with Input/Loop monitor control
for v1.**

The April prototype assumed the per-track Play/Mute control could map to a
generic track mute. That is no longer the v1 contract.

For the Input Audio-backed scope:

- playing a loop means setting monitor mode to Loop;
- taking the loop out means setting monitor mode to Input;
- mixer mute remains the mixer mute and must not be overloaded by the looping
  page;
- a loop-only silence command that also suppresses live input is a new runtime
  command and is out of scope unless the product owner explicitly asks for it.

The page copy may still use performer-friendly labels, but builder-facing
artifacts must name the canonical command as Input/Loop monitor mode.

## Remaining Readiness Gap

The only product-owner question required before the next PM layer is Q1: one
capable track now, or wait for plural simultaneous looping. After that answer,
PM can write an accepted architecture, spec, plan, and implementation handoff
for the chosen scope.
