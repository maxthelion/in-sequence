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

- **Track** — one project-scoped musical lane with a stable identity, immutable **track type**, and a fixed 16-slot **pattern bank** feeding a destination.
- **Track type** — the top-level shape of a track (`instrument`, `drum`, `slice`, chord pseudo-track). Determines compatible generators, voicing behavior, and workspace shape.
- **Voicing** — how a track type realizes note material at the destination side: monophonic instrument voice, tagged drum voices, slice voices, or chord broadcast behavior.
- **Generator kind** — a reusable category of generator (`manual-mono`, `drum-pattern`, `slice-trigger`, etc.) used for compatibility filtering and UI affordances.
- **Generator instance** — one project-scoped entry in the generator pool, referenced by phrases through a source ref.
- **Generator** — a block that produces notes or values. Typically composed as step-gen × pitch-gen (following glaypen).
- **Clip pool** — the project-scoped set of reusable clip instances that phrases may point at.
- **Pattern** — one slot in a track's 16-slot pattern bank. Holds a **source mode** (`.generator(GeneratorID)` or `.clip(ClipID)`) plus an optional human-readable name.
- **Source mode** — the content of a pattern slot: `.generator(GeneratorID)` or `.clip(ClipID)` pointing into the project pools. Phrase never stores a source mode directly; it stores a pattern index, and the pattern carries the source mode.
- **Clip** — concrete, stored step data for a track. Optional per track; present when material has been frozen or hand-authored.
- **Phrase** — reusable, N-bar unit (default 8 bars × 16 steps = 128 steps). A row in the phatcontroller-style grid: stores a **cell per (track × layer)**, where a cell carries an authored value (`single`, `bars`, `steps`, or `curve`) or inherits the layer's per-track default. Phrase never carries source modes directly — the Pattern layer resolves to each track's pattern bank.
- **Song** — the ordered list `project.phrases: [Phrase]`, played top-to-bottom. Not a separate data structure and not a phrase-ref chain. To repeat something, list the same phrase twice. To make edits propagate, phrases reference shared pool entries through pattern banks.
- **Layer** — a project-scoped definition of what kind of per-track, per-phrase data lives in one column of the phrase grid. Each layer declares a value/editor type, a per-track default, and a runtime target (pattern index, mute, macro row, block param, voice-route override, etc.).
- **Cell** — the authored value at the intersection of a phrase, a track, and a layer. Tagged union:
  - `.inheritDefault`
  - `.single(Value)`
  - `.bars([Value])`
  - `.steps([Value])`
  - `.curve(ControlPoints)`
  Runtime expands every cell into a per-step value stream that blocks consume via `interpret`.
- **Stream** — a typed value flow through the system. Every output of every block is a stream.
- **Sink** — a block that terminates a stream outside the pipeline DAG: MIDI-out, audio-param, chord-context broadcast, macro-row writer.
- **Pipeline** — a directed path from source through transforms to sink within a phrase.
- **Voice tag** — an abstract label (`kick`, `snare`, `hat`, `clap`...) carried on note-stream entries for drum tracks; decouples rhythmic material from sonic realization.

## Scoping: project vs phrase

Following phatcontroller and Octatrack's part/pattern split: **tracks and shared pools are project-scoped, while phrases choose pattern indexes and layer-cell values**.

- **Project-scoped (stable across phrases):**
  - The set of tracks, their identities (kick, bass, lead, pad...), and their **track types**
  - Voice preset / voicing contract per track (interpretation map, local param baselines, default sound identity)
  - `voice-route` destination assignments (MIDI channel, bus, FX chain)
  - **Per-track pattern bank** — exactly 16 pattern slots per track, each holding a `SourceRef` (`.generator(id)` or `.clip(id)`) and an optional name
  - `generatorPool` — project-scoped generator instances, filtered by track type compatibility
  - `clipPool` — project-scoped clip instances, filtered by track type compatibility
  - **Layer definitions** — the list of layers this project uses, their per-track defaults, and their editor/value kinds
  - Template library, saved fill presets, chord-generator library
  - **Phrase list** — `phrases: [Phrase]` in playback order. This is the song; there is no phrase-ref wrapper
