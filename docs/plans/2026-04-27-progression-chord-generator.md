# Progression Chord Generator

**Parent context:** `../progressive`, `wiki/pages/generator-algos.md`, `wiki/pages/project-layout.md`, and the current generated-source pipeline.
**Status:** Not started. Tag `v0.0.NN-progression-chord-generator` at completion.

## Summary

Port the useful musical core of `../progressive` into sequencer-ai as a new polyphonic chord generator.

The generator should output chords from a progression anchored by a root position. Users can seed it from a preset progression catalog, then manually edit the root and each relative chord position. The in-app UI should be much simpler than `progressive`: no web keyboard-performance surface, no Tone.js synth presets, no standalone MIDI device selector, and no browser-local storage. The sequencer already owns playback, destinations, transport, and persistence.

The important packaging decision: this should be a native generator feature, not an embedded copy of the web app.

- Pure harmony data and algorithms belong in `Sources/Musical/`.
- Serializable generator state belongs in `Sources/Document/`.
- Runtime evaluation stays in `GeneratedSourceEvaluator`.
- SwiftUI editor components live under `Sources/UI/TrackSource/Generator/`.
- Preset progressions should be bundled app data, either generated into Swift tables or loaded from a resource file through a small catalog API.

## What `../progressive` Contains

`../progressive` is a compact TypeScript browser app:

- `src/main.ts` contains the chord table, progression parsing, variant generation, voice leading, UI, Tone.js synth playback, Web MIDI output, and a small sequencer.
- `public/chordprogressions.json` contains preset progressions with:
  - `notation`
  - `songs`
  - `description`
  - `common_additions`
  - `genres`
  - `keywords`
- Chord slots are roman-numeral tokens such as `i`, `VII`, `vi`, `V7`, `bVIadd9`.
- `getVariants(...)` expands a base roman numeral into common chord qualities.
- `voiceNotes(...)` maps progression-relative intervals to MIDI notes for the selected root.
- `applyVoiceLeading(...)` picks octave shifts that minimize motion from the previous voicing, constrained roughly to MIDI `36...96`.
- The sequencer mode can play whole chords or arpeggiate them up/down/up-down.

What is worth porting:

- preset progression catalog;
- roman numeral chord spelling;
- a root-position anchor with other chords positioned relative to it;
- chord-quality variants;
- root transposition;
- deterministic voice-leading;
- optional arpeggiation modes after the chord mode lands.

What should not be ported directly:

- Tone.js synths and effects;
- browser DOM UI;
- Web MIDI output selection;
- localStorage state;
- keyboard bindings as the primary app interaction.

## Product Shape

Add a new generator kind for poly tracks:

- `GeneratorKind.progressionChordGenerator`
- `GeneratorParams.progressionChord(...)`

The generator emits one chord per chord slot according to track/phrase timing. By default it should trigger at the start of each bar and emit a chord whose notes last the full bar. That default should be configurable: users can change when chord slots advance and how long the emitted notes are held.

The central model is not "four unrelated absolute chords." It is:

1. one root-position anchor chord;
2. a sequence of relative chord positions from that anchor;
3. per-slot modifications for quality, extension, inversion/voicing, and later probability or timing.

This keeps the progression portable. Changing the root from C to D, or changing the anchor from `i` to `I`, should move the other slots musically rather than requiring the user to rewrite every chord as an absolute pitch set.

Suggested controls:

- Root note, e.g. C, D, Eb/F# depending on existing note-name policy.
- Root position / anchor chord, e.g. `I` or `i`.
- Preset progression picker.
- Editable relative slots, each with position offset and variant.
- Chord advance interval, defaulting to one bar.
- Chord gate/hold length, defaulting to the full advance interval.
- Voicing mode:
  - close position;
  - voice-led, based on `progressive`'s minimum-motion algorithm.
- Register range, defaulting near `36...96`.
- Note shape: velocity and gate, reusing existing `NoteShape`.
- Optional output mode:
  - chord, v1 default;
  - arpeggio up/down/up-down, later.

The generator should be usable anywhere a poly generator is currently usable: as a track source, and eventually as a harmonic sidechain source if the project wants progression-generated chords to guide other generators.

## Model

Add pure musical types:

