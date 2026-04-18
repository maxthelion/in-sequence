---
title: "Polyend Play Reference"
category: "architecture"
tags: [polyend-play, reference, step-sequencer, groovebox, variations, perform-mode]
summary: Summary of the Polyend Play's data model and sequencer concepts worth borrowing — work steps, per-track independence, variations, chance/action, fill tool, and perform mode.
last-modified-by: user
---

## Why this page

The Polyend Play is one of three reference devices informing the unified sequencer-ai design (others: [[octatrack-reference]], [[cirklon-reference]]). This page captures the *concepts* — not the button combinations — and flags what's distinctive enough to steal. Sourced from the Polyend Play manual v1.0.1.

## Hierarchy

```
Project
├── Sample Pool (folders drive Fill + Random)
├── Master FX (Reverb, Delay, Sound, Limiter, Saturation — preset-only)
└── Pattern (×128)
    ├── Audio tracks (×8)
    └── MIDI tracks (×8)
        ├── Steps (1–64, paged 16/32/48/64)
        └── Variations (×16 per track)
```

Each pattern holds 16 tracks. Tracks are independent in every meaningful axis: length, speed (tempo division), swing, play mode, variations. A pattern's "length" is just the longest track.

## The "work step" model

A pattern is edited in two modes, determined by whether anything is selected:

- **Nothing selected** → knob turns adjust the **work step** — a virtual "next step I'm about to place." You set its sample, note, volume, filter, FX, repeat, chance/action, etc. first; pressing a grid pad places a concrete step with all those values.
- **Step(s) selected** → knob turns edit the selected step(s). Multi-select supports rectangles via Shift + diagonal corners.

This "pick-first, place-after" model is the central UX idea. It means every step carries a *complete* snapshot of parameters, not just "note + velocity."

## Per-step parameters

Each step holds: `sample`, `note`, `octave`, `microtune`, `volume`, `pan`, `filter cutoff`, `resonance`, `attack`, `decay`, `reverb send`, `delay send`, `overdrive`, `bit depth`, `sample start`, `sample end`, `repeat type`, `repeat grid`, `chance`, `action`, `move`, `micromove`. Every parameter is automatable per step, always.

In MIDI mode the sample-oriented knobs re-purpose: Sample/Folder becomes `MIDI channel` + `program` (channel is *per-step*, unusually), Sample Start becomes `chord type` from a built-in chord table.

## Per-track independence

Each track has its own:

- **Length** 1–64 (paged 16/32/48/64)
- **Speed** — division/multiple of project tempo, `1/16` to `8/1` (and `Pause`)
- **Swing**
- **Play mode** — 35 options determining step-order traversal (forward, reverse, random, custom)
- **Variations** — 16 alt versions of the full track; switch live

Consequence: polyrhythms / polymetres are free, and each track is effectively its own mini-sequence.

## Variations

Per-track, up to 16 alternate step layouts. Switching a variation applies at the end of the current pattern (or on next step with Shift). Quick-copy a track's current content into an empty variation slot to start a new version. Audio and MIDI tracks have independent variation sets. Variations are the primary mechanism for intra-pattern change — the Play doesn't rely on "fill patterns" or pattern-swaps for short variation.

## Chance / Action

Every step carries a (`chance`, `action`) pair:

- `chance`: `Always`, `N%`, `Group with last` (only plays if previous conditional on track played), `Play N/Skip M` (play N pattern cycles, skip M), `Skip N/Play M`
- `action`: `Play Step` (default) or a mutation — `Random Sample`, `Random Note`, `Random Octave Up`, `Random Microtune`, `Random Cutoff`, `Random Repeat`, `Random Sample Start`, `Random Sample End`, `Humanize` (random micromove)

A `chance` gate optionally mutates the step rather than just gating it.

## Fill tool

Generates steps algorithmically over a selection. Modes:

- **Random** (controlled density)
- **Euclidean** (with event count)
- **Beat** — 128 preset genre beats; places kick/snare/hat across 1–3 selected tracks using samples from the `kick` / `snare` / `hat` sample-pool folders (folder names drive the algorithm)
- **Kick / Snare / HiHat** — individual instrument patterns

The sample-pool *folder structure* is a first-class input to the algorithm. Non-Beat fills use the work step's parameters as the template.

## Perform mode

A modal "live dub" overlay. Select tracks. Pads become 8 columns of punch-in effect presets:

- Red `Tune`, Orange `Cutoff`, Yellow `Overdrive/Bit-Depth`, Green `Rearrange` (playhead shuffler), Cyan `Repeat`, Violet `Delay`, Purple `Reverb`, Pink `Loop` (audio buffer)

Momentary or latched. Knob changes in perform mode revert to stored values on exit (the pattern is not mutated), but latched effects persist and re-engage when you re-enter. Perform is audio-only; MIDI tracks are out of scope.

## Pattern chaining

Patterns live on a 128-pad grid. **Adjacent pads = chained**; blank pads break the chain. You can have many independent chain-groups on the same grid, jumped into manually. No traditional numbered song list.

## Other ideas

- **View controller** — grid reconfigures into keyboard or isomorphic grid for note input; also used for selecting notes to edit
- **Scales filter** — scale/root constraint applied at input *and* output
- **Randomize knob** — the `%` controls *range*, not event count — every selected event gets a new value within `±%` of current
- **Save/Recall (workspace)** — pattern snapshot you can bounce between mid-performance
- **16-level undo/redo**, always; autosave on Stop

## What's distinctive / borrowable

- **Work step as a first-class editable.** A "next step I'm about to place" object separate from the grid is a clean way to avoid modal pick-vs-edit confusion.
- **Per-track length + speed + swing + play mode.** Tracks are almost sovereign. Polyrhythm becomes emergent, not a special mode.
- **Variations per track, not per pattern.** Orthogonal to pattern-chains; changes within a section without touching arrangement.
- **Chance/Action with probabilistic mutation.** More expressive than Octatrack's pure-gating conditional trigs: the gate *can also* mutate the step if it fires.
- **Sample-pool folder structure as algorithmic input.** The Fill/Beat tool reads folder names (`kick`, `snare`, `hat`) to know what to do. Convention over configuration at the dataset layer.
- **Perform mode as a non-destructive overlay.** Perform-only state (knob values, latched FX) is explicitly separate from pattern state; reverts on exit.
- **Grid-as-arrangement pattern map.** No song list; adjacency on a grid is the arrangement. Multiple independent chains coexist.
- **Save/Recall workspace snapshot.** One-key revert to a known-good state during performance.
