---
feature: input-audio
created: 2026-06-03
status: ready-for-build-loop-promotion
sources:
  - README.md
  - docs/roadmap/input-audio/spec.md
  - docs/roadmap/input-audio/plan.md
  - docs/roadmap/input-audio/architecture-review.md
  - docs/roadmap/input-audio/architecture.md
  - docs/roadmap/input-audio/existing-state.md
  - docs/roadmap/input-audio/decisions.md
  - docs/roadmap/input-audio/open-questions.md
  - docs/roadmap/input-audio/prototype-approval.md
  - docs/roadmap/input-audio/ux-review.md
---

# Input Audio Implementation Handoff

## Purpose

This handoff packages the accepted Input Audio v1 PM artifacts into
builder-ready scope. It should be used to open a future build loop, but it does
not itself promote a build loop or route implementation.

Input Audio v1 makes external audio a first-class performance source in
In-Sequence: a producer can select audio hardware, create one audio input track,
monitor live input through the mixer, record a quantized loop buffer, switch
between live input and loop playback, and see useful waveform/level feedback.

## Build-Loop Boundary

A future build loop should own the full Input Audio v1 workflow end to end:

- Preferences-based independent input and output device selection.
- One audio input track per session.
- Mixer-routed live input monitoring.
- Input versus Loop monitor modes, with only one signal reaching the mixer at a
  time.
- Hardware input-channel selection: mono channel 1, mono channel 2, stereo.
- Bar-quantized ARM, cancel-before-start, auto-start, auto-stop, and destructive
  loop replace.
- Bar-locked loop playback when entering Loop mode.
- Live level feedback plus streamed and completed waveform bucket publication.
- Document compatibility for existing `.seqai` files.

The build loop should remain additive to the existing document, engine, mixer,
sample, slicer, and workspace paths. Do not broaden this into audio looping,
loop slicing, waveform editing, multiple input tracks, export, or generalized
audio graph replacement.

## Exact First Implementation Slice

The first slice is CoreAudio device enumeration, preference persistence, and
AUHAL switch/rollback validation only.

Build the smallest engine-facing path that can:

- enumerate input and output devices with UID, display name, direction, and
  channel count;
- persist `preferredInputDeviceUID` and `preferredOutputDeviceUID` outside
  `.seqai` document state;
- apply an input UID and output UID to the running macOS audio engine path;
- show an applying/success/failure state through a minimal Preferences-facing
  surface or validation harness;
- roll back to the previous successful UID after a failed switch and persist
  nothing from the failed selection;
- fall back to the system default when a previously preferred device is missing
  at launch, with non-blocking Preferences feedback.

Do not add `.audioInput`, the audio input workspace, waveform UI, or bar-locked
recording until this slice records reliable AUHAL switching evidence or records
the architecture rework condition below.

## AUHAL Stop / Architecture-Rework Condition

If setting the AUHAL current-device property by UID cannot be made reliable for
the local macOS `AVAudioEngine` path, stop the build loop before broad UI or
track-model work.

The stop condition is met if the implementation cannot demonstrate all of:

- successful input and output device switch without app restart;
- engine recovery after stopping, applying the UID, and restarting;
- failed-switch rollback to the previous successful UID;
- no failed UID persisted into app preferences;
- missing preferred device fallback to the system default.

When this condition is met, write architecture-rework evidence instead of
continuing. The rework should decide whether Input Audio needs a fuller graph
rebuild strategy, different device ownership in `MainAudioGraph`, or changed
Preferences downtime/error UX. Do not hide this behind prototype polish.

## Subsequent Builder Slices

After the device-switch validation slice passes, continue in this order:

1. Add `.audioInput` authored model fields and document compatibility coverage.
   Persist only track kind, `recordBarLength` defaulting to 2 bars, and
   `inputChannel`. Use optional/default-safe Codable handling.
2. Complete the `TrackType` switch audit across `Sources/`, with explicit
   `.audioInput` behavior for creation, naming, workspace routing, clip/pattern
   shape, mixer display, destinations, transport indicators, and fixtures.
