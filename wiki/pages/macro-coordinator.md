---
title: "Macro Coordinator"
category: "architecture"
tags: [engine, coordinator, layers, phrase, snapshot, tick, scheduling]
summary: The per-tick evaluator that reads phrase-layer cells and produces a LayerSnapshot consumed in the prepare phase of the tick loop.
last-modified-by: codex
---

## Role

The `MacroCoordinator` runs in the **prepare phase** of the engine tick loop (see [[engine-architecture]]#tick-lifecycle). Its job is simple: for the step that is about to play, evaluate every active phrase layer's cell for every track, and publish a plain-struct `LayerSnapshot` that downstream apply-points read.

It does not generate notes. It does not own pipeline state. It reads `Project` plus a phrase id plus a global step index and returns a value.

## What it evaluates

For each active layer, for each track, the coordinator calls `PhraseModel.resolvedValue(for:trackID:stepIndex:)` at the upcoming step and packs the result into a typed field on `LayerSnapshot`:

- `.mute` → `snapshot.mute[trackID]: Bool`

Future layers add fields such as `volume`, `transpose`, or `intensity`; the expansion is additive.

## Mute semantics

`.mute` currently uses **source-mute** semantics.

- a muted track does not emit its own AU or MIDI output
- a muted track is also filtered out before the router sees it
- routes sourced from that track therefore fall silent too

This is the current intentional behavior, locked in by the engine mute tests. If a later product decision wants DAW-style output-mute instead, the change belongs in the routing/apply boundary rather than in phrase-layer evaluation itself.

## What it does not do

- Compute notes. Note material is pre-generated; the coordinator only evaluates modulations applied on top.
- Advance the song. `Project.selectedPhraseID` is provided as input.
- Own clock counters beyond the step index. Phrase-relative counters will land alongside the first consumer that needs them.

## Why a separate component

Three responsibilities are kept apart:

- **Source cache** (edit-time): generators produce note programs on edit.
- **Coordinator** (prepare-time): reads phrase cells and produces a snapshot.
- **Dispatch** (step-boundary): drains an `EventQueue` and fires sinks.

The coordinator is the seam that lets phrase layers reach runtime without each generator or sink reading the document directly.

## Related pages

- [[engine-architecture]] — where the coordinator fits in the tick lifecycle
- [[document-model]] — `PhraseModel` and `PhraseLayerDefinition`
