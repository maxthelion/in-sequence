# sequencer-ai — North Star Design

**Status:** Draft (overview)
**Date:** 2026-04-18
**Audience:** self / future collaborators
**Reference material:** [[sequencerbox-domain-model]], [[phatcontroller]], [[glaypen-reference]], [[octatrack-reference]], [[cirklon-reference]], [[polyend-play-reference]]

## Purpose

Unified **macOS-native** step sequencer synthesizing the strongest ideas from the user's prior projects and three reference devices. The goal of this doc is a coherent conceptual architecture — the shape of the thing — not an implementation plan. A separate implementation plan (via superpowers:writing-plans) will follow once this is approved.

## Platform and stack

macOS-native app (Apple Silicon primary; Intel tolerated where it falls out for free).

- **Language:** Swift.
- **UI:** SwiftUI, with AppKit escape hatches where SwiftUI strains (large drag-and-hover grids, fine-grained rotary knobs, per-pixel waveform editing).
- **Audio engine:** AVAudioEngine + AudioToolbox; Accelerate for DSP (transient detection, envelope analysis, slice RMS, possibly FFT for spectral slice labeling).
- **MIDI:** CoreMIDI; MIDI 2.0 where the device supports it (similar to what the [[phat]] project already uses via its MIDIManager).
- **AU hosting (design capability; implementation post-MVP):** AUv3 instruments and effects usable as pipeline sources and bus FX. AUv3 MIDI processors (e.g. the user's own [[phat]] extension) usable as inline MIDI transforms or sinks — so Phat becomes one of the sequencer's voices rather than a separate app.
- **Persistence:** Codable → JSON files in `~/Library/Application Support/sequencer-ai/` for templates, voice-preset library, fill-preset library; project `.seqai` document files in user-chosen locations. Autosave on edit; undo/redo stack at project scope.
- **Threading:** Pipeline DAG executor runs on a scheduling queue driven by the audio render clock for sample-accurate timing; UI thread writes block params via lock-free command queues read on the audio thread.
- **Why native over web:** sub-millisecond render-thread scheduling, proper realtime thread separation, native sample playback, AUv3 hosting, CoreMIDI without browser permission flows, and direct integration with the user's existing Swift AU work ([[phat]]).
- **iPadOS:** not a goal; most SwiftUI code should port trivially if demand justifies it later. AVAudioEngine is Apple-platforms-common.

## Design goals

1. **Start fast with generated material, then sweep.** The main workflow is: several voices with default generators playing in minutes, then make coarse-grained, high-level changes — both pre-programmed and performance-triggered.
2. **Macro authoring in abstract terms.** The macro/song layer speaks musical intent (intensity, tension, register, chord) not generator mechanics (step probability, interval bias). Each voice interprets abstract values in its own character.
3. **Compositional uniformity.** Generators, chord providers, fills, macro automation, routing — all are instances of one primitive: a typed block in a pipeline DAG. New capabilities drop into the block palette; they don't require special-case code.
4. **Pre-programmed and performative on equal footing.** "Every 8th bar is different" (authored) and "hold this fill preset for 2 bars" (live) share mechanism and state.
5. **Generative ↔ stamped-with-variation ↔ frozen is a continuum.** Not a modal choice. Any voice moves along it by block-level configuration.
6. **Drum tracks are visually one rhythm, sonically many voices.** Rhythm, voice identification, and routing are three independent concerns.
7. **MIDI-first, audio-side optional.** Octatrack-style crossfader-to-alt-bus is in scope as a design capability but out of scope for MVP implementation.

## Non-goals (for this doc)

- UI layout / wireframes — will follow separately once the model is fixed
- Implementation plan (tech stack, module breakdown, file structure) — follows via writing-plans
- Audio engine details (DSP, sampler machines, analog modeling)
- External sync as master, CV/gate output, .mid export

## Vocabulary

- **Track** — one instrument channel, project-scoped. Has an immutable **track type**, an inline **destination**, an optional **group membership**, and owns a fixed-size **pattern bank** of 16 patterns. Implemented as a pipeline ending in a MIDI or audio sink.
- **Track type** — one of `monoMelodic` / `polyMelodic` / `slice`. Immutable after track creation. Drum "parts" (kick, snare, hat, …) are **not** a separate track type; they are `monoMelodic` tracks conventionally grouped into a `TrackGroup` with a shared drum-machine destination (see §"Drum tracks as groups"). Immutability means "change the mind" = create a new track and migrate references.
- **Track group** — a project-scoped container that bundles N member tracks for collective operations: group-level mute / solo, group bus routing, optional `sharedDestination` that pulls member-track output through one shared AU (the drum-machine use case), and a display color for matrix tinting. Tracks belong to at most one group. See §"Drum tracks as groups."
- **Destination** — where a track's note stream ends up. Tagged union: `.midi(port, channel, noteOffset)` / `.auInstrument(componentID, stateBlob)` / `.internalSampler(bankID, preset)` / `.none` / `.inheritGroup`. The `.inheritGroup` variant is only valid when the track is in a group whose `sharedDestination` is set; at tick time the track's notes route through the group's shared destination instead of its own. Hybrid allowed: a drum group can have most members `.inheritGroup` while one member uses its own `.auInstrument(...)` to get a dedicated voice.
- **Pattern** — one slot in a track's 16-slot pattern bank (indexed 0..15, project-scoped, track-owned). Holds a **source mode** (either `.generator(GeneratorID)` or `.clip(ClipID)`) plus an optional human-readable name. All 16 slots always exist; empty slots default to `.generator(GeneratorID)` pointing at the track-type's default generator.
- **Source mode** — the content of a pattern slot: `.generator(GeneratorID)` referring into the generator pool, or `.clip(ClipID)` referring into the clip pool. Phrase never stores a source mode directly — phrase stores the pattern index and the pattern carries the source mode.
- **Generator kind** — a code-defined generated-source family. The current roster is `mono-generator`, `poly-generator`, `slice-generator`; each kind declares which track types it's compatible with. See §"Components inventory." Future AU MIDI processors do **not** become separate generator kinds — they replace a trigger or pitch stage inside the generated-source pipeline.
- **StepAlgo** — one of the trigger-generation strategies a generator stage composes to decide *whether* a note seed fires on a given step: `manual` / `randomWeighted` / `euclidean` / `perStepProbability` / `fromClipSteps`.
- **PitchAlgo** — one of the pitch-expansion / transformation strategies a pitch stage composes to decide *what pitch output* to emit from an incoming note seed: `manual` / `randomInScale` / `randomInChord` / `intervalProb` / `markov` / `fromClipPitches` / `external`.
- **Generator instance** — a user-configured generated-source pipeline, referenced by pattern slots. A generated source is an ordered pipeline of **trigger stage → one or more pitch stages → shared NoteShape**. Mono tracks use one pitch stage; poly tracks share one trigger stage across multiple pitch lanes; slice tracks use a trigger stage plus slice indexes instead of pitch stages. Pitch stages consume one primary note-seed stream and zero or more named sidechains; v1 ships `harmonicSidechain` (`none` / `projectChordContext` / `clip(ClipID)`). Example: `"verse-bass" = mono-generator(trigger: manual([..], basePitch: 60), pitch: randomInScale(root: 36, scale: .minor, spread: 12), NoteShape(vel: 95, gate: 3))`.
- **Clip** — concrete, stored step data with annotations, living in the project's **clip pool**. Has a compatibility tag (which track types may play it). Created by hand-authoring, freezing live generator output, or loading from the library.
- **Phrase** — reusable, N-bar unit (default 8 bars × 16 steps = 128 steps). A row in the phatcontroller-style grid: stores a **cell per (track × layer)**, where a cell carries an authored value (single, bars, per-step, or curve) or inherits the layer's per-track default. Phrases never carry source modes directly — the pattern-index layer resolves to the per-track pattern bank. Ghosts phatcontroller's phrase concept.
- **Song** — the ordered list `project.phrases: [Phrase]`, played top-to-bottom. Not a separate data structure — there is no "song" object, no phrase-refs, no repeat-count sugar, no conditional refs. To play something twice, list the same phrase twice. To de-duplicate edits, phrases reference shared pool entries (patterns, generators, clips) — editing the pool affects every phrase using it.
- **Layer** — a project-scoped definition of *what kind* of per-track per-phrase data goes in one column of the phrase grid. Each layer declares a value type (`boolean`, `scalar(0..127)`, `scalar(0..1)`, `patternIndex`, `chord`, `enumTag`, …), a per-track default value, and a target — what the layer's resolved value does at runtime (picks the pattern slot, drives a block param, writes a macro row, overrides a voice route, mutes). Users can add custom layers. The shipped-by-default layers include `Pattern`, `Mute`, `Volume`, `Transpose`, `Intensity`, `Density`, `Tension`, `Register`, `Variance`, `Brightness`, `FillFlag`, `Swing`.
- **Cell** — what's stored at the intersection of a phrase, a track, and a layer. A tagged union:
  - `.inheritDefault` — use the layer's per-track default (the "orange strip")
  - `.single(Value)` — one value for the whole phrase
  - `.bars([Value])` — one value per bar of the phrase
  - `.steps([Value])` — one value per step of the phrase (step-level authoring)
  - `.curve(ControlPoints)` — a time-varying curve over the phrase's duration
  The runtime expands every cell into a per-step value stream that blocks consume via the `interpret` transform.
- **Stream** — a typed value flow through the system. Every output of every block is a stream.
- **Sink** — a block that terminates a stream outside the pipeline DAG: MIDI-out, audio-param, chord-context broadcast, macro-row writer.
- **Pipeline** — a directed path from source through transforms to sink within a phrase. The source is determined by the active pattern on that track in that phrase; extra transforms are a power-user escape hatch in the Graph view.
- **Voice tag** — an abstract label (`kick`, `snare`, `hat`, `clap`...) carried on note-stream entries for drum tracks; decouples rhythmic material from sonic realization. Indexes both `Voicing.presets` and the `voice-route` sink's destination map.

## Track types, patterns, and phrases

Three track types, immutable after creation. Each track owns a fixed bank of 16 patterns. Phrases pick one pattern per track. The phrase does not carry source modes directly — it references pattern indexes into the per-track bank.

### The three track types

| Type | One-line | UI surface | Generator kinds (examples) |
|---|---|---|---|
| `monoMelodic` | bass, lead, drum voice — single note per step | pitch-lane editor (one note per step visible) | `mono-generator(step: euclidean, pitch: manual)` (the drum-voice pattern), `mono-generator(step: manual, pitch: randomInScale)` (melodic), `markov-note-chain` |
| `polyMelodic` | pads, chords, arp output | chord/stack editor (multi-note per step) | `chord-generator`, `note-gen-poly`, `arp-source`, `template-poly-pattern` |
| `slice` | sliced-loop playback | per-slice row grid | `slice-trigger`, `slice-markov`, `template-slice-pattern` |

Chord-producing material is **not** a fourth type: a "chord track" is a `polyMelodic` track whose active pattern's source mode is `.generator(id)` pointing at a `chord-generator` instance. **Drum parts are not a fourth type either** — each drum voice (kick, snare, hat, …) is its own `monoMelodic` track, typically configured with an euclidean or manual step algo and a constant pitch. Drum parts are grouped via `TrackGroup` for collective operations and optionally share a single drum-machine AU via `sharedDestination`; see §"Drum tracks as groups."

### The pattern bank (per track)

Every track owns exactly 16 pattern slots, indexed 0..15. Each slot holds:

```
Pattern
├── sourceMode: SourceRef           // .generator(GeneratorID) | .clip(ClipID)
└── name: String?                   // optional, user-editable
```

All 16 slots always exist. At track creation every slot is initialised to `.generator(defaultGeneratorID)` where `defaultGeneratorID` is a track-type-appropriate starter (e.g. a default `euclidean-drums` instance for drum tracks, `random-notes-in-scale-mono` for monoMelodic). Users edit slots over time; unedited slots just keep playing their defaults.

Pattern bank operations are track-local:

- **Copy** within a track: slot 3 → slot 7. Both slots now reference the same generator / clip id, with independent names.
- **Copy** between tracks of the same type: allowed, subject to compatibility filtering of the referenced pool entry.
- **Clear** a slot: resets it to `.generator(defaultGeneratorID)` for that track type.

### Project-scoped pools (unchanged)

Patterns reference into two project-scoped pools:

- `generatorPool: [GeneratorInstance]` — user-configured generator instances. Editing an instance propagates to every pattern slot (across tracks and phrases) that references it.
- `clipPool: [Clip]` — stored clips with annotations. Same propagation semantics.

Pool entries carry a `compatibleWith: Set<TrackType>` field (inherited from their kind for generators, declared at clip creation for clips).

### Phrase structure

A phrase is now a layer/cell matrix:

```
Phrase
├── name: String
├── lengthBars: Int
├── stepsPerBar: Int
└── cells: [CellAssignment]                // one per (trackID, layerID)

CellAssignment
├── trackID: TrackID
├── layerID: LayerID
└── cell: Cell

Cell
├── .inheritDefault
├── .single(Value)
├── .bars([Value])
├── .steps([Value])
└── .curve([Double])                       // scalar-only; sampled per step
```

The project owns the authoritative `layers: [Layer]` list. Every phrase carries one cell for every `(track, layer)` pair. When a track or layer is added, existing phrases are synchronised to include a new `.inheritDefault` cell for that pair. No phrase is ever missing a track/layer assignment.

Pattern selection is now just the built-in `Pattern` layer targeting `.patternIndex`. Muting is the built-in `Mute` layer targeting `.mute`. Tempo can be authored the same way via a BPM layer targeting `.macroRow("bpm")`. There is no separate `macroGrid` object any more; rows are the layer list, and phrase-local behavior lives in each cell's edit mode.

### Compatibility filtering at the slot editor

When the user opens a pattern slot's source picker in the Pattern editor, the choices are:

- `generatorPool.filter { $0.compatibleWith.contains(track.type) }`
- `clipPool.filter { $0.compatibleWith.contains(track.type) }`

The filter never exposes a melodic generator to a slice track, or a slice-trigger clip to a `monoMelodic` track.

### Track-type immutability

A track's type is set at creation and never changes. The 16-slot pattern bank is typed alongside it; all slots are constrained to the track's type. "Change the mind" is "create a new track of the desired type, migrate the phrase indexes, delete the old track."

## Drum tracks as groups

Drum parts don't get a special track type. A kick is a `monoMelodic` track. A snare is a `monoMelodic` track. A hat is a `monoMelodic` track. They're grouped via `TrackGroup` for the shared affordances users expect from a "drum track": mute the whole kit, compress it to a shared bus, collapse it to one cell in the matrix, share a single AU instance.

### `TrackGroup` shape

```swift
public struct TrackGroup: Codable, Equatable, Identifiable, Sendable {
    public let id: TrackGroupID
    public var name: String                          // "Drums", "Keys", "Backing vocals"
    public var color: String                         // hex / named colour for matrix tint
    public var memberIDs: [TrackID]                  // ordered; controls collapsed-cell order

    /// If set, member tracks whose `Destination == .inheritGroup` route here instead of their own.
    /// Use case: one drum-machine AU plays all member voices, addressed by note number.
    public var sharedDestination: Destination?

    /// Per-member note offset added to each note's pitch when routed through `sharedDestination`.
    /// Ignored for members whose Destination is not `.inheritGroup`.
    public var noteMapping: [TrackID: Int]

    public var mute: Bool                            // group-level mute; OR'd with per-member mute
    public var solo: Bool                            // group-level solo
    public var busSink: BusRef?                      // future: route the group's audio to a shared bus
}

// Project:
document.trackGroups: [TrackGroup]
```

A track belongs to **at most one** group (stored as `track.groupID: TrackGroupID?`). Removing a track from a group sets `track.groupID = nil`; if that track's `destination` was `.inheritGroup`, it auto-converts to `.none` and the UI surfaces a warning asking the user to pick a new destination.

### The three drum-setup ergonomics the model supports

1. **One drum-machine AU, many voices** (the Battery / Addictive Drums case):

   ```
   group "Drums"
     sharedDestination: .auInstrument(Battery)
     noteMapping: [kickTrackID: 36, snareTrackID: 38, hatTrackID: 42, …]
     memberIDs:  [kickTrackID, snareTrackID, hatTrackID, …]

   kickTrack.destination  = .inheritGroup     // routes through group's Battery at note 36
   snareTrack.destination = .inheritGroup     // routes through group's Battery at note 38
   hatTrack.destination   = .inheritGroup     // routes through group's Battery at note 42
   ```

   One AU instance. One AU editor window. Per-track patterns, per-track generators, per-track lengths — all still work because each member is an independent track.

2. **One independent AU per voice** (the Digitakt / per-part-granularity case):

   ```
   group "Drums"
     sharedDestination: nil
     memberIDs:  [kickTrackID, snareTrackID, hatTrackID, …]

   kickTrack.destination  = .auInstrument(kickAU)
   snareTrack.destination = .auInstrument(snareAU)
   hatTrack.destination   = .auInstrument(hatAU)
   ```

   Each voice has its own AU, its own FX chain (when insert-effects ship), its own life. Group still gives you collective mute/solo/bus-compress.

3. **Hybrid — mostly shared, some dedicated** (the "my kick needs its own specialist, everything else is the drum-machine" case):

   ```
   group "Drums"
     sharedDestination: .auInstrument(Battery)
     noteMapping: [snareTrackID: 38, hatTrackID: 42, …]     // no entry for kickTrackID
     memberIDs:  [kickTrackID, snareTrackID, hatTrackID, …]

   kickTrack.destination  = .auInstrument(dedicatedKickAU)   // bypasses group's Battery
   snareTrack.destination = .inheritGroup                    // routes to Battery at 38
   hatTrack.destination   = .inheritGroup                    // routes to Battery at 42
   ```

   Per-member opt-out by setting a concrete destination instead of `.inheritGroup`. Group still mutes all three together, still soloes together, still bus-routes together.

### Drum-kit preset (library asset)

A **drum-kit preset** is a library asset that bootstraps one of the three setups above. Encodes:

- A list of member-track definitions (name, default generator instance, pattern-bank seed, inherit-group flag, noteMapping entry)
- The group's `sharedDestination` template (if any)
- The group's suggested name + color

Applying a preset: user clicks "Add Drum Kit" in the Tracks matrix → picks a preset ("808", "Acoustic", "Techno") → the app creates N tracks + a `TrackGroup`, wires them per the preset's definition, navigates to the group detail (or to the first member track). MVP ships a handful of hard-coded `DrumKitPreset` values in `Sources/Musical/DrumKitPresets.swift`; later, preset import from the library folder.

### Resolution logic at tick time

```swift
func effectiveDestination(for trackID: TrackID) -> (Destination, pitchOffset: Int) {
    let track = tracks[trackID]!
    if case .inheritGroup = track.destination {
        guard let groupID = track.groupID, let group = trackGroups[groupID] else {
            return (.none, 0)        // orphaned inheritGroup → silent; UI warns
        }
        guard let shared = group.sharedDestination else {
            return (.none, 0)        // group has no shared destination → silent; UI warns
        }
        return (shared, group.noteMapping[trackID] ?? 0)
    }
    return (track.destination, 0)
}
```

Applied once per note event before dispatch. The `pitchOffset` is added to the event's `NoteEvent.pitch`.

### Worked example (updated)

Three phrases (verse / chorus / breakdown) and a kick track with three interesting pattern slots — 0 (steady euclidean kick), 3 (half-time variation), 7 (frozen fill clip captured live):

```
kickTrack.patterns[0]  = .generator(euclidKickInstanceID)     // "steady kick"
kickTrack.patterns[3]  = .generator(halfTimeKickInstanceID)   // "half-time kick"
kickTrack.patterns[7]  = .clip(liveFillClipID)                // "captured fill" (from freeze)
// slots 1, 2, 4-6, 8-15 = default

versePhrase.cells[(kickTrack.id, patternLayer.id)]     = .single(.index(0))
chorusPhrase.cells[(kickTrack.id, patternLayer.id)]    = .single(.index(0))
breakdownPhrase.cells[(kickTrack.id, patternLayer.id)] = .single(.index(3))
fillPhrase.cells[(kickTrack.id, patternLayer.id)]      = .single(.index(7))
```

Editing the params of `euclidKickInstanceID` in the generator pool affects verse + chorus kicks together (both reference it via slot 0). Switching the breakdown phrase to use the captured fill is still a single pattern-layer value change: `3 → 7`.

## Arpeggiator — a known edge

Arpeggiators bridge polyphonic input (a held chord) to monophonic output (one note per step). Two viable homes:

- A generator kind compatible with `polyMelodic` (input-side): chord-context in, chord-pattern out. The track stays poly; a pattern slot can reference an arp-source generator instance.
- A transform block that lives downstream of a poly source and upstream of a mono sink — doesn't fit the simple `SourceRef` world and requires a power-user Graph-view override.

Resolved for MVP: **arp-as-source-kind for `polyMelodic`**. The output is still one-or-more notes per step, so calling it poly is honest. A mono-side arp is deferred; when we need it, we'll promote the Graph-view escape hatch as a first-class thing.

## Scoping: project vs phrase

Following phatcontroller and Octatrack's part/pattern split: **tracks are project-scoped, pipelines are phrase-scoped**.

- **Project-scoped (stable across phrases):**
  - The set of tracks, their identities (kick, bass, lead, pad...), and their **track types** (`monoMelodic` / `polyMelodic` / `slice`)
  - Per-track **destination** — inline value of type `Destination` (`.midi` / `.auInstrument` / `.internalSampler` / `.none` / `.inheritGroup`)
  - **Track groups** — `trackGroups: [TrackGroup]`; each group bundles member tracks and optionally owns a shared destination (drum-machine AU case) with a per-member note-offset map. Tracks belong to at most one group
  - **Per-track pattern bank** — exactly 16 pattern slots per track, each holding a `SourceRef` (`.generator(id) | .clip(id)`) and an optional name. Every slot always exists; empty-at-creation slots default to the track-type's default generator
  - **Generator pool** — user-configured `GeneratorInstance`s (e.g. "my punchy kick", "verse-lead-wander"), each an instance of a registered `GeneratorKind`, with params. Patterns reference these
  - **Clip pool** — stored clips with annotations, tagged by track-type compatibility. Grows as the user hand-authors, freezes, or imports. Patterns reference these
  - Template library, saved fill presets, chord-generator library (library-scoped imports that feed the pools)
  - **Layer definitions** — the list of layers this project uses (pattern, mute, volume, intensity, …) plus their per-track defaults. Users can add/remove/rename layers
  - **Phrase list** — `phrases: [Phrase]` in playback order. This IS the song; there is no separate song object
- **Phrase-scoped (can vary per phrase):**
  - **Cell values** for every `(track, layer)` pair — `.inheritDefault`, `.single`, `.bars`, `.steps`, or `.curve`. One cell per (track, layer) intersection
  - Chord-gen pipeline configuration (progression, tension mapping) — carried on a layer or on the phrase itself
  - Power-user graph override: extra transform blocks beyond the default pipeline implied by the track's type and active pattern's source mode (Graph view only)

A voice preset swap at project scope instantly propagates to every phrase. A layer-default change in the project's orange strip instantly propagates to every phrase that isn't overriding it. A pool edit (generator instance or clip) affects every pattern slot (and therefore every phrase) that references it. Adding a new track creates a new column in the phrase grid; every phrase gets `.inheritDefault` cells for every layer on that track, so nothing new explicit is authored.

## The two layers (song + phrase)

```
┌───────────────────────────────────────────────────────────┐
│ PROJECT.PHRASES  (the song — ordered phrase list)          │
│                                                            │
│   ┌──────────── phrase grid ────────────┐                 │
│   │         track1 track2 … trackN      │                 │
│   │ phrase0   [c]   [c]  …   [c]        │ ← cells for the  │
│   │ phrase1   [c]   [c]  …   [c]        │   active layer   │
│   │ phrase2   [c]   [c]  …   [c]        │                 │
│   │ …                                   │                 │
│   └─────────────────────────────────────┘                 │
│   Layer selector: [Pattern][Mute][Volume][Intensity]…     │
│   Each cell = .inheritDefault | .single | .bars           │
│               | .steps | .curve                            │
└───────────────────────┬───────────────────────────────────┘
                        │ at tick time, each cell expands to
                        │ a per-step value; layers with target
                        │ .patternIndex pick the track's
                        │ pattern slot; the other layers
                        │ fan out as scalar/boolean streams
                        ▼
┌───────────────────────────────────────────────────────────┐
│ PIPELINE (per track, within the current phrase)            │
│   active pattern's source → transforms → sink              │
│   (chord-gen / voice-route / midi-out / audio-param …)    │
└───────────────────────┬───────────────────────────────────┘
                        │ emits MIDI events + audio routing
                        ▼
                   EXTERNAL / ENGINE
```

Only two conceptual levels:

- **The song** = the ordered phrase list. Playhead steps top-to-bottom. No phrase-refs, no repeat-count sugar, no conditionals.
- **The phrase** = one row of the grid, containing cells for every (track, layer). At tick-time, cells expand to per-step streams that feed the pipeline's blocks.

### Phrase layer (macro coordinator via layers)

Each phrase, during its N-bar lifetime, evaluates every `(track, layer)` cell and emits the corresponding per-step stream. The macro coordinator's job is no longer "author abstract rows as phrase-wide streams"; it's "evaluate this phrase's cells and fan them out to the right targets."

**Clock output** (unchanged, read by every block):

- `absSongStep` — step index across the full phrase list
- `phraseStep` — step within the current phrase (0 .. N-1)
- `barInPhrase` — 0 .. phraseBarCount - 1
- `phraseIndex` — which phrase is playing (not `repeat-count` — phrases play once each in order)

**Layer evaluation** (the thing that replaces "abstract expression vector" + "concrete rows"):

For each active layer, for each track, the tick reads `phrase.cells[(trackID, layerID)]`:

- `.inheritDefault` → use `layer.defaults[trackID]`
- `.single(v)` → `v` for every step
- `.bars([v0, v1, …])` → step function, each `v_i` held for one bar
- `.steps([v0, v1, …])` → per-step values; array length must match `phrase.stepCount`
- `.curve(controlPoints)` → sampled at each step

The resulting per-step value is then routed by the layer's `target`:

- `target = .patternIndex` → the track's active pattern slot for that step. Cells of type `patternIndex` usually author a single value per phrase (one pattern for the whole phrase), but `.bars` or `.steps` subdivisions allow pattern-switching mid-phrase — the song/phrase grid thereby carries *intra-phrase* pattern variation without invoking phrase-ref overrides.
- `target = .macroRow(rowName)` → writes to a named macro row that blocks read via the `interpret` transform. This is the bridge to the spec's existing macro-interpret machinery: the `intensity`, `density`, `tension`, etc. rows become `Layer`s targeting `.macroRow("intensity")`, `.macroRow("density")`, and so on.
- `target = .blockParam(blockID, paramKey)` → writes directly into a block param (equivalent to a per-step param-lock originating from the phrase grid).
- `target = .voiceRouteOverride(tag)` → per-phrase override of the drum voice-route destination for a named tag.
- `target = .mute` → phrase-scoped per-track mute.

Chord-context broadcast (root / chord-type / scale) stays a pipeline-emitted stream from a `chord-generator`-sourced track, not a layer. The `chord-generator`'s params can themselves be driven by layers (a `Tension` layer targeting `.blockParam(chordGenID, "tensionBias")`).

### Default layers shipped with a new project

| Layer name   | Value type       | Target                          | Notes |
|--------------|------------------|---------------------------------|-------|
| `Pattern`    | `patternIndex`   | `.patternIndex`                 | Defaults to 0 per track. The "what plays" layer |
| `Mute`       | `boolean`        | `.mute`                         | Defaults to `false` per track |
| `Volume`     | `scalar(0..127)` | `.macroRow("volume")`           | Defaults set per track; consumed by a track-level gain block or passed to audio-side when the audio engine lands |
| `Transpose`  | `scalar(-24..24)`| `.macroRow("transpose")`        | Semitones |
| `Intensity`  | `scalar(0..1)`   | `.macroRow("intensity")`        | Abstract row — per-track interpretation as before |
| `Density`    | `scalar(0..1)`   | `.macroRow("density")`          | |
| `Tension`    | `scalar(0..1)`   | `.macroRow("tension")`          | |
| `Register`   | `scalar(0..1)`   | `.macroRow("register")`         | |
| `Variance`   | `scalar(0..1)`   | `.macroRow("variance")`         | |
| `Brightness` | `scalar(0..1)`   | `.macroRow("brightness")`       | |
| `FillFlag`   | `boolean`        | `.macroRow("fill-flag")`        | Boolean per phrase; drives fill-aware blocks |
| `Swing`      | `scalar(0..1)`   | `.macroRow("swing-amount")`     | Timing jitter input |

Users add custom layers via the "+" button in the layer selector. The project's `layers: [Layer]` list is the authoritative set.

### Per-track interpretation (unchanged)

Blocks downstream of the macro-row streams continue to interpret them per track. A `monoMelodic` track's `interpret(row: "intensity", target: note-generator.density-bias)` says "intensity = velocity + a little density on this voice"; a drum track's interpret can say "intensity = hat density + snare ghost probability". The layer → macro-row mechanism just changes how the rows are authored and stored; the `interpret` transform downstream is identical.

### Pipeline layer

Every working component in the system is a block in a phrase-scoped DAG. Three kinds:

- **Sources** — emit streams: `note-generator`, `clip-reader`, `chord-generator`, `euclidean-drum-gen`, `template-clip`, `authored-row`, `saw-ramp`, `midi-in`
- **Transforms** — read ≥1 stream, emit ≥1 stream: `force-to-scale`, `quantise-to-chord`, `randomise(±N)`, `accumulate`, `grab-from(track)`, `transpose-by-stream`, `note-repeat`, `step-order`, `interpret(abstract-row → local-param)`, `voice-split`, `voice-merge`, `density-gate`, `tap-prev(stream)`
- **Sinks** — terminate streams outside the DAG: `midi-out`, `chord-context`, `macro-row[name]`, `audio-param[bus,param]`, `voice-route`, `trigger[fill]`

Cycles are forbidden at authoring time. Legitimate "read last tick" cases use the explicit `tap-prev` block.

## Streams (typed)

Connections between blocks are typed. The allowed stream types:

- `note-stream` — `{ pitch, velocity, length, gate, voice-tag? }` per step
- `scalar-stream` — continuous 0–1 (abstract rows, CC values, automation)
- `chord-stream` — `{ root, chord-type, scale }` per bar (or per step, for rapid modulations)
- `event-stream` — discrete triggers (fill-flag, bar-tick)
- `gate-stream` — boolean on/off per step
- `step-index-stream` — integer step selector (the output of step-order blocks)

Connections are type-checked at graph authoring time.

## The macro coordinator as information substrate

Every block receives the macro coordinator's tick, exposing:

- Clock counters (`absSongStep`, `phraseStep`, `barInPhrase`, `phraseIndex`)
- Current **macro-row values** (snapshot at this step) — these are the per-step values produced by evaluating the current phrase's cells in all layers whose `target` is `.macroRow(rowName)`. A layer called "Intensity" with target `.macroRow("intensity")` populates the `intensity` row at each tick from its cell value (single / bars / steps / curve). Blocks read these named rows via the `interpret` transform.
- Subscribed upstream streams

Blocks do not reach "around" the macro coordinator; all musical state comes through it. This makes phrase behavior fully inspectable and freeze-able.

## Per-track interpretation

A track's generator has its own **local params** (step pulse count, interval-bias vector, octave-range, play-mode...). Abstract rows reach these params via **interpret** transform blocks, each of shape:

```
interpret(row: abstract-row, param: local-param, curve, weight, baseline)
```

Example pipeline for a bass track:

```
macro.intensity ─┐
macro.register  ─┼─▶ [interpret × 4] ─▶ local-params ─┐
macro.tension   ─┤                                     │
macro.variance  ─┘                                     ▼
chord-context   ──────────────▶ [quantise-to-chord] ──▶ note-gen ──▶ midi-out
```

Different tracks with the same generator type use different interpretation-block configurations, so the same `intensity` sweep produces a register drop on a bass and an ornament increase on a lead. Interpretation configs are savable as **voice presets** shipped in a library: `bass-default`, `lead-default`, `pad-default`, `drum-default`.

## Chord as a first-class pipeline

No "chord row" special case. A chord generator is a pipeline:

- Source: `chord-generator` (or `authored-chord-row`, or `midi-in` as live chord input)
- Reads: macro clock, abstract vector (tension → dissonance bias, register → progression root bias)
- Sink: `chord-context`

Every pitch-emitting pipeline downstream may subscribe to `chord-context` and declare its consumption mode: `ignore` | `scale-root` | `chord-pool` | `transpose`. A drum pipeline ignores; a bass uses `scale-root`; a pad uses `chord-pool`.

Swapping a generated chord progression for an authored one is replacing the source block; downstream sees the same `chord-stream`.

## Drum tracks

Drums are one pipeline whose source emits a **tagged note-stream** and whose sink is a **voice-route**:

```
[template-clip(tagged)] ─▶ [note-repeat(tags=[hat])] ─▶ [voice-route] ─┬─▶ midi-out ch1 (kick)
                                                                       ├─▶ midi-out ch2 (snare)
                                                                       └─▶ audio-bus-alt (hat)
```

### Three independent concerns

| Concern | Mechanism |
|---|---|
| Rhythmic material | Template-clip or drum-generator emitting tagged notes |
| Voice identity | The `voice-tag` on each note — abstract labels, not MIDI numbers or sample names |
| Sonic realization | The `voice-route` sink's tag-to-destination mapping |

Swap one without touching the others.

### Templates

A drum template is a named tagged-note clip in a library — grouped by genre (`house-basic`, `dnb-breakbeat`, `techno-tuff`, `half-time-trap`). Ships with voice tags populated and **step annotations** baked in (see next section) so "techno kick" carries its own 20% off-beat probability built in — that's the template's character. Applying a template writes its tagged clip into a track's source; the existing `voice-route` mapping is preserved.

### Transforms can filter by tag

`note-repeat(tags=[hat])` — ratchet hats only. `density-gate(tags=[kick, snare])` — thin kicks and snares with the density macro; hats stay dense. Unfiltered = applies to all tags. Power users can `voice-split → [transforms per sub-stream] → voice-merge` for fully independent per-voice transforms.

### UI render

The drum clip editor shows N rows (one per distinct tag in use), Cirklon-CK-drum-grid style. The mixer shows one channel strip per unique `voice-route` destination. Single authoring surface, per-voice sonic treatment.

## Sliced-loop tracks

A sliced-loop track loads one audio file, slices it, and plays slices on sequencer steps. **Shape is identical to a drum track** — slices are voice-tags, the same `voice-route` sink hands each slice to its own bus, and every macro-controllable transform applies unchanged.

### Pipeline

```
[slice-clip] ─▶ [step-order(preset)] ─▶ [note-repeat(tags=[hat])]
             ─▶ [voice-route] ──┬─▶ bus-sub  (slice-player, "kick")
                                ├─▶ bus-mid  (slice-player, "snare")
                                └─▶ bus-hi   (slice-player, "hat")
```

The slice-clip emits a tagged `note-stream` where `voice-tag` identifies the slice, `velocity` is slice gain, and `length` optionally clamps playback. Everything downstream is shared with drum tracks.

### Slicing (analysis-time)

Runs at sample load, not realtime. Three modes: **transient** (onset detection, default for breaks), **grid** (N equal divisions, tempo-aware), **manual** (user drags boundaries). Optional **auto-labeling** via spectral-centroid + envelope analysis tags slices as `kick` / `snare` / `hat` / `perc` / `other` (post-MVP; when absent, slices ship as `slice-1..N` and the user renames).

A slice set is `[{ index, start, end, peak-rms, suggested-tag? }]`, stored alongside the sample reference.

### Per-slice settings

Per slice (stored in the sample-track config, not in clips):

- `start`, `end`
- `pitch-offset` (semitones, default 0)
- `reverse` (boolean)
- `envelope` (attack, hold, release)
- `gain` (dB)
- `tag` (user-editable label; default auto)
- `route-override?` (optional per-slice bus; otherwise inherited from the voice-route entry for this tag)

### Macro interactions (free from existing blocks)

- `step-order` reorders slice triggers — retrograde plays the break backwards; `seeded-shuffle` scrambles repeatably. This is the "respond to fills with reordering" case directly.
- `note-repeat(tags=[hat])` — classic break hat-ratchet.
- `density-gate(tags=[kick])` — thin the kick with the density macro while hats stay dense.
- `voice-route` routes `kick` slices to a sub-bus, `hat` slices to a hi-pass bus — the "kick and hats in a break to different busses" use case.

Fill presets apply identically: `drop = { order-preset: retrograde, repeat-active: on }` scrambles and ratchets a break by reusing the same macro machinery every other track uses.

### Added sources

- `slice-clip(sample-ref, slice-set-ref)` — stored sliced-loop pattern; step annotations apply (play-prob, pitch-jitter, etc.)
- `slice-generator(sample-ref, slice-set-ref, strategy)` — emits slice triggers from a generator (euclidean-over-tags, Markov-over-tag-transitions, random-from-pool)

### UX

Load sample → auto-slice → waveform editor with boundaries, per-slice envelope/pitch/reverse/tag. Clip editor shows one row per distinct tag (same as drum grid). Dropping notes on grid = trigger that slice on that step.

### MVP sequencing

Sliced-loop tracks need a working audio engine (sample playback, buses, FX chain), which the audio-side section flags as post-MVP. The data model is part of the north star; implementation sits alongside the audio engine phase. MVP ships without sampled tracks; the shape is committed so they drop in cleanly later.

## Generative ↔ Stamped continuum

Not a modal choice. Four typical points on the continuum, all the same pipeline shape:

| Workflow | Source | Transforms | Character |
|---|---|---|---|
| Pure generative | `note-generator` | macro-driven `interpret`s | Every loop different |
| Stamped + variation | `clip-reader` | (annotations do the work) | Same clip; varies via `play-prob` + jitter |
| Stamped frozen | `clip-reader` | (no jitter) | Deterministic replay |
| Hybrid | `voice-merge(clip-reader, note-generator)` | — | Committed parts + generated parts |

Moving a track from generative to stamped is: freeze the live output into a clip (glaypen sliding-window capture), swap `note-generator` for `clip-reader` in the pipeline, optionally annotate.

## Step annotations and parameter locks (first-class clip data)

A stored clip's step is:

```
{ step, pitch, velocity, length, gate, voice-tag?,
  play-prob?,       // 0–1; per-play gate mask
  conditional?,     // 1ST | PRE | NEI | A:B cycle | X%
  vel-jitter?,      // ±N
  pitch-jitter?,    // ±N semitones (post-FTS)
  timing-jitter?,   // micro-timing ± fraction-of-step
  locks?: { "block-id.param-name" → value }  // Elektron-style p-locks
}
```

Ratcheting is per-step-locked via `locks["note-repeat.gate-prob"]` — no separate annotation field. Consolidates all per-step mechanism into the locks map.

All fields optional. Unset = deterministic, no overrides. The `clip-reader` source honors them natively.

### Parameter locks (Elektron-style)

The `locks` map generalizes Elektron p-locks: **any block param marked lockable can be overridden per step**. At clip-read time, for this step, the pipeline executor pushes locked values onto referenced blocks for this tick only. Unset → block uses its authored default.

Subsumes Cirklon's per-step CC / aux values and Octatrack's sample locks (`voice-route.tag → "different-slice"` is a lock on the voice-route's routing for that step). Lockable params are declared by the block author; defaults include source generator's pitch bias, interpretation-map weights, note-repeat count/shape, step-order preset, voice-route destinations, filter cutoff (audio-side), envelope parameters.

Annotations may also be **stream-driven** rather than static: `play-prob` can bind to a scalar-stream so the phrase's `density` macro row lowers every clip's gate probability during a breakdown. This is how the abstract macro vector reaches even stamped material. Locks can likewise be bound to streams — a per-step "lock value" that itself varies per play.

## Fills

Two mechanisms, equal footing:

### Dedicated phrase rows (pre-programmed)

A fill is just another phrase in the list. If you want a fill every 8 bars in an 8-bar song, insert a fill phrase after every 8 regular phrases — or, more compactly, have a short 1-bar fill phrase inserted once. Because phrases share pool entries (patterns, generators, clips) for the tracks that are the same as the surrounding phrases, the fill phrase only differs in whichever cells are overridden (e.g. a different pattern index on the snare, higher intensity on the hats). Editing the surrounding phrases doesn't disturb the fill and vice versa.

There is no longer a separate "phrase variant" concept — variants were a way of expressing "mostly phrase A, slightly different"; in the layer/cell model, overrides are the cell-level delta from defaults, so each phrase is already just its deltas.

### Fill presets (performance, or scheduled)

A named **static** overlay of macro-row value adjustments — applied instantaneously when activated:

```
FillPreset "breakdown" = { intensity: 0.2, density: 0.2, register: 0.3,
                           order-preset: reverse, repeat-active: off }
FillPreset "drop"      = { intensity: 1.0, tension: 0.7, fill-flag: on,
                           crossfader: 1.0 }
```

Because fills are in abstract space, each track's pipeline responds in character via its own interpretation map. Applied live (hold / latch) or scheduled in the song at a step.

### Takes (captured time-varying macros)

The time-varying counterpart to a fill preset. A **Take** is a recorded N-bar sequence of every macro-row change, fill-preset activation, XY-pad move, and punch-in toggle during a capture window — replayable anywhere, on any phrase, at any time.

**Capture flow:** In Perform view, press **Capture** → dialog asks how many bars (4/8/16/custom) → app arms, next N bars are recorded → saved to library as `take-NN` with auto-name (renameable in Library view).

**Playback:** Triggered from the Perform pad grid (momentary / latched / one-shot), or attached to a specific phrase row in the song so the take auto-plays when that phrase begins (Octatrack-arranger-style row action, now realised as a per-phrase attachment rather than a phrase-ref override).

**Composition mode (per Take):**
- **Relative (default)** — values stored as offsets from the baseline captured context; replaying applies those offsets to whatever the current phrase has. A Take that spiked `intensity` 0.5 → 0.7 reads as `+0.2 peak` and produces a spike to 0.5 when run on a phrase at baseline 0.3. Preserves shape across contexts.
- **Absolute** — stored values replace the phrase's authored rows during replay. Used when absolute levels matter (e.g. "bring everything to zero" drop).

Takes are reusable across phrases (not locked to the capture phrase), composable (two Takes can layer, one modulating `intensity`, another modulating `tension`), and persist in the library alongside templates and fill presets. Phrase variants remain as hand-authored alt-phrases; Takes are the flow-preserving capture unit.

## Audio-side (sketch; out of MVP)

- Per track: `bus` enum (`main` / `alt`). Each bus has its own FX chain.
- **Crossfader** — per-track or global 0–1 value, morphing between two snapshots of (bus sends + FX params). Direct lift of Octatrack scenes + crossfader.
- Crossfader position is a macro row (`crossfader`) — so "intro → drop" can be pre-programmed as an automation, not just a live gesture.
- Mixer strip per unique sink destination; `voice-route` sinks produce multiple strips per drum track.

MVP ships audio as single-bus pass-through; the alt-bus and crossfader are an architecture-level reservation.

## UX surfaces

Main window is a custom studio shell: persistent top chrome and a lower context workspace that swaps wholesale by mode/selection. Perform mode is an overlay, not a separate route.

### Always visible

- **Studio chrome** (top) — project title, transport, main mode buttons (Song / Phrase / Track / Mixer / Perform / Library / Preferences), engine state, and compact status pills. This should feel like instrument chrome, not a document-app toolbar.
- **Contextual track selection** — track picking lives inside the active workspace where it adds the most value (the phrase matrix header, a dedicated track matrix, or the Mixer strips), rather than in a permanently duplicated shell strip.
- **Context workspace** (lower body) — the entire lower surface changes with the active mode. This is the main canvas, not a sidebar/detail layout.
- **Inspector details** (embedded or floating) — selection-specific controls live inside the active workspace or in a lightweight floating inspector, not as a permanent macOS form rail.

### Main content views

| View | Controls |
|---|---|
| **Song** | Ordered phrase list. Rows = phrases in playback order; controls = add / duplicate / reorder / remove / attach fills or takes. There is no separate phrase-ref wrapper; repeating something means inserting the phrase again. Timeline and playhead still sit here. |
| **Phrase (phatcontroller macro grid)** | Phrase rows form the left rail and the track cells fill the main grid; the matrix itself carries the track header/selection affordance. One selected **layer** is shown at a time. Default layers: Pattern, Mute, Volume, Transpose, Intensity, Density, Tension, Register, Variance, Brightness, FillFlag, Swing, plus user-added layers. Cell previews and editing modes are type-driven: booleans get `Single` / `Bars` toggles; indexed layers like Pattern get slot-selection `Single` / `Bars`; scalar layers get `Single`, `Bars`, per-step drawing, and curve/ramp editors. Chord-context displays as named harmonic states by bar rather than a raw scalar. |
| **Tracks** | Flat, group-aware track matrix. Cards show track identity and type; grouped drum-kit members share tint and group labelling. Commands: add mono track, add poly track, add slice track, add drum kit, duplicate, delete, and later move between groups. |
| **Track** | Split workspace: **source editor on the left, destination editor on the right**. The left side chooses and edits the phrase-scoped note source for the selected track type; the right side owns sound/routing identity. Mono/poly melodic tracks show generator / clip / MIDI-in source homes; slice tracks show slice-trigger and waveform-oriented source tooling. Drum kits are represented as grouped mono tracks rather than a special track type. "Show wiring" reveals the deeper DAG for power users. Commands: freeze, stamp, clear. |
| **Chord generator** | Source-type toggle (generator / authored / midi-in). If generator: chord pool, scale, progression strategy, interpretation map (tension → dissonance, register → progression-root-bias). If authored: per-bar progression editor (degrees or chord names, optional inversions). Consumption matrix showing which tracks subscribe and in what mode (ignore / scale-root / chord-pool / transpose). Local transport. |
| **Mixer** | Per-track channel strips (vol / pan / mute / solo), bus assignment (main / alt), send-A and send-B, crossfader, per-bus FX chain slots, VU meters, master bus. Drum tracks expose one strip per `voice-route` destination (so a drum track with kick-to-subBus, snare-to-mid, hat-to-hi shows three strips). |
| **Live** | Performance matrix over the current phrase/layer state. It follows the flat track list, can optionally collapse `TrackGroup`s into aggregate cells, and edits cells using the same type-driven rules as the Phrase view: toggles for booleans, indexed slot pickers for Pattern, scalar drags / bar editors / ramps for continuous layers. Song/Free transport mode lives in the transport chrome, not inside this view. |
| **Perform** (overlay) | Fill-preset pad grid (momentary / latched), separate Take pad grid (triggers captured macros with momentary / latched / one-shot), XY pad for continuous abstract-vector control (X = intensity, Y = tension by default; configurable), Polyend-Play-style punch-in effects (repeat / reverse / loop / step-shuffle), per-track select pads for fill targeting, **Capture** button → prompts bar-count → records next N bars as a new Take. Floats over any content view. |
| **Library** | Browser of library assets: voice presets, drum templates, fill presets, **Takes**, chord-gen presets, sample slice sets, saved phrases. Preview, tag / search, drag-drop into tracks / pad grids. Source flag (bundled vs user). Import / export for sharing across projects. |
| **Clip editor** (Elektron-style step sequencer for instrument tracks) | 16-cell step grid per bar (pages for longer clips); cell state shows trig / p-lock / conditional / probability / slide / ratchet. Click toggles trig; hold a step + twist any knob in the Track destination panel or floating inspector → records a **parameter lock** on that step instead of changing baseline (classic Elektron gesture). Inspector "Locks" section lists active locks per step with remove buttons. Sub-grids below show velocity / length / delay / micro-timing as mini bar graphs (Cirklon row-view style). Conditional selector per step. For drum / sample-tagged clips the layout switches to tagged rows × steps. |
| **Graph** (power-user, optional) | Full pipeline DAG for the current phrase. Drag-wire blocks, block palette sidebar, inspector for selected block. Hidden by default; accessible via a "show wiring" toggle in Track view or as a standalone view for deep editing. |
| **Preferences** | MIDI devices & virtual endpoints, clock master/slave, audio device & latency, AU scan + whitelist, default phrase length + time signature, appearance, keyboard shortcuts. |

### View shape-shifting based on selection

Several views are specializations rather than alternatives:

- Selecting a track routes the workspace into that track type's editor shape — monoMelodic / polyMelodic tracks open **Track view**, drum tracks open **Drum view**, sliced-loop tracks open **Sample view**, and a chord-gen pseudo-track opens **Chord generator view**.
- The **destination/sound half** of the workspace similarly shape-shifts per track type (MIDI destination vs AU embed vs tag-to-route assignment); it is part of the track-type editor, not a separate first-class mode.
- **Clip editor** can appear inline inside Track/Drum/Sample view or be pinned as its own view for heavy editing sessions.

### Navigation feel

- Opening a project drops into Song view
- One-click from Song to any Phrase → opens Phrase view with that phrase active
- Clicking a track row in Phrase view (or a track card in the Tracks matrix) opens its Track/Drum/Sample view
- Clicking the chord-context row in Phrase view opens Chord generator view
- Perform and Mixer are global: same state regardless of which phrase or track is active
- Library is a drawer that can overlay any view (drag-drop target)

## Workflow (acid test)

The design's validation: this user story should feel natural.

1. **Start fast.** User adds 6 tracks; each gets a default voice preset (bass, lead, pad, kick, snare, hat), a default generator instance seeded in pattern slot 0 of its pattern bank, and a default cell of `.inheritDefault` on every layer. Chord-gen runs with a default progression. Hit play; immediately hear a coherent groove.
2. **Shape the voices.** Per track, tweak local params (pitch range, preferred intervals) or swap voice preset.
3. **Phrase the arrangement.** Open the phrase grid. In the Intensity layer, draw an 8-bar ramp on the bass cell. In the Tension layer, set a `.bars` cell on the pad with a bump at bar 6. The chord-gen's output responds; bass register drops; lead pushes dissonance; snare density increases. One authoring gesture → every voice responds in-character.
4. **Stamp what works.** On the bass, hit freeze. A clip is captured from the last 16 steps and appended to `clipPool`. The bass track's pattern slot 0 is rewired from `.generator(id)` to `.clip(newClipID)`. Optionally populate step annotations (jitter velocity ±5, 80% play-prob on off-beats).
5. **Sweep.** Add a new phrase row to the list — call it `fill`. In its Pattern layer, set a different pattern index on the snare and hats. In the Intensity layer, set `.single(1.0)`. Insert the `fill` row after every 8 regular phrase rows to get a regular fill.
6. **Perform.** Live, hold a `breakdown` fill preset over bars 14–16. Sounds right because abstract. Captured into a take if wanted; attached to a phrase row so it auto-replays there.

## Components inventory (block palette sketch)

This section lists **generator kinds** (code-defined, registered in the block palette). User-configured **generator instances** of these kinds live in the project's generator pool (see §"Track types, patterns, and phrases" → "Project-scoped pools"). Each kind declares which track types it's compatible with; the UI filters the source picker by those declarations.

### Generated source pipeline — `trigger → pitch → note shape`

Most generated sources are now expressed as a fixed-slot pipeline:

- **Trigger stage** — evaluates a `StepAlgo` and emits note seeds at a configured base pitch (default middle C).
- **Pitch stage** — consumes the primary note-seed stream, optionally reads named sidechains, and expands or transforms those seeds into actual note output.
- **NoteShape** — supplies shared per-note values such as velocity and gate length.

This keeps the glaypen / sequencerbox split, but changes the semantics slightly: `StepAlgo` is trigger generation; `PitchAlgo` is pitch expansion / transformation. Future AU MIDI processors plug into these stage slots rather than introducing a parallel "MIDI processor kind" subsystem.

Mono generators use one trigger stage and one pitch stage. Poly generators use one trigger stage shared across multiple pitch lanes. Slice generators use one trigger stage plus slice indexes instead of pitch stages. Drum voices remain ordinary `monoMelodic` tracks — typically a mono generator whose pitch stage always resolves to a constant note number.

#### StepAlgo variants

Shared across mono / poly / slice generated-source kinds.

| Variant | Params | Notes |
|---|---|---|
| `manual` | `pattern: [Bool]` (length = pattern step count) | User-drawn step mask. Matches the classic step-sequencer UX |
| `randomWeighted` | `density: Double (0..1)` | N random positions per pattern where N = density × stepCount. Stable across ticks within a pattern unless re-rolled |
| `euclidean` | `pulses: Int`, `steps: Int`, `offset: Int` | Bjorklund distribution — hats, house-music snare patterns etc. |
| `perStepProbability` | `probs: [Double]` (length = stepCount) | HotStepper-style per-step probability bars. Re-rolls every loop |
| `fromClipSteps` | `clipID: ClipID` | Use an existing clip's step mask as the trigger source. Allows layering rhythm from one clip with pitch expansion from another stage |

#### PitchAlgo variants

Used by pitched stages (mono, poly). A pitch stage consumes one primary note-seed stream plus zero or more named sidechains. V1 ships one sidechain input: `harmonicSidechain` (`none` / `projectChordContext` / `clip(ClipID)`). Slice generators use `[SliceIndex]` instead of pitch stages.

| Variant | Params | Notes |
|---|---|---|
| `manual` | `pitches: [Int]`, `pickMode: .sequential | .random` | Replace each incoming seed pitch with a value from the configured pool |
| `randomInScale` | `root: Int`, `scale: ScaleID`, `spread: Int` (semitones) | Expand each incoming seed into one scale-constrained output pitch. "Fully random" = `scale = .chromatic, spread = 24` |
| `randomInChord` | `root: Int`, `chord: ChordID`, `inverted: Bool`, `spread: Int` | Expand against a chord pool. If `harmonicSidechain = projectChordContext` or `clip(...)`, the sidechain replaces the local chord source |
| `intervalProb` | `root: Int`, `scale: ScaleID`, `degreeWeights: [Double]` (one weight per scale degree) | Choose an interval relative to the current input seed and weighted degree table |
| `markov` | `root: Int`, `scale: ScaleID`, `styleID: StyleProfileID`, `leap: 0..1`, `color: 0..1` | History-aware pitch transformation. `styleID` picks a pre-baked weight profile (`vocal` / `balanced` / `jazz` / …); `leap` and `color` are macro-controllable overlays |
| `fromClipPitches` | `clipID: ClipID`, `pickMode: .sequential | .random` | Use a clip-derived pitch pool as the pitch source |
| `external` | `port: String`, `channel: Int`, `holdMode: .pool | .latest` | Incoming MIDI fills a pitch pool. In v1 this remains an explicit stub until external pitch capture lands |

**Mapping to the user's examples:**

| "..." | Trigger stage | Pitch stage |
|---|---|---|
| Fully random | `randomWeighted(0.5)` | `randomInScale(root, .chromatic, spread: 24)` |
| Within an octave | `randomWeighted(0.5)` | `randomInScale(root, .major, spread: 12)` |
| In a chord | any | `randomInChord(root, chord)` |
| In relation to preceding notes | any | `markov(root, scale, styleID: .balanced)` |
| Clip rhythm + random scale pitches | `fromClipSteps(clipID)` | `randomInScale(…)` |

#### Static code tables (not library-scoped)

The following reference data is **shipped with the binary as static tables** (project-agnostic, read-only, versioned with the code). Not in `~/Library/Application Support/sequencer-ai/library/` — that folder is for user-saved things (voice presets, templates, takes, clips).

- **`ScaleID`** — 19 scales lifted from glaypen: chromatic, major, natural minor, harmonic minor, melodic minor, major pentatonic, minor pentatonic, blues, dorian, mixolydian, lydian, phrygian, locrian, whole-tone, diminished, augmented, gypsy, hungarian-minor, akebono / japanese / hirajoshi / in-sen / iwato / kumoi / pelog (the non-Western scales live behind a "More scales" reveal in the picker).
- **`ChordID`** — 16 chords lifted from sequencerbox: major-triad, minor-triad, augmented-triad, diminished-triad, major-7th, minor-7th, dominant-7th, diminished-7th, augmented-7th, half-diminished-7th, major-6th, minor-6th, major-9th, minor-9th, major-11th, minor-11th.
- **`StyleProfileID`** — 3 profiles lifted from HotStepper: `vocal` (narrow intervals, strong repeat bias, descending tilt), `balanced` (all-rounder), `jazz` (wider intervals, higher leap tolerance, more color tones). Each profile carries `ascendBias`, `descendBias`, `repeatBias`, `leapPenalty`, `reversalTrigger` and related weights. Encoded as a static struct in `Sources/Musical/StyleProfiles.swift`.

Code location: `Sources/Musical/{Scales,Chords,StyleProfiles}.swift`. One source of truth; never duplicated into JSON. When we add scales or chords, they are code changes, versioned, type-safe.

### Generator kinds — the actual list

| Kind | Composition | Compatible track types | Notes |
|---|---|---|---|
| `mono-generator` | `TriggerStage × PitchStage × NoteShape` | `monoMelodic` | The workhorse. Covers classic step-seq (manual trigger × manual pitch), scale walks, clip-fed rhythm with generated pitch expansion, markov lines, and constant-pitch drum voices |
| `poly-generator` | `TriggerStage × [PitchStage] × NoteShape` | `polyMelodic` | One shared trigger stage fans into multiple pitch lanes. A "chord-generator" is a `poly-generator` instance with trigger = `manual([true])` and one or more chord-aware pitch stages |
| `slice-generator` | `TriggerStage × [SliceIndex]` — **deferred** to sub-spec 11 | `slice` | Slice infra is its own spec; the trigger-stage slot is reserved now so future MIDI/AU stage replacements fit the same shape |

**Why the shrink:** the previous inventory enumerated "random-notes-in-scale-mono", "markov-note-chain", "chord-generator", "euclidean-drum-gen" as distinct kinds. These are now *instances* of `mono-generator` or `poly-generator` with specific stage choices. The inventory is shorter; the user's vocabulary stays rich because named *presets* of those kinds ship in the library (`bass-random-pentatonic`, `lead-jazz-markov`, `kick-euclidean-4`, …).

**Time-varying generator params:** any generator-instance param (density, spread, degreeWeights, leap, color, …) can be driven by a Layer with target `.blockParam(generatorInstanceID, paramKey)`. The layer's cell supplies the per-step value. This is the glaypen "param history indexed by step" capability, realised through the phrase grid instead of a separate automation lane — author the curve once on a phrase's layer cell, and it runs every time that phrase plays.

### Sources — clip mode

A track's pattern-slot source can also be `.clip(ClipID)`, which reads from the project's clip pool. Clips are tagged with track-type compatibility at creation; the picker filters the same way as for generators. There is no separate `clip-reader` *kind* in the inventory — clip mode is its own direct source branch, distinct from the generated-source pipeline. The `fromClipSteps` / `fromClipPitches` stage variants above let a *generated source* reference a clip as raw input material, distinct from playing that clip directly.

**Transforms:**
- `force-to-scale(scale, root)` — scene-level pitch correction
- `quantise-to-chord(mode: scale-root|chord-pool|transpose|ignore)` — consumes `chord-stream`
- `randomise(pitch=±N, vel=±M, timing=±T)` — global or tag-filtered
- `accumulate(+N per bar|step|repeat)` — Cirklon-style
- `grab-from(track, field)` — Cirklon inter-track
- `transpose-by-stream(scalar-stream)` — continuous transpose
- `note-repeat(count, shape, velocity-shape, gate)` — ratchet
- `step-order(preset | user-perm)` — deterministic playhead reorder
- `interpret(abstract-row → local-param, curve, weight, baseline)` — the interpretation primitive
- `voice-split / voice-merge` — per-tag stream manipulation
- `density-gate(threshold-stream, tag-filter?)` — probabilistic gate
- `tap-prev(stream)` — one-tick-delayed read for legitimate feedback-like patterns

**Sinks:**
- `midi-out(port, channel, note-offset?)`
- `chord-context` (broadcast; single per phrase; consumed by `quantise-to-chord`)
- `macro-row[name]` — writes to an abstract row
- `audio-param[bus, param]` — writes to a mixer/FX parameter
- `voice-route(tag → destination map)` — drum sink
- `trigger[fill-flag | ...]` — event-stream terminators

## State, persistence, freeze

- All project track identities/types, phrase pipeline configurations, clip data (with annotations), voice-route maps, song structure, and macro grids live in a **project document** — a `.seqai` file (Codable, JSON internally for diff-friendliness; may compact to binary later if size matters).
- **Templates, voice presets, fill presets, chord-gen presets, slice-set analyses** are **library-scoped** (project-agnostic) — saved to `~/Library/Application Support/sequencer-ai/library/` as individual files, shareable by copying.
- Autosave on edit; document dirty-flag at the project scope; project-level undo/redo stack.
- **Freezing** captures a live generator's output across a window into a new clip. The pipeline is reconfigured in place: source block swapped from the generator to a `clip-reader` pointing at the new clip. Generator config preserved (re-swappable).

## Explicitly out of scope for MVP

- Audio sampling / playback engine (sliced-loop tracks, bus FX, crossfader) — sketched and architecturally reserved, implemented in a later phase
- **AUv3 plugin hosting** — architecturally reserved; implemented in the audio-engine phase
- MIDI note input beyond live chord-feed and manual-pitch-options capture
- Per-track CV/gate output
- External sync as master (slave to incoming MIDI clock is in scope)
- `.mid` or other sequence export
- iPadOS port

## Decomposition for implementation

Likely sub-specs, ordered for MVP:

0. **App scaffold** — Xcode project, Swift package layout, SwiftUI app shell, document-based architecture, `~/Library/Application Support/sequencer-ai/` bootstrap, CoreMIDI device discovery + virtual endpoints
1. **Core engine** — Swift tick loop driven from the audio render clock, pipeline DAG executor, block registry, typed streams, lock-free UI↔render command queue, basic block set (note-gen, clip-reader, force-to-scale, quantise-to-chord, interpret, midi-out)
2. **Macro coordinator and phrase model** — project-scoped layers, per-(phrase, track, layer) cells, type-driven cell editors
3. **Song model** — ordered `phrases: [Phrase]` list, song-clock + transport driving top-to-bottom playback, phrase-insertion / reorder / duplicate UX
4. **Chord layer** — chord-generator, chord-context plumbing, consumption modes
5. **Tracks + groups** — flat tracks, `TrackGroup`, drum-kit presets as grouped mono tracks, destination inheritance
6. **Step annotations** — clip-reader honors annotations, annotation editor UI
7. **Fills** — fill preset overlays (phrase-attached takes + live-triggered performance overlays). Pre-programmed fills are just additional phrase rows, already covered by the phrase-list model
8. **Perform layer** — live fill triggering, capture into variants
9. **Note-repeat & step-order blocks**
10. **Audio-side** — bus routing, crossfader, FX chain (probably split into its own spec)
11. **Sliced-loop tracks** — sample loading, slicing analysis, slice-clip/slice-generator sources, slice-player bus target (post audio-side)
12. **Freeze / stamp workflow** — sliding-window capture, in-place pipeline reconfiguration

Each gets its own implementation plan. This design document is the north star they all reference.

## Open questions

Known ambiguities deliberately left for the first implementation plan to resolve (noted so they're not forgotten):

- **(Resolved)** Phrase default length: 8 bars × 16 steps = 128 steps; per-phrase override available.
- **(Resolved)** Abstract macro row count: 6 — intensity, density, register, tension, variance, brightness. Energy merged into intensity (per-track interpretation maps decide whether intensity drives velocity, density, register, or a mix).
- **(Resolved)** Block graph authoring UX: preset-first by default; "Show wiring" toggle in Track view reveals the DAG inline; dedicated Graph view for heavier rewiring. Community can ship pipeline presets that use custom blocks.
- **(Resolved)** Library format & location: hybrid — bundled defaults read-only from app bundle; user content in `~/Library/Application Support/sequencer-ai/library/`; merged at runtime; Library view shows both with source flagged. JSON format throughout.
- **(Resolved)** Performance capture: not into phrase variants, but into **Takes** (reusable time-varying macros). Capture button prompts bar-count, records next N bars, saves to library with auto-name. Default relative composition (offsets from captured baseline); per-take absolute-lock toggle. Triggered from perform pad grid or scheduled in song.
- **(Resolved)** Cycle policy: cycles forbidden in the DAG; `tap-prev` provides the one-tick-delayed escape hatch for legitimate feedback-like cases. Validation runs **both at authoring time** (graph editor refuses offending connections) **and at runtime** (on phrase load, for defense against externally-edited files and library-import migrations).
- **(Resolved)** State lifetime for stateful blocks (accumulators, Markov chains, conditional counters, LFO phase, random seeds): configurable per block. Default = **persist within a phrase** but reset at phrase boundaries. Each stateful block exposes a lifetime setting (`reset-per-tick` / `reset-per-bar` / `reset-per-phrase-start` (default) / `reset-on-pattern-switch` / `persist-across-song`) for explicit overrides.
- **(Resolved)** AUv3 hosting: strictly out-of-process (Apple's AUv3 default; matches the [[phat]] app's own `.loadOutOfProcess`). State persisted via `AUAudioUnit.fullState` captured into the project document's Codable serialization. Standard macOS app-sandbox + AU entitlements. Implementation detail lives in the audio-engine sub-spec.
- **(Resolved)** Document model: classic macOS — one window per document, SwiftUI `DocumentGroup` / NSDocumentController. Enables side-by-side comparison and inter-project drag-drop without a custom tab bar.
- **(Resolved)** One song per `.seqai` document. Cross-song reuse via the library folder. Extension to multi-song-per-doc is a future option (wrap a list around the root song) if the need arises.
- **(Resolved)** Sliced-loop tempo behavior: configurable per slice-track. Default **resample** (pitch-shifts with tempo, MPC / Octatrack-Flex / sampler-tradition). Per-track alternatives: **time-stretch** (formant-preserving) for melodic loops, **lock-per-slice** (native-rate playback) for one-shots. MVP ships resample first; time-stretch lands in the sample-engine phase.
- **(Resolved)** Annotation × macro composition: **multiply**. A template annotation is attenuated by the macro at that step: `effective = annotation × macro`. Macro at 1.0 → template plays as authored; macro at 0 → silenced. Applies to play-prob, jitter amounts, ratchet-prob, and all scalar-stream-compatible annotations.
- **(Resolved)** Macro vs lock precedence: **lock wins**. A per-step parameter lock is absolute — it replaces whatever the macro would produce for that param at that step. Macros only modulate params that are not locked on the current step. Matches Elektron semantics.
- **(Resolved)** Macro-row source: strict one-or-other at the top-level UX surface — a row is either authored or generator-sourced. Layering is available via explicit `merge` transform block in the Graph view for power users, or by freezing a generator's output into authored values and then editing.
- **(Resolved)** Ratcheting: no separate `ratchet-prob` annotation. Per-step ratchet control is a p-lock on `note-repeat.gate-prob`, unifying the mechanism with all other per-step parameter overrides.
- **(Resolved)** Chord-context granularity: per-step stream in the data layer (no loss of resolution). Chord-gen output blocks default to "quantise to bar" — one chord per bar for the clean common case. Per-block toggle off quantise-to-bar for jazz-style mid-bar changes.
- **(Resolved)** Voice-route fan-out: yes. Each tag maps to a **list** of destinations; every destination receives the event. Drum view surfaces "+ destination" per tag for layering (kick → sub-bus + external-gate-trigger, etc.).
- **(Resolved)** Phrase variant storage: **full copy**. Variants are independent after creation; edits to the base do not ripple. Predictable, simpler data model. A linked-variant mode could be added later if the ripple workflow becomes wanted.
- **(Resolved)** BPM stacking: **project default + per-phrase BPM override layer, most-specific wins**. BPM becomes a layer (`target = .macroRow("bpm")` or a dedicated transport-side target) so a phrase can set its own tempo. Tempo ramps can be added later by setting a `.curve` cell on the BPM layer for a phrase.
- **(Resolved)** Lockable-param registry: each block declares its own `lockableParams: [...]` list. Core blocks (note-generator, note-repeat, step-order, quantise-to-chord, voice-route, interpret, force-to-scale, filter/envelope blocks) ship with curated lockable lists tuned to the musical use-cases. Custom blocks opt in explicitly. Unspecified → no lockable params.
- **(Resolved)** Note entry: four methods, all simultaneous — mouse-on-grid, computer-keyboard-as-piano (DAW standard), external MIDI input, on-screen View controller (Polyend-Play-style). All always available.
- **(Resolved)** Bundled content: curated starter kit targeting ~20 drum templates (Techno / House / DnB / HipHop / Jazz / Trap / Breakbeat / Exotic), 8 voice presets (Bass / Lead / Pad / Arp / Pluck / Sub / Noise / Drone), 6 fill presets (Drop / Build / Breakdown / Reverse / Half-time / Tension), 4 chord-gen presets (Pop / Jazz / Minor / Dark). Category list and approximate counts committed so Library view and pad grids are designed for the right volume. Actual content authored in a dedicated content sub-spec late in development.
