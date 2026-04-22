# Sampler Filter: Built-in Per-Track Multi-mode Filter

**Parent spec:** `docs/specs/2026-04-18-north-star-design.md`
**Status:** Not started. Tag `v0.0.NN-sampler-filter` at completion.

## Summary

Every sampler-driven track (destination `.sample` or `.internalSampler`) gets a built-in filter node in its audio path, between the per-track mixer and the main mixer. The filter defaults to a 2-pole low-pass at 20 kHz with zero resonance — inaudible by default, so adding it doesn't change the sound of existing documents.

The filter exposes: **type** (LP / HP / BP / Notch), **poles** (1 / 2 / 4), **cutoff** (Hz, log-mapped), **resonance** (0..1), and **drive** (0..1).

Filter state lives on `StepSequenceTrack`, not on `Destination`, so it survives a sample swap within the same track. It's auto-populated when the track's destination becomes a sampler variant and cleared when the destination moves to a non-sampler (AU / MIDI).

The filter's five parameters surface as **built-in track macros** via the [track macro parameters plan](2026-04-22-track-macro-parameters.md), so they immediately show up in Phrase view and Live view without filter-specific UI plumbing.

## Scope: in

- `SamplerFilterSettings` document type (`type`, `poles`, `cutoffHz`, `resonance`, `drive`)
- `SamplerFilterNode` audio node, inserted between `trackMixer` and `engine.mainMixerNode`
- Insertion, tear-down, and reconnection paths in `SamplePlaybackEngine`
- Extension of `BuiltinMacroKind` with `samplerFilterCutoff`, `samplerFilterReso`, `samplerFilterDrive`, `samplerFilterType`, `samplerFilterPoles`
- Auto-population of filter macros on the track when destination becomes sampler-shaped
- Minimal UI: a filter controls row in `SamplerDestinationWidget` (type picker, poles picker, three knobs)

## Scope: out (deliberately deferred)

- Custom `AUAudioUnit` DSP subclass. V1 wraps `AVAudioUnitEQ` with one parametric band, which is cheap and gets us LP/HP/BP/Notch correctly. 1-pole and 4-pole are **stored in the model but approximated in DSP** via Q manipulation — not acoustically correct slopes. This is deliberate: ship the model and UX, swap the DSP later.
- Per-voice independent filters. One filter per track, shared by all voices on that track.
- Filter on non-sampler tracks (e.g. putting a filter on an AU destination). If we want that later, it becomes a general "track insert" concept — a different plan.
- Envelope-follower or key-tracked cutoff. Macros handle per-step modulation; audio-rate modulation is a separate plan.
- Saturation / drive algorithm choices. One fixed soft-clip curve.

## Dependencies

- **Hard dependency**: the track macro parameters plan (`2026-04-22-track-macro-parameters.md`) must ship first. This plan adds cases to `BuiltinMacroKind` and relies on `TrackMacroApplier` dispatch; neither exists without the macros plan.
- `SamplePlaybackEngine` already manages per-track `AVAudioMixerNode`s (`Sources/Audio/SamplePlaybackEngine.swift:156`).
- `StepSequenceTrack` already exists; this plan adds a `filter` field to it.

## File Structure (post-plan)

