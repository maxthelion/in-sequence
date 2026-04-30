# Step Order — Existing State

## Summary

No step-order primitives exist anywhere in the codebase. The entire playback
path resolves a sequential `stepInPhrase` integer and passes it unchanged through
every layer of the stack. The feature is a greenfield addition.

---

## How the playhead is currently resolved

The tick path is a straight pipeline with one integer index driving everything:

1. `TickClock` (`Sources/Engine/TickClock.swift`) fires a monotonically
   increasing `UInt64` `tickIndex` at the configured BPM / stepsPerBar rate.

2. `EngineController.processTick` (`Sources/Engine/EngineController.swift:766`)
   calls `prepareTick(upcomingStep:)`.

3. `prepareTick` (`EngineController.swift:778`) performs the only modular
   reduction in the hot path:

   ```swift
   let phraseStepCount = playbackSnapshot.phraseBuffer(for: playbackSnapshot.selectedPhraseID)?.stepCount ?? 1
   let stepInPhrase = Int(upcomingStep % UInt64(max(1, phraseStepCount)))
   ```

   `stepInPhrase` is then used for every downstream operation in that tick:
   - `PlaybackSnapshot.layerSnapshot(phraseID:stepInPhrase:)` to read mute /
     fill / macro values for that step.
   - `EngineController.resolvedStepNotes(for:in:phraseID:stepIndex:…)` for
     every track (line 820).

4. `resolvedStepNotes` (`EngineController.swift:1438`) calls
   `PlaybackSnapshot.resolvedStep(phraseID:trackID:stepInPhrase:)`
   (`Sources/Engine/PlaybackSnapshot.swift:55`), which reads
   `TrackPhrasePlaybackBuffer.patternSlotIndex[normalizedIndex]` to decide
   which pattern slot is active for that step, then resolves clip or generator
   notes using the same `stepIndex` value passed through to
   `GeneratedSourceEvaluator.resolveClipStep` and `evaluateSourceStep`.

5. `NoteGenerator.tick` (`Sources/Engine/Blocks/NoteGenerator.swift:46`) uses
   `context.tickIndex % stepPattern.count` for the legacy block path, but note
   that in the live path this is bypassed because `prepareTick` injects
   `preparedNotesByBlockID` (the `resolvedStepNotes` output) directly.

### Critical line — the single modular reduction

```
EngineController.swift:797
let stepInPhrase = Int(upcomingStep % UInt64(max(1, phraseStepCount)))
```

This is the one place where the absolute tick counter becomes a phrase-scoped
step index. A step-order map would transform this value before it propagates to
all downstream callers.

---

## Where the step-index is consumed after `stepInPhrase` is set

| Call site | File | Line | Role |
|---|---|---|---|
| `layerSnapshot(phraseID:stepInPhrase:)` | `PlaybackSnapshot.swift` | 90 | Reads mute / fill / macro values |
| `resolvedStepNotes(…stepIndex:…)` | `EngineController.swift` | 820 | Gate for all note output |
| `resolvedStep(phraseID:trackID:stepInPhrase:)` | `PlaybackSnapshot.swift` | 55 | Looks up pattern slot + macro overrides |
| `evaluateSourceStep(…stepIndex:…)` | `GeneratedSourceEvaluator.swift` | 58 | Drives generator note output |
| `resolveClipStep(…stepIndex:…)` | `GeneratedSourceEvaluator.swift` | 303 | Drives clip note output |
| `processSourceNotes(…stepIndex:…)` | `GeneratedSourceEvaluator.swift` | 360 | Post-processing (pitch algo, etc.) |

Every consumer receives `stepInPhrase` directly. There is no secondary lookup
between the tick source and note output.

---

## Scope question — resolved

The user stories left the scope (project / phrase / track / layer) open. After
inspection, **phrase-level scoping is the most natural fit** for the following
reasons:

- `stepInPhrase` is the single integer that all per-track note resolution
  reads. A per-phrase step-order map replaces one value and every track in that
  phrase automatically uses the remapped index.
- `PhrasePlaybackBuffer` (`Sources/Engine/PhrasePlaybackBuffer.swift`) already
  carries per-phrase, per-track data. A step-order map fits as an additional
  field or as a parallel `phraseStepOrderByID` dictionary on `PlaybackSnapshot`.
- Track-level scoping would require inserting a per-track remap before `resolvedStep`,
  which is called inside the per-track loop in `prepareTick`. This is feasible
  but requires a second lookup per track per tick.
- Project-level scoping (one shared map) would be the simplest data model but
  cannot be per-phrase without extra indirection.

