# Autoslice Algorithm — Existing State

Inspected on 2026-04-29. Scope is read-only; no production code was changed.

---

## What exists today

### PCM buffer access and sample loading

`Sources/Audio/SliceAnalyzer.swift` — private helper `monoSamples(from:)` reads an `AVAudioFile` into a flat `[Float]` array by mixing all channels to mono. This is the PCM entry point the prototype heuristics would call. It reads the entire file into memory in one shot (using `AVAudioPCMBuffer` with `frameCapacity: file.length`), which is fine for break loops but would need chunking for very long files.

`Sources/Audio/WaveformDownsampler.swift` — reads any `AVAudioFile` URL and returns a peak-per-bucket `[Float]` array (default 64 buckets). Results are cached by URL and bucket count in an `NSCache`. The slicer UI already calls this at 256 buckets. A prototype can reuse it directly for low-resolution waveform rendering without touching production code.

`Sources/Document/AudioSample.swift` — carries `lengthSeconds: Double?`, `lengthFrames: Int64?`, and `sampleRate: Double?`. `lengthSeconds` is the primary input for a BPM-hypothesis function. `sampleRate` is needed to convert frame counts to time. Both may be `nil` (populated by `AudioSampleLibrary` at load time).

### Existing transient detection

`Sources/Audio/SliceAnalyzer.swift` — `transientSlices(file:sensitivity:)` implements a full onset detector:

- Computes RMS energy in 1 024-sample windows (`rmsWindows`).
- Derives spectral flux (positive RMS delta between adjacent windows).
- Smooths flux with a five-sample moving average.
- Thresholds at `mean + sensitivity * stddev` (default `sensitivity = 1.5`; the UI uses `0.35`).
- Enforces a 50 ms minimum distance between transients.
- Refines each rough frame by a sub-window peak search (`refinedTransientFrame`) and then an attack-edge walk-back (`strongestAttackEdge`).

The function returns `[SliceMarker]` where `markers[0]` is the whole-sample span and subsequent markers are transient-bounded slices.

This detector is the key primitive the prototype needs. It already returns frame positions at sample-rate resolution, which is precise enough to compute grid-alignment scores.

### Waveform downsampling

`Sources/Audio/WaveformDownsampler.swift` — covered above. Produces peak-magnitude buckets suitable for drawing a waveform in an HTML canvas or SwiftUI `Canvas`. No dependency on the production app; accessible via `WaveformDownsampler.downsample(url:bucketCount:)`.

### BPM / bar-length metadata

`Sources/Document/SliceSet.swift` — `SliceSet` carries two optional metadata fields:

- `bpmHint: Double?` — intended to store a BPM value alongside a slice set, but is never written or read by any production path today (inspected all call sites; only declaration exists).
- `bars: Double?` — written by `SliceTrackWorkspaceView.analyzedSliceSet` as `Double(analysisBars)` (1, 2, or 4 bar picker). Read nowhere else.

Neither field feeds back into the analysis or the engine. They exist as placeholder storage for future use.

### Grid slicing

`Sources/Audio/SliceAnalyzer.swift` — `gridSlices(file:divisions:)` divides a file into `N` equal-length slices. The UI drives `divisions = analysisBars * 16`. There is no BPM awareness; the grid is purely time-proportional.

### Existing UI for analysis — `SliceTrackWorkspaceView`

`Sources/UI/Slicer/SliceTrackWorkspaceView.swift` — the production slicer workspace implements a two-phase "Auto Detect" flow:

1. **Propose** (`proposeAutoSlices`) — runs `SliceAnalyzer.transientSlices` or `gridSlices` based on user picker, wraps the result in a `SliceSet`, shows it as `analysisDraft` overlaid on the waveform.
2. **Apply** (`applyAnalysis`) — commits the draft to the document and resizes the clip to `analysisBars * 16` steps.

Controls exposed: transient vs. grid mode picker; 1/2/4 bar picker; sensitivity slider (0.15–0.75); slice count read-out; Apply and Cancel buttons.

The UI never ranks hypotheses, never attempts BPM inference from duration, and never scores transient alignment against a grid.

### Slicer waveform view

`Sources/UI/Slicer/SlicerWaveformView.swift` — simple waveform with vertical marker lines rendered from `SliceSet.markers`. No transient alignment overlay, no grid-ghost visualization.

`Sources/UI/Slicer/SliceTrackEditingControls.swift` — `SliceTrackWaveformEditor` adds zoom (1–8×), scroll, whole-sample start/end handles (S/E), and drag-to-move slice boundaries. The visible bucket range is computed from the zoom/scroll state.

`Sources/UI/WaveformView.swift` — `Canvas`-based bar chart rendering `[Float]` buckets. Used inside both the slicer and the step grid. Can be embedded in a standalone HTML prototype by reimplementing the bucket chart in JavaScript/Canvas.

### Slice marker model

`Sources/Document/SliceMarker.swift` — `SliceMarker` holds `startFrame`, `endFrame`, `gain`, `reverse`, `microTimingSteps`, and `tag`. The `tag` field is used by the engine dispatcher to route trigger events (e.g. `"slice-3"`, `"slice-run-2"`). No `role` or `classification` field exists yet.