```
Sources/Document/
  SamplerFilterSettings.swift        NEW — type/poles/cutoff/resonance/drive + defaults
  StepSequenceTrack.swift            MODIFIED — add `filter: SamplerFilterSettings`
  TrackMacroDescriptor.swift         MODIFIED — extend BuiltinMacroKind with five filter cases
  Project+Tracks.swift               MODIFIED — auto-populate filter macros when dest becomes sampler

Sources/Audio/
  SamplerFilterNode.swift            NEW — wraps AVAudioUnitEQ(numberOfBands: 1), exposes set(...)
  SamplePlaybackEngine.swift         MODIFIED — attach/connect filter between mixer and mainMixer;
                                                tear down on removeTrack
  TrackMacroApplier.swift            MODIFIED — dispatch .samplerFilter* builtins to SamplerFilterNode

Sources/UI/
  SamplerDestinationWidget.swift     MODIFIED — add filter controls row (type, poles, knobs)

Tests/SequencerAITests/
  Document/
    SamplerFilterSettingsTests.swift               NEW — round-trip, defaults, clamping
    StepSequenceTrackFilterDefaultTests.swift      NEW — defaults and legacy decode
    ProjectTrackSamplerFilterMacrosTests.swift     NEW — auto-populate on destination change
  Audio/
    SamplerFilterNodeTests.swift                   NEW — passthrough default, HP attenuation test
    SamplePlaybackEngineFilterWiringTests.swift    NEW — attach/detach exactly once per track
  Engine/
    TrackMacroApplierSamplerFilterTests.swift      NEW — macro writes hit the filter node
```

## Task 1 — `SamplerFilterSettings`

**Goal:** Pure document type, no DSP.

**Files:** `Sources/Document/SamplerFilterSettings.swift`, `Tests/.../SamplerFilterSettingsTests.swift`

```swift
enum SamplerFilterType: String, Codable, CaseIterable, Sendable {
    case lowpass, highpass, bandpass, notch
}

enum SamplerFilterPoles: Int, Codable, CaseIterable, Sendable {
    case one = 1, two = 2, four = 4
}

struct SamplerFilterSettings: Codable, Equatable, Hashable, Sendable {
    var type: SamplerFilterType = .lowpass
    var poles: SamplerFilterPoles = .two
    var cutoffHz: Double = 20_000       // 20..20_000
    var resonance: Double = 0           // 0..1
    var drive: Double = 0               // 0..1

    func clamped() -> SamplerFilterSettings
    init(from decoder:) // decodeIfPresent with stored-property fallbacks, same pattern as SamplerSettings
}
```

Default is bypass-transparent: `.lowpass` at 20 kHz with zero resonance/drive leaves signal unchanged within audible range, so existing documents remain bit-identical before a user touches the filter.

**Tests:**
- Round-trip with each `type` and each `poles` value.
- Legacy JSON without `filter` key decodes with defaults.
- `clamped()` bounds cutoff, resonance, drive.

## Task 2 — `StepSequenceTrack.filter` + auto-population

**Goal:** Every track carries a filter settings struct. The associated built-in macro bindings exist only when the destination is sampler-shaped.

**Files:** `Sources/Document/StepSequenceTrack.swift`, `Sources/Document/Project+Tracks.swift`, `Sources/Document/TrackMacroDescriptor.swift`

### 2a — Add `filter: SamplerFilterSettings = .init()` to `StepSequenceTrack`

Read the file end-to-end first; match the existing `Codable` pattern (`decodeIfPresent` fallback, no migration shim).

### 2b — Extend `BuiltinMacroKind`

```swift
enum BuiltinMacroKind: String, Codable, CaseIterable, Sendable {
    // Existing from macros plan:
    case sampleStart
    case sampleLength
    case sampleGain

    // NEW in this plan:
    case samplerFilterCutoff      // Hz, 20..20_000, log-mapped in UI
    case samplerFilterReso        // 0..1
    case samplerFilterDrive       // 0..1
    case samplerFilterType        // indexed: lowpass / highpass / bandpass / notch
    case samplerFilterPoles       // indexed: 1 / 2 / 4
}
```

For each kind, the `TrackMacroDescriptor` factory (defined in the macros plan) needs entries returning the right `minValue / maxValue / defaultValue / valueType`:

- `samplerFilterCutoff`: scalar, 20..20_000, default 20_000
- `samplerFilterReso`: scalar, 0..1, default 0
- `samplerFilterDrive`: scalar, 0..1, default 0
- `samplerFilterType`: patternIndex, 0..3, default 0 (lowpass)
- `samplerFilterPoles`: patternIndex, 0..2, default 1 (→ `.two`)

### 2c — Auto-population