```swift
struct ProgressionAnchor: Codable, Equatable, Hashable, Sendable {
    var rootMIDI: Int
    var token: RomanChordToken // usually I or i, but editable
}

struct RomanChordToken: Codable, Equatable, Hashable, Sendable {
    var degree: RomanDegree
    var accidental: Int
    var quality: RomanChordQuality
    var extension: RomanChordExtension?
}

struct ProgressionPreset: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: String
    var notation: String
    var description: String
    var songs: [String]
    var genres: [String]
    var keywords: [String]
    var commonAdditions: [String]
}

struct ProgressionSlot: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: UUID
    var relativePosition: ChordRelativePosition
    var modification: ChordSlotModification
}
```

Add generator params:

```swift
struct ChordRelativePosition: Codable, Equatable, Hashable, Sendable {
    var scaleDegreeOffset: Int
    var accidentalOffset: Int
}

struct ChordSlotModification: Codable, Equatable, Hashable, Sendable {
    var qualityOverride: RomanChordQuality?
    var extensionOverride: RomanChordExtension?
    var selectedVariant: RomanChordToken?
}

struct ProgressionChordGeneratorParams: Codable, Equatable, Hashable, Sendable {
    var anchor: ProgressionAnchor
    var slots: [ProgressionSlot]
    var timing: ProgressionChordTiming
    var voicing: ChordVoicingMode
    var register: ClosedRange<Int>
    var outputMode: ProgressionChordOutputMode
    var shape: NoteShape
}

struct ProgressionChordTiming: Codable, Equatable, Hashable, Sendable {
    var advanceEverySteps: Int // default: one bar, usually 16 steps
    var gateLengthSteps: Int   // default: same as advanceEverySteps
    var phaseOffsetSteps: Int  // default: 0, start of bar
}

enum ChordVoicingMode: String, Codable, Equatable, Hashable, Sendable {
    case close
    case voiceLed
}

enum ProgressionChordOutputMode: String, Codable, Equatable, Hashable, Sendable {
    case chord
    case arpUp
    case arpDown
    case arpUpDown
}
```

Implementation detail: Swift `ClosedRange<Int>` is Codable, but a small explicit `MIDIRegisterRange { low, high }` may be better for validation and UI.

Extend:

```swift
enum GeneratorParams {
    case progressionChord(ProgressionChordGeneratorParams)
}

enum GeneratedSourcePipelineContent {
    case progressionChord(ProgressionChordGeneratorParams)
}
```

Recommendation: do not force this into the existing `.poly(trigger:pitches:shape:)` shape. A progression generator has its own timebase, root anchor, relative slot positions, variants, and voice-leading state. Encoding it as fake pitch lanes would hide the domain model and make the editor awkward.

## Evaluation Semantics

For step `n`:

1. Resolve timing:
   - `advanceEverySteps` defaults to one bar;
   - `gateLengthSteps` defaults to `advanceEverySteps`;
   - `phaseOffsetSteps` defaults to `0`.
2. Resolve `progressionStep = n - phaseOffsetSteps`.
3. Resolve `slotIndex = (progressionStep / advanceEverySteps) % slots.count`.
4. If `progressionStep % advanceEverySteps != 0`, emit no new chord in v1.
5. Resolve the slot's `relativePosition` against the `anchor`.
6. Apply the slot's modification / selected variant.
7. Resolve the resulting roman token to pitch-class intervals relative to the anchor root.
8. Choose a voicing:
   - `close`: place notes near the root/register default.
   - `voiceLed`: choose octave shifts that minimize distance from the prior emitted chord.
9. Emit one `GeneratedNote` per chord tone using shared `NoteShape` for velocity and timing `gateLengthSteps` for note length.
10. Persist evaluator state needed for voice-leading in `GeneratedSourceEvaluationState`.

For arpeggio modes later:

1. Keep the same chord-slot resolution.
2. Resolve and voice the current chord at the slot boundary.
3. Emit one chord tone on each sub-step according to `arpUp`, `arpDown`, or `arpUpDown`.

The seeded default should be "one chord per bar, held for the full bar." Shorter gates and faster/slower progression movement are user-editable timing settings, not separate generator kinds.

## Preset Packaging

There are two reasonable approaches.

### Option A — Swift table

Convert `public/chordprogressions.json` into `Sources/Musical/ProgressionPresets.swift`.

Pros:

- simple tests;
- no resource-loading path;
- easy availability in document/UI code.

Cons:

- large static data file if the catalog grows;
- editing presets requires code generation or manual Swift edits.

### Option B — bundled JSON resource

Copy a cleaned version of `public/chordprogressions.json` into `Sources/Resources/` and expose it through `ProgressionPresetCatalog`.

Pros:

- data remains data;
- easier to refresh from `progressive`;
- better if the catalog becomes large.

Cons:

- resource wiring and loading tests needed;
- `Sources/Musical` cannot directly depend on app resource loading if we want it to stay pure.

Recommendation for v1: use a bundled JSON resource with a pure decoder type. Keep the loader thin and deterministic, and add a test that validates every preset parses into slots.

## UI Shape

Add a specialized editor shown only for `progressionChord` params.

Suggested file layout:

```text
Sources/UI/TrackSource/Generator/
  ProgressionChordGeneratorEditor.swift
  ProgressionPresetPicker.swift
  ProgressionSlotGrid.swift
  RomanChordTokenPicker.swift
  ChordVoicingControls.swift
```

The first version should be compact:

- top row: preset picker, root note picker, root-position/anchor picker;
- second row: advance interval, gate length, phase offset, voicing mode, and register;
- main area: horizontal slot grid;
- each slot: relative position, resolved chord label, modification/variant menu, duplicate/delete;
- add slot button at the end;
- preview strip using the same generated-source preview path.

Manual editing should allow:

- replacing a slot from a roman-token palette;
- nudging a slot's relative position up/down by scale degree or accidental;
- cycling variants like `progressive` does;
- overriding each slot's quality or extension independently;
- adding/removing/reordering slots;
- clearing back to preset defaults.

Avoid copying the `progressive` performance-pad UI. In sequencer-ai the track already plays through the transport and destination system; the editor should configure the generator, not become a second instrument surface.

## Integration With Chord Context

This generator can be useful in two ways:

1. As a normal poly note source: emits notes to the track destination.
2. As harmonic context: broadcasts the current chord to the project chord-context lane so other generators can use `.projectChordContext`.

V1 should implement normal note output first.

Then add an optional routing path:

- route progression chord generator output to `.chordContext(...)`, or
- add a generator setting `publishChordContext: Bool`.

The routing approach is more consistent with the existing `RouteDestination.chordContext` model. It also avoids making generator params responsible for global project state.

## Task 1 — Extract and port harmony primitives

**Goal:** Move the useful `progressive` harmony logic into pure Swift.

- [ ] Add roman chord token model.
- [ ] Add `ProgressionAnchor`.
- [ ] Add `ChordRelativePosition` and `ChordSlotModification`.
- [ ] Add parser for progression notation split on `-` and en dash.
- [ ] Convert parsed preset notation into anchor + relative positions.
- [ ] Add interval resolver for major/minor degrees, flat degrees, seventh/sixth/ninth/add/sus variants.
- [ ] Add variant generation equivalent to `getVariants(...)`.
- [ ] Add root transposition.
- [ ] Add tests using known tokens from `progressive`: `i`, `VII`, `V7`, `bVIadd9`, `IIm7b5`.

Acceptance:

- All bundled preset `notation` strings parse successfully.
- Presets are stored as one anchor plus relative slot positions, not as unrelated absolute chords.
- Token interval output matches `progressive` for representative chords.

## Task 2 — Add preset catalog

**Goal:** Seed progressions from `progressive`'s preset data.

- [ ] Normalize `public/chordprogressions.json` into app resource data.
- [ ] Add `ProgressionPreset` and `ProgressionPresetCatalog`.
- [ ] Preserve descriptive metadata for search/filtering.
- [ ] Add tests that every preset parses and has at least two slots.

Acceptance:

- New projects can seed a progression generator from bundled presets.
- Invalid preset JSON fails in tests rather than at runtime.

## Task 3 — Add generator params and default pool entry

**Goal:** Make progression chords a first-class poly generator.

- [ ] Add `GeneratorKind.progressionChordGenerator`.
- [ ] Add `GeneratorParams.progressionChord(...)`.
- [ ] Add default params seeded from a small reliable progression, e.g. `i-VII-VI-VII` or `I-V-vi-IV`.
- [ ] Seed timing as one chord per bar with full-bar gate.
- [ ] Add a compatible default generator pool entry for `.polyMelodic`.
- [ ] Add Codable round-trip and legacy decode tests.

Acceptance:

- Existing documents decode unchanged.
- New progression generators appear for poly tracks.
- Default playback emits one full-bar chord at each bar boundary.

## Task 4 — Evaluate progression chords

**Goal:** Produce chord notes from the shared generated-source evaluator.

