---
feature: input-audio
created: 2026-06-03
status: ready-for-implementation-handoff
sources:
  - README.md
  - docs/roadmap/input-audio/spec.md
  - docs/roadmap/input-audio/architecture-review.md
  - docs/roadmap/input-audio/architecture.md
  - docs/roadmap/input-audio/existing-state.md
  - docs/roadmap/input-audio/decisions.md
  - docs/roadmap/input-audio/open-questions.md
next_artifact: docs/roadmap/input-audio/implementation-handoff.md
---

# Input Audio Implementation Plan

## Purpose

This plan translates the accepted v1 Input Audio product contract into a
builder-ready implementation sequence. It preserves the README intent around
getting sound running quickly, capturing performance output, and turning liked
loops into arrangement material, while keeping the architecture review's
document/runtime, timing, and thread-discipline boundaries intact.

The plan is intentionally validation-first. Builders should prove the risky
CoreAudio/AUHAL and scheduling paths before spending broad effort on UI polish.

## Scope Boundary

V1 implements:

- Preferences-based independent input and output device selection.
- One audio input track per session.
- Mixer-routed live input monitoring.
- Input versus Loop monitoring modes, with mutual exclusion at the mixer.
- Hardware input-channel selection: mono channel 1, mono channel 2, stereo.
- Bar-quantized ARM, auto-start, auto-stop, and destructive loop replace.
- Bar-locked loop playback when entering Loop mode.
- Live level feedback and streamed/completed waveform bucket publication.
- Document compatibility for existing `.seqai` files.

V1 does not implement multiple audio input tracks, aggregate-device setup,
sample-rate or buffer-size controls, a step-pattern grid, waveform editing,
slicing, trimming, overdub, time-stretching, pitch-shifting, captured PCM
persistence, or audio-file export.

## Implementation Sequence

### 1. Validate CoreAudio Device Switching First

Goal: prove the Preferences contract before broad UI or track-workspace work.

Build the smallest engine-facing slice that can enumerate devices and switch
the active input/output device by UID:

- Add a CoreAudio device enumeration surface that can list input and output
  devices with UID, display name, direction, and channel count.
- Add a preference store for `preferredInputDeviceUID` and
  `preferredOutputDeviceUID` outside `.seqai` document state.
- Add `MainAudioGraph` device-switch methods for input and output UIDs.
- Validate AUHAL current-device property switching by stopping the engine,
  applying the device UID, restarting the engine, and confirming audio graph
  recovery.
- Implement failed-switch rollback: restore the previous successful UID,
  persist nothing from the failed selection, and surface a non-blocking failure
  state.
- Implement missing-device-at-launch fallback to the system default plus a
  non-blocking Preferences banner.

Exit evidence:

- A focused device-switch validation result that records whether AUHAL rewire
  works reliably for the local macOS engine path.
- Tests or manual evidence for success, failed switch rollback, and missing
  preferred device fallback.
- If AUHAL switching cannot be made reliable, stop and record an architecture
  rework need before continuing into UI polish.

### 2. Add Document Model And Compatibility

Goal: make `.audioInput` authored state explicit without breaking existing
documents.

Add the persisted v1 fields only:

- `TrackType.audioInput`.
- `StepSequenceTrack.recordBarLength`, defaulting to 2 and constrained to 1,
  2, 4, or 8 bars.
- `StepSequenceTrack.inputChannel`, using an `AudioInputChannel` enum for
  mono channel 1, mono channel 2, and stereo.

Compatibility requirements:

- Decode new fields with `decodeIfPresent`.
- Encode optional/defaulted fields without requiring old documents to carry
  them.
- Do not persist arm state, pending ticks, monitor mode, capture buffers,
  recorded loop buffers, waveform scan state, or audio-device choices.
- Add load/save coverage proving existing `.seqai` documents still decode after
  the new track type and fields are introduced.

Complete `TrackType` switch audit:

- Before landing `.audioInput`, grep all `TrackType` and `switch trackType`
  usages under `Sources/`.
