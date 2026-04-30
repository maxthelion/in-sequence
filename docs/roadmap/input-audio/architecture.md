---
feature: input-audio
created: 2026-04-30
---

# Input Audio — Architecture

This document is the architecture guardrails pass for the Input Audio feature.
It draws on `user-stories.md`, `existing-state.md`, `ux-review.md` (accepted,
2026-04-30), the audio-looping ux-review (accepted, 2026-04-30), and the wiki
pages for engine-architecture, routing, track-destinations, document-model,
and architecture-guardrails. It is input for `architecture-review.md`; spec must
not be written until that review carries `verdict: accepted`.

---

## 1. Application Invariants the Feature Must Preserve

1. **Document-truth separation.** Only authored musical state belongs in the
   `.seqai` document. Capture buffers, transient arm state, pending-trigger
   flags, and real-time waveform scan data are runtime/session state and must
   never be written into the document. The architecture-guardrails page is
   explicit: "transient capture/history buffers" are out of document scope.

2. **One canonical source of playback truth.** The current app preserves this
   by compiling `PlaybackSnapshot` from document state before each tick. Adding
   a live audio path must not introduce a second playback truth. The audio
   engine's capture tap and monitor routing are runtime-only; they do not
   replace or shadow the snapshot.

3. **Optional-field document compatibility.** Any new fields on
   `StepSequenceTrack` or `Project` must use `encodeIfPresent` /
   `decodeIfPresent` so existing `.seqai` files load cleanly into a build that
   has this feature. This pattern is already followed by `attachedGeneratorID`
   in `TrackPatternBank`.

4. **No allocation or locking on future render thread.** The AVAudioEngine
   install-tap callback is a render-adjacent context. Buffer accumulation in the
   tap block must use pre-allocated ring/PCM buffers, not Swift heap allocation.
   This is a "future-thread discipline" guardrail per architecture-guardrails §
   "Realtime And Future Audio Thread Rules."

5. **No broad rewrites to existing dispatch paths.** `EngineController`'s
   `syncAudioOutputs(for:)` and `syncSampleMixers(for:)` handle AU and sample
   destinations. The audio input path should be an additive branch, not a
   replacement of those methods.

6. **TrackType extensibility audit.** `TrackType` is `CaseIterable` and drives
   UI dispatch in multiple switch statements (existing-state § 7). Adding
   `.audioInput` requires a complete audit of those switch sites. The
   implementation loop must not leave unhandled cases as implicit fallthrough.

---

## 2. Data / Runtime Model

### 2.1 Persisted fields (in `.seqai` document, on `StepSequenceTrack`)

These fields represent authored decisions that must survive save/load:

| Field | Type | Notes |
|---|---|---|
| `trackType` | `TrackType` — new `.audioInput` case | Drives UI dispatch and engine sync |
| `recordBarLength` | `Int` (1, 2, 4, or 8) | Default 2. The bar count chosen before arming. |
| `inputChannel` | `AudioInputChannel` (new enum: `.mono1`, `.mono2`, `.stereo`) | Per-track hardware channel assignment. Confirmed in scope per UX Q11. |

No other audio-input fields belong in the document. Arm state, pending-trigger
state, and captured PCM data are all transient.

### 2.2 Transient session state (not persisted; lives in `EngineController` or a new `AudioInputTrackRuntime`)

| Field | Type | Notes |
|---|---|---|
| `armState` | `AudioInputArmState` enum: `.idle`, `.armed`, `.recording`, `.hasLoop` | Canonical arm state. Owner: `EngineController` (per §3 below). |
| `monitorMode` | `AudioInputMonitorMode` enum: `.liveInput`, `.loop` | Whether the track passes live signal or recorded loop to the mixer. |
| `captureBuffer` | `AVAudioPCMBuffer` | Pre-allocated at arm time based on `recordBarLength` × samples per bar at session sample rate. |
| `captureWritePosition` | `Int` (frame index) | How many frames have been written into the capture buffer. Reset at arm. |
| `pendingStartTick` | `Int?` | The tick index at which recording should begin. Set at arm time. Cleared on recording start. |
| `recordedLoopBuffer` | `AVAudioPCMBuffer?` | The completed loop, kept in memory until replaced or the track is removed. |
| `waveformBuckets` | `[Float]` | Downsampled from `recordedLoopBuffer` after recording completes. Used by `WaveformView`. |

These fields are owned by a new `AudioInputTrackRuntime` struct (or equivalent)
held per-track inside `EngineController`, analogous to how `EngineController`
currently holds per-track generator IDs and output runtimes.

### 2.3 Audio device preference (not in document; app-support preference)

