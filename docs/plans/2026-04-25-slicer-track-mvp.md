# Slicer Track MVP — Sliced-Loop Playback Plan

**Parent spec:** `docs/specs/2026-04-18-north-star-design.md` §"Sliced-loop tracks"
**Reference:** `wiki/pages/octatrack-reference.md` (Flex machine + slice grid + sample locks)
**Status:** Not started. Tag `v0.0.NN-slicer-track-mvp` at completion.

## Summary

Make `TrackType.slice` audible. Today it's a placeholder: `Project+Tracks.swift:101` defaults a slice track to `.internalSampler(bankID: .sliceDefault, preset: "empty-slice")`, `EngineController.swift:540` returns "Internal sampler pending", and `SliceIndexEditor.swift` is a comma-separated text field that emits slice indexes nothing consumes. This plan delivers the end-to-end path:

1. Load a loop (drag-drop into the project pool, or pick from `.loop`-category samples in the existing `AudioSampleLibrary`).
2. Auto-slice it (grid mode by default; transient mode optional). The waveform editor shows boundaries and supports manual drag.
3. Trigger slices from the step grid. Slice 0 = whole-sample, so a fresh track plays the loop on step 1 immediately — same shape as Octatrack's "first trig plays the file" default.
4. Per-slice gain / start-trim / end-trim / reverse stored alongside the sample, not on the track.
5. Tracker-style "play from this slice for the rest of the bar" step mode (one step replaces the per-step trigs that follow it within the bar).
6. Per-slice micro-timing offset so transient-detected hits land on the step they belong to even when they don't fall exactly on a 16th.

**Verified end-to-end by:** create project → drag a 2-bar break onto the window → see it land in the loop category → add a slice track → it auto-grids to 16 slices and plays the whole sample at step 1 → switch to transient mode → 8 transients detected, plotted on the waveform → enter notes on the step grid by clicking slice rows → playback hits the correct slice on each step → drag a slice boundary to nudge the kick onto step 0 → "play from slice 4" step mode test plays the second half of the loop starting on the trigger step.

## Architecture

A slicer is a **track-shaped feature** that owns a reference to a sample plus a slice set; it is **not** a per-step destination. The destination is *where the audio comes out* (mixer + bus); the slicer is *what produces the audio for that track*. Concretely:

- New project-scoped pool: `Project.sliceSetPool: [SliceSet]`. Each `SliceSet` references one `AudioSample` (via existing `AudioFileRef`) plus an ordered `[SliceMarker]` and analysis metadata (BPM, bars, mode-used).
- New destination case: `Destination.slicer(sliceSetID: UUID, settings: SlicerSettings)`. The destination still owns *track-wide* knobs (gain, voice mode mono / poly-N, pitch transpose). **Per-slice** settings (start, end, gain, reverse) live on the `SliceMarker` so they survive a destination swap and so two tracks can share a slice set without per-track confusion.
- Slice 0 is **always** the whole-sample slice. Auto-slicing creates slices 1..N alongside it; users edit slices 1..N freely, but slice 0's range always tracks `[0, sampleLength]`. This gives "first step plays the whole loop" without a special case in the dispatcher.
- Generator/clip output is a tagged note stream where `voice-tag = "slice-N"` (or the user's custom tag), per the spec. The engine resolves `voice-tag → SliceMarker` at dispatch and schedules the file with a frame range.

Why pool-shaped, not inline on `StepSequenceTrack`:

- Sample locks (Octatrack idiom). A step's parameter-lock can swap to a different `sliceSetID` at low cost — one ID, not a deep copy.
- Two slice tracks can target the same loop with different per-track voice modes / transposes without duplicating the marker array.
- Future "slice library" / cross-project slicing reuses the same shape with a different `AudioFileRef` storage variant.

Playback path extends `SamplePlaybackEngine` rather than introducing a parallel engine. The engine already does per-track mixers and 16-voice round-robin; it just doesn't accept frame ranges on `play(...)`. The new `playSlice(...)` overload accepts `(sampleURL, startFrame, endFrame, settings, trackID, when)` and uses `AVAudioFile.framePosition` + `scheduleSegment` to play the requested region. No new graph nodes; no new threading model.

## Tech Stack

Swift 5.9+, SwiftUI (`Canvas`-based waveform editor), AVFoundation (`AVAudioFile.framePosition`, `AVAudioPlayerNode.scheduleSegment(_:startingFrame:frameCount:at:completionHandler:)`), Accelerate (`vDSP` energy / onset envelope for transient mode), Foundation, XCTest. No new package dependencies. **Deliberately not** pulling in a third-party slicer / BPM library — onset detection in MVP is ~80 lines of `vDSP_meanv` + simple peak-picking; richer detection lands in a follow-up plan.

## Dependencies

- **Hard:** `2026-04-19-sample-pool.md` — done; gives us `AudioSamplePool`, `AudioSample`, `AudioFileRef`, the loop category, and `SamplePlaybackEngine` per-track mixers.
- **Soft (forward-compat only):** `2026-04-22-track-macro-parameters.md` and `2026-04-22-sampler-filter.md` — when they ship, slicer tracks pick up `sampleStart` / `sampleLength` / `sampleGain` / filter macros for free because they live on the same audio path. This plan does **not** hard-depend on them: macro hooks are stubbed where the structure obviously needs them, but the MVP ships without macro UI for slicer-specific params.
- **Soft (vision alignment):** the spec's `note-repeat` macro and `voice-route` sink are part of the macro plan family. The slicer track emits a tagged stream the moment those macros land, no slicer-side change needed.

## Scope: in

- `SliceMarker` + `SliceSet` + `SlicerSettings` document types
- `SliceSetPool` on `Project` (new field, codable with absent-key default)
- `Destination.slicer(sliceSetID:, settings:)` case
- Grid auto-slicing (N equal divisions, default 16) and transient auto-slicing (vDSP-based onset detection)
- Manual slice editing in a new `SlicerWaveformWindow` (drag boundaries, add / remove markers, rename)
- Per-slice gain / start-trim / end-trim / reverse / micro-timing offset
- "Slice 0 = whole sample" invariant; freshly-created slice tracks have step 0 wired to slice 0 so the loop plays end-to-end on bar 1
- Tracker-style "play from slice N for rest of bar" per-step mode (one new field on the slice clip's step entry)
- `SamplePlaybackEngine.playSlice(...)` plus `EngineController` dispatch path for `Destination.slicer`
- Loop import workflow surface: existing drop overlay covers the file-copy path; this plan adds an "Add Slice Track from loop" entry point that picks one
- Wiki page on the slicer model

## Scope: out (deferred — see "Follow-up plans")

- **BPM auto-detection.** MVP reads BPM from filename (`*_130bpm_*` style) or asks the user. Auto-detection is a focused follow-up; see appendix for prior-art notes.
- **Live recording / pickup machine.** Octatrack-style "record from input or another bus into a circular buffer" needs an `AudioInputHost` (CoreAudio device picker, AVAudioEngine input node permissions, ring-buffer policy) and a bus-tap on track or main mixers. Big enough to deserve its own plan.
- **Bus-tap sampling.** Tap a track or master mixer into a recording buffer. Same plan as live recording.
- **Auto-labeling slices** by spectral-centroid + envelope. Slices ship as `slice-1..slice-N`; user renames if they want kick/snare/hat tags. Spec §"Slicing" already flags this as post-MVP.
- **`slice-generator`** (Markov over slice tags, euclidean over tags). MVP ships only the `slice-clip` source. The generator family is a follow-up; the data shape it'll consume — `SliceSet` + tag map — already exists post-MVP.
- **Live performance ratchet** (hold a pad → fire current step on 16ths). MVP delivers the slice-trigger primitive; ratchet is launchpad-side scheduling that fires the same primitive multiple times. Falls out of `note-repeat` macro work.
- **Per-slice filter / envelope DSP.** One filter per *track* arrives via the sampler-filter plan. Per-slice envelopes mean per-voice DSP, which is a separate decision.
- **Time-stretching.** Slices play at the file's sample rate. Pitching with stretch (Octatrack `RATE`/`PTCH`) is post-MVP.
- **Slice across multiple files.** A slice set references one sample. Composite slice sets (drum chops from N samples) wait.

## Open question (decide before Task 1)

**Where should slice 0 = whole-sample live in the data model?**

Two options:

- **(A)** Always synthesise slice 0 in the runtime — `SliceSet.markers: [SliceMarker]` only stores user-meaningful slices 1..N; `SliceSet.allSlices` is computed and prepends `[0, length]`. Pro: invariant is enforced by code, not by data. Con: the marker editor has to know "you can't drag this one."
- **(B)** Store slice 0 explicitly as the first marker. Pro: editor is uniform — every visible marker is a real array entry. Con: marker[0]'s range must be invariant-maintained on file length changes (cheap to enforce in `SliceSet.normalize()`).

Recommend **(B)** because it makes the waveform editor and the persistence shape uniform. Marker[0]'s `start = 0` and `end = sampleLength` are recomputed any time the underlying sample changes; the editor just disables drag handles on marker 0. **Decision deferred to Task 1's design moment** but flagged here so the implementer doesn't dither.

## File Structure (post-plan)

```
Sources/Document/
  SliceMarker.swift                      NEW — start, end, gain, reverse, microTimingSteps, tag
  SliceSet.swift                         NEW — sampleID + markers + analysis metadata + normalize()
  SlicerSettings.swift                   NEW — per-track: voiceMode, transpose, gain
  Destination.swift                      MODIFIED — add .slicer case; audit Kind / summary / withoutTransientState
  Project.swift                          MODIFIED — sliceSetPool: [SliceSet] field
  Project+SliceSets.swift                NEW — pool helpers (add / remove / lookup / firstSliceFor)
  Project+Tracks.swift                   MODIFIED — defaultDestination(.slice) → .slicer with empty SliceSet
  ClipContent.swift                      MODIFIED — note-grid step entry gains optional playFromSliceForRest flag (tracker-style)

Sources/Audio/
  SliceAnalyzer.swift                    NEW — grid + transient mode; pure function over AVAudioFile
  SamplePlaybackEngine.swift             MODIFIED — add playSlice(url, startFrame, endFrame, settings, trackID, when)
                                                    via AVAudioPlayerNode.scheduleSegment

Sources/Engine/
  ScheduledEvent.swift                   MODIFIED — add .sliceTrigger payload
  EngineController.swift                 MODIFIED — Destination.slicer branch in prepareTick + dispatchTick

Sources/Document/GeneratedSourceEvaluator.swift   MODIFIED — slice case emits voice-tag stream
                                                              (drop the "synthetic MIDI 60+sliceIndex" hack)

Sources/UI/Slicer/
  SlicerWaveformWindow.swift             NEW — top-level window: full waveform, slice markers, per-slice inspector
  SlicerWaveformView.swift               NEW — Canvas: peak buckets + draggable boundaries
  SliceInspectorView.swift               NEW — per-slice gain / reverse / trim / micro-timing controls
  SlicerSourceWidget.swift               NEW — track-source widget: slice grid, "open waveform" button, slicing-mode picker
  TrackDestinationEditor.swift           MODIFIED — .slicer branch wires to SlicerSourceWidget
  TracksMatrixView.swift                 MODIFIED — "Add Slice" picks a loop from the pool (or empty)

wiki/pages/
  slicer-tracks.md                       NEW — model + waveform editor + slice 0 invariant + step modes

Tests/SequencerAITests/
  Document/
    SliceMarkerTests.swift               NEW
    SliceSetTests.swift                  NEW
    SlicerSettingsTests.swift            NEW
    DestinationSlicerTests.swift         NEW
    ProjectSliceSetPoolTests.swift       NEW
    ClipContentTrackerStepModeTests.swift NEW
  Audio/
    SliceAnalyzerGridTests.swift         NEW
    SliceAnalyzerTransientTests.swift    NEW (uses generated impulse fixture)
    SamplePlaybackEnginePlaySliceTests.swift NEW (integration-tagged)
  Engine/
    EngineControllerSliceTriggerTests.swift NEW
    GeneratedSourceEvaluatorSliceTagStreamTests.swift NEW
  UI/
    SlicerSourceWidgetTests.swift        NEW (ViewModel-level)
    SlicerWaveformViewTests.swift        NEW (drag + boundary commit)
```

---

## Task 1 — `SliceMarker` + `SliceSet` + `SlicerSettings` document types

**Goal:** Pure value types with codable round-trip. No I/O, no DSP.

**Files:** `Sources/Document/SliceMarker.swift`, `SliceSet.swift`, `SlicerSettings.swift` + tests.

**Types:**

```swift
struct SliceMarker: Codable, Equatable, Hashable, Sendable {
    var id: UUID
    var startFrame: Int64
    var endFrame: Int64
    var gain: Double = 0           // dB, [-60, +12]
    var reverse: Bool = false
    var microTimingSteps: Double = 0   // sub-step offset, [-0.5, +0.5] (1 = full step)
    var tag: String = ""           // user-editable; default empty (UI shows "slice N")
}

enum SliceMode: String, Codable, Sendable { case grid, transient, manual }

struct SliceSet: Codable, Equatable, Hashable, Sendable, Identifiable {
    var id: UUID
    var sampleID: UUID
    var markers: [SliceMarker]     // markers[0] is always the whole-sample slice
    var mode: SliceMode = .grid    // mode used to author the current marker layout
    var bpmHint: Double?           // user-supplied or filename-derived; nil = unknown
    var bars: Double?              // user-supplied length-in-bars; nil = unknown

    /// Enforces invariants: markers[0] = [0, sampleLengthFrames]; markers sorted by startFrame;
    /// no marker exceeds sampleLengthFrames; ids unique.
    mutating func normalize(sampleLengthFrames: Int64)
}

enum SlicerVoiceMode: String, Codable, CaseIterable, Sendable {
    case mono              // retrigger steals the previous voice
    case polyphonic        // overlapping slices share the voice pool
}

struct SlicerSettings: Codable, Equatable, Hashable, Sendable {
    var gain: Double = 0           // dB, [-60, +12]
    var transpose: Int = 0         // semitones, [-48, +48] (reserved; no resampler in MVP)
    var voiceMode: SlicerVoiceMode = .mono
}
```

`SliceSet.normalize` is the single integrity boundary — call after any edit.

**Tests:**

- `SliceMarker` round-trip codable; legacy decode without optional fields.
- `SliceSet.normalize` reorders out-of-order markers; clamps an out-of-range end; injects markers[0] if missing.
- `SlicerSettings.clamped()` bounds gain/transpose.
- All three types `Sendable` (compile-time check via `@Sendable` conformance).

- [ ] Tests
- [ ] Implement
- [ ] Green
- [ ] Commit: `feat(document): SliceMarker + SliceSet + SlicerSettings value types`

---

## Task 2 — `Destination.slicer` case

**Goal:** New tagged-union case wired through `Kind`, `kindLabel`, `summary`, `withoutTransientState`.

**Files:** `Sources/Document/Destination.swift` + `DestinationSlicerTests.swift`.

```swift
case slicer(sliceSetID: UUID, settings: SlicerSettings)
```

`Kind.slicer`, `kindLabel = "Slicer"`, `summary` includes a slice-count placeholder ("Slicer • 16 slices"). `withoutTransientState` returns `self` (no in-memory state to scrub). Audit every other switch on `Destination` — the comment in `Destination.swift:27` lists the audit points (EngineController routing, AudioInstrumentHost loading, TrackDestinationEditor selection, Mixer/Inspector summaries) — and add `.slicer` branches that compile but defer behaviour to later tasks (engine = enqueue slice trigger event handled in Task 7; UI = wire to SlicerSourceWidget in Task 9).

**Tests:**

- Round-trip codable.
- Equality compares both id and settings.
- `withoutTransientState` is a no-op.
- Each `Destination.Kind` audit point now has a `.slicer` branch — caught by exhaustive switches on `Destination` enums in tests (no `default:` clauses).

- [ ] Tests
- [ ] Implement
- [ ] Green
- [ ] Commit: `feat(document): Destination.slicer case`

---

## Task 3 — `Project.sliceSetPool` field + helpers

**Goal:** Project owns a pool of slice sets. Codable with absent-key default. Helpers analogous to `clipPool` access patterns.

**Files:** `Sources/Document/Project.swift`, `Project+SliceSets.swift` + tests.

```swift
extension Project {
    func sliceSet(id: UUID?) -> SliceSet?
    mutating func addSliceSet(_ set: SliceSet)
    mutating func removeSliceSet(id: UUID)
    mutating func updateSliceSet(id: UUID, _ update: (inout SliceSet) -> Void)
    func firstSliceSet(for sampleID: UUID) -> SliceSet?  // O(N) — pool stays small
}
```

`Project+Tracks.swift:101` updates: `defaultDestination(for: .slice)` becomes `.slicer(sliceSetID: emptyPlaceholderID, settings: .init())`. Define the empty placeholder as a deterministic UUID in `SliceSet.empty` — a sliceSet with no `sampleID` and a single full-range marker over a zero-length sample. The runtime tolerates this and produces silence; the UI prompts "Choose a loop." This avoids a special-case "track with no slice set" branch.

**Tests:**

- Fresh project: `sliceSetPool.isEmpty`.
- Legacy JSON without `sliceSetPool` decodes with empty pool.
- Add / remove / update round-trip.
- `defaultDestination(for: .slice)` returns the empty placeholder.

- [ ] Tests
- [ ] Implement
- [ ] Green
- [ ] Commit: `feat(document): sliceSetPool on Project + helpers`

---

## Task 4 — `SliceAnalyzer` (grid + transient)

**Goal:** Pure function over `AVAudioFile` returning `[SliceMarker]`. No I/O after the file is open; no AVAudioEngine.

**Files:** `Sources/Audio/SliceAnalyzer.swift` + `SliceAnalyzerGridTests.swift` + `SliceAnalyzerTransientTests.swift`.

```swift
enum SliceAnalyzer {
    static func gridSlices(file: AVAudioFile, divisions: Int) -> [SliceMarker]
    static func transientSlices(file: AVAudioFile, sensitivity: Double) -> [SliceMarker]
}
```

Grid is trivial — equal divisions of `file.length` into `divisions` markers, plus marker[0] = full range.

Transient detection (MVP, ~80 lines of vDSP):

1. Read into a mono float buffer (sum + normalise channels).
2. Compute per-window RMS using `vDSP_meanv` over 1024-frame windows (≈23 ms at 44.1 kHz).
3. Compute spectral flux as the positive difference between adjacent windows' RMS — the lightweight onset envelope.
4. Smooth with a 5-window moving average.
5. Pick peaks: a window is a transient if it exceeds (mean + `sensitivity * stddev`) and is the local max within ±5 windows.
6. Convert peak windows to frame positions; build markers between successive transients; reject markers shorter than 50 ms (collapse).

The 50 ms minimum and 1024-window are MVP defaults baked into the function — they're tunable in a later plan when we ship a "slicing settings" sheet. `sensitivity` defaults to `1.5` (≈ moderate threshold, matches Octatrack's mid-sensitivity).

**Tests:**

- Grid: 100-frame mono file, divisions = 4 → markers[0]=[0,100], [1]=[0,25], [2]=[25,50], [3]=[50,75], [4]=[75,100].
- Transient on a generated 4-impulse fixture (silence with 4 evenly-spaced spikes): returns 5 markers (whole + 4 transients) at the spike frames ± one-window tolerance.
- Transient with sensitivity = 0.0 returns more markers than sensitivity = 3.0 on the same file (monotonic threshold response).
- Transient on pure silence returns just the whole-sample marker.

- [ ] Tests (with generated fixture WAVs)
- [ ] Implement
- [ ] Green
- [ ] Commit: `feat(audio): SliceAnalyzer grid + transient onset detection`

---

## Task 5 — `SamplePlaybackEngine.playSlice(...)`

**Goal:** Add a slice-aware playback entry point alongside `play(...)`. Reuses the existing voice pool, per-track mixer, and queue.

**Files:** `Sources/Audio/SamplePlaybackEngine.swift` + `SamplePlaybackEnginePlaySliceTests.swift`.

```swift
func playSlice(
    sampleURL: URL,
    startFrame: AVAudioFramePosition,
    endFrame: AVAudioFramePosition,
    settings: SlicerSettings,
    trackID: UUID,
    at when: AVAudioTime?
) -> VoiceHandle?
```

Implementation: same lifecycle as `play(...)` but uses `voice.scheduleSegment(file, startingFrame: startFrame, frameCount: AVAudioFrameCount(endFrame - startFrame), at: when, completionHandler: nil)` instead of `scheduleFile`. Voice gain = `settings.gain` linear-converted, ignoring transpose for MVP (no resampler). `voiceMode == .mono` reuses the existing single-voice-per-track stealing already implemented; `.polyphonic` uses round-robin from the global 16-voice pool, same as drum tracks. Reverse playback (per-slice flag) is **not** implemented in this task — see Task 6's gap section.

**Tests (integration-tagged, may skip if AVAudioEngine can't run in CI):**

- Play a known fixture from frame 1000 → 5000: the voice handle is non-nil; no crash.
- Mid-segment stop: stopVoice silences within a few ms.
- Two slices in flight (polyphonic mode): both render; voice count stays ≤ pool size.
- `endFrame > file.length`: clamped to `file.length`.

- [ ] Tests
- [ ] Implement
- [ ] Green
- [ ] Commit: `feat(audio): SamplePlaybackEngine.playSlice with frame range`

---

## Task 6 — Reverse playback (per-slice)

**Goal:** Honour `SliceMarker.reverse`.

`AVAudioPlayerNode` doesn't play files backwards directly. Two approaches:

- **(i)** Pre-buffer the slice into an `AVAudioPCMBuffer`, reverse the samples in-memory, schedule the buffer with `scheduleBuffer`. Cheap for short slices; allocates per slice.
- **(ii)** Cache a reversed copy of the file the first time a reverse-flagged slice plays. Larger memory footprint; faster steady-state.

MVP uses **(i)** with an LRU cache on `(fileURL, startFrame, endFrame)` of size 32. The cache lives in `SamplePlaybackEngine` and is invalidated when the slice set's marker layout changes for that sample (caller-side: `Project+SliceSets.swift` notifies engine on marker mutation).

**Files:** extend `SamplePlaybackEngine.swift` + dedicated tests.

**Tests:**

- Forward and reversed render the same total RMS (within tolerance).
- Reversed render of a fixture file's first 8000 frames matches the offline-reversed buffer (sample-level).
- Cache eviction at 33rd unique slice: oldest entry dropped.

- [ ] Tests
- [ ] Implement
- [ ] Green
- [ ] Commit: `feat(audio): per-slice reverse playback via reversed-buffer cache`

---

## Task 7 — `EngineController` slice dispatch

**Goal:** When a slice track's generator emits a tagged note stream, schedule one `playSlice(...)` per event.

**Files:** `Sources/Engine/ScheduledEvent.swift`, `Sources/Engine/EngineController.swift` + tests.

`ScheduledEvent.Payload.sliceTrigger(trackID, sampleURL, startFrame, endFrame, settings, scheduledHostTime)` — new case mirroring `.sampleTrigger`.

`prepareTick`: extend the existing sample-dispatch loop (`EngineController.swift:679`) with a `.slicer` branch:

```swift
guard case let .slicer(sliceSetID, settings) = track.destination else { ... }
guard let set = documentModel.sliceSet(id: sliceSetID),
      let sample = library.sample(id: set.sampleID),
      let url = try? sample.fileRef.resolve(libraryRoot: ...)
else { continue }
for event in events {
    let sliceIndex = sliceIndex(forVoiceTag: event.voiceTag, set: set) ?? 0
    let marker = set.markers[sliceIndex]
    let microFrames = Int64(marker.microTimingSteps * tickFramesAtCurrentBpm)
    eventQueue.enqueue(ScheduledEvent(
        scheduledHostTime: now,
        payload: .sliceTrigger(
            trackID: track.id,
            sampleURL: url,
            startFrame: marker.startFrame + microFrames,
            endFrame: marker.endFrame,
            settings: settings,
            scheduledHostTime: now
        )
    ))
}
```

Helper: `sliceIndex(forVoiceTag:set:)` — parses `slice-N` tags or matches user-renamed `marker.tag`. Empty / missing tag → slice 0.

`dispatchTick`: drain `.sliceTrigger` and call `samplePlaybackEngine.playSlice(...)` (mirrors how `.sampleTrigger` flows through today).

Update `EngineController.swift:540` — replace "Internal sampler pending" status string with a real "Slicer • <sliceset name> • <N slices>" rendering.

**Tests:**

- A track with `.slicer` and a 16-grid slice set: ticking step 0 enqueues exactly one slice trigger with marker[0] (the whole-sample slice).
- Step 5 with voice-tag `"slice-3"`: enqueues a trigger with marker[3]'s frame range.
- `microTimingSteps = -0.25` shifts startFrame back by quarter-step duration (computed from current BPM).
- Muted track / muted in layer snapshot: no events enqueued.
- Mode `.polyphonic` allows two events on the same step (chord-like) — both reach the engine; mono mode only takes the last.

- [ ] Tests
- [ ] Implement
- [ ] Green
- [ ] Commit: `feat(engine): slicer dispatch through SamplePlaybackEngine.playSlice`

---

## Task 8 — `GeneratedSourceEvaluator` slice case → tagged stream

**Goal:** Replace the `clampMIDI(60 + sliceIndex)` hack at `GeneratedSourceEvaluator.swift:233` with a real voice-tagged note stream that the dispatch path in Task 7 can consume.

**Files:** `Sources/Document/GeneratedSourceEvaluator.swift` + tests.

The slice case currently emits notes with a synthetic MIDI pitch and no voice tag. Rework it to emit `GeneratedNote(pitch: 60, velocity: shape.velocity, length: shape.gateLength, voiceTag: "slice-\(sliceIndex)")`. The pitch is irrelevant for slicer dispatch; we keep `60` so the legacy MIDI path (if a slicer track is ever switched to a MIDI destination) still produces a deterministic note.

This unblocks the spec's "shape is identical to drum tracks" promise: drum tracks already emit voice-tagged streams; slicer tracks now do too. Future slice-generators land into the same evaluation path.

**Tests:**

- Existing `GeneratorParams.slice(trigger:, sliceIndexes: [3, 1, 4])` evaluation now emits voice tags `"slice-3"`, `"slice-1"`, `"slice-4"` in the corresponding cycle positions.
- Empty `sliceIndexes` → all events tagged `"slice-0"` (whole-sample default).

- [ ] Tests
- [ ] Implement
- [ ] Green
- [ ] Commit: `feat(generator): slice evaluator emits voice-tagged stream`

---

## Task 9 — `SlicerSourceWidget` (track-source UI)

**Goal:** Replace the placeholder slice-track UI at `SliceIndexEditor.swift` with a real widget showing slice rows, an "Open Waveform" button, and a slicing-mode picker. Mirrors `SamplerDestinationWidget` shape.

**Files:** `Sources/UI/Slicer/SlicerSourceWidget.swift`, `Sources/UI/TrackDestinationEditor.swift` (route `.slicer` to the widget) + tests.

Widget content:

- Top: sample picker — "Loop: <name>" with prev / next / pick-from-pool / drop-target affordances. Picking from pool filters `AudioSampleLibrary.samples(in: .loop)`. (`.unknown`-categorised loops aren't auto-discovered; the user can re-categorise via the existing import sheet.)
- Slicing mode picker: Grid (with division stepper, default 16) / Transient (with sensitivity slider) / Manual.
- "Re-slice" button: runs `SliceAnalyzer` with the current mode + parameters and replaces markers 1..N. Marker 0 (whole-sample) is preserved.
- A compact slice list: each row shows `slice-N` (or user tag), length in ms, and a small play / stop button that auditions just that slice.
- "Open waveform editor" button — opens the `SlicerWaveformWindow` (Task 10).
- Voice mode toggle (mono / poly).
- Track gain slider (binds to `SlicerSettings.gain`).

**Tests (ViewModel-level, matches repo convention):**

- Picking a sample creates a fresh slice set with marker[0] only and assigns it to the track.
- "Re-slice" with grid divisions = 8 produces 9 markers (0 + 1..8).
- Voice mode toggle writes through to `Destination.slicer.settings`.

- [ ] Tests
- [ ] Implement widget + integration in TrackDestinationEditor
- [ ] Green
- [ ] Commit: `feat(ui): SlicerSourceWidget with mode picker + slice list`

---

## Task 10 — `SlicerWaveformWindow` + `SlicerWaveformView` + `SliceInspectorView`

**Goal:** A separate window (or large sheet) showing the full sample, slice markers, and a per-slice inspector. The visual primitive a user reaches for when they want to nudge a slice into the right place.

**Files:** `Sources/UI/Slicer/SlicerWaveformWindow.swift`, `SlicerWaveformView.swift`, `SliceInspectorView.swift` + tests.

`SlicerWaveformView` (SwiftUI `Canvas`):

- Reuses `WaveformDownsampler` for peak buckets at the window's pixel width.
- Overlays slice markers as vertical lines; selected marker highlighted.
- Drag a marker to move its `startFrame` (and the previous marker's `endFrame`); snaps to zero-crossings within ±5 ms by default (tunable later).
- Marker 0's drag handles are disabled (whole-sample invariant).
- Click a slice region to select it; selection drives `SliceInspectorView`.
- Right-click on the waveform: "Insert marker here" / "Delete selected marker."

`SliceInspectorView`:

- Tag (text field).
- Gain slider [-60, +12 dB].
- Reverse toggle.
- Start trim, end trim (frame steppers — they edit the marker's own start/end within the bounds of the previous and next markers).
- Micro-timing steps slider [-0.5, +0.5].

`SlicerWaveformWindow` chrome:

- Top bar: sample name, BPM hint field (free-text — feeds `SliceSet.bpmHint`), bars field (`SliceSet.bars`).
- "Re-slice" button mirrors the source widget's button.
- "Audition slice" button on the inspector plays the current selection through `SamplePlaybackEngine.audition` (preview path, not the track mixer).

**Tests:**

- Drag a marker → its `startFrame` updates and `SliceSet.normalize` is called once on mouseup (not on every drag tick).
- Inserting a marker between existing ones renumbers correctly; ids stay stable.
- Marker 0's drag is rejected (no state change on drag attempt).
- Editing BPM hint + bars writes through to `SliceSet`.

- [ ] Tests
- [ ] Implement
- [ ] Green
- [ ] Commit: `feat(ui): SlicerWaveformWindow with marker editing + inspector`

---

## Task 11 — Tracker-style "play from slice N for rest of bar" step mode

**Goal:** One step on a slicer clip can override the rest-of-bar behaviour: instead of firing the per-step trigs that follow, the loop plays continuously from slice N to the bar's end. This is the "phrase-offset" idea Renoise / OpenMPT track sequencers use to "rewind the loop."

**Files:** `Sources/Document/ClipContent.swift`, `Sources/Engine/EngineController.swift`, `Sources/Document/GeneratedSourceEvaluator.swift` (only the slice-clip read path — not `slice-generator`), tests.

Data shape extension on the slice-clip's step entry:

```swift
struct SliceClipStep: Codable, Equatable, Hashable, Sendable {
    var sliceIndex: Int
    var velocity: Int = 100
    var playMode: PlayMode = .single

    enum PlayMode: String, Codable, Sendable {
        case single                  // fire slice once
        case runFromHere             // play slices [sliceIndex..N] continuously, suppressing
                                     // per-step trigs until the bar boundary
    }
}
```

Engine impact:

- `prepareTick` for a `runFromHere` step computes the contiguous slice run starting at `sliceIndex` and schedules **one** `playSlice` covering `[markers[sliceIndex].startFrame, sampleEndFrame]` — i.e. one long playback, not N short ones. This is intentionally simpler than the spec's "still emit a tagged stream and let `voice-route` see them" — for MVP the contiguous run is one voice. (Per-slice envelopes don't apply within a `runFromHere` segment in MVP; they will once the per-slice envelope DSP lands.)
- A subsequent step within the bar that's *also* a sample trig **steals** the voice — the new trigger replaces the in-flight long playback. This matches Octatrack mono-machine retrigger semantics.

**Tests:**

- Step 4 = `runFromHere(sliceIndex: 2)`, steps 5..15 = single trigs of arbitrary slices: only step 4's trigger is enqueued; steps 5..15 are silenced for the rest of the bar; bar wrap re-arms normal trig dispatch.
- Step 4 = `runFromHere(2)`, step 8 = `single(5)`: step 4 enqueues its long playback; step 8 enqueues a new trigger that steals the voice (mono mode).
- Round-trip codable for the step-mode field; absent field decodes to `.single`.

- [ ] Tests
- [ ] Implement
- [ ] Green
- [ ] Commit: `feat(slicer): tracker-style runFromHere step mode`

---

## Task 12 — Wiki + tag

**Goal:** Document the model so the next agent / contributor doesn't reverse-engineer it.

**Files:** `wiki/pages/slicer-tracks.md` (new), `wiki/pages/track-destinations.md` (modified), `wiki/pages/document-model.md` (modified — note `sliceSetPool`).

Page content:

- The "slice 0 = whole sample" invariant and why.
- `SliceSet` as pool-shaped vs inline-on-track (decision rationale, links Task 0 open question).
- Slicing modes (grid / transient / manual) and what `SliceAnalyzer` does in MVP vs follow-ups.
- The `runFromHere` step mode's one-voice simplification and the trade-off (no per-slice envelopes within a run).
- The relationship to drum tracks (same voice-tag stream shape) so future readers don't think this is a parallel system.
- Cross-link `octatrack-reference.md`'s Flex / sample-locks paragraphs.

Tag: `git tag -a v0.0.NN-slicer-track-mvp -m "Slicer track MVP: SliceSet pool, Destination.slicer, grid + transient slicing, waveform editor, runFromHere step mode"`. Increment NN against current latest at completion time.

- [ ] Wiki page
- [ ] Tag
- [ ] Commit: `docs(wiki): slicer-tracks page + tag`

---

## Test Plan (whole-plan)

- **Document:** value-type round-trips, `SliceSet.normalize` invariants, pool helpers, legacy decode without `sliceSetPool`.
- **Audio:** grid slicer correctness; transient slicer monotonic-sensitivity; play-slice frame-range correctness; reverse cache eviction.
- **Engine:** slice trigger enqueued exactly once per tagged event; micro-timing offsets shift start frame; `runFromHere` suppresses follow-up steps to bar boundary; mute paths skip enqueue.
- **UI:** widget mode picker drives re-slice; waveform marker drag commits once; marker 0 immovable.
- **Manual smoke** before tag:
  1. Drop a 2-bar break onto the app; pool gets a `.loop` entry.
  2. Add Slice Track → step 1 plays the whole break end-to-end at the project BPM.
  3. Switch to Transient mode → 6–10 markers appear; replay the bar, hits land on the right beats.
  4. Click slice 3, drag start handle → kick onset slides onto step 4. Replay confirms.
  5. Set step 4 = `runFromHere(2)` → bar plays its first half normally, then jumps to slice 2 and plays through to the end uninterrupted.
  6. Toggle voice mode poly → two overlapping slices on step 8 both render.
  7. Save, close, reopen — slice set survives, UI restores.

## Follow-up plans (separate documents, not part of this MVP)

These were in the initial brainstorm but earn their own plans:

- **`docs/plans/YYYY-MM-DD-bpm-auto-detection.md`** — onset-envelope autocorrelation BPM detector. Prior art to evaluate: aubio's `tempo` algorithm (autocorrelation + comb-filter on onset envelope, MIT-licensed C — not portable as-is to Swift but the algorithm is documented), Ellis 2007 "Beat Tracking by Dynamic Programming" (the librosa beat tracker's algorithmic root, papered + simple to port), Apple's `MusicHaptics` framework (extracts beats but no public BPM API). MVP path: vDSP onset envelope + autocorrelation + peak picking in [60, 200] BPM. Filename heuristic (regex for `(\d+)bpm` in the loop name) ships first as a stopgap.
- **`docs/plans/YYYY-MM-DD-pickup-machine.md`** — Octatrack-style live recording. Adds an `AudioInputHost` (CoreAudio device picker, microphone permission, AVAudioEngine input node), a circular `AudioRecordingBuffer` per slicer track, a "Record" arm + transport-synced start/stop, and a "tap from track bus" path that wires another track's per-track mixer through a tap-node into the same buffer. Big enough for a dedicated plan (input permissions on macOS, device-selection UX, sample-rate negotiation).
- **`docs/plans/YYYY-MM-DD-slice-auto-labeling.md`** — spectral-centroid + envelope-shape classifier tags slices as kick/snare/hat/perc/other.
- **`docs/plans/YYYY-MM-DD-slice-generator.md`** — `slice-generator` source: euclidean-over-tags, Markov-over-tag-transitions, random-from-pool. Drops into the existing generator pipeline once the macros plan ships `voice-route`.
- **`docs/plans/YYYY-MM-DD-live-pad-ratchet.md`** — hold-pad-fires-current-step-on-Nths. Performance-side scheduling on top of the slice-trigger primitive this plan delivers.

## Appendix — BPM detection prior art (research notes)

Captured here so the BPM follow-up plan can cite from a single place rather than reconvening the search:

| Approach | Idea | Pro / Con |
|---|---|---|
| **aubio `tempo`** | Onset envelope (HFC or complex-domain) + autocorrelation + dynamic-programming beat tracker | Battle-tested in DJing (Mixxx, Rekordbox-adjacent tools); C library, no Swift binding — would need a thin shim or a direct port. ~300 lines of core algorithm. |
| **Ellis 2007 (librosa)** | Onset strength → autocorrelation → DP beat tracker | Classic research baseline; algorithmic description is clean enough to reimplement in pure Swift + vDSP. Slightly slower than aubio's HFC variant but more accurate on swung material. |
| **Filename regex** | `(\d{2,3})\s*bpm` case-insensitive | Cheap; captures the common "loop_130bpm.wav" naming. Won't help on samples without a BPM in the filename. |
| **User-supplied BPM + bars** | "This is 2 bars at 130 BPM" | No DSP; deterministic. Right answer for power users. Default UX path in this MVP. |
| **Apple `MusicHaptics` / `AVAudioFile`** | Apple frameworks | No public BPM API on macOS as of 2026-01. |
| **Spotify-style `librosa.beat.beat_track`** | Onset envelope + tempogram + Viterbi | Most accurate; heaviest implementation. Premature for our scope. |

Recommendation for the BPM plan: ship filename regex first (one task, ~30 lines), then Ellis-style DP beat tracker as the upgrade path. Skip aubio binding unless we hit accuracy walls.

---

## Goal-to-task traceability (self-review)

| Goal / requirement | Task |
|---|---|
| `SliceMarker` + `SliceSet` + `SlicerSettings` document types | 1 |
| `Destination.slicer` case | 2 |
| `sliceSetPool` field + helpers | 3 |
| Grid + transient slicing | 4 |
| Slice playback path (frame range) | 5 |
| Reverse playback per slice | 6 |
| Engine dispatch for slicer destinations | 7 |
| Voice-tagged stream from slice generator | 8 |
| Track-source widget (sample picker, slicing mode, slice list) | 9 |
| Waveform editor window with per-slice inspector | 10 |
| Tracker-style "play from slice N for rest of bar" | 11 |
| Slice 0 = whole-sample invariant | 1 (data), 3 (default destination), 10 (UI immovable handles) |
| First step in fresh phrase plays whole sample | 3 (default empty placeholder + step-1-wired) + 11 (default `.single` mode) |
| Per-slice micro-timing offset | 1 (data), 7 (engine application) |
| Loop-import workflow | Existing sample-pool drop overlay; this plan adds the "Add Slice Track from loop" picker (Task 9) |
| Documentation | 12 |

## Assumptions

- One slice set per slicer track for MVP. Per-pattern slice-set swap (sample-lock-style) is post-MVP — the data shape on `Destination.slicer` accommodates it without change because the destination already references a `sliceSetID`; only the engine path needs to learn to read it from a per-pattern lock.
- Mono-voice mode is default. Polyphonic mode shares the global voice pool with drum tracks.
- BPM in MVP is user-supplied (or filename-derived). Mismatch between the user's BPM and the actual loop BPM produces drift — flagged visually in the waveform editor (slice markers vs. project step grid) but not auto-corrected.
- Reverse playback uses an in-memory reversed-buffer cache. 32-entry LRU is enough for typical slice counts; tunable in a follow-up if needed.
- The `runFromHere` step mode plays its segment as one continuous voice. Per-slice envelopes / pitch-offsets do not apply within a `runFromHere` segment in MVP — documented in the wiki page. Resolved properly when per-slice envelope DSP lands.
- We don't add a `sliceSetID`-aware sample-lock yet. Sample locks are an Octatrack idiom worth in their own right; the slicer plan deliberately ships without them so that lock semantics get a focused design pass.