- **Phrase-scoped (can vary per phrase):**
  - **Cell values** for every `(track, layer)` pair — `.inheritDefault`, `.single`, `.bars`, `.steps`, or `.curve`
  - Pattern selection per track via the **Pattern** layer or equivalent phrase-owned pattern-index map
  - Chord-gen pipeline configuration (progression, tension mapping)
  - Optional graph-view override for advanced per-phrase wiring beyond the default source-mode shape

A voice preset swap at project scope instantly propagates to every phrase. A layer-default change instantly propagates to every phrase that is still inheriting it. A pool edit affects every pattern slot, and therefore every phrase, that references it.

## Track types and source modes

The persisted top-level choice is **track type**, not "track source". Track type is project-scoped and effectively immutable once a track has meaningful content, because it defines the workspace shape, compatible generators, and destination contract. Phrases then choose a **source mode** within that track type.

### Track types

| Track type | Default voicing | Main editor shape | Compatible source modes |
|---|---|---|---|
| `instrument` | Monophonic or chord-aware pitched voice | Source editor left, destination editor right | `generator`, `clip`, `template`, `midi-in` |
| `drum` | Tagged per-voice drum events | Drum lanes and voice routing | `generator`, `clip`, `template` |
| `slice` | Tagged slice-trigger voices | Waveform/slice editor plus routing | `generator`, `clip` |
| `chord` pseudo-track | Broadcast chord-context, not direct note output | Chord generator / progression editor | `generator`, `clip`, `midi-in` |

### Source-mode rules

- Source modes live on **patterns**, not directly on phrases.
- A phrase should normally store **`[TrackID: Int]`** pattern indexes, where each track-local pattern slot points at a compatible generator instance or clip from the project pools.
- Compatibility filtering is enforced by track type. A drum track cannot point at a manual mono generator; an instrument track cannot point at a slice-trigger generator.
- The happy path editor is track-type specific: manual mono step sequencer for instrument generators, per-voice drum rows for drums, slice triggers for slice tracks.
- The graph editor remains the power-user escape hatch: it can reveal or override the default source-mode wiring, but it does not replace the pattern-bank + layer/cell model as the primary persisted shape.
- The arpeggiator question resolves inside **generator kind / instance**, not as a separate track type. An arpeggiator is an instrument-compatible generator kind or transform chain.

## The two layers (song + phrase)

