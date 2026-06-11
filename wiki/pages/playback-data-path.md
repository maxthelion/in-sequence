---
title: "Playback Data Path"
category: "architecture"
tags: [playback, notes, snapshot, clips, generators, phrases, engine]
summary: The canonical path from authored project state to the note events emitted for a track on a step.
last-modified-by: codex
---

## Question This Page Answers

At step N, what determines the notes that play?

The short answer:

```
LiveSequencerStoreState / Project
  -> SequencerSnapshotCompiler
  -> PlaybackSnapshot
  -> PhrasePlaybackBuffer + TrackSourceProgram + ClipBuffer
  -> EngineController.resolvedStepNotes
  -> GeneratedSourceEvaluator
  -> GeneratedNote
  -> NoteEvent
  -> audio / MIDI / routing dispatch
```

The important rule is that the hot tick path reads a compiled `PlaybackSnapshot`, not the full document model.

## Authored State

The persisted document owns the musical truth:

- `tracks`
- `patternBanks`
- `clipPool`
- `generatorPool`
- `sliceSetPool`
- `layers`
- `phrases`
- `selectedPhraseID`

During editing, `LiveSequencerStoreState` is the resident state used for snapshot compilation. Some transitional call sites still compile from a `Project`, but that path creates a throwaway store state and delegates to the same compiler.

See `SequencerSnapshotCompiler.compile(state:)` and `SequencerSnapshotCompiler.compile(project:)`.

## Snapshot Compilation

`SequencerSnapshotCompiler` produces a `PlaybackSnapshot`.

The snapshot contains:

- `tracks` and `trackOrder`;
- `clipPool`, `generatorPool`, and `sliceSetPool`;
- `clipBuffersByID`;
- `trackProgramsByTrackID`;
- `phraseBuffersByID`;
- `selectedPhraseID`.

The compiler is responsible for turning authored structures into arrays and lookup tables that are cheap and deterministic to read on a tick.

### Clip Buffers

`ClipBuffer` stores:

- `steps: [ClipStepBuffer]`;
- `lengthSteps`;
- macro binding order;
- per-step macro override values.

`ClipBuffer.step(at:)` wraps step indexes into the clip length. `ClipBuffer.macroOverrides(at:)` returns only the per-step macro overrides that are present.

### Track Source Programs

`TrackSourceProgram` stores the playable program for one track:

- slot programs;
- macro binding IDs;
- macro defaults.

Each slot is one of:

- `.clip(clipID, modifierGeneratorID, modifierBypassed)`;
- `.generator(generatorID, modifierGeneratorID, modifierBypassed)`;
- `.empty`.

This is the compiled version of the track's pattern-bank source choices.

### Phrase Playback Buffers

`PhrasePlaybackBuffer` stores per-phrase, per-track arrays:

- `patternSlotIndex`;
- `mute`;
- `fillEnabled`;
- `macroValues`.

These arrays are produced by resolving phrase layer values for every step in the phrase. This is where phrase/layer authoring becomes a compact step-indexed playback table.

## Tick Preparation

`EngineController.processTick(tickIndex:now:)` performs a prepare/dispatch cycle.

For the upcoming step, `prepareTick(upcomingStep:now:)`:

1. reads the current `PlaybackSnapshot`;
2. computes `stepInPhrase` by wrapping the absolute step into the selected phrase length;
3. asks the snapshot for a `LayerSnapshot`;
4. applies resolved macro values to AU/sampler destinations;
5. iterates snapshot-carried tracks;
6. calls `EngineController.resolvedStepNotes(...)` for each track;
7. converts generated notes to `NoteEvent`s;
8. passes prepared notes to the executor.

Mute is applied later in dispatch/routing boundaries through `LayerSnapshot`.

## Resolving One Track Step

`EngineController.resolvedStepNotes(...)` is the central per-track resolution function.

It first asks the snapshot for:

- `ResolvedTrackPlaybackStep` via `playbackSnapshot.resolvedStep(...)`;
- `TrackSourceProgram` via `playbackSnapshot.sourceProgram(for:)`.

`ResolvedTrackPlaybackStep` carries:

- the selected pattern slot index;
- mute state;
- fill-enabled state;
- resolved macro values after phrase defaults and clip-step overrides.

Then the selected `SlotProgram` decides which source path runs.

## Clip Source Path

For `.clip(clipID, modifierGeneratorID, modifierBypassed)`:

1. look up the `ClipPoolEntry`;
2. call `GeneratedSourceEvaluator.resolveClipStep(...)`;
3. pass the resolved fill flag;
4. optionally pass the source notes through a modifier generator;
5. return `[GeneratedNote]`.

The fill flag chooses between the main lane and fill lane when the clip has fill data.

## Generator Source Path

For `.generator(generatorID, modifierGeneratorID, modifierBypassed)`:

1. look up the `GeneratorPoolEntry`;
2. call `GeneratedSourceEvaluator.evaluateSourceStep(...)`;
3. optionally pass the source notes through a modifier generator;
4. return `[GeneratedNote]`.

