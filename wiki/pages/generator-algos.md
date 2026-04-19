---
title: "Generator Algos"
category: "architecture"
tags: [generator, composition, musical, patterns, migration]
summary: The generator-algo model for sequencer-ai: musical lookup tables, StepAlgo × PitchAlgo composition, GeneratorParams, and the legacy migration from the old flat GeneratorKind shape.
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

`GeneratorParams` is a tagged union keyed by `GeneratorKind`:

- `mono`
- `poly`
- `drum`
- `template`
- `slice`

## Generator kinds and pool entries

`GeneratorKind` now uses the spec's five-case roster:

- `monoGenerator`
- `polyGenerator`
- `drumKit`
- `templateGenerator`
- `sliceGenerator`

Each `GeneratorPoolEntry` now carries:

- `id`
- `name`
- `trackType`
- `kind`
- `params`

`GeneratorPoolEntry.defaultPool` seeds three valid project defaults:

- one instrument generator
- one drum generator
- one slice generator

## Legacy migration

Two compatibility shims keep older documents loading cleanly:

1. Legacy `GeneratorKind` values decode into the new names:
   - `manualMono` → `monoGenerator`
   - `drumPattern` → `drumKit`
   - `sliceTrigger` → `sliceGenerator`

2. Legacy `GeneratorPoolEntry` payloads that have no `params` field backfill from `kind.defaultParams`.

That means older documents can load, be edited, and be re-saved into the new shape without a separate migration step.

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
