---
title: "Generator Algos"
category: "architecture"
tags: [generator, composition, musical, patterns, migration]
summary: "The generated-source model: trigger/pitch stages, chord-palette generation, shared evaluation, and compatibility boundaries."
last-modified-by: codex
---

## Overview

The generated-source model is now split into two layers:

- `Sources/Musical/` ships static musical lookup tables and pure helper algorithms.
- `Sources/Document/` owns the serializable generator model used inside `.seqai` documents.

The key architectural move is replacing the old flat generator shape with a small fixed-slot pipeline:

- `TriggerStageNode` wraps a `StepStage`
- `StepStage` decides **when** a note seed fires and what base pitch it starts from
- `PitchStageNode` wraps a `PitchStage`
- `PitchStage` expands or transforms the incoming note seeds into actual note output
- `NoteShape` carries shared per-note knobs such as velocity and gate length
- `GeneratorParams` groups those pieces per generator kind

The current branch already uses the same model for:

- document serialization
- note preview
- runtime playback in `EngineController`

So the editor, preview, and transport all read through one shared generated-source evaluator instead of separate forks.

## Musical tables

`Sources/Musical/` contains the shipped reference data:

- `ScaleID`, `Scale`, `Scales`
- `ChordID`, `ChordDefinition`, `Chords`
- `StyleProfileID`, `StyleProfile`, `StyleProfiles`
- `Euclidean` helper logic for Bjorklund step distribution

These tables are:

- read-only
- bundled with the app
- not library-overridable yet
- usable from pure document/eval code without importing runtime systems

## Document-layer generator model

The serializable generated-source pieces live under `Sources/Document/`:

- `StepAlgo`
  - `manual`
  - `randomWeighted`
  - `euclidean`
  - `perStepProbability`
  - `fromClipSteps`
- `PitchAlgo`
  - `manual`
  - `randomInScale`
  - `randomInChord`
  - `intervalProb`
  - `markov`
  - `fromClipPitches`
  - `external` (stub)
- `NoteShape`
- `StepStage`
- `PitchStage`
- `TriggerStageNode`
- `PitchStageNode`
- `GeneratedSourcePipeline`
- `HarmonicSidechainSource`
- `GeneratorParams`

`GeneratorParams` is a tagged union keyed by the currently supported generator families:

- `mono`
- `poly`
- `chordGenerator`
- `progressionChordGenerator` (legacy decode/playback only)
- `drum`
- `slice`
- `template`

The important semantic change is:

- `StepAlgo` is now a **trigger-generation** strategy
- `PitchAlgo` is now a **pitch-expansion / transformation** strategy

Pitch stages consume:

- one primary note-seed stream
- zero or more named sidechains

V1 ships one named sidechain:

- `harmonicSidechain`
  - `.none`
  - `.projectChordContext`
  - `.clip(UUID)`

## Generator kinds and pool entries

The user-creatable `GeneratorKind` roster is:

- `monoGenerator`
- `polyGenerator`
- `chordGenerator`
- `sliceGenerator`

Each `GeneratorPoolEntry` carries:

- `id`
- `name`
- `trackType`
- `kind`
- `params`

`GeneratorPoolEntry.defaultPool` seeds valid project defaults for:

- mono tracks
- poly tracks
- chord tracks
- slicer tracks

## Current stance

The chord generator is offered only to Chord tracks. Its Trigger stage chooses
firing steps; its Chords stage chooses stable chord-palette slot IDs and bounded
inversion variation. Runtime evaluation resolves those choices into immutable
snapshot data and uses the seeded evaluation context, so identical input and
seed produce identical notes without UI lookup or unseeded randomness on the
playback path.

`progressionChordGenerator` remains serialized and playable so existing Poly
projects round-trip without source loss, but it is hidden from new creation and
kind switching. There is no automatic conversion: its manual progression shape
cannot always be represented by the random palette-choice model without losing
intent. `GeneratorParams.template` remains an internal deferred payload shape.

## Runtime stance

Generated-source evaluation now runs through one shared helper:

- `GeneratedSourceEvaluator`

The runtime shape is:

1. trigger stage emits note seeds
2. pitch stage(s) expand or transform those seeds
3. note shape applies shared velocity / gate values

This evaluator is used by both:

- preview UI
- `EngineController` playback preparation

Generator-source slots run this full pipeline directly. A modifier generator is
an optional second pass over already-realized source notes, not the mechanism
that makes the source generator's Pitch tab audible. When a generator is baked
to a clip, the resulting clip stores the live-resolved notes while the slot
retains the generator id as an inactive recipe for switching back to live
generation.

Stateful pitch stages use role- and slot-scoped `GeneratedSourceEvaluationState`
lanes: source-generator memory is separate from modifier-generator memory, and
two pattern slots reusing the same generator do not share scoped pitch memory.
Source state is mirrored into the legacy lane for precompute/fallback
continuity, but modifier state does not leak into that lane.

The following are still intentionally deferred:

- AU-backed trigger or pitch stages
- arbitrary track-to-track note sidechains
- external MIDI pitch capture for `PitchAlgo.external`
- richer clip-backed trigger semantics beyond the current clip-pool hook-ins
- track-type rename from the older 3-case enum to the newer spec split

## Related pages

- [[project-layout]] — where `Musical/` and `Document/` sit in the dependency graph
- [[document-model]] — the wider `.seqai` data model
- [[engine-architecture]] — the runtime path that now consumes the shared evaluator