Per the document-model guardrails ("No window state"), device selection belongs
in `UserDefaults` or an app-support JSON file, not in `.seqai`. The preferred
pattern in this codebase is a dedicated store (analogous to `RecentVoicesStore`
at `~/Library/Application Support/sequencer-ai/voices/history.json`).

Proposed: `AudioDevicePreference` stored at
`~/Library/Application Support/sequencer-ai/audio-device.json`.
Fields: `preferredInputDeviceUID: String?`, `preferredOutputDeviceUID: String?`.

UIDs are stable across reboots on macOS (unlike `AudioDeviceID` integers).

---

## 3. Arm State Ownership (Boundary with Audio Looping)

The audio-looping ux-review (§ "Cohesion with Input Audio," open Q3) raised the
question: does arm state live in the Input Audio track model, or in a parallel
looping-page concept?

**Decision: arm state is owned by `EngineController` as part of
`AudioInputTrackRuntime`, keyed by `trackID`. Both the single-track workspace
(Input Audio) and the looping page (Audio Looping) read from and write to the
same state via `EngineController`.**

Rationale:
- Arm state is not authored document data; it is live session state.
- There is already one authoritative runtime owner for per-track session state:
  `EngineController`.
- Duplicating arm state into a looping-page-specific store would create two
  sources of truth — a red flag per architecture-guardrails §
  "Small Boundaries Over Broad Rewrites."
- The audio-looping feature's architecture pass should reference this document
  as the canonical arm-state source and treat the looping page as a view into
  `EngineController`.

The audio-looping page's ARM button calls the same mutation path as the
single-track workspace ARM button — they are two views of the same state.

---

## 4. Resolving the Five Most Consequential UX Open Questions

### Q1 — Engine restart on device switch

**Resolved: no full engine restart required for most device switches; a short
rewire phase (~0.5–1 s) is sufficient.**

On macOS, `AVAudioEngine` wraps a HAL `AudioUnit` (AUHAL). Switching the
underlying input device can be done by:
1. Stopping the engine (`engine.stop()`).
2. Setting the device UID on the AUHAL element via `AudioUnitSetProperty` with
   `kAudioOutputUnitProperty_CurrentDevice`.
3. Restarting the engine (`try engine.start()`).

This is faster than full teardown and node reconnection. The preferences
prototype's ~1 s disabled state and busy indicator is the correct UX shape.
The spec must also define a failure path: if `engine.start()` throws after
rewire (e.g., the device claims exclusive access), the preferences UI must show
an error state and fall back to the previous device UID. This failure path is
missing from the prototype (ux-review Q5).

The app-support `AudioDevicePreference` is updated only on success, not
optimistically on selection.

### Q2 — Independent vs. aggregate device selection

**Resolved: independent input/output device selection.**

The prototype shows this correctly. macOS HAL natively supports separate input
and output devices via separate AUHAL units (or one AUHAL unit with separate
input/output element configuration). AVAudioEngine uses this. No aggregate
device is needed unless the user wants to sync clock between two interfaces —
which is out of scope for this milestone. `AudioDevicePreference` stores
`preferredInputDeviceUID` and `preferredOutputDeviceUID` as independent fields.

### Q6 — Step-pattern grid on the audio input track

**Resolved: no step-sequencer pattern grid on the audio input track in this
milestone.**

The UX review called this "a meaningful product decision." The user stories and
notes do not describe a pattern grid. The slicer track has one because slices
are triggered by pattern steps; the audio input track captures and loops live
audio without step-triggered playback. Adding a grid would require a third
layout region (the prototype has no space for it), a new pattern kind, and
significant engine work.

The architecture defers the grid entirely. The audio input track workspace has
two regions only: the waveform/record/monitor panel (left-centre) and the mixer
routing stub (bottom). This is consistent with the accepted prototype 02 layout.