`GeneratedSourceEvaluator` owns generator semantics: trigger stages, pitch stages, progression chords, drum voices, slices, probability, and generator-local evaluation state.

## Modifier Path

Both clip and generator sources may have a modifier generator.

If the modifier is present and not bypassed:

```
GeneratedSourceEvaluator.processSourceNotes(...)
```

is called with:

- the source notes;
- the modifier generator params;
- the same step index;
- clip choices;
- chord context;
- generated-source evaluation state;
- RNG.

This keeps source selection and source processing distinct.

## Note Conversion And Dispatch

The resolved `[GeneratedNote]` is converted to `[NoteEvent]` by `EngineController.noteEvent(from:)`.

`NoteEvent` clamps and carries:

- pitch;
- velocity;
- length;
- gate;
- optional voice tag;
- optional slice parameters.

The executor receives prepared notes by block ID. Downstream dispatch then reaches:

- hosted AU instruments;
- internal sampler / slicer paths;
- MIDI destinations;
- project-level routes;
- chord context broadcasts where relevant.

See [[engine-architecture]] and [[routing]].

## Macro Value Precedence

Macro values are resolved before dispatch:

1. clip-step override wins when present;
2. phrase-layer value is next;
3. descriptor default is fallback.

This is compiled into `PlaybackSnapshot.resolvedStep(...)` using `TrackSourceProgram` and `ClipBuffer`.

See [[track-macros]].

## Invariants

- The hot path reads `PlaybackSnapshot`, not arbitrary SwiftUI view state.
- Step-indexed data should be represented as arrays or array-like buffers.
- Pattern selection is phrase-layer state, not a property of the clip itself.
- Source selection is per track pattern slot.
- Clip and generator sources use the same final note payload type: `GeneratedNote`.
- Modifier generators process source notes and should not fork the playback path.
- Runtime-only audition or capture state should stay transient until explicitly saved into document state.

## UI Observation Budget

The reverse direction — engine state flowing back into SwiftUI — is
budgeted (architecture verdict 2026-06-12 §2). High-frequency state goes
through narrow, dedicated publishers, and only LEAF views may observe it:

- **Tick-rate** (`transportTickIndex`, the main-published transport
  mirror): read only by per-card playhead leaves
  (`TrackCardCellPreviewLeaf`, `TrackCardStrokeOverlay`,
  `PhraseLaunchProgressBar`). Cells whose value cannot vary with the step
  (`single` / `inheritDefault`) must not register the dependency at all,
  and leaf output sits behind an Equatable guard so same-value
  re-resolutions stop at the leaf (the `ChannelMeterBank` displayState
  dedupe shape).
- **Meter/capture-rate** (`audioInputRuntimeRevision`, meter
  `displayState`): one leaf per displaying control
  (`AudioInputRuntimeBadge`, the mixer strip meters).
- **Gesture/engage-rate** (`noteRepeatRuntimeUIRevision`): read inside
  `noteRepeatRuntimeSnapshot(for:)` so the runtime trigger leaves update
  on engage/release without any page-wide invalidation.

Page and card bodies depend on document/selection state only. The reason
this is a playback invariant and not just a UI nicety: broad invalidation
makes main-thread load proportional to playback activity, and any
remaining tick-path main dependency then makes playback timing
proportional to UI cost — the closed feedback loop behind the tracks-page
BPM sag. Two regression nets pin it:

- `TracksPageInvalidationTests` asserts zero page/card re-evaluations per
  transport tick (with leaf-activity and probe positive controls).
- `TickPathMainIsolationTests` drives `processTick` under a saturated
  main thread and bounds the loaded median tick time; the DEBUG
  `TickPathMainSyncGuard` reports any sync-to-main reached from the
  marked tick path.

When adding a view that wants per-step/per-meter updates, give the
tick-rate read its own smallest-possible leaf `View` and keep the read in
that leaf's `body` proper — not in a `GeometryReader`/container closure,
whose evaluation context is not documented. Lazy-container item closures
(`ForEach` in `LazyVGrid`) count as the card body, not a leaf: a
tick-rate read there re-builds every visible card per tick.

Known followers of the OLD shape (follow-up): `TrackSourceEditorView` and
`SliceTrackWorkspaceView` compute `playingClipStepIndex` in their page
bodies, so those single-track editor pages still re-evaluate per tick
while playing.

## Known Transitional Areas

- Some APIs still have project-based compile helpers for tests or transitional callers.
- Some wiki pages still mention `MacroCoordinator`; the current tick path uses snapshot buffers and `PlaybackSnapshot.layerSnapshot(...)` for layer-derived runtime values.
- Generator lookup and clip lookup in `PlaybackSnapshot` are still array searches in helper methods, even though the surrounding path is buffer-oriented.

## Related Pages

- [[application-overview]]
- [[information-architecture-ux]]
- [[document-model]]
- [[generator-algos]]
- [[track-macros]]
- [[engine-architecture]]
- [[architecture-guardrails]]
