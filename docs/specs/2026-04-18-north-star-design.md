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

- **Track** — one instrument channel (voice), conceptually. Implemented as a pipeline ending in a MIDI or audio sink.
- **Generator** — a block that produces notes or values. Typically composed as step-gen × pitch-gen (following glaypen).
- **Clip** — concrete, stored step data for a track. Optional per track; present when material has been frozen or hand-authored.
- **Phrase** — reusable, N-bar unit (default 8 bars × 16 steps = 128 steps). Contains a macro grid plus a graph of pipelines. Ghosts phatcontroller's phrase concept.
- **Song** — ordered chain of phrase-refs, each specifying phrase id, repeat count, and optional per-ref overrides.
- **Stream** — a typed value flow through the system. Every output of every block is a stream.
- **Sink** — a block that terminates a stream outside the pipeline DAG: MIDI-out, audio-param, chord-context broadcast, macro-row writer.
- **Pipeline** — a directed path from source through transforms to sink within a phrase.
- **Voice tag** — an abstract label (`kick`, `snare`, `hat`, `clap`...) carried on note-stream entries for drum tracks; decouples rhythmic material from sonic realization.

## Scoping: project vs phrase

Following phatcontroller and Octatrack's part/pattern split: **tracks are project-scoped, pipelines are phrase-scoped**.

- **Project-scoped (stable across phrases):**
  - The set of tracks and their identities (kick, bass, lead, pad...)
  - Voice preset per track (generator type, interpretation map, local param baselines)
  - `voice-route` destination assignments (MIDI channel, bus, FX chain)
  - Template library, saved fill presets, chord-generator library
- **Phrase-scoped (can vary per phrase):**
  - Per-track pipeline customization — which source block (live generator vs clip-reader vs template), its params, any extra transform blocks
  - Clip data (with step annotations) for that track in that phrase
  - Macro grid values (authored rows + generator-sourced row assignments)
  - Chord-gen pipeline configuration (progression, tension mapping)
- **Phrase-ref-scoped (per-use overrides):**
  - Macro-row value offsets applied only on one usage of a phrase in the song

A voice preset swap at project scope instantly propagates to every phrase. A clip edit stays in one phrase. This means adding a new track to a song is a one-place operation; changing its sound across the whole song is also a one-place operation; tweaking its notes for one section is local.

## The three layers

```
┌───────────────────────────────────────────────────────────┐
│ SONG                                                       │
│   [phrase-ref A ×2]  [phrase-ref A-fill ×1]  [ref B ×4]   │
└───────────────────────┬───────────────────────────────────┘
                        │ emits song-clock: (abs-step, bar, repeat)
                        ▼
┌───────────────────────────────────────────────────────────┐
│ PHRASE                                                     │
│   ├ macro coordinator                                      │
│   │   clock + bar/repeat counters                          │
│   │   abstract expression vector (intensity, tension, ...) │
│   │   concrete rows (mute, bus, send, fill-flag)           │
│   └ pipeline graph                                         │
│       ├ chord-gen pipeline      → chord-context            │
│       ├ fill-ramp pipeline      → macro-row[intensity]     │
│       ├ track 1 pipeline        → midi-out ch1             │
│       ├ track N pipeline        → midi-out chN             │
│       └ drum pipeline           → voice-route (multi-sink) │
└───────────────────────┬───────────────────────────────────┘
                        │ emits MIDI events + audio routing
                        ▼
                   EXTERNAL / ENGINE
```

### Song layer

A song is an ordered list of **phrase-refs**. Each phrase-ref specifies:

- `phrase-id` — which phrase to play
- `repeats` — integer
- optional `overrides` — macro-row value overrides for this ref only (e.g., "play phrase A with intensity +0.2 on this occurrence")
- optional `conditional` — a condition under which this ref replaces or supplements another (Octatrack-style A:B cycle conditional at song level; supports the "every 8th bar/phrase is different" use case without inventing a new mechanism)

The song layer is the thinnest. Most expression happens at the phrase level.

### Phrase layer (macro coordinator)

