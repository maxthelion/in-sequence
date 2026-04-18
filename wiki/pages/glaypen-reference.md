---
title: "Glaypen Reference"
category: "architecture"
tags: [glaypen, generative, midi, reference, pitch-history, generators]
summary: Summary of the Glaypen generative MIDI playground — pluggable pitch/step generators, time-stamped param history, and a sliding pitch-history window that freezes generated material into clips.
last-modified-by: user
---

## Why this page

Glaypen (github.com/maxthelion/glaypen) is the user's existing generative-MIDI prototype. It is the strongest reference in this wiki for **how to do generative tracks** — both realtime and stamped-to-a-pattern — and so informs the unified sequencer-ai design alongside [[sequencerbox-domain-model]], [[octatrack-reference]], [[cirklon-reference]], and [[polyend-play-reference]]. This page captures the concepts worth lifting.

## What Glaypen is

A browser (TypeScript / Web MIDI) app built around a `GrooveBox` root. Each sequencer tick produces at most one note by composing:

- a **step generator** — decides *whether* a note fires on this step
- a **pitch generator** — decides *what* pitch to play if it does

Generated notes stream out over MIDI in real time. Everything emitted is also captured in a `PitchHistory` ring, from which a sliding window can be frozen into an editable `Clip`.

## Hierarchy

```
GrooveBox                                   (root; Web MIDI, scales, chord tables, mode)
├── GeneratorManager                        (current params + param history)
├── PitchHistory                            (ring buffer of every emitted Step)
├── 4 modes → different active sequencer:
│   ├── 0: generativeSequencer   (Sequencer)
│   ├── 1: clipSequencer         (edit sliding window)
│   ├── 2: clipSequencer         (save)
│   └── 3: songSequencer         (arrange saved clips)
├── ClipSaver                              (64-slot clip store in localStorage)
└── MidiManager
```

## Generators (strategy pattern)

Both step and pitch generators are pluggable strategies, chosen by an integer `stepMode` / `pitchMode` on the current params.

**Step generators** — all answer `stepProbability(step) → 0..1`:

- `StepGenerator` (default) — flat probability from `stepProbability` param
- `EuclidianStepGenerator` — Bjorklund-style Euclidean distribution of `stepPulseNumber` across `stepsInBar`
- `ManualStepGenerator` — per-step probability array (`manualSteps[16]`), user-drawn

**Pitch generators** — all answer `getNextPitch() → MIDI note`:

- `PitchGenerator` (default) — weighted random over a scale, where the weights are a per-degree probability vector `scaleIntervalProbabilities[]`; optional octave jitter via `octaveRange` + `octaveProbability`
- `ChordGenerator` — random note from the currently selected chord (over a scale + root)
- `ManualPitchGenerator` — picks from `manualPitchOptions`, which are filled live by playing an external MIDI controller

`GeneratorManager.buildCurrentStepGenerator()` / `buildCurrentPitchGenerator()` are simple factories.

## Generator params

A single flat record describes the entire generative state:

```ts
{ tonic, scaleIndex, scaleKey, scaleOctaveRoot,
  stepsInBar, stepProbability, stepPulseNumber, manualSteps,
  pitchRange, octaveRange, octaveProbability,
  scaleIntervalProbabilities,          // weighted random over degrees
  chordIndex, chordKey, chordRoot, chordOctaveRoot, chordScaleIndex,
  stepMode, pitchMode, color }
```

Two things make this interesting:

### 1. Interval-probability vector

`scaleIntervalProbabilities` is a length-9 array of weights applied to scale degrees when picking the next pitch. A bias toward `[3, 5, 7]` produces very different melodies from a bias toward `[0, 2, 4]`, with the same scale and range. This is the single cleanest knob for "musicality" control.

### 2. Param history with step-indexed timestamps

Every `setGeneratorParam` call:

1. Duplicates `currentGeneratorParams` into a new object
2. Pushes it onto `generatorParamsArray`
3. Records `[newParamIndex, absoluteStep]` into `genChanges`