If the user later requests step-trigger-from-loop (e.g., "play a slice of the
loop on each step"), that belongs in a follow-on feature or an extension of the
slicer destination model.

### Q7 — Live input routing when in Loop mode

**Resolved: live input is gated by monitor mode; only one signal path reaches
the mixer at a time.**

When `monitorMode == .liveInput`:
- The `AVAudioEngine.inputNode` tap is connected to the pre-master mixer via a
  passthrough node.
- The recorded loop buffer is not sent to the mixer.

When `monitorMode == .loop` (and a loop exists):
- The recorded loop plays back via a looped `AVAudioPlayerNode` connected to
  the pre-master mixer.
- The input node tap is installed for recording capability only; the passthrough
  to the mixer is disconnected.

When `monitorMode == .loop` and no loop exists:
- Neither signal reaches the mixer. The track is silent.

This is a clean separation that avoids summing live and loop signals
accidentally. The "loop-input" state in the prototype (loop buffered, monitoring
live input simultaneously) maps to `monitorMode == .liveInput` with
`armState == .hasLoop` — it is not a distinct routing mode, just the state
where loop data exists but the user has chosen to monitor live input again.
The spec should confirm whether this concurrent state is intentional product
behaviour or should require the user to explicitly re-arm.

### Q8 — Overdub vs. destructive replace

**Resolved: destructive replace for this milestone; no confirmation dialog.**

Rationale:
- Overdub requires mixing into the existing PCM buffer, which adds audio
  processing complexity (gain normalisation, format matching).
- The user stories make no mention of overdub; the analogous Octatrack feature
  also defaults to destructive replace.
- The prototype shows destructive replace with no warning; the ux-review notes
  this as acceptable for the prototype but flags it for spec.
- For a first milestone, silent overwrite on next recording completion is
  sufficient. The spec should note that no confirmation dialog is shown at arm
  time, but the ARM button's visual state (pulsing amber) communicates that a
  recording is about to happen.

If overdub is added later, it becomes a new `armMode` enum case rather than a
change to the core record path.

---

## 5. Remaining Open Questions Resolved Without User Input

**Q3 — Sample rate / buffer size controls:** Defer to a later milestone. The
preferences prototype's subordinated section is correct. The spec must explicitly
exclude these from the v1 scope. Device selection is sufficient; the engine will
use the device's default sample rate and buffer size.

**Q4 — Missing device at next launch:** Fall back silently to the system default
input/output devices and show a banner in Preferences ("Previously selected
device 'Scarlett 2i2' is not connected — using system default"). No blocking
error or launch gate. The banner dismisses when a device is selected or the user
closes Preferences.

**Q9 — Real-time waveform during recording:** Real-time fill (streamed). The
prototype's animated fill is the accepted UX. The implementation must maintain a
lightweight running-max array alongside the capture buffer and publish bucket
updates on a display-link or timer callback from the UI layer. The implementation
loop must not access the capture buffer directly from the main thread; bucket
updates are the only UI-facing data derived from the render-adjacent tap.

**Q10 — BPM change after recording:** Out of scope. The spec must explicitly
state that the loop is fixed at its recorded sample length. No time-stretching or
pitch-shifting is performed. If BPM changes after recording, the loop plays at
its original duration and drifts relative to the new tempo. This is acceptable
for a v1 performance tool.

**Q11 — Per-track hardware channel selector:** In scope. Confirmed by the
prototype and practical necessity. The `inputChannel` field on
`StepSequenceTrack` (§2.1) carries this. The implementation must re-route the
AUHAL input element format when the channel changes.

**Q12 — Navigation away while recording:** Recording continues in the background
(does not stop when the user navigates to another track). `armState` remains
`.recording` on the track's runtime regardless of which workspace view is
visible. The track list should show a red recording indicator (a small pulsing
dot or label) on the audio input track card while `armState == .recording` so
the user has visual feedback from outside the workspace.

---

## 6. Audio Engine Architecture

### 6.1 Device enumeration and selection

A new `AudioDeviceEnumerator` (in `Sources/Audio/`) will:
- Use `AudioObjectGetPropertyData` with `kAudioHardwarePropertyDevices` to list
  `AudioDeviceID`s.
- Filter by direction (input or output) using
  `kAudioDevicePropertyStreams`.
- Expose `AudioDeviceSummary` value types: `{ id: AudioDeviceID, uid: String, name: String, channelCount: Int }`.
- Publish updates when devices are added or removed via
  `kAudioHardwarePropertyDevices` property listener.

This is analogous to how `MIDISession` enumerates MIDI endpoints. No
`AVAudioEngine` knowledge; pure CoreAudio.

### 6.2 Engine device switching

`MainAudioGraph` gains a method `setInputDevice(uid: String) throws` and
`setOutputDevice(uid: String) throws`. Each:
1. Stops the engine.
2. Gets the `AudioDeviceID` for the UID.
3. Sets it on the AUHAL input/output element via `AudioUnitSetProperty`.
4. Restarts the engine.
5. On failure, restores the previous device UID and rethrows.

The preferences view model calls this method and reflects the applying/applied/
failed state.

### 6.3 Input node tap and monitor routing

For each audio input track, `MainAudioGraph` installs a tap on
`engine.inputNode` filtered to the track's `inputChannel`. (If multiple audio
input tracks are created in the future, a shared input mixer distributes the
signal; for v1, one audio input track is sufficient.)

Two `AVAudioNode` connections are managed per track:
- **Passthrough node:** `inputNode` → `AVAudioMixerNode` (input monitor mixer)
  → `preMasterMixer`. Active when `monitorMode == .liveInput`.
- **Playback node:** `AVAudioPlayerNode` (loop player) → `preMasterMixer`.
  Active when `monitorMode == .loop` and a loop buffer exists.

Switching monitor mode disconnects one and connects the other. Node connections
in `AVAudioEngine` can be changed while the engine is running (by stopping the
relevant node first), which avoids a full engine restart on mode switch.

### 6.4 Capture tap

`engine.inputNode.installTap(onBus:bufferSize:format:block:)` accumulates
frames into the pre-allocated `captureBuffer`. The tap block:
1. Is render-adjacent; no allocation, no Swift class creation.
2. Advances `captureWritePosition`.
3. Updates the running-max bucket array for waveform display (lightweight
   per-bucket comparison, no allocation).
4. When `captureWritePosition >= captureBuffer.frameLength`, atomically sets a
   completion flag (use `os_unfair_lock` or a `UnsafeAtomic<Bool>`).

The `TickClock` callback in `EngineController.prepareTick` checks the completion
flag and, if set:
1. Copies `captureBuffer` into `recordedLoopBuffer`.
2. Triggers waveform bucket finalisation.
3. Transitions `armState` to `.hasLoop`.
4. Removes the capture tap.
5. Establishes the loop playback node.

### 6.5 Quantized arm and `TickClock` integration

When the user taps ARM:
1. `EngineController` sets `armState = .armed` for the track.
2. It computes `pendingStartTick`: the next tick index where
   `tickIndex % stepsPerBar == 0` (bar boundary).
3. `pendingStartTick` is stored in `AudioInputTrackRuntime`.

On each `prepareTick`, `EngineController` checks: if `armState == .armed &&
tickIndex == pendingStartTick`:
1. Pre-allocates `captureBuffer` (frames = `recordBarLength × beatsPerBar ×
   (60 / BPM) × sampleRate`, computed at this moment to capture current BPM).
2. Installs the capture tap.
3. Sets `armState = .recording`.
4. Clears `pendingStartTick`.

This reuses the existing `prepareTick` location without adding a new command
kind — the arm command is a UI mutation that sets `AudioInputTrackRuntime`
fields; the tick loop reads those fields.

An alternative is a new `.armRecord(trackID)` / `.cancelArm(trackID)` command
pair in `CommandQueue`. This is cleaner if the command queue is the intended
UI-to-engine communication channel for all state. Both approaches are sound;
the implementation loop should choose based on whether the current command-queue
pattern already handles per-track transient state.

---

## 7. Mutation Paths

| Trigger | Mutation | Owner |
|---|---|---|
| User picks input device in Preferences | `AudioDevicePreference.preferredInputDeviceUID` updated; `MainAudioGraph.setInputDevice(uid:)` called | `PreferencesViewModel` → `MainAudioGraph` |
| User creates audio input track | New `StepSequenceTrack` with `trackType: .audioInput`, `recordBarLength: 2`, `inputChannel: .stereo`; document updated; `EngineController` sets up `AudioInputTrackRuntime` | Document mutation + `EngineController.syncAudioOutputs` extension |
| User selects bar length | `StepSequenceTrack.recordBarLength` updated in document | Document mutation |
| User selects input channel | `StepSequenceTrack.inputChannel` updated in document; `EngineController` re-routes input tap | Document mutation + engine re-route |
| User taps ARM (from track workspace or looping page) | `AudioInputTrackRuntime.armState = .armed`, `pendingStartTick` computed | `EngineController` (UI sends command or direct call) |
| User cancels ARM | `AudioInputTrackRuntime.armState = .idle`, `pendingStartTick = nil` | `EngineController` |
| Bar boundary reached while armed | `EngineController.prepareTick` detects `pendingStartTick`; allocates buffer; installs tap; `armState = .recording` | `EngineController` (tick loop) |
| Recording completes (buffer full) | Tap completion flag detected in `prepareTick`; `recordedLoopBuffer` set; `armState = .hasLoop`; waveform buckets finalised | `EngineController` (tick loop) |
| User toggles Input/Loop mode | `AudioInputTrackRuntime.monitorMode` toggled; `MainAudioGraph` reconnects nodes | `EngineController` (UI command) |
| User navigates away while recording | No change; `armState` persists across workspace navigation | `EngineController` (state is engine-owned, not view-owned) |

---

## 8. Existing Patterns to Follow

- **`RecentVoicesStore`** as the pattern for `AudioDevicePreference` storage
  (app-support JSON, read at launch, written on change).
- **`WaveformDownsampler`** as the conceptual reference for bucket generation,
  but adapted for a PCM buffer source (not a file URL). A new
  `AudioInputWaveformBuffer` type should own the running-max state.
- **`WaveformView`** is reusable as-is; it renders `[Float]` buckets regardless
  of source.
- **`SliceTrackWorkspaceView`** as the layout reference for the audio input
  track workspace view: waveform region top, controls below, mixer routing stub
  at bottom.
- **`TrackType` switch audit:** follow the pattern established when `.slice` was
  added — audit every `switch trackType` in `Sources/` and add an `.audioInput`
  branch.
- **`decodeIfPresent` / `encodeIfPresent`** for all new `StepSequenceTrack`
  fields (follow `attachedGeneratorID` precedent).

---

## 9. Risks and Dependencies

1. **CoreAudio AUHAL property-set on macOS.** This is the only approach to
   device switching that avoids full engine teardown. It requires direct
   `AudioUnitSetProperty` calls with `kAudioOutputUnitProperty_CurrentDevice`.
   If Apple's implementation of `AVAudioEngine` does not support this cleanly
   (e.g., internal state inconsistency after property set), a full engine
   rebuild may be needed and the preferences UX would need to reflect longer
   downtime. This risk must be validated early in implementation (spike before
   spec is written).

2. **Multiple audio input tracks.** The architecture above assumes one audio
   input track per session (sufficient for v1). If the user creates a second
   audio input track, the single `engine.inputNode` tap must multiplex to both
   tracks' capture buffers and monitor nodes. This is solvable with a shared
   input mixer node, but the v1 spec should explicitly limit to one audio input
   track and enforce this in the UI (disable the "Create audio input track"
   action if one already exists).

3. **AVAudioEngine and `inputNode` on macOS vs. iOS.** The existing-state report
   notes that `engine.inputNode` is available on macOS. The feature is macOS-
   only for this milestone. No iOS considerations.

4. **Thread discipline for completion flag.** The tap completion flag shared
   between the render-adjacent tap and `prepareTick` (which runs on the
   `TickClock` DispatchSourceTimer queue) must use an atomic primitive or a
   lock-free mechanism. Swift's `Atomic` (from swift-atomics, if available) or
   `OSAtomicTestAndSet` is appropriate. This is a correctness requirement, not
   just a performance one.

5. **Dependency on audio-looping feature.** The arm state ownership defined here
   (§3) is the contract the audio-looping feature's architecture must reference.
   Audio looping cannot be specced until this architecture document is reviewed
   and accepted.

6. **`TrackType` extensibility audit scope.** The existing-state report lists
   multiple switch sites but does not enumerate them exhaustively. The
   implementation loop must grep all `switch trackType` occurrences in
   `Sources/` before adding the new case to ensure no silent fallthrough.

---

## 10. Architecture Questions for Review

The following questions are not blockers for beginning the review, but the
architecture reviewer should address them:

A. **Single vs. shared inputNode tap.** For a single audio input track, a
   direct tap on `inputNode` is simplest. If the app ever supports two audio
   input tracks, a shared tap feeding multiple buffers is needed. Should the
   architecture already abstract this via an "input distribution node," or is a
   v1 direct tap with a one-track limit acceptable?

B. **`CommandQueue` vs. direct field mutation for arm state.** Should ARM /
   cancel-arm be `CommandQueue` items (consistent with the existing
   `setParam`/`setBPM` pattern), or should arm state be a direct field set on
   `AudioInputTrackRuntime` from the UI layer (acceptable because
   `EngineController` already guards its internals with its own queue)? The
   architecture does not mandate one; both are sound. The review should pick one
   for spec.

C. **`AVAudioPlayerNode` loop playback.** `AVAudioPlayerNode.scheduleBuffer(_:
   at:options:completionCallbackType:completionHandler:)` with the `.loops`
   option is the standard loop-playback pattern. However, the loop must start
   sample-accurately at the bar boundary where the recording ended, not at an
   arbitrary time. The architecture review should confirm whether loop start
   timing relative to the `TickClock` is required for v1 (Octatrack-style lock)
   or whether a best-effort start (loop playback begins immediately on mode
   switch) is acceptable.

D. **Waveform bucket publishing to UI.** The running-max bucket array is updated
   in the tap block (render-adjacent). SwiftUI must not read this array directly.
   The recommended pattern is a `@Published` bucket array on an
   `ObservableObject` updated via `DispatchQueue.main.async` from a display-link
   or periodic timer. The review should confirm this is the correct seam.
