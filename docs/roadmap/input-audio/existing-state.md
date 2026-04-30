# Input Audio — Existing State

Inspected on 2026-04-29 against branch `codex/tracks-perform-scenes-workspace`.

---

## 1. Track Model

**What exists**

`TrackType` (`Sources/Document/TrackType.swift`) is an enum with three cases: `monoMelodic`, `polyMelodic`, and `slice`. There is no `audioInput` (or equivalent) case.

`Destination` (`Sources/Document/Destination.swift`) has seven cases — `.midi`, `.auInstrument`, `.internalSampler`, `.sample`, `.slicer`, `.inheritGroup`, `.none`. There is no `.audioInput` case and no concept of a hardware-input routing target.

`StepSequenceTrack` carries `trackType: TrackType`, `destination: Destination`, and `mix: TrackMixSettings`. None of these can represent "live audio from an interface". There is also no field for a record buffer, a bar-length selection, a monitor mode (live vs. loop), or a pending-record-trigger state.

**Gaps vs. user stories**

- Stories 2–6 all depend on a new track kind (or destination variant) that the document model does not model.
- No record buffer is defined anywhere in `Sources/Document/` or `Sources/Audio/`.
- No bar-length-in-bars field exists on any track type.
- No quantized-arm / pending-trigger state exists in `Project`, `StepSequenceTrack`, or `EngineController`.

---

## 2. Audio Engine

**What exists**

`MainAudioGraph` (`Sources/Audio/MainAudioGraph.swift`) wraps `AVAudioEngine`. It exposes the engine's `preMasterMixer`, manages master chains (send-effects), and provides attach/detach/connect helpers. It does not touch `engine.inputNode` anywhere. There is no installation of a tap on the hardware input node, no `AVAudioMixerNode` for routing live input to the pre-master mixer, and no recording buffer allocation.

`SamplePlaybackEngine` (`Sources/Audio/SamplePlaybackEngine.swift`) implements `SamplePlaybackSink` for file-backed playback and slice playback. It has no `record(...)` or `captureInput(...)` surface.

`EngineController` (`Sources/Engine/EngineController.swift`) manages the tick clock, pipeline builder, and sync loops. Its `syncAudioOutputs(for:)` only handles `.auInstrument` destinations. Its `syncSampleMixers(for:)` only handles `.sample` and `.slicer` destinations. Neither method has a branch for live audio input.

The `TickClock` (`Sources/Engine/TickClock.swift`) fires a software timer at step boundaries (`stepsPerBar` = 16 steps per bar default). A bar boundary is detectable as `tickIndex % stepsPerBar == 0`. This is the mechanism a quantized-arm feature would hook into, but no such hook exists yet.

`EngineController.start()` calls `sampleEngine.start()` and then starts the clock, but it never calls `engine.start()` to enable the hardware input node. (The engine is started via `MainAudioGraph.start()` which is called elsewhere; the point is that no code enables or configures input monitoring.)

**Gaps vs. user stories**

- Story 2 (route live input to mixer): `AVAudioEngine.inputNode` is never connected anywhere. No tap is installed. No input mixer node is managed.
- Story 3 (record to buffer): No `AVAudioPCMBuffer` capture path exists. No recording state machine is present.
- Story 4 (bar-length selector): The bar boundary is computable from `transportTickIndex % stepsPerBar`, but no record-arm countdown or auto-stop uses it.
- Story 5 (quantized arm): No pending-arm state exists in the engine or document. The clock queue has no deferred-trigger mechanism.
- Story 6 (live-input vs. loop toggle): No monitoring-mode state exists in the engine.

---

## 3. Preferences — Audio Interface Selection

**What exists**

`PreferencesView` (`Sources/UI/PreferencesView.swift`) has an `AudioPreferences` sub-view. Its body is:

```swift
private struct AudioPreferences: View {
    var body: some View {
        Form {
            Text("Audio device selection placeholder")
        }.padding()
    }
}
```

This is a confirmed placeholder. No `CoreAudio` device enumeration is present anywhere in `Sources/`. No `UserDefaults` key for a preferred input or output device ID is written or read in any Swift file. No `AudioDeviceID` / `kAudioHardwarePropertyDevices` call appears in the codebase.

The MIDI preferences tab (also in `PreferencesView`) does enumerate `MIDISession` endpoints, and that implementation provides a reference pattern for building audio device enumeration. However, there is no analogous audio device session object.

`MainAudioGraph` does not expose a method for switching the underlying `AVAudioEngine` to a different `AVAudioDevice`.

**Gaps vs. user stories**

- Story 1 (select interface): The preferences UI is a non-functional stub. No device list, no selection, no persistence, no engine-side apply path.

---

## 4. UI

**What exists**

There is no `AudioInputTrackWorkspaceView` or equivalent. The workspace routing in `WorkspaceDetailView` / `ContentView` dispatches on `TrackType`; since there is no `audioInput` track type, there is no track page for it.