`setGenParamsFromIndex(step)` walks back to the newest `genChange` whose step ≤ target step, reconstituting the parameter state at that moment in the sequencer's life. **Generator params themselves are automatable by time.** This is how a generative pattern gets "composition" — you change the params during playback and the system remembers when.

Plus 64 numbered **preset slots** (`loadOrSaveAtIndex(i)`): first press saves, subsequent presses load — no explicit save/load toggle.

## Pitch history and window-to-clip

`PitchHistory` records every emitted step by absolute step number. A window (default 16 steps) slides over the buffer:

- `moveWindow(±1)` — nudge
- `moveWindowToPosition(fraction)` — jump
- `setLength(n)` — resize
- `stepsForCurrentWindow()` — extract the window as `ClipRawData`

`GrooveBox.adjustWindow()` turns that into a `Clip` and hands it to a `ClipSequencer`. **The user plays in generative mode, likes a 16-step phrase, slides the window onto it, and commits it — done.** This is the central "realtime generation → stamped pattern" workflow.

## Clip mutation

Once frozen, clips support:

- `shiftLeft` / `shiftRight` — rotate steps
- `shufflePitches` — re-assign each occupied step a random pitch from the clip's own used-pitch pool
- `shuffleSteps` — re-scatter occupied steps over random positions
- `setClipDensity(0..1)` — add or remove random steps to hit a target density
- `setClipLength(n)` — grow/shrink
- 64-slot `ClipSaver` (localStorage)

Note the detail: density and pitch-shuffle both sample from the clip's *own* distribution, so mutations stay within the clip's character.

## Scales and chords

Embedded tables (hardcoded on `GrooveBox`):

- 19 scales — Chromatic, Major, Harmonic/Melodic Minor, Major/Minor Pentatonic, Blues, Akebono, Japanese, Hirajoshi, In-Sen, Iwato, Kumoi, Pelog, Whole Tone, Augmented, Diminished, Gypsy, Hungarian Minor
- 9 chords — major/minor/dim/aug triads, M7/m7/dom7, sus2, sus4
- Major and minor relative-chord numerals (I, ii, iii, IV, V, vi, vii)

These are the musical-knowledge constants a sequencer usually has to fetch from a library like `chorus` (sequencerbox's dependency).

## What's distinctive / borrowable

- **Orthogonal step × pitch generator split.** Step-gate and pitch-pick are two strategies composed per tick. Adding a new generator (e.g. a Markov pitch generator or a poly-chord step gate) is a single class with a one-method interface.
- **Generator params history indexed by step.** Time-varying generative parameters without a separate automation lane. The sequencer's absoluteStep is the automation clock.
- **Interval-probability vector over a scale.** Per-degree weighting is a small parameter surface that produces enormous musical variety.
- **Manual-input modes** that turn external MIDI into inputs for the generator (`manualPitchOptions`). "Teach the generator your pitches" without leaving generative mode.
- **Sliding window freeze.** The bridge between generative realtime and committed patterns. Relevant directly to the unified-sequencer design: generative tracks can emit either to MIDI or into a capture buffer, and any window of that buffer can be stamped as a pattern with one action.
- **Density as a clip-level knob.** Not per-step probability — whole-clip density, with random add/remove to hit the target. Cheap, musical, reusable for "dev → arrangement" dial-ins.
- **Preset slots that auto-toggle save/load.** A single physical button per slot, with behavior decided by whether it's empty. The right affordance for live use.

## Gaps (things sequencer-ai would want to add or change)

- Single-track — Glaypen generates one monophonic stream at a time; a unified system needs per-track generator instances
- Fixed 16-step window hardcoded in places; generalising to per-track window lengths is a prerequisite
- No note-off/length modelling in pitch history; notes are fixed-duration at capture time
- `currentGeneratorParams` is a flat object; splitting into "pitch-side" and "step-side" sub-records would be cleaner now that the generators are orthogonal
- Param history is unbounded (an `absoluteStep`-growing array) — needs compaction for long sessions
