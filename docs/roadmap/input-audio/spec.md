---
feature: input-audio
created: 2026-06-03
status: accepted-v1-product-contract
sources:
  - README.md
  - docs/roadmap/input-audio/notes.md
  - docs/roadmap/input-audio/user-stories.md
  - docs/roadmap/input-audio/existing-state.md
  - docs/roadmap/input-audio/ux-review.md
  - docs/roadmap/input-audio/open-questions.md
  - docs/roadmap/input-audio/architecture-review.md
  - docs/roadmap/input-audio/prototype-approval.md
  - docs/roadmap/input-audio/decisions.md
next_artifact: docs/roadmap/input-audio/plan.md
---

# Input Audio Spec

## Purpose

Input Audio makes external audio a first-class performance source in
In-Sequence. A producer can choose an audio interface, create one audio input
track, monitor live hardware input through the mixer, arm a bar-quantized
recording, capture a loop buffer, switch between live input and the recorded
loop, and see waveform feedback on the track page.

This v1 contract supports the project goals of getting sound running quickly,
capturing performance output, and turning a loop the user likes into material
that can sit with the rest of the session.

## V1 Product Contract

### Audio Device Selection

- Preferences has an Audio surface for selecting input and output devices.
- Input and output devices are independently selectable. Aggregate-device
  setup is out of scope.
- Device choices are app preferences, not `.seqai` document state.
- A successful selection updates subsequent audio routing without requiring an
  app restart.
- While a device switch is applying, Preferences shows a short disabled/apply
  state so the user understands the engine is rewiring.
- A failed switch restores the previous successful device UID, persists nothing
  from the failed selection, and shows a non-blocking failed/error state.
- If a previously selected device is missing at launch, the app falls back to
  the system default and shows a non-blocking Preferences banner naming the
  missing device when that context is available.
- Device lists must tolerate normal studio clutter: built-in devices,
  interfaces, virtual devices, Bluetooth devices, and disconnected previously
  selected devices.

### Audio Input Track

- V1 allows a maximum of one audio input track per session.
- Creating an audio input track adds it to the session, gives it a mixer route,
  and starts tracking live input runtime state for that track.
- Once one audio input track exists, the UI disables or hides creation of a
  second one and should explain the one-track v1 limit in local UI copy.
- Removing the track tears down its live input route, capture tap, loop playback
  node, transient buffers, and waveform state.
- The track has no step-pattern grid in v1. Its workspace is centered on input
  monitoring, record controls, loop monitoring, waveform feedback, and mixer
  routing.
- The track has a hardware input-channel selector with mono channel 1, mono
  channel 2, and stereo choices.
- Input-channel changes are available while idle or monitoring. They are locked
  while armed or recording unless the user first cancels the arm state.

### Monitoring Modes

- The track has two user-facing monitor modes: Input and Loop.
- Input mode sends live hardware input to the mixer. If a loop is already
  buffered, the loop does not also play through the mixer in Input mode.
- Loop mode sends the recorded loop to the mixer. Live input passthrough is
  disconnected in Loop mode.
- If Loop mode is selected before a loop exists, the track is silent and the UI
  communicates that no loop is available.
- The prototype's "loop-input" state is represented as Input mode with a loop
  buffered. The UI should still make the buffered loop visible enough that the
  user knows it is available to switch back to Loop mode.
- Switching modes is immediate as a command to the engine, but loop playback is
  bar-locked: entering Loop mode starts loop playback at the next bar boundary.

### Bar Length And Quantized Recording

- The track exposes recording lengths of 1, 2, 4, and 8 bars.
- The default recording length is 2 bars.
- Bar length persists with the track until changed.
- Bar length is locked while armed or recording. The user can cancel arm, change
  the length, then arm again.
- Pressing ARM queues recording for the next bar boundary.
- While armed, the UI shows a pending-trigger state and allows the user to tap
  ARM again to cancel.
- At the next bar boundary, recording starts automatically.
- Recording stops automatically after the selected number of bars.
- Recording continues if the user navigates away from the audio input track
  workspace. The track list or track header shows a recording indicator while
  capture is active.
