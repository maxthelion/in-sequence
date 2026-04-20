---
title: "Generator Algos"
category: "architecture"
tags: [generator, composition, musical, patterns, migration]
summary: The generator-algo model for sequencer-ai: musical lookup tables, StepAlgo × PitchAlgo composition, GeneratorParams, and the current three-kind pool shape.
last-modified-by: codex
---

## Overview

The generator model is now split into two layers:

- `Sources/Musical/` ships static musical lookup tables and pure helper algorithms.
- `Sources/Document/` owns the serializable generator model used inside `.seqai` documents.

The key architectural move is replacing the old flat generator shape with an orthogonal composition:

- `StepAlgo` decides **when** a note fires
- `PitchAlgo` decides **which pitch** to emit
- `NoteShape` carries shared per-note knobs such as velocity and gate length
- `GeneratorParams` groups those pieces per generator kind

This plan intentionally does **not** wire the new algos into the running engine yet. The existing runtime `NoteGenerator` block still uses its inlined params until the engine-integration follow-up lands.

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

The serializable generator pieces live under `Sources/Document/`:

- `StepAlgo`
  - `manual`
  - `randomWeighted`
  - `euclidean`
  - `perStepProbability`
  - `fromClipSteps` (stub until clip resolution lands)
- `PitchAlgo`
  - `manual`
  - `randomInScale`
  - `randomInChord`
  - `intervalProb`
  - `markov`
  - `fromClipPitches` (stub)
  - `external` (stub)
- `NoteShape`
- `GeneratorParams`

`GeneratorParams` is a tagged union keyed by the currently supported generator families:

- `mono`
- `poly`
- `slice`

## Generator kinds and pool entries

`GeneratorKind` now uses the current three-case roster:

- `monoGenerator`
- `polyGenerator`
- `sliceGenerator`

Each `GeneratorPoolEntry` now carries:

- `id`
- `name`
- `trackType`
- `kind`
- `params`

`GeneratorPoolEntry.defaultPool` seeds three valid project defaults:

- one mono generator
- one poly generator
- one slice generator

## Current stance

The repo now assumes the fresh model only:

- no legacy `GeneratorKind` decode shims
- no retired `drumKit` / `templateGenerator` cases
- no compatibility-only backfill paths for old generator payloads

## Current limits

The following are still intentionally deferred:

- engine/runtime wiring of `StepAlgo` and `PitchAlgo`
- UI for editing generator algos directly
- clip-backed source resolution
- external MIDI pitch capture
- track-type rename from the older 3-case enum to the newer spec split

## Related pages

- [[project-layout]] — where `Musical/` and `Document/` sit in the dependency graph
- [[document-model]] — the wider `.seqai` data model
- [[engine-architecture]] — the current runtime that will eventually consume these algos