`Sources/Document/SliceSet.swift` — `SliceMode` is an enum with cases `.grid`, `.transient`, `.manual`. No `.auto` or `.bpmInferred` case exists.

### Transient role classification

`Sources/Document/AudioSampleCategory.swift` — defines `.kick`, `.snare`, `.hatClosed`, `.hatOpen`, `.hatPedal`, etc. as sample-level categories. This is not slice-level classification; it describes the whole sample file in the library, not individual hits within a break loop.

`Sources/Document/SliceMarker.swift` — no role/classification field.

There is no transient role classifier anywhere in the codebase. The `.breaks` category in `AudioSampleCategory` simply marks a whole sample as a break loop; it does not classify individual transients within it.

### Tests covering the existing detector

`Tests/SequencerAITests/Audio/SliceAnalyzerTests.swift` — three tests:

- `test_gridSlices_includeWholeSampleAndEqualUserRegions` — verifies N+1 markers with correct proportional frames.
- `test_transientSlices_alwaysIncludeWholeSample` — verifies marker[0] is the whole-file span.
- `test_transientSlices_alignMarkersToPulseOnsets` — synthesizes a 44 100 Hz, 1-second file with pulses at frames 0, 11 025, 22 050, 33 075 and asserts markers land within ±512 frames of each onset.
- `test_transientSlices_doNotBacktrackIntoSustainedPreviousAudio` — verifies attack-edge detection in the presence of a sustained sine bed.

No tests cover BPM inference, grid-alignment scoring, multi-hypothesis ranking, or slightly-too-long loop trimming.

---

## Where the current state diverges from the user stories

| Story | Gap |
|---|---|
| 1. BPM hypothesis from duration | No code exists. `AudioSample.lengthSeconds` provides the input; the math (duration / (bars * (60/BPM)) = 1) is straightforward but unimplemented. |
| 2. Transient alignment score | No code exists. Transient frame positions from `SliceAnalyzer` are the right input; scoring against a 16-step grid at each BPM candidate is unimplemented. |
| 3. Slightly-too-long handling | No code exists. The current analysis makes no attempt to trim or search for a better loop boundary. |
| 4. Multiple ranked start/end suggestions | No code exists. The current flow returns exactly one proposal. |
| 5. Transient role classification | No code exists. `AudioSampleCategory` covers whole-file categorisation only. |
| 6. Isolated prototype (not wired in) | This story is satisfied by the research intent: nothing in `Sources/` needs to change for the prototype to run. The existing `SliceAnalyzer` and `WaveformDownsampler` can be called from a standalone Swift command-line tool or their logic can be reimplemented in JavaScript for an HTML prototype. |

---

## Model gaps vs. UX/workflow gaps

**Model gaps (would eventually need new code in `Sources/`):**
- No BPM-inference function.
- No grid-alignment scoring function.
- No multi-hypothesis output type (e.g. `[(bpm: Double, bars: Int, startFrame: Int64, endFrame: Int64, score: Double)]`).
- `SliceMarker` has no `role` or `classification` field.
- `SliceSet.bpmHint` and `SliceSet.bars` are stub fields that are never read; they would need semantics attached to be useful.

**UX/workflow gaps (production app, out of scope for this prototype milestone):**
- No ranked hypothesis list displayed to the user.
- No "suggest loop boundaries" UI affordance separate from the current "Auto Detect" panel.
- No transient role overlay on the waveform view.
- No audition-by-candidate UI.

---

## Architecture constraints

- `SliceAnalyzer` is a pure Swift enum with static methods and no `@MainActor` or `Observable` dependencies. Its private helpers (`monoSamples`, `rmsWindows`, `movingAverage`, `isLocalMaximum`) are all side-effect-free. The algorithm logic can be lifted into a standalone Swift package or reimplemented verbatim in JavaScript for an HTML prototype without linking against the app target.
- `WaveformDownsampler` is similarly self-contained but holds a process-lifetime `NSCache`; a prototype that calls it from a command-line harness would skip the cache (cold path always runs).
- `AVAudioFile` is available in both macOS app and macOS command-line targets. A Swift command-line prototype that calls `SliceAnalyzer.transientSlices` directly is the lowest-friction route to testing algorithm variants without touching `Sources/`.
- The `SliceMode` enum (`.grid`, `.transient`, `.manual`) would need a new case to represent a BPM-inferred result if that were ever brought into the production app, but that is outside the current prototype scope.

---

## Relevant tests and missing coverage

| File | What it covers | Missing |
|---|---|---|
| `Tests/.../Audio/SliceAnalyzerTests.swift` | Grid slicing, transient detection accuracy, backtrack prevention | BPM inference, grid-alignment scoring, multi-hypothesis ranking, loop-trim heuristics |
| `Tests/.../Document/SliceSetTests.swift` | Normalization, marker lookup, selection policy, boundary editing | BPM/bars field semantics, classification field |
| `Tests/.../Audio/WaveformDownsamplerTests.swift` | Bucket computation | Not a gap for this feature |

The prototype exploration does not require any test changes in `Tests/`. New heuristic tests would only be written once a direction is selected and brought into the production codebase.