- Add explicit `.audioInput` behavior for track creation, default naming,
  workspace routing, pattern/clip shape, mixer display, transport indicators,
  destination behavior, and any test fixtures.
- Do not rely on `default` branches or implicit fallthrough for the new case.

Exit evidence:

- A switch-audit note listing each touched `TrackType` site and the chosen
  `.audioInput` behavior.
- Document compatibility tests for old documents and a new audio-input track.

### 3. Introduce Engine Runtime And Command Surfaces

Goal: establish one engine-owned runtime source of truth before wiring UI
controls.

Add an `AudioInputTrackRuntime` or equivalent per-track runtime owned by
`EngineController`, keyed by track ID. Runtime state includes:

- arm state: idle, armed, recording, has loop;
- monitor mode: Input or Loop;
- pending start tick;
- capture buffer and write position;
- recorded loop buffer;
- capture progress;
- waveform scan/bucket state.

Add explicit engine command or command-queue mutation surfaces for:

- ARM;
- cancel ARM;
- monitor-mode change;
- input-channel reroute.

The architecture review selected command-queue-style mutations for these
runtime changes. SwiftUI must call those surfaces rather than mutate
`EngineController` internals directly.

Exit evidence:

- Unit coverage for command acceptance, one-track runtime setup/teardown, ARM
  cancellation, and invalid-route silent state.
- A code path showing track removal tears down runtime state, taps, loop
  playback nodes, transient buffers, and waveform state.

### 4. Wire Live Input And Loop Playback Through The Mixer

Goal: route hardware input and recorded loop playback through the existing
pre-master path without broad audio graph rewrites.

Use the accepted v1 direct `engine.inputNode` path:

- Install and manage one input tap under the one-track limit.
- Route live input through a passthrough/input monitor node to the existing
  pre-master mixer when monitor mode is Input.
- Route recorded loop playback through an `AVAudioPlayerNode` to the existing
  pre-master mixer when monitor mode is Loop and a loop exists.
- Keep Loop mode silent when no loop exists.
- Ensure only one of live input or loop playback reaches the mixer at a time.
- Reroute the hardware input channel when the track's channel selection changes,
  but lock channel changes while armed or recording unless ARM is first
  cancelled.
- Extend existing engine sync paths additively; do not replace current AU,
  sample, or slicer routing logic.

Exit evidence:

- Mixer-routing tests or manual engine evidence for Input mode, Loop mode,
  Loop-without-buffer silence, and no live-plus-loop double monitoring.
- Channel-selection evidence for mono 1, mono 2, stereo, and unavailable input.

### 5. Implement Bar-Locked Capture And Playback Scheduling

Goal: make capture and loop playback musically aligned with the sequencer.

Use `TickClock`/transport bar boundaries as the scheduling authority:

- ARM computes or records the next bar boundary as `pendingStartTick`.
- Capture starts only when the tick loop reaches the pending bar boundary.
- Capture buffer length is computed at arm/start time from selected bar length,
  BPM, beats per bar, and sample rate.
- Recording auto-stops after the selected 1, 2, 4, or 8 bars.
- Completion destructively replaces any existing recorded loop buffer.
- Navigating away does not cancel armed or recording state.
- Entering Loop mode schedules loop playback for the next bar boundary.
- BPM-change adaptation after recording remains excluded; the captured loop
  keeps its sample length.

Exit evidence:

- Focused scheduling tests for next-bar ARM start, cancel-before-start,
  auto-stop after each supported bar length, destructive replace, and
  navigation-away persistence.
- Loop playback timing evidence that Loop mode begins on a bar boundary rather
  than immediately.

### 6. Publish Waveform And Level Feedback Safely

Goal: give useful visual feedback without exposing render-adjacent buffers to
SwiftUI.

Implement waveform publication as copied main-thread snapshots:

- The tap updates preallocated running bucket state while recording.
- A display-link or timer-backed publisher copies lightweight bucket snapshots
  to the main thread for SwiftUI.
