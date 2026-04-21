---
title: "Generator Algos"
category: "architecture"
tags: [generator, composition, musical, patterns, migration]
summary: The generated-source model for sequencer-ai: trigger and pitch stages, musical lookup tables, shared evaluation, and the current three-kind pool shape.
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

`GeneratorKind` now uses the current three-case roster:

- `monoGenerator`
- `polyGenerator`
- `sliceGenerator`

Each `GeneratorPoolEntry` carries:

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
- no compatibility-only backfill paths for old generator payloads
- generator pool/UI expose the current three-kind roster (`monoGenerator`, `polyGenerator`, `sliceGenerator`)
- `GeneratorParams.template` remains as an internal deferred payload shape, not an exposed pool kind

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
