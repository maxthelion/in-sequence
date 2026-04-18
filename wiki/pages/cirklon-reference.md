---
title: "Cirklon Reference"
category: "architecture"
tags: [cirklon, sequentix, reference, step-sequencer, midi, instrument-definitions]
summary: Summary of the Sequentix Cirklon's data model and sequencer concepts worth borrowing — instrument definitions, dual pattern types (P3/CK), aux rows, scenes, and song mode.
last-modified-by: user
---

## Why this page

The Cirklon is one of three reference devices informing the unified sequencer-ai design (others: [[octatrack-reference]], [[polyend-play-reference]]). This page captures the *concepts* — not the button combinations — and flags what's distinctive enough to steal. Sourced from the Cirklon Operation Manual v1.20.

## Hierarchy

```
Songs (multiple in RAM)                 — one plays at a time
└── Song
    ├── Instrument assignments (per track)
    ├── Workscene                        — editable scratch scene
    ├── Scenes[]                         — saved snapshots of pattern+mute selections
    └── Tracks[]  (16 / 32 / 48 / 64; configurable)
        └── Pattern (P3 or CK)

Instrument Definitions                   — global, independent of songs
```

Tracks have a ring of up to 64; the panel surfaces 16 at a time, banked via the BAR encoder. Each track plays one pattern at a time on one instrument.

## Instrument Definitions

A global, named abstraction of a target MIDI device. Each instrument carries:

- MIDI port (5 DIN ports, 6 USB virtual ports, CV, USB host on Cirklon 2) + base channel
- **Multi** flag (channel chosen per track when enabled)
- **Poly Spread** — a polyphonic pattern spread across N consecutive monophonic synths; 5 voice-alloc modes
- `CC0=bankM` / `CC32=bankL` for bank select
- `No Xpose` / `No FTS` — globally disable transpose & force-to-scale (drums)
- `pre-send pgm` — send program changes early so the target catches the scene change
- `default note`, `default pattern type`
- User-defined note and controller *labels* — track/pattern editing shows names, not numbers

Songs just reference instruments by name. Swap the instrument definition → every song that uses it retargets.

## Pattern types

Two coexisting formats. Choose per pattern. Both participate equally in scenes and songs.

### P3 pattern (step-matrix)

Up to 16 bars × 16 steps. Each step has numeric rows and flag rows:

- **Rows:** `note`, `velo`, `length` (fractional up to "hold"), `delay` (tick offset at 192 ppqn), `auxA`–`auxD`
- **Flags:** `gate`, `tie`, `skip`, `X` (defeat scene transpose/FTS), and on/off for each of the 4 aux rows
- **Pattern-level:** `direction` (forward/reverseA/reverseB/alternate/pendulum/random/brownian/eitherway), `timebase` (1, 2, 4, 8, 16, 32, 64, triplet variants, `Prh` polyrhythm), `last step` (per bar), `bar length`

Non-linear directions and step skipping are what P3 data gets you; CK can't do them because it's an event list.

### CK pattern (event list)

A list of MIDI events with timestamps + per-note length. Polyphonic (up to 16 simultaneous notes per track). Length can be set to `infinite` (plays through once). Primary UI is a **drum grid** — rows are auto-populated per unique note seen. Each row has `VELO`, `LENG`, `DELAY` sub-rows visible in row view. Best for real-time capture and polyphonic drum patterns.

## Aux rows

Each of the 4 aux rows on a P3 pattern can be assigned to one of:

- MIDI CC (0–127)
- After-touch, pitch-bend, program change, NRPN
- Aux events (pre-defined macros — sync, FTS, etc.)

This is how CCs and controllers share the same step-level editing grammar as notes. Configurable per pattern.

## Scenes and the workscene

A scene stores: pattern selection per track, initial mute/active state, `Gbar` (global bar offset), `Length` (scene duration), `Song Advance` (auto vs. manual), `Force To Scale`, `Xpose`.

**Scenes do not own the patterns** — the same pattern can appear in many scenes. Editing the pattern changes what every scene using it will play.

The **workscene** is a temporary scratch pad you start each song in. Saving the workscene appends it to the numbered scene list; the workscene stays as-is for continued edits.

## Song mode

Three modes: `auto` (advance only on SONG page), `song` (always except in pattern edit), `work` (manual only). In song play, scenes advance for their configured length; scenes can require manual advance or sit in a scene loop (finite or infinite). Fill patterns can be designated per track and triggered to temporarily replace the current pattern.

## Force-to-Scale

Pattern notes are re-snapped to a scene-level scale + root. Per-step `X` flag defeats it. Per-instrument `No FTS` defeats it globally. `Apply FTS` bakes the transformation into the pattern permanently.

## Editing ergonomics

- **Gang** — select a set of steps; edits apply to all equally (numeric values only, not flags)
- **Slope edit** — hold one step encoder, turn another → the in-between steps ramp linearly (great for velocity/CC ramps and chromatic runs)
- **First step** — rotate the pattern so an arbitrary step becomes step 1
- Per-instrument custom labels mean the UI reads as "kick / snare / hat" or "cutoff / resonance" instead of note numbers / CC numbers

## What's distinctive / borrowable

- **Instrument definitions as a named, global, reusable target.** Decouples the song from MIDI wiring; makes re-routing the whole rig a one-line change. The single best Cirklon idea to import.
- **Dual pattern types.** P3 for step-sequencing discipline + non-linear playback; CK for unconstrained event capture. A unified codebase can hold both if the abstraction is right (time-stamped event vs. step-indexed row).
- **Aux rows.** Per-step CC / NRPN / PB / AT treated exactly like notes. No distinction between "note grid" and "automation lane."
- **Workscene.** Scenes are not the canvas; they're snapshots of a canvas. This is how users edit-then-save without a modal "scene edit" mode.
- **Polyrhythm timebase (`Prh`).** Distribute N steps evenly across one bar — different from per-track length.
- **Scene-level FTS with per-step defeat.** Musical transposition without destructive data loss.
- **Gang + slope edit.** Trivial to implement, high ergonomic payoff.
- **Labelled notes and CCs per instrument.** UI affordance that changes the feel of the whole thing.