- [ ] Extend `GeneratedSourcePipelineContent`.
- [ ] Extend `GeneratedSourceEvaluator.cycleLength(...)`.
- [ ] Extend `GeneratedSourceEvaluator.evaluateStep(...)`.
- [ ] Extend `GeneratedSourceEvaluationState` with prior chord/voicing state.
- [ ] Add configurable progression timing: advance interval, gate length, and phase offset.
- [ ] Implement close voicing.
- [ ] Implement voice-led voicing using the `progressive` minimum-motion algorithm.
- [ ] Add tests for slot timing, wrapping, emitted notes, gate/velocity, and voice-leading.

Acceptance:

- A four-slot progression emits one chord at each configured chord boundary.
- Default timing emits at bar starts with full-bar note lengths.
- Edited timing can advance faster/slower and shorten gates.
- Output is deterministic in preview/tests.
- Voice-led mode keeps nearby voicings without leaving the register.

## Task 5 — Add native generator editor

**Goal:** Let users seed and edit progressions without exposing the generic pitch-lane UI.

- [ ] Add `ProgressionChordGeneratorEditor`.
- [ ] Route `.progressionChord` in `GeneratorParamsEditorView`.
- [ ] Add preset picker.
- [ ] Add root picker.
- [ ] Add root-position / anchor picker.
- [ ] Add timing controls for advance interval, gate length, and phase offset.
- [ ] Add editable slot grid.
- [ ] Add per-slot relative position controls.
- [ ] Add modification / variant selector per slot.
- [ ] Add voicing/register controls.
- [ ] Add preview using `GeneratedSourceEvaluator.previewNotes(...)`.

Acceptance:

- User can choose a preset and immediately play it through a poly track.
- By default, chords trigger at the start of each bar and last the full bar.
- User can configure chord advance and gate length.
- User can manually edit the anchor and each relative chord after seeding.
- The UI does not show irrelevant poly pitch-lane controls for this generator.

## Task 6 — Chord-context routing follow-up

**Goal:** Let progression chords drive other generators harmonically.

- [ ] Decide whether chord-context publication is route-only or generator-owned.
- [ ] Prefer route-only if existing routing can carry generated chord identity cleanly.
- [ ] Emit or derive `Stream.chord` / `Chord` from the active progression slot.
- [ ] Add tests showing another generator using `.projectChordContext` follows the progression.

Acceptance:

- A progression generator can provide chord context without also needing to be audible.
- Existing note output routing remains unchanged.

## Task 7 — Documentation

**Goal:** Make the new generator understandable and maintainable.

- [ ] Update `wiki/pages/generator-algos.md`.
- [ ] Add a short note in `wiki/pages/project-layout.md` if preset resources introduce a new loader.
- [ ] Document the difference between:
  - chord note output;
  - chord context broadcast;
  - harmonic sidechain consumption.

Acceptance:

- A new contributor can tell where harmony tables, presets, document params, evaluation, and UI each live.

## Open Questions

- Should the default root note be project-global later, or generator-local only in v1?
- Should root position default to `I`/`i` from the preset, or should presets be normalized to a fixed anchor with explicit mode?
- Should progression slots store parsed tokens only, or also the original notation string for display fidelity?
- Should common additions from the preset metadata seed variant suggestions per slot?
- Should arpeggio modes ship with v1 or follow after chord output works?
- Should timing controls be step-based in v1, or offer musically named values like `1 bar`, `2 bars`, `1/2 bar`?
- Should a progression generator be allowed on mono tracks as arpeggio-only, or stay poly-only?
- Should progression-generated chord context use the existing `ChordID` set, or does `Chord` need richer roman/interval metadata?

## Test Plan

- Musical:
  - token parser;
  - preset parser;
  - interval resolution;
  - variant generation;
  - voice-leading register constraints.
- Document:
  - `GeneratorParams.progressionChord` Codable round-trip;
  - legacy project decode;
  - generator pool compatibility.
- Evaluation:
  - chord boundary firing;
  - progression wrapping;
  - emitted notes for known roots/progressions;
  - voice-led vs close-position output;
  - preview determinism.
- UI:
  - editor displays for progression generator only;
  - preset selection replaces slots;
  - manual slot edits update params;
  - preview reflects edited progression.
- Manual smoke:
  - create poly track;
  - choose progression chord generator;
  - seed from preset;
  - set root note and root position;
  - confirm default output is one full-bar chord per bar;
  - shorten gate and advance interval, then confirm playback follows the edited timing;
  - play through AU or MIDI destination;
  - edit one slot and hear the next phrase reflect the changed chord.