The macros plan already wires "destination becomes sampler-shaped → populate built-in macros." Extend that list from three (start/length/gain) to eight (add the five filter kinds). Destination swapping away from sampler-shaped removes all eight.

Binding-id stability is the same: deterministic hash of `(trackID, builtinKind.rawValue)`.

**Tests:** `ProjectTrackSamplerFilterMacrosTests`:
- Setting `.internalSampler` adds the five filter bindings (on top of the three sample-level ones from the macros plan).
- Setting `.auInstrument` removes all eight.
- Switching between `.sample` and `.internalSampler` doesn't duplicate or recreate bindings — the ids are the same.
- A clip macro lane keyed to the filter cutoff binding id survives destination swaps between `.sample` and `.internalSampler`.

## Task 3 — `SamplerFilterNode`

**Goal:** A wrapper around `AVAudioUnitEQ` that presents the five-parameter surface and maps it to EQ band settings.

**Files:** `Sources/Audio/SamplerFilterNode.swift`, `Tests/.../SamplerFilterNodeTests.swift`

```swift
final class SamplerFilterNode {
    let avNode: AVAudioUnitEQ        // numberOfBands: 1

    init()

    func apply(_ settings: SamplerFilterSettings)

    // Fine-grained setters used by the macro applier (avoid reapplying the whole
    // struct every prepared step; only the changed field is written).
    func setType(_ type: SamplerFilterType)
    func setPoles(_ poles: SamplerFilterPoles)
    func setCutoff(hz: Double)
    func setResonance(_ normalized: Double)
    func setDrive(_ normalized: Double)
}
```

### Band configuration mapping

`AVAudioUnitEQFilterType` supports `.lowPass`, `.highPass`, `.bandPass`, `.parametric`. Map:

- `.lowpass → .lowPass`
- `.highpass → .highPass`
- `.bandpass → .bandPass`
- `.notch → .parametric` with gain = -40 dB and bandwidth derived from resonance (tighter Q = narrower notch)

### Poles approximation (documented compromise)

`AVAudioUnitEQ` doesn't expose slope directly. V1 approximation:

- `.one` (6 dB/oct) → `bandwidth = 1.0` (wide, gentle)
- `.two` (12 dB/oct) → `bandwidth = 0.5` (default)
- `.four` (24 dB/oct) → `bandwidth = 0.15` (tight)

This is **not a correct pole count**; it's a perceptual stand-in. Write one comment on `setPoles` noting this and linking to the follow-up `AUAudioUnit` subclass plan (not filed yet). Do not invent a fake slope with multiple cascaded bands in v1 — one band, one approximation, swap the whole DSP later.

### Resonance and drive

- Resonance → `band.bypass = false; band.filterType = ...; globalGain = 0; band.gain = resonance * 18 dB` for LP/HP/BP (audibly resonant bump near cutoff). Clamp resonance value before mapping.
- Drive is applied as `globalGain += drive * 12 dB` so it's audible without being a separate saturation stage. V1 is not real saturation — document this.

### Bypass-transparency test

At defaults (`lowpass`, `two`, 20 kHz, 0, 0), a 1 kHz sine passes through with RMS change < 0.5 dB. This is the acceptance test.

**Tests:** `SamplerFilterNodeTests` using `AVAudioEngine` offline render:
- Default settings: 1 kHz sine RMS within 0.5 dB before vs. after.
- `.highpass` at 10 kHz: 1 kHz sine attenuated by more than 20 dB.
- `.lowpass` at 500 Hz: 5 kHz sine attenuated by more than 15 dB.
- Changing `type` updates the underlying `filterType` enum on the band.
- Setter methods don't allocate (confirmed by not creating new bands).

## Task 4 — Insertion in `SamplePlaybackEngine`

**Goal:** Filter sits between the per-track mixer and `engine.mainMixerNode`.

**Files:** `Sources/Audio/SamplePlaybackEngine.swift`, `Tests/.../SamplePlaybackEngineFilterWiringTests.swift`