```
┌───────────────────────────────────────────────────────────┐
│ PROJECT.PHRASES  (the song — ordered phrase list)          │
│                                                            │
│   ┌──────────── phrase grid ────────────┐                 │
│   │         track1 track2 … trackN      │                 │
│   │ phrase0   [c]   [c]  …   [c]        │ ← cells for the │
│   │ phrase1   [c]   [c]  …   [c]        │   active layer  │
│   │ phrase2   [c]   [c]  …   [c]        │                 │
│   │ …                                   │                 │
│   └─────────────────────────────────────┘                 │
│   Layer selector: [Pattern][Mute][Volume][Intensity]…     │
│   Each cell = .inheritDefault | .single | .bars           │
│               | .steps | .curve                            │
└───────────────────────┬───────────────────────────────────┘
                        │ at tick time, each cell expands to
                        │ a per-step value; the Pattern layer
                        │ picks the track's pattern slot and
                        │ the other layers fan out as scalar /
                        │ boolean streams
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

### Phrase layer (macro coordinator)

Each phrase is a phatcontroller-style authoring row. The active view shows tracks across the top, phrases down the side, and one selected **layer** at a time. Every cell stores one of:

- `.inheritDefault`
- `.single(Value)`
- `.bars([Value])`
- `.steps([Value])`
- `.curve(ControlPoints)`

At runtime, each phrase emits per-step for the duration of its length:

- Clock: absolute song-step, phrase-relative step, bar-in-phrase, repeat-count
- Resolved layer values such as `Pattern`, `Mute`, `Volume`, `Transpose`, `Intensity`, `Density`, `Tension`, `Register`, `Variance`, `Brightness`, `FillFlag`, and `Swing`
- Structured-but-broadcast values such as `chord-context`

Layer editing affordances are **type-driven**, following phatcontroller rather than generic DAW automation:

- boolean / toggle layers expose `Single` and `Bars`
- indexed-choice layers such as `Pattern` expose `Single` and `Bars`
- scalar layers expose `Single`, `Bars`, `Steps`, and `Curve`

The selected layer controls both the preview style used in the matrix and the modal/docked editor that opens for a cell.

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

- Clock counters (absolute step, phrase-step, bar-in-phrase, repeat)
- Current abstract-row values (snapshot at this step)
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

A fill is just another phrase in the ordered list. If you want a fill every 8 bars in an 8-bar song, insert a fill phrase after every 8 regular phrases. Because phrases share pool entries through pattern banks, the fill phrase only needs to differ in the cells that are actually overridden.

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

**Playback:** Triggered from the Perform pad grid (momentary / latched / one-shot), or attached to a specific phrase row in the ordered list so the take auto-plays when that phrase begins.

**Composition mode (per Take):**
- **Relative (default)** — values stored as offsets from the baseline captured context; replaying applies those offsets to whatever the current phrase has. A Take that spiked `intensity` 0.5 → 0.7 reads as `+0.2 peak` and produces a spike to 0.5 when run on a phrase at baseline 0.3. Preserves shape across contexts.
- **Absolute** — stored values replace the phrase's authored rows during replay. Used when absolute levels matter (e.g. "bring everything to zero" drop).

Takes are reusable across phrases (not locked to the capture phrase), composable (two Takes can layer, one modulating `intensity`, another modulating `tension`), and persist in the library alongside templates and fill presets. There is no separate phrase-variant feature anymore; alternate sections are simply additional phrase rows with different cells.

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
- **Contextual track selection** — track picking lives inside the active workspace where it adds the most value (for example, the phrase matrix header or a dedicated track matrix), rather than in a permanently duplicated shell strip.
- **Context workspace** (lower body) — the entire lower surface changes with the active mode. This is the main canvas, not a sidebar/detail layout.
- **Inspector details** (embedded or floating) — selection-specific controls live inside the active workspace or in a lightweight floating inspector, not as a permanent macOS form rail.

### Main content views

| View | Controls |
|---|---|
| **Song** | Ordered phrase list. Rows = phrases in playback order; controls = add / duplicate / reorder / remove / attach fills or takes. There is no separate phrase-ref wrapper; repeating something means inserting the phrase again. Timeline and playhead still sit here. |
| **Phrase (phatcontroller macro grid)** | Phrase rows form the left rail and the track cells fill the main grid; the matrix itself carries the useful track header/selection affordance instead of relying on a duplicated shell strip. One selected **layer** is shown at a time. Default layers: Pattern, Mute, Volume, Transpose, Intensity, Density, Tension, Register, Variance, Brightness, FillFlag, Swing, plus user-added layers. Cell previews and editing modes are type-driven: booleans get toggle-style `Single` / `Bars`; indexed layers like Pattern get slot-selection `Single` / `Bars`; scalar layers get `Single`, `Bars`, per-step drawing, and curve/ramp editors. Chord-context displays as named harmonic states by bar rather than a raw scalar. |
| **Track** (instrument track) | Split workspace: **source editor on the left, destination editor on the right**. The left side chooses and edits the phrase-scoped note source for the current track type; the right side owns sound/routing identity. For instrument tracks the current happy path is a manual monophonic step source, but the same workspace must reserve visible homes for `clip-reader`, `template`, and `midi-in`. "Show wiring" reveals the deeper DAG for power users. Commands: freeze, stamp, clear. |
| **Drum** | Tag list with per-tag player assignment (MIDI channel+note, internal sampler voice, or AU instance), per-tag bus routing, per-tag velocity curve. Optional kit-level template applied to this track's clip. |
| **Sample** | Waveform with draggable slice boundaries, auto-slice (transient / grid) + re-analyze. Per-slice: start / end / pitch-offset / reverse / envelope / gain / tag / route-override. Spectral view + auto-labeling toggle. Audition playback. |
| **Chord generator** | Source-type toggle (generator / authored / midi-in). If generator: chord pool, scale, progression strategy, interpretation map (tension → dissonance, register → progression-root-bias). If authored: per-bar progression editor (degrees or chord names, optional inversions). Consumption matrix showing which tracks subscribe and in what mode (ignore / scale-root / chord-pool / transpose). Local transport. |
| **Mixer** | Per-track channel strips (vol / pan / mute / solo), bus assignment (main / alt), send-A and send-B, crossfader, per-bus FX chain slots, VU meters, master bus. Drum tracks expose one strip per `voice-route` destination (so a drum track with kick-to-subBus, snare-to-mid, hat-to-hi shows three strips). |
| **Perform** (overlay) | Fill-preset pad grid (momentary / latched), separate Take pad grid (triggers captured macros with momentary / latched / one-shot), XY pad for continuous abstract-vector control (X = intensity, Y = tension by default; configurable), Polyend-Play-style punch-in effects (repeat / reverse / loop / step-shuffle), per-track select pads for fill targeting, **Capture** button → prompts bar-count → records next N bars as a new Take. Floats over any content view. |
| **Library** | Browser of library assets: voice presets, drum templates, fill presets, **Takes**, chord-gen presets, sample slice sets, saved phrases. Preview, tag / search, drag-drop into tracks / pad grids. Source flag (bundled vs user). Import / export for sharing across projects. |
| **Clip editor** (Elektron-style step sequencer for instrument tracks) | 16-cell step grid per bar (pages for longer clips); cell state shows trig / p-lock / conditional / probability / slide / ratchet. Click toggles trig; hold a step + twist any knob in the Track destination panel or floating inspector → records a **parameter lock** on that step instead of changing baseline (classic Elektron gesture). Inspector "Locks" section lists active locks per step with remove buttons. Sub-grids below show velocity / length / delay / micro-timing as mini bar graphs (Cirklon row-view style). Conditional selector per step. For drum / sample-tagged clips the layout switches to tagged rows × steps. |
| **Graph** (power-user, optional) | Full pipeline DAG for the current phrase. Drag-wire blocks, block palette sidebar, inspector for selected block. Hidden by default; accessible via a "show wiring" toggle in Track view or as a standalone view for deep editing. |
| **Preferences** | MIDI devices & virtual endpoints, clock master/slave, audio device & latency, AU scan + whitelist, default phrase length + time signature, appearance, keyboard shortcuts. |

### View shape-shifting based on selection

Several views are specializations rather than alternatives:

- Selecting a track routes the workspace into that track type's editor shape — instrument tracks open **Track view**, drum tracks open **Drum view**, sliced-loop tracks open **Sample view**, and a chord-gen pseudo-track opens **Chord generator view**.
- The **destination/sound half** of the workspace similarly shape-shifts per track type (MIDI destination vs AU embed vs tag-to-route assignment); it is part of the track-type editor, not a separate first-class mode.
- **Clip editor** can appear inline inside Track/Drum/Sample view or be pinned as its own view for heavy editing sessions.

### Navigation feel

- Opening a project drops into Song view
- One-click from Song to any Phrase → opens Phrase view with that phrase active
- Clicking a phrase cell or another contextual track selector opens the relevant Track/Drum/Sample view
- Clicking the chord-context row in Phrase view opens Chord generator view
- Perform and Mixer are global: same state regardless of which phrase or track is active
- Library is a drawer that can overlay any view (drag-drop target)

## Workflow (acid test)

The design's validation: this user story should feel natural.

1. **Start fast.** User adds 6 tracks; each gets a default voice preset (bass, lead, pad, kick, snare, hat), a default generator instance seeded into pattern slot 0, and `.inheritDefault` cells on every shipped layer. Hit play; immediately hear a coherent groove.
2. **Shape the voices.** Per track, tweak local params (pitch range, preferred intervals) or swap voice preset.
3. **Phrase the arrangement.** Open the Phrase grid. In the Intensity layer, draw an 8-bar ramp on the bass cell. In the Tension layer, switch the pad cell to `Bars` and bump bar 6. Chord-gen responds; bass register drops; lead pushes dissonance; snare density increases. One authoring gesture → every voice responds in-character.
4. **Stamp what works.** On the bass, hit freeze. A clip is captured from the last 16 steps and appended to `clipPool`. The active pattern slot rewires from `.generator(id)` to `.clip(newClipID)`. Optionally populate step annotations (jitter velocity ±5, 80% play-prob on off-beats).
5. **Sweep.** Add a `fill` phrase row to the song list. In its Pattern layer, pick a different slot for the snare and hats; in its Intensity layer, set `.single(1.0)`. Insert that phrase row after every 8 regular rows to get a recurring fill.
6. **Perform.** Live, hold a `breakdown` fill preset over bars 14–16. Sounds right because abstract. Captured into a Take if wanted.

## Components inventory (block palette sketch)

### Generator kinds

| Generator kind | Emits | Compatible track types | Notes |
|---|---|---|---|
| `manual-mono` / `note-generator(step-gen, pitch-gen)` | note-stream | `instrument` | Current happy path; arpeggiator can live here or as a transform chain |
| `chord-generator` | chord-stream | `chord` pseudo-track | Tension-aware chord picker |
| `euclidean-drum-gen` | tagged note-stream | `drum` | Per-tag euclidean rhythms |
| `clip-reader(clip-ref)` | note-stream / tagged note-stream | `instrument`, `drum`, `slice`, `chord` | Plays stored clip with step annotations |
| `template-clip(template-ref)` | tagged note-stream | `instrument`, `drum` | Tagged clip with annotations |
| `slice-clip(sample-ref, slice-set-ref)` | tagged note-stream | `slice` | Sliced-loop pattern with tagged slice triggers |
| `slice-generator(sample-ref, slice-set-ref, strategy)` | tagged note-stream | `slice` | Emits slice triggers (euclidean-over-tags, Markov, pool-random) |
| `authored-row(values[])` | scalar-stream | phrase macro rows | Static per-step values |
| `saw-ramp(period)` | scalar-stream | phrase macro rows | Generative scalar, useful for auto-intensity |
| `midi-in(port, channel)` | note-stream / chord-stream | `instrument`, `chord` | External feed |

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
2. **Macro coordinator and phrase model** — project-scoped layers + per-phrase cells, phatcontroller-style editing modes, authored-value expansion into runtime streams
3. **Song model** — ordered `phrases: [Phrase]` list, song-clock + transport driving top-to-bottom playback, phrase insertion / reorder / duplicate UX
4. **Chord layer** — chord-generator, chord-context plumbing, consumption modes
5. **Drums and tagged streams** — voice-tag on note-stream, voice-route sink, template library, drum-gen
6. **Step annotations** — clip-reader honors annotations, annotation editor UI
7. **Fills** — fill preset overlays plus phrase-attached fills / takes. Pre-programmed fills are ordinary phrase rows with different cell values
8. **Perform layer** — live fill triggering, capture into takes
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
- **(Resolved)** Performance capture lands in **Takes** (reusable time-varying macros). Capture button prompts bar-count, records next N bars, saves to library with auto-name. Default relative composition (offsets from captured baseline); per-take absolute-lock toggle. Triggered from the perform pad grid or attached to phrase rows.
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
- **(Resolved)** Phrase variants are no longer a first-class concept. A fill / alt section is just another phrase row whose cells differ from the surrounding rows; shared pool references preserve reuse where needed.
- **(Resolved)** BPM stacking: **project default + per-phrase BPM layer override, most-specific wins**. Tempo ramps can be added later by giving the BPM layer a `.curve` cell.
- **(Resolved)** Lockable-param registry: each block declares its own `lockableParams: [...]` list. Core blocks (note-generator, note-repeat, step-order, quantise-to-chord, voice-route, interpret, force-to-scale, filter/envelope blocks) ship with curated lockable lists tuned to the musical use-cases. Custom blocks opt in explicitly. Unspecified → no lockable params.
- **(Resolved)** Note entry: four methods, all simultaneous — mouse-on-grid, computer-keyboard-as-piano (DAW standard), external MIDI input, on-screen View controller (Polyend-Play-style). All always available.
- **(Resolved)** Bundled content: curated starter kit targeting ~20 drum templates (Techno / House / DnB / HipHop / Jazz / Trap / Breakbeat / Exotic), 8 voice presets (Bass / Lead / Pad / Arp / Pluck / Sub / Noise / Drone), 6 fill presets (Drop / Build / Breakdown / Reverse / Half-time / Tension), 4 chord-gen presets (Pop / Jazz / Minor / Dark). Category list and approximate counts committed so Library view and pad grids are designed for the right volume. Actual content authored in a dedicated content sub-spec late in development.