`WaveformView` (`Sources/UI/WaveformView.swift`) is a generic bar-graph waveform component driven by `[Float]` buckets. It is used by the slicer track. It could be reused for a recorded-loop display.

`SliceTrackWorkspaceView` (`Sources/UI/Slicer/SliceTrackWorkspaceView.swift`) is the closest analog to the requested UI. It has:
- a waveform panel backed by `WaveformDownsampler` (file-backed; not suitable for a live record buffer as-is)
- a pattern/step control area
- a sample player panel on the right

`WaveformDownsampler` (`Sources/Audio/WaveformDownsampler.swift`) reads an audio file URL and downsamples it to a bucket array. It is file-based and synchronous. A live-input recording would need a different path to populate waveform buckets from a PCM buffer rather than a file.

**Gaps vs. user stories**

- Story 7 (waveform): `WaveformView` can render buckets, but there is no code path from a capture buffer to a bucket array. `WaveformDownsampler` only reads file URLs.
- Stories 2–6 have no UI representation at all (no track page, no mode toggle, no bar-length picker, no arm button, no pending-trigger indicator).

---

## 5. Persistence

No audio-input-related fields exist in `Project`, `StepSequenceTrack`, or any sub-model. A new track kind with a record buffer cannot survive a save/load cycle without new `Codable` fields.

Audio interface selection is not persisted. The `document-model.md` wiki page notes that "no window state" and no non-document preferences are stored in `.seqai`; a preferred audio device would correctly live in `UserDefaults` or an app-support JSON file (analogous to `RecentVoicesStore`).

---

## 6. Tests

No test file in `Tests/` references audio input, record buffers, or CoreAudio device selection. The `Audio/` test group (`Tests/SequencerAITests/Audio/`) covers `MainAudioGraph`, `SamplePlaybackEngine`, `MasterBusHost`, `SliceAnalyzer`, and `WaveformDownsampler` — all output-only. There are no tests for:

- device enumeration
- input node configuration
- record-buffer capture
- quantized-arm logic
- live-input vs. loop monitor toggle

---

## 7. Architecture Constraints

**AVAudioEngine input node on macOS**

On macOS, `AVAudioEngine.inputNode` exists and is connected by default to the system's default input device. Switching to a non-default device requires using the lower-level `CoreAudio` API (`AudioHardwareSetProperty`, `AVAudioEngine` does not expose a direct device-selector method). This means the implementation will need a thin `CoreAudio` wrapper to enumerate `kAudioObjectSystemObject` devices and set the input device on the engine's aggregate or on the underlying `AudioUnit`.

**Recording granularity**

Recording from `inputNode` via `installTap(onBus:bufferSize:format:block:)` is render-thread safe. The captured `AVAudioPCMBuffer` frames must be accumulated into a fixed-length buffer (1/2/4/8 bars × samples-per-bar at the session sample rate). Bar length in samples = `(60 / BPM) × beatsPerBar × sampleRate`. Since BPM is mutable, the buffer size should be computed at arm time, not at record start.

**Quantized arm and the software clock**

`TickClock` fires every `stepsPerBar` step per bar. `transportTickIndex % stepsPerBar == 0` is the bar boundary. Arming the record could set a flag inspected in `prepareTick` or in the render tap; both require a thread-safe signal. The current `CommandQueue` / event model only carries MIDI and AU note events; a new command kind (`.armRecord`) would be needed.

**TrackType extensibility**

`TrackType` is `CaseIterable` and drives UI dispatch in multiple switch statements (track name defaults, pitch defaults, step pattern defaults, clip content shape, workspace view selection). Adding a new case requires auditing all those sites.

**Document versioning**

Any new fields on `StepSequenceTrack` or new top-level project collections (e.g., a record buffer or pending-arm state) must not break existing `.seqai` documents. Optional `Codable` fields decoded with `decodeIfPresent` are the safe pattern already used elsewhere.

---

## 8. Summary of Gaps by Story

| Story | Model gap | Engine gap | UI gap | Preferences gap |
|---|---|---|---|---|
| 1. Select interface | None (pref only) | Device-switch API | Placeholder stub | Full: no enumeration, no persistence |
| 2. Create audio input track | No `audioInput` TrackType or destination | No inputNode tap, no input mixer | No track page | — |
| 3. Record to loop buffer | No record buffer model | No capture tap, no buffer accumulation | No record control | — |
| 4. Choose bar length | No bar-length field | No auto-stop logic | No bar-length picker | — |
| 5. Quantized arm | No pending-trigger field | No arm-command kind | No arm indicator | — |
| 6. Toggle live/loop | No monitor-mode field | No monitor-mode routing | No toggle | — |
| 7. Waveform on track page | No buffer-to-buckets path | — | No audio-input workspace view | — |

---

## Next Action

Write `spec.md` for Input Audio, drawing from `user-stories.md` and this existing-state report.