- When recording completes, the captured loop replaces any previous loop for
  that track. V1 is destructive replace, with no overdub and no confirmation
  dialog at arm time.
- After recording completes, the resulting loop is available in Loop mode and
  plays in time with the session from a bar boundary.

### Waveform And Level Feedback

- Input mode shows live input level feedback.
- Armed and recording states show clear visual progress toward the capture
  boundary.
- During recording, the waveform fills from lightweight streamed bucket updates.
- After recording completes, the waveform is drawn from the actual captured loop
  buffer, not placeholder fixture data.
- Re-recording replaces the waveform when the new loop completes.
- SwiftUI consumes main-thread waveform bucket snapshots only. UI code must not
  read tap-owned capture buffers directly.
- The waveform is read-only in v1. Editing, slicing, trimming, and step
  triggering from the waveform are excluded.

### Mixer And Runtime Behavior

- The live input path and loop playback path both route through the existing
  mixer/pre-master path as a standard track signal.
- V1 uses a direct `engine.inputNode` tap under the one-track limit. A shared
  input distributor is deferred until multiple audio input tracks are in scope.
- Only one of live input or loop playback reaches the mixer at a time.
- Missing or invalid hardware input leaves the track in a non-crashing silent
  state with local UI feedback. ARM is unavailable until a valid input route is
  present.
- ARM, cancel ARM, monitor-mode changes, and input-channel rerouting go through
  explicit engine command or command-queue mutation surfaces. SwiftUI must not
  mutate engine runtime internals directly.
- Runtime-owned state includes arm state, pending start tick, monitor mode,
  capture buffer, recorded loop buffer, capture progress, and waveform scan
  state.
- Authored document state is limited to the track kind, selected bar length,
  and input channel.
- Existing `.seqai` documents must continue to load after the new audio input
  fields and track type are added.

## Acceptance Criteria

- Selecting a different input or output interface in Preferences applies
  routing without app restart, reports applying/success/failure states, and
  restores the last successful device on failure.
- Launching with a missing preferred device falls back to the system default and
  shows a non-blocking Preferences banner.
- Creating an audio input track adds one mixer-routed track with visible live
  input level feedback.
- Attempting to create another audio input track after one already exists is
  prevented by the UI and runtime.
- Selecting 1, 2, 4, or 8 bars before arming produces a recording of the chosen
  musical length at the session tempo used for capture.
- Pressing ARM shows a pending state, starts capture at the next bar boundary,
  and supports cancellation before capture begins.
- Recording auto-stops at the selected bar length and leaves a loop buffer that
  can play back from a bar boundary.
- Input mode and Loop mode route mutually exclusive signals to the mixer.
- Re-arming after a loop exists replaces the previous loop when the new capture
  completes.
- Navigation away during recording does not cancel capture, and the active
  recording state remains visible outside the workspace.
- The waveform display updates during recording and renders the completed loop
  from captured audio data.

## V1 Exclusions

- More than one audio input track per session.
- A shared input distribution layer for multiple audio input tracks.
- Aggregate-device setup.
- User controls for sample rate or buffer size.
- A step-sequencer grid on the audio input track.
- Waveform editing, slicing, trimming, or step-triggering.
- Overdub recording.
- Time-stretching, pitch-shifting, or BPM-change adaptation after recording.
- Simultaneous live input plus loop playback through the mixer.
- Persisting captured PCM loop buffers into `.seqai`.
- Exporting captured audio files.
- Production styling, spacing, or DOM structure from the HTML prototypes as
  implementation requirements.

## Carry-Forward Risks For Plan

- CoreAudio/AUHAL device switching should be validated before broad UI polish,
  because failure recovery is part of the accepted contract.
- Bar-locked loop playback needs focused scheduling validation against
  `TickClock`, `AVAudioPlayerNode`, and engine sample time.
- Capture completion and waveform publication need thread-discipline checks so
  render-adjacent tap state is not read directly by SwiftUI.
- Adding `.audioInput` requires a complete `TrackType` switch audit across the
  app.

## Product-Owner Attention

No product-owner decision is needed for this spec. The accepted UX review,
prototype approval, open-question reconciliation, architecture review, and v1
decisions provide enough PM authority for `plan.md` authoring.