- Recording progress and live level feedback use the same thread-safe handoff
  rule.
- On capture completion, final waveform buckets are generated from the captured
  loop buffer and published as the stable completed waveform.
- Re-recording replaces the displayed waveform only when the new loop
  completes.

Exit evidence:

- Thread-discipline review showing no SwiftUI code reads tap-owned buffers.
- UI or view-model tests for streamed buckets, final buckets, and waveform
  replacement after re-record.

### 7. Build The User-Facing Surfaces

Goal: expose the accepted v1 workflow without adding out-of-scope controls.

Preferences:

- Device lists for input and output.
- Applying, success, failed, and missing-device banner states.
- Disabled/apply state while the engine is rewiring.
- No v1 sample-rate or buffer-size controls as functional implementation
  scope.

Track creation and navigation:

- Create one audio input track with a mixer route and default 2-bar/stereo
  choices.
- Prevent creating a second audio input track in both UI and runtime.
- Explain the one-track v1 limit in local UI copy.
- Show an active recording indicator outside the workspace when recording
  continues after navigation.

Audio input workspace:

- No step-pattern grid.
- Input-channel selector.
- 1/2/4/8-bar length selector, locked while armed or recording.
- ARM/cancel pending state.
- Input/Loop monitor mode control.
- Loop unavailable state when Loop mode has no buffer.
- Live level, capture progress, streamed waveform, and completed waveform.
- Existing mixer route affordance consistent with other track workspaces.

Exit evidence:

- Visual evidence for Preferences and the audio input workspace.
- Workflow evidence for create track, arm, cancel, record, loop playback,
  re-record, and navigate-away recording indicator.

### 8. Final Integration And Regression Pass

Goal: prove Input Audio is additive and does not regress existing track types.

Required checks:

- Existing audio graph, sample, slicer, track, document, and workspace tests.
- New tests for device preferences, document compatibility, command surfaces,
  scheduling, waveform publication, and one-track enforcement.
- Manual or automated smoke pass for existing melodic, poly melodic, and slice
  tracks after `.audioInput` is added.
- Direct check that old `.seqai` documents still load.
- Direct check that no captured PCM data is persisted into `.seqai`.

Exit evidence:

- Test summary with failures fixed or explicitly recorded.
- Visual/audio evidence for the full v1 workflow.
- Updated implementation handoff evidence naming completed slices, residual
  risks, and any product-owner attention needed.

## Suggested Builder Slices

1. CoreAudio device enumeration, preference persistence, AUHAL switch/rollback
   validation.
2. `.audioInput` document model, compatibility tests, and complete
   `TrackType` switch audit.
3. Engine runtime state plus command surfaces for ARM, cancel, monitor mode,
   and input-channel reroute.
4. Mixer routing for live input, silent invalid route, and loop playback node.
5. Bar-locked capture and loop playback scheduling.
6. Waveform/level snapshot publication.
7. Preferences UI and audio input workspace UI.
8. Integration evidence and regression pass.

Builders may combine adjacent slices only after the CoreAudio validation result
is known. Device switching and timing/thread handoff remain the highest-risk
areas and should not be hidden behind UI completion.

## Quality Gates

- Product contract remains v1: one audio input track, destructive replace,
  Input/Loop mutual exclusion, no step grid, no PCM persistence.
- Audio-device choices are preferences, not document state.
- Runtime-owned capture and monitor state never become document truth.
- UI-to-engine changes use explicit command/mutation surfaces.
- Bar starts and loop playback are validated against tick/sample timing, not
  only by visual state.
- Waveform data crossing to SwiftUI is copied onto the main thread.
- All `TrackType` switch sites are audited for `.audioInput`.
- Existing documents and existing track types continue to work.

## Product-Owner Attention

No product-owner decision is needed for this plan. The accepted UX review,
prototype approval, open-question reconciliation, architecture review,
decisions, and spec close the v1 product choices needed for implementation
planning.