3. Add engine-owned `AudioInputTrackRuntime` state keyed by track ID plus command
   surfaces for ARM, cancel ARM, monitor-mode changes, and input-channel
   rerouting. SwiftUI must not mutate runtime internals directly.
4. Wire the direct v1 `engine.inputNode` tap and live input path through the
   existing pre-master mixer. Add loop playback through `AVAudioPlayerNode`.
   Ensure Input and Loop monitoring are mutually exclusive at the mixer.
5. Implement `TickClock`/bar-boundary capture and loop scheduling: next-bar ARM
   start, auto-stop after 1/2/4/8 bars, destructive replace, navigation-away
   continuity, and bar-locked Loop mode playback.
6. Publish live level, recording progress, streamed waveform buckets, and final
   waveform buckets through copied main-thread snapshots. SwiftUI must never
   read tap-owned buffers directly.
7. Build the accepted user-facing surfaces: Preferences device selection, one
   audio input track creation, local one-track-limit copy, hardware channel
   selector, bar length selector, ARM/cancel states, Input/Loop mode, unavailable
   loop/input states, waveform/level display, mixer routing affordance, and
   recording indicators outside the workspace.
8. Run the final regression pass across existing audio graph, sample, slicer,
   track, document, and workspace behavior.

## Required Exit Evidence

The build loop is complete only when it leaves compact evidence for:

- AUHAL device-switch validation, including success, failed-switch rollback, and
  missing-device fallback.
- Document compatibility: old `.seqai` documents load, new audio-input tracks
  save/load, and captured PCM is not persisted.
- `TrackType` switch audit listing each touched site and chosen `.audioInput`
  behavior.
- Runtime command coverage for ARM, cancel ARM, monitor-mode changes,
  input-channel rerouting, one-track enforcement, track removal teardown, and
  invalid-route silent state.
- Mixer-routing behavior for Input mode, Loop mode, Loop-without-buffer silence,
  no live-plus-loop double monitoring, mono channel 1, mono channel 2, stereo,
  and unavailable input.
- Scheduling behavior for next-bar ARM start, cancel-before-start, auto-stop for
  1/2/4/8 bars, destructive replace, navigation-away recording continuity, and
  bar-locked loop playback.
- Thread-discipline review proving SwiftUI consumes copied waveform/level
  snapshots only.
- Visual evidence for Preferences and the audio input workspace, including
  applying/failure/missing-device states, idle/armed/recording/loop states,
  Loop-without-buffer, one-track-limit UI, waveform feedback, and recording
  indicator outside the workspace.
- Regression checks for existing melodic, poly melodic, slice, sample, mixer,
  document, and workspace flows.

## V1 Exclusions

Do not implement or infer these in v1:

- more than one audio input track per session;
- shared input distribution for multiple audio input tracks;
- aggregate-device setup;
- sample-rate or buffer-size controls;
- a step-sequencer grid on the audio input track;
- waveform editing, slicing, trimming, or step-triggering;
- overdub recording;
- time-stretching, pitch-shifting, or BPM-change adaptation after recording;
- simultaneous live input plus recorded loop playback through the mixer;
- captured PCM persistence in `.seqai`;
- captured-audio file export;
- production styling, spacing, or DOM structure from the HTML prototypes as
  implementation requirements.

## Residual Risks

- AUHAL device switching may require architecture rework if property switching
  does not recover the existing `AVAudioEngine` path reliably.
- Bar-locked playback needs focused timing validation across `TickClock`,
  `AVAudioPlayerNode`, engine sample time, and transport state.
- Tap completion and waveform publication are correctness risks if shared state
  uses allocation, unsafe locking, or direct UI reads.
- Adding `.audioInput` can regress existing app flows if any `TrackType` switch
  site relies on default behavior.
- Existing global project readiness summaries may lag these PM artifacts; use
  this file and the durable PM summary as the current PM lane readiness source.

## Product-Owner Attention

No product-owner decision is needed for build-loop promotion. The accepted UX
review, prototype approval, reconciled open questions, architecture review,
decisions, spec, and plan close the v1 product choices needed for implementation.