Each phrase emits per-step for the duration of its length:

- Clock: absolute song-step, phrase-relative step, bar-in-phrase, repeat-count
- **Abstract expression vector** (authored as rows on a grid, or stream-sourced from generators):
  - `intensity` (0–1)
  - `density` (0–1)
  - `register` (0–1)
  - `tension` (0–1)
  - `variance` (0–1)
  - `brightness` (0–1)
- **Concrete rows**:
  - `mute` (per-track, toggle)
  - `bus` (per-track, enum: main / alt)
  - `send-A`, `send-B` (per-track, 0–127)
  - `fill-flag` (toggle)
  - `repeat-active`, `repeat-amount` (note-repeat macro)
  - `order-preset` (categorical step-order override)
  - `global-transpose` (semitones)
  - `swing-amount` (0–1)
  - `crossfader` (0–1, for audio-side)
- **Structured-but-broadcast**:
  - `chord-context` — the output of a chord-gen pipeline, broadcast as `(root, chord-type, scale)`; consumers subscribe and choose interpretation mode

Abstract rows are pluggable per row between **authored source** (user-drawn values across the phrase's steps) and **generated source** (a generator pipeline writes to the row). Switching authored ↔ generated is a toggle.

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

### Phrase variants (pre-programmed)

A phrase can have named variants: `phrase-A`, `phrase-A-fill-1`. A variant is a full phrase with the same track graph but different macro-row values and/or different source configurations. The song chain points at variants directly or via conditional refs.

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

**Playback:** Triggered from the Perform pad grid (momentary / latched / one-shot), or scheduled on a phrase-ref in the song as an Octatrack-arranger-style row action.

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

Main window is a macOS NavigationSplitView: sidebar → content → inspector. Transport is a persistent top bar. Perform mode is an overlay, not a separate route.

### Always visible

- **Transport bar** (top) — play / stop / record / tap-tempo, BPM, swing, position (phrase:bar:step), follow-playback toggle, global freeze button
- **Navigation sidebar** (left, collapsible) — Song / Phrase / Track-N / Mixer / Perform / Library / Preferences; track entries show voice name + color; drum tracks expose their tag list inline
- **Inspector** (right, collapsible, context-sensitive) — properties of the current selection: step, block, track, phrase-ref, slice, clip; editable in-place

### Main content views

| View | Controls |
|---|---|
| **Song** | Phrase-ref chain editor. Rows = refs; columns = phrase-id, repeats, per-ref macro overrides, conditional (every-Nth), scene A/B, transpose, BPM, mute mask. Special rows: HALT / LOOP (finite or ∞) / JUMP / REM. Timeline with playhead; drag phrases from library. |
| **Phrase (phatcontroller macro grid)** | Tracks × 128-step grid × parameter-layer switcher. Layers: 6 abstract rows (intensity / density / register / tension / variance / brightness) + concrete rows (mute / bus / send / fill-flag / repeat-active / order-preset / global-transpose / swing / crossfader). Per row: authored-vs-generator-sourced toggle. Chord-context row renders as chord names by bar, not scalar values. Per-track interpretation maps decide how each voice routes intensity (velocity, density, register, or a mix). |
| **Track** (generic MIDI/AU instrument track) | Pipeline editor (simple source-picker default; "show wiring" reveals DAG for power users). Voice-preset picker. Interpretation-map editor (abstract-row → local-param, curve, weight). Local generator params. Inline clip viewer and step-annotation editor (play-prob, jitter, conditional). Commands: freeze, stamp, clear. |
| **Sound** | MIDI destination (port / channel / program, Cirklon-style labeled CCs and notes) or AU plugin embed + preset. Used for generic instrument tracks. Drum and sample tracks use their specialized views instead. |
| **Drum** | Tag list with per-tag player assignment (MIDI channel+note, internal sampler voice, or AU instance), per-tag bus routing, per-tag velocity curve. Optional kit-level template applied to this track's clip. |
| **Sample** | Waveform with draggable slice boundaries, auto-slice (transient / grid) + re-analyze. Per-slice: start / end / pitch-offset / reverse / envelope / gain / tag / route-override. Spectral view + auto-labeling toggle. Audition playback. |
| **Chord generator** | Source-type toggle (generator / authored / midi-in). If generator: chord pool, scale, progression strategy, interpretation map (tension → dissonance, register → progression-root-bias). If authored: per-bar progression editor (degrees or chord names, optional inversions). Consumption matrix showing which tracks subscribe and in what mode (ignore / scale-root / chord-pool / transpose). Local transport. |
| **Mixer** | Per-track channel strips (vol / pan / mute / solo), bus assignment (main / alt), send-A and send-B, crossfader, per-bus FX chain slots, VU meters, master bus. Drum tracks expose one strip per `voice-route` destination (so a drum track with kick-to-subBus, snare-to-mid, hat-to-hi shows three strips). |
| **Perform** (overlay) | Fill-preset pad grid (momentary / latched), separate Take pad grid (triggers captured macros with momentary / latched / one-shot), XY pad for continuous abstract-vector control (X = intensity, Y = tension by default; configurable), Polyend-Play-style punch-in effects (repeat / reverse / loop / step-shuffle), per-track select pads for fill targeting, **Capture** button → prompts bar-count → records next N bars as a new Take. Floats over any content view. |
| **Library** | Browser of library assets: voice presets, drum templates, fill presets, **Takes**, chord-gen presets, sample slice sets, saved phrases. Preview, tag / search, drag-drop into tracks / pad grids. Source flag (bundled vs user). Import / export for sharing across projects. |
| **Clip editor** (Elektron-style step sequencer for instrument tracks) | 16-cell step grid per bar (pages for longer clips); cell state shows trig / p-lock / conditional / probability / slide / ratchet. Click toggles trig; hold a step + twist any knob in Track / Sound / Inspector → records a **parameter lock** on that step instead of changing baseline (classic Elektron gesture). Inspector "Locks" section lists active locks per step with remove buttons. Sub-grids below show velocity / length / delay / micro-timing as mini bar graphs (Cirklon row-view style). Conditional selector per step. For drum / sample-tagged clips the layout switches to tagged rows × steps. |
| **Graph** (power-user, optional) | Full pipeline DAG for the current phrase. Drag-wire blocks, block palette sidebar, inspector for selected block. Hidden by default; accessible via a "show wiring" toggle in Track view or as a standalone view for deep editing. |
| **Preferences** | MIDI devices & virtual endpoints, clock master/slave, audio device & latency, AU scan + whitelist, default phrase length + time signature, appearance, keyboard shortcuts. |

### View shape-shifting based on selection

Several views are specializations rather than alternatives:

- Selecting a track in the sidebar routes to **Track view** — but a drum track routes to **Drum view**, a sliced-loop track routes to **Sample view**, and a chord-gen pseudo-track routes to **Chord generator view**. Same sidebar slot, different content shape.
- **Sound view** similarly shape-shifts per track type (MIDI destination vs AU embed); for drum and sample tracks it's absorbed into Drum/Sample view respectively.
- **Clip editor** can appear inline inside Track/Drum/Sample view or be pinned as its own view for heavy editing sessions.

### Navigation feel

- Opening a project drops into Song view
- One-click from Song to any Phrase → opens Phrase view with that phrase active
- Clicking a track row in Phrase view (or a track in the sidebar) opens its Track/Drum/Sample view
- Clicking the chord-context row in Phrase view opens Chord generator view
- Perform and Mixer are global: same state regardless of which phrase or track is active
- Library is a drawer that can overlay any view (drag-drop target)

## Workflow (acid test)

The design's validation: this user story should feel natural.

1. **Start fast.** User adds 6 tracks; each gets a default voice preset (bass, lead, pad, kick, snare, hat) with pre-wired pipelines and sensible defaults. Chord-gen runs with a default progression. Hit play; immediately hear a coherent groove.
2. **Shape the voices.** Per track, tweak local params (pitch range, preferred intervals) or swap voice preset.
3. **Phrase the arrangement.** Open macro grid. Draw `intensity` ramp over 8 bars. Draw `tension` bump on bar 6. Chord-gen's output responds; bass register drops; lead pushes dissonance; snare density increases. One authoring gesture → every voice responds in-character.
4. **Stamp what works.** On the bass, hit freeze. A clip is captured from the last 16 steps. Pipeline's source is now `clip-reader` instead of the live generator. Optionally populate step annotations (jitter velocity ±5, 80% play-prob on off-beats).
5. **Sweep.** Create `phrase-A-fill-1` variant with `intensity=1, tension=0.8, repeat-active=on` on the last bar. Add to song as every-8th conditional ref.
6. **Perform.** Live, hold a `breakdown` fill preset over bars 14–16. Sounds right because abstract. Captured into a new variant if wanted.

## Components inventory (block palette sketch)

**Sources:**
- `note-generator(step-gen, pitch-gen)` — glaypen-orthogonal
- `chord-generator` — tension-aware chord picker
- `euclidean-drum-gen` — per-tag euclidean rhythms
- `clip-reader(clip-ref)` — plays stored clip with step annotations
- `template-clip(template-ref)` — tagged clip with annotations
- `slice-clip(sample-ref, slice-set-ref)` — sliced-loop pattern with tagged slice triggers
- `slice-generator(sample-ref, slice-set-ref, strategy)` — generator emitting slice triggers (euclidean-over-tags, Markov, pool-random)
- `authored-row(values[])` — static per-step values
- `saw-ramp(period)` — generative scalar, useful for auto-intensity
- `midi-in(port, channel)` — external feed

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

- All pipeline configurations, clip data (with annotations), voice-route maps, song structure, macro grids live in a **project document** — a `.seqai` file (Codable, JSON internally for diff-friendliness; may compact to binary later if size matters).
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
2. **Macro coordinator and phrase model** — abstract/concrete rows, authored-source blocks, phrase structure
3. **Song model** — phrase-ref chain, conditional refs, phrase variants
4. **Chord layer** — chord-generator, chord-context plumbing, consumption modes
5. **Drums and tagged streams** — voice-tag on note-stream, voice-route sink, template library, drum-gen
6. **Step annotations** — clip-reader honors annotations, annotation editor UI
7. **Fills** — fill preset overlays, conditional phrase-refs at song level
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
- **(Resolved)** State lifetime for stateful blocks (accumulators, Markov chains, conditional counters, LFO phase, random seeds): configurable per block. Default = **persist across repeats of the same phrase-ref** but reset between refs. Each stateful block exposes a lifetime setting (`reset-per-tick` / `reset-per-bar` / `reset-per-ref-start` (default) / `reset-per-ref-switch` / `persist-across-song`) for explicit overrides.
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
- **(Resolved)** BPM stacking: **project default + phrase-ref override, most-specific wins**. No phrase-level BPM. Tempo ramps between refs can be added later as a song-row feature without breaking this model.
- **(Resolved)** Lockable-param registry: each block declares its own `lockableParams: [...]` list. Core blocks (note-generator, note-repeat, step-order, quantise-to-chord, voice-route, interpret, force-to-scale, filter/envelope blocks) ship with curated lockable lists tuned to the musical use-cases. Custom blocks opt in explicitly. Unspecified → no lockable params.
- **(Resolved)** Note entry: four methods, all simultaneous — mouse-on-grid, computer-keyboard-as-piano (DAW standard), external MIDI input, on-screen View controller (Polyend-Play-style). All always available.
- **(Resolved)** Bundled content: curated starter kit targeting ~20 drum templates (Techno / House / DnB / HipHop / Jazz / Trap / Breakbeat / Exotic), 8 voice presets (Bass / Lead / Pad / Arp / Pluck / Sub / Noise / Drone), 6 fill presets (Drop / Build / Breakdown / Reverse / Half-time / Tension), 4 chord-gen presets (Pop / Jazz / Minor / Dark). Category list and approximate counts committed so Library view and pad grids are designed for the right volume. Actual content authored in a dedicated content sub-spec late in development.
