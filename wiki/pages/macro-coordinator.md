---
title: "Macro Coordinator"
category: "architecture"
tags: [engine, coordinator, layers, phrase, snapshot, tick, scheduling, historical]
summary: Historical/transitional note on MacroCoordinator. The current canonical phrase/source playback path is PlaybackSnapshot-based.
last-modified-by: codex
---

## Current Status

This page is historical/transitional.

The current canonical runtime path is `SequencerSnapshotCompiler` → `PlaybackSnapshot` → `PlaybackSnapshot.layerSnapshot(...)` / `EngineController.resolvedStepNotes(...)`.

For the current per-step note and phrase-layer path, read [[playback-data-path]] first.

`MacroCoordinator` may still exist in source or tests as a transitional component, but it should not be treated as the architecture that new playback features extend.

## Previous Role

The original role of `MacroCoordinator` was to run in the **prepare phase** of the engine tick loop (see [[engine-architecture]]#tick-lifecycle). For the step about to play, it evaluated active phrase layer cells for every track and produced a plain-struct `LayerSnapshot` for downstream apply-points.

It did not generate notes. It did not own pipeline state. It read `Project` plus a phrase id plus a global step index and returned a value.

## What it evaluates

In the older path, for each active layer and track, the coordinator called `PhraseModel.resolvedValue(for:trackID:stepIndex:)` at the upcoming step and packed the result into a typed field on `LayerSnapshot`:

- `.mute` → `snapshot.mute[trackID]: Bool`

The current snapshot compiler performs the equivalent phrase-layer resolution ahead of the tick into `PhrasePlaybackBuffer` arrays:

- `patternSlotIndex`
- `mute`
- `fillEnabled`
- `macroValues`

`PlaybackSnapshot.layerSnapshot(...)` then reads those arrays for the current step.

## Mute semantics

`.mute` currently uses **source-mute** semantics.

- a muted track does not emit its own AU or MIDI output
- a muted track is also filtered out before the router sees it
- routes sourced from that track therefore fall silent too

This remains the intentional behavior. If a later product decision wants DAW-style output-mute instead, the change belongs in the routing/apply boundary rather than in phrase-layer evaluation itself.

## What it does not do

- Compute notes. Note material is pre-generated; the coordinator only evaluates modulations applied on top.
- Advance the song. `Project.selectedPhraseID` is provided as input.
- Own clock counters beyond the step index. Phrase-relative counters will land alongside the first consumer that needs them.

## Why a separate component

Three responsibilities are kept apart:

- **Source cache** (edit-time): generators produce note programs on edit.
- **Coordinator** (prepare-time): reads phrase cells and produces a snapshot.
- **Dispatch** (step-boundary): drains an `EventQueue` and fires sinks.

The same separation still matters, but the current seam is the compiled snapshot:

- **Authoring state**: document/live store.
- **Compile-time**: `SequencerSnapshotCompiler`.
- **Runtime buffer**: `PlaybackSnapshot`.
- **Prepare-time**: `PlaybackSnapshot.layerSnapshot(...)` and `EngineController.resolvedStepNotes(...)`.
- **Dispatch**: `EventQueue` and concrete sinks.

## Related pages

- [[engine-architecture]] — where the coordinator fits in the tick lifecycle
- [[playback-data-path]] — current canonical phrase/source/note resolution path
- [[document-model]] — `PhraseModel` and `PhraseLayerDefinition`