### 4a — Graph insertion

Current graph (`SamplePlaybackEngine.swift:156-163`):

```
voices[trackID] -> trackMixers[trackID] -> engine.mainMixerNode
```

New graph:

```
voices[trackID] -> trackMixers[trackID] -> trackFilters[trackID].avNode -> engine.mainMixerNode
```

Changes:

- Add `private var trackFilters: [UUID: SamplerFilterNode] = [:]`.
- In `trackMixer(for:)`, after attaching + creating the mixer:
  1. Build filter node, attach its `avNode`.
  2. Disconnect mixer from main if it was auto-connected (audit `engine.connect`).
  3. `engine.connect(mixer, to: filter.avNode, format: nil)`
  4. `engine.connect(filter.avNode, to: engine.mainMixerNode, format: nil)`
  5. Store in `trackFilters`.

### 4b — Tear-down

If the engine already has a `removeTrack(_:)` / `tearDownTrack(_:)` path, extend it. If not, add one that disconnects and detaches both the mixer and the filter. Audit the existing disconnect code paths (`SamplePlaybackEngine.swift:92, 131, 134`) before deciding — don't duplicate logic.

### 4c — Settings application

Add a path for the engine's owner to apply `SamplerFilterSettings` to a track's filter:

```swift
func applyFilter(_ settings: SamplerFilterSettings, trackID: UUID) {
    performSync {
        trackFilters[trackID]?.apply(settings)
    }
}
```

This is called from the document layer on track-level changes. The per-step macro path goes through `TrackMacroApplier` (Task 5) and uses the finer-grained setters.

**Tests:** `SamplePlaybackEngineFilterWiringTests`:
- After starting the engine and routing a voice through one track, exactly one `SamplerFilterNode` exists for that track.
- Two tracks have two distinct filters.
- Stopping the engine + tearing down the track removes the filter; re-adding creates a fresh one.
- Offline render through the engine with filter at HP 10 kHz attenuates a 1 kHz sine — end-to-end check that the filter is in the signal path, not silently bypassed.

## Task 5 — `TrackMacroApplier` dispatch for filter macros

**Goal:** When the coordinator emits `macroValues[trackID][filterCutoffBindingID] = 800`, the applier writes 800 Hz into the track's filter node.

**Files:** `Sources/Audio/TrackMacroApplier.swift`, `Tests/.../TrackMacroApplierSamplerFilterTests.swift`

In the switch on `TrackMacroSource`, extend the `.builtin(...)` branch:

```swift
case .builtin(let kind):
    switch kind {
    case .sampleStart, .sampleLength, .sampleGain:
        samplerEngine.setVoiceParam(trackID: trackID, kind: kind, value: value)
    case .samplerFilterCutoff:
        samplerEngine.filterNode(for: trackID)?.setCutoff(hz: value)
    case .samplerFilterReso:
        samplerEngine.filterNode(for: trackID)?.setResonance(value)
    case .samplerFilterDrive:
        samplerEngine.filterNode(for: trackID)?.setDrive(value)
    case .samplerFilterType:
        let idx = Int(value.rounded()).clamped(to: 0..<SamplerFilterType.allCases.count)
        samplerEngine.filterNode(for: trackID)?.setType(SamplerFilterType.allCases[idx])
    case .samplerFilterPoles:
        let idx = Int(value.rounded()).clamped(to: 0..<SamplerFilterPoles.allCases.count)
        samplerEngine.filterNode(for: trackID)?.setPoles(SamplerFilterPoles.allCases[idx])
    }
```

Expose `SamplePlaybackEngine.filterNode(for:)` as an internal accessor — the applier doesn't build its own node registry; it asks the engine. This keeps ownership clean: the engine owns node lifetime; the applier just writes.