Recommended first-pass scope: **per-phrase, per-track toggle** — one step-order
map per phrase that can be toggled on or off independently per track, stored
alongside the phrase's existing `TrackPhrasePlaybackBuffer`.

---

## Model gaps

| Gap | Detail |
|---|---|
| No `stepOrderMap` field | `StepSequenceTrack`, `PhraseModel`, `PhrasePlaybackBuffer`, `TrackPhrasePlaybackBuffer`, `PlaybackSnapshot` all lack any step-order concept. |
| No toggle flag | No `stepOrderEnabled: Bool` or equivalent anywhere in the document model. |
| No persistence | `Project+Codable.swift` has no step-order key; `SeqAIDocument.swift` cannot round-trip such a value. |
| No compiler path | `SequencerSnapshotCompiler.compilePhraseBuffer` (`Sources/Engine/SequencerSnapshotCompiler.swift:291`) does not populate any remapping structure. |
| No UI surface | `PhraseWorkspaceView.swift`, `TrackWorkspaceView.swift`, and `PhraseModel.defaultSet` define no step-order layer. |

---

## UX / workflow gaps

- No editor exists for entering a step-index array (e.g. `[0,1,2,3,3,3,7,8]`).
- No visual indicator shows that a track's playhead is remapped vs. sequential.
- No toggle affordance (on/off) is wired to any control.
- The phrase matrix (`PhraseWorkspaceView`) has no step-order row in its layer
  grid.

---

## Existing primitives the feature could lean on

| Primitive | File | Relevance |
|---|---|---|
| `PhraseLayerDefinition` / `PhraseCell.steps` | `Sources/Document/PhraseModel.swift:366` | The `.steps([PhraseCellValue])` cell mode already carries a per-step integer value per track per phrase. A `stepOrder` layer of type `.patternIndex` (integer 0–15) could model the lookup array without a new cell type. |
| `PhraseLayerTarget` | `Sources/Document/PhraseModel.swift:347` | Adding a `.stepOrder` target case would let the compiler identify and process the map in `compilePhraseBuffer`. |
| `TrackPhrasePlaybackBuffer` | `Sources/Engine/PhrasePlaybackBuffer.swift:3` | Parallel to `patternSlotIndex: [UInt8]`, a `stepOrderMap: [UInt8]?` field (nil = disabled) could carry the compiled map on the tick path. |
| `PlaybackSnapshot.resolvedStep` | `Sources/Engine/PlaybackSnapshot.swift:55` | The `normalizedIndex` calculation at line 67 is the natural insertion point for a step-order remap: replace `stepInPhrase` with `stepOrderMap?[stepInPhrase] ?? stepInPhrase` before reading `patternSlotIndex`. |
| `SnapshotChange` / incremental compile | `Sources/Engine/SequencerSnapshotCompiler.swift` | The incremental `compile(changed:previous:state:)` path already handles layer changes; a `stepOrderChanged` flag in `SnapshotChange` would trigger phrase buffer recompilation without a full rebuild. |

No randomisation or alternative-order toggles exist. The feature is completely new.

---

## Architecture constraints

- The tick path runs on the `TickClock`'s private `DispatchQueue`. Any data the
  map reads must be pre-compiled into `PlaybackSnapshot` / `PhrasePlaybackBuffer`
  before the tick fires; it must not touch `LiveSequencerStore` or `Project`
  at tick time.
- `PhrasePlaybackBuffer` is `Sendable` and `Equatable`. Any new field must
  preserve both conformances.
- Step-order state must survive `exportToProject()` / `importFromProject()`,
  which means it needs a `Codable` home in `Project` (likely on `PhraseModel`
  or as a new top-level pool, similar to `patternBanks`).

---

## Relevant tests (existing)

| Test file | Coverage |
|---|---|
| `Engine/SequencerSnapshotCompilerSemanticsTests.swift` | Phrase buffer compilation semantics |
| `Engine/PlaybackSnapshotBuffersOnlyTests.swift` | `resolvedStep` and `layerSnapshot` resolution |
| `Engine/EngineControllerTests.swift` | `resolvedStepNotes` and `prepareTick` integration |
| `Engine/NoteGeneratorTests.swift` | `NoteGenerator.tick` step-index arithmetic |

## Missing test coverage

- No tests verify that a remapped step index produces different note output than
  the sequential index.
- No tests cover a toggled-off map restoring sequential behaviour.
- No codable round-trip tests for step-order data.
- No snapshot compiler tests for a step-order `PhraseLayerTarget`.