**Tests:** `TrackMacroApplierSamplerFilterTests` with a fake engine that records setter calls:
- Cutoff macro = 1200 → `setCutoff(hz: 1200)` called exactly once.
- Type macro = 2.0 → `setType(.bandpass)`.
- Type macro = -1 or 99 → clamped to valid range, no crash.
- Poles macro = 0.4 → rounds to 0 → `setPoles(.one)`.
- Missing filter node (e.g. track's destination is an AU) → applier skips silently, does not throw.

## Task 6 — UI: filter controls in `SamplerDestinationWidget`

**Goal:** A visible filter strip on sampler-destination tracks, independent of the macro picker. This is the "I just want to tweak the filter without setting up automation" path.

**Files:** `Sources/UI/SamplerDestinationWidget.swift`

Layout (a single horizontal row, wrapping to a second row on narrow widths):

- Type picker: segmented control with LP / HP / BP / Notch
- Poles picker: segmented control with 1 / 2 / 4
- Cutoff knob: log-mapped 20..20 k
- Resonance knob: 0..1
- Drive knob: 0..1

Each control edits `track.filter.*` directly. The existing macro system sees the new value through `TrackMacroApplier` on the next prepared step (no separate write path — the control's `onChange` calls `samplerEngine.applyFilter(track.filter, trackID:)` for immediate feedback, and the per-step macro dispatch keeps them in sync).

**Do not** add duplicate phrase-layer / Live-view knobs for the filter in this plan — those come for free from the macros plan. This row is the destination-level "what the filter is right now" readout + editor.

**Tests:** none for the SwiftUI layer (matches repo convention). One ViewModel-level test: `onCutoffChanged(1200)` writes `track.filter.cutoffHz = 1200` and calls `samplerEngine.applyFilter` exactly once.

## Test Plan (whole-plan)

- **Document**: filter settings round-trip, legacy doc decode, macro auto-population on destination swap.
- **Audio**: filter node passthrough-at-defaults, HP/LP frequency tests, wiring tests (exactly-one-per-track).
- **Engine**: applier dispatches each of the five filter macro kinds to the right setter with clamping.
- **Manual smoke**:
  1. Open existing doc with a sampler track → sound is bit-identical (defaults are transparent).
  2. Drag filter cutoff knob to 500 Hz on an LP → audibly duller.
  3. Change type to HP → low end disappears.
  4. Change poles 1 → 4 → audibly steeper (even though it's a Q-based approximation).
  5. Set phrase cell `samplerFilterCutoff = .steps([200, 800, 3000, 12000])` → four filter sweeps per bar.
  6. Set a clip macro-lane override for step 1 of cutoff → that step opens fully even while the phrase steps 2–4 sweep.
  7. Switch destination sampler → AU → filter disappears from Phrase view; switch back → filter macros reappear with the same values (bindings are stable by id).

## Assumptions

- `AVAudioUnitEQ` with one band is sufficient fidelity for v1. The DSP can be swapped for a custom `AUAudioUnit` subclass later without touching the doc model, macros, UI, or wiring — only `SamplerFilterNode`'s internals change.
- Poles are a perceptual Q-based approximation, documented at the node, not a real slope order.
- One filter per track. If per-voice filtering becomes necessary, it's a separate refactor.
- Non-sampler tracks (AU / MIDI) don't get a filter in v1. General "track inserts" is a future plan.

## Traceability

| Requirement                                                  | Task |
|--------------------------------------------------------------|------|
| Built-in filter plugin attached to sampler                   | 3, 4 |
| Default low-pass                                             | 1 (SamplerFilterSettings default), 3 |
| Options for poles                                            | 1 (SamplerFilterPoles), 3 (mapping), 6 (picker) |
| Options for HP / BP / Notch                                  | 1 (SamplerFilterType), 3 (band mapping), 6 |
| Editable in Live / Phrase / clip macro lane                  | Covered by macros plan via filter-macro auto-population (Task 2) |
| Survives sample swap within the same track                   | 2a (filter on StepSequenceTrack, not Destination) |
| Default is transparent (zero-regression on existing docs)    | 3 (bypass-transparency test) |
