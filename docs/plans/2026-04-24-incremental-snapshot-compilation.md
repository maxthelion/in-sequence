# Incremental Snapshot Compilation

> **Driver:** `SequencerSnapshotCompiler.compile(state:)` rebuilds every clip buffer, every track program, and every phrase buffer on every `publishSnapshot()` call. Measured ~32 ms on an 8-track reference project in `StepGridTapLatencyTests`. For a single-step toggle on one clip, all but one ClipBuffer is re-produced identically. Tap-to-audible-change carries that cost.
>
> **Enables:** [2026-04-24-sub-cell-modulation.md](./2026-04-24-sub-cell-modulation.md) — adding per-cell curve descriptors and LFO overlays will grow per-buffer compile cost; incremental compile lets those additions land without regressing baseline tap-to-invalidation latency.
>
> **Driven by:** the original V2 plan's §3, which called for "Publishing a live mutation recompiles only affected buffers and swaps the immutable snapshot reference." That invariant was aspirational; the compiler shipped in Phase 1b is a whole-state rebuild.

## Summary

Replace the monolithic `compile(state:) -> PlaybackSnapshot` with a pair:

- `compile(state:)` — the full rebuild, unchanged. Used at load, activate, undo/redo, and as the correctness reference.
- `compile(changed: SnapshotChange, previous: PlaybackSnapshot, state: LiveSequencerStoreState) -> PlaybackSnapshot` — the incremental rebuild. Takes the previous snapshot, reuses every buffer that wasn't affected, rebuilds only the buffers the change descriptor names.

The session's typed mutation API already knows what changed: `mutateClip` → clip X, `mutatePhrase` → phrase Y, `mutatePatternBank` → track Z's program, `mutateTrack` → track structure, `setSelectedTrackID` → selection metadata. Each typed method reports its change shape; `publishSnapshot(changed:)` routes to the incremental compiler. Structural changes (add/remove track, add/remove clip) keep using the full rebuild.

For a single-step toggle: change descriptor is `.clip(clipID)`; the incremental compiler produces the same snapshot as `compile(state:)` but in ~constant time. The full compile stays in the test matrix as the correctness oracle.

## Guardrails

- **Bit-identical output.** For every mutation shape, incremental compile produces a `PlaybackSnapshot` equal to what `compile(state:)` would have produced from the post-mutation state. An equivalence test enforces this across a matrix of fixtures × mutation types.
- **Reference equality where possible.** Buffers that weren't affected by a change keep their existing references — no copy, no reallocation. Verify via `===` on the dictionary values where applicable (Swift `Array` and `Dictionary` have copy-on-write value semantics; the underlying storage stays shared if no mutation happens).
- **Full compile remains the default path in two places.** Document load / `activate()` and `apply(documentModel:)` / `ingestExternalDocumentChange`. These represent "everything might have changed"; no caller can legitimately claim a narrow change shape there.
- **No drift.** If the typed mutation API grows (new `mutateX` method), the incremental compiler must handle its change shape or fall back explicitly. An `@unknown default` or explicit `fatalError("add a SnapshotChange case for Y")` catches drift at compile time, not at runtime.
- **Tick path unaffected.** The tick reads a compiled `PlaybackSnapshot`; it doesn't care whether the snapshot was produced by full or incremental compile. No tick changes.
- **Observation layer unaffected.** `SessionSnapshotPublisher` still holds the snapshot reference; `.replace(newSnapshot)` still fires `@Observable` notifications the same way.
- **Thread safety preserved.** Incremental compile runs on the main thread inside `publishSnapshot()`. The tick thread continues to read the engine's installed snapshot under `stateLock`. No new concurrency surface.
- **Benchmarks enforce the win.** `StepGridTapLatencyTests` (the Phase 6 benchmark from the UI read-path cutover) asserts tap-to-invalidation under 16 ms on the reference project. That test fails today (32 ms). After this plan: must pass. The benchmark goes from aspirational to enforced.

## Architecture

```
SnapshotChange enum
  .clip(clipID: UUID)                ← content mutation
  .phrase(phraseID: UUID)            ← cells mutation
  .track(trackID: UUID)              ← StepSequenceTrack field change (mix, destination, macros, filter)
  .patternBank(trackID: UUID)        ← pattern-bank / slot / modifier change
  .generator(generatorID: UUID)      ← generator params or metadata
  .selection                         ← selectedTrackID / selectedPhraseID
  .layers                            ← phrase layer definitions changed (affects every phrase buffer)
  .routes                            ← routing, tick-irrelevant but reported for completeness
  .trackStructure                    ← add/remove/reorder tracks (fallback to full)
  .clipPool                          ← add/remove clip (fallback to full)
  .generatorPool                     ← add/remove generator (fallback to full)
  .bulk([SnapshotChange])            ← batched mutations from session.batch { … }

SequencerSnapshotCompiler
  static func compile(state: LiveSequencerStoreState) -> PlaybackSnapshot
    [full rebuild — the oracle]

  static func compile(changed: SnapshotChange,
                      previous: PlaybackSnapshot,
                      state: LiveSequencerStoreState) -> PlaybackSnapshot
    [reuse previous buffers where unaffected; rebuild the rest]

SequencerDocumentSession+Mutations
  private func publishSnapshot(changed change: SnapshotChange) {
      let newSnapshot = SequencerSnapshotCompiler.compile(
          changed: change,
          previous: engineController.currentPlaybackSnapshotForTesting,
          state: store.compileInput()
      )
      engineController.apply(playbackSnapshot: newSnapshot)
      snapshotPublisher.replace(newSnapshot)
  }

  func mutateClip(id:_:) {
      // mutate store
      publishSnapshot(changed: .clip(id))
  }
  func mutatePhrase(id:_:) {
      publishSnapshot(changed: .phrase(id))
  }
  // … etc
```

The `previous` snapshot reference is obtained from `engineController.currentPlaybackSnapshotForTesting` — the accessor already exists and is guarded by `stateLock`. Read under the lock once per publish, compile, reinstall.

## Change-descriptor → rebuild plan

Per change kind, what does the incremental compiler rebuild, and what does it reuse:

| Change | Rebuild | Reuse (from previous) |
|---|---|---|
| `.clip(id)` | `clipBuffersByID[id]` | all other clipBuffers, all trackPrograms, all phraseBuffers, tracks, clipPool (replace one entry), generatorPool, trackOrder, selectedPhraseID |
| `.phrase(id)` | `phraseBuffersByID[id]` | all clipBuffers, all trackPrograms, other phraseBuffers, tracks, pools, metadata |
| `.track(id)` | the track's entry in `tracks`; `trackProgramsByTrackID[id]` if pattern-bank–adjacent fields changed; otherwise just the tracks array entry | clipBuffers, pool buffers, phraseBuffers, other tracks |
| `.patternBank(id)` | `trackProgramsByTrackID[id]` | all clipBuffers, other trackPrograms, all phraseBuffers (they reference slot *indices*, not source IDs — per-step slot index is independent of the bank contents), tracks, pools |
| `.generator(id)` | `generatorPool` (replace one entry) | all clipBuffers, trackPrograms, phraseBuffers, tracks, metadata |
| `.selection` | selection fields on the snapshot | all buffers and pools |
| `.layers` | all `phraseBuffersByID` (each phrase's per-step mute/fill/macro values depend on the phrase-layer definitions) | clipBuffers, trackPrograms, pools, tracks |
| `.routes` | routes array on the snapshot (if carried) | all buffers and pools |
| `.trackStructure` | **full rebuild** via `compile(state:)` | nothing |
| `.clipPool` | **full rebuild** | nothing (any dependent clipBuffer reference could have been invalidated) |
| `.generatorPool` | **full rebuild** | nothing |
| `.bulk(changes)` | union of per-change rebuilds; if any element is a full-rebuild case, fall back to full | varies |

`.bulk` for `session.batch { store in … }` unions the changes each nested mutation reports. If the union contains `.trackStructure` or `.clipPool` or `.generatorPool`, fall back to full compile. Otherwise rebuild each unique affected buffer once.

Two tricky cases worth calling out:

- **`.layers`** — every phrase buffer depends on the layer definitions (for mute/fill/macro resolution). A layer edit invalidates all phrase buffers. Not a full rebuild, but close to one. Still worth distinguishing because clipBuffers and trackPrograms reuse.
- **`.patternBank(id)` vs `.phrase(phraseID)`** — a pattern-bank edit changes which clip plays at which phrase-step-index, but the `patternSlotIndex[step]` array itself comes from the phrase's authored layers, not the bank. So the phrase buffer does NOT need rebuilding on pattern-bank edits. The track program alone captures the bank's effect on resolution. Verify with tests.

## Early Guardrail Tests

Failing first, per phase.

### Phase 1 — `SnapshotChange` type + incremental API scaffolding

- `SnapshotChangeTypeTests`
  - `.bulk([])` and `.bulk([.selection])` collapse to sensible shapes.
  - `.bulk([.trackStructure, .clip(id)])` flattens to force a full rebuild.
  - Union / conflict semantics for `.bulk`.

### Phase 2 — per-domain incremental compilers, with full-compile parity

- `IncrementalCompileEquivalenceTests` — the oracle-match test. Parameterised over fixture projects × mutation shapes:
  - Given a fixture project, call `compile(state:)` → `full`.
  - Apply a mutation (clip edit / phrase edit / track edit / etc.) to the store.
  - Call `compile(state:)` on the mutated state → `expected`.
  - Reset, apply mutation via the typed path, read the session's current snapshot → `incremental`.
  - Assert `expected == incremental`. Byte-level equality on every field.
  - Matrix: 10 mutation shapes × 3 fixture sizes × 2 authored-complexity levels = 60 cases at least. Don't skimp on this suite.
- `ReferenceReuseTests`
  - After `.clip(clipA)` incremental compile: `newSnapshot.clipBuffersByID[clipB] === previousSnapshot.clipBuffersByID[clipB]` (ObjectIdentifier check if buffers are classes; otherwise verify by-value equality and document that Swift COW preserves storage identity).
  - Same for phraseBuffers, trackPrograms, pools under mutations that shouldn't touch them.
- `FullRebuildFallbackTests`
  - `.trackStructure`, `.clipPool`, `.generatorPool` force full rebuild. Verify by spying on the full-compile entry point's call count.
- `LayersChangeRebuildsAllPhraseBuffersTests`
  - `.layers` mutation rebuilds every phrase buffer, reuses everything else.

### Phase 3 — session routing

- `SessionPublishUsesIncrementalPathTests`
  - Every typed mutation reports a correct `SnapshotChange`.
  - Spy on `compile(state:)` vs `compile(changed:...)` call counts. `mutateClip` → one incremental call, zero full calls. `appendTrack` → zero incremental, one full (fallback). `batch { mutateClip; mutateClip }` → one incremental with `.bulk`.

### Phase 4 — performance benchmark passes

- `StepGridTapLatencyTests` (existing) — previously aspirational. After this plan: assert tap-to-invalidation under 16 ms. Budget enforced; regression fails CI.
- Add `BulkMutationLatencyTests` — a `session.batch` touching 3 clips + 1 phrase produces one incremental compile under 16 ms.

## Implementation Phases

### Phase 1 — `SnapshotChange` type + scaffolding

- Define `SnapshotChange` in `Sources/Engine/SnapshotChange.swift`.
- Add `compile(changed: SnapshotChange, previous: PlaybackSnapshot, state: LiveSequencerStoreState) -> PlaybackSnapshot` to `SequencerSnapshotCompiler`. Initial implementation: delegate to `compile(state:)` for every change kind (no actual incrementality yet). This lands the API surface with full-compile-under-the-hood.
- Wire `SequencerDocumentSession.publishSnapshot()` to accept an optional `changed:` parameter; route to `compile(changed:)` when supplied, `compile(state:)` otherwise.
- Tests from Phase 1 green (structural only).

This phase ships as a refactor with no behavioural change. Every publish still does a full compile.

### Phase 2 — real incremental compilers

Implement the per-domain narrow rebuilds:

- `.clip(id)`:
  - Copy `previous` by value (cheap — it's a struct holding dicts/arrays; COW keeps storage shared).
  - Recompile just the one `ClipBuffer` using `compileClipBuffer(for: state.clipPool.first(where: id), state: state)`.
  - Replace `clipBuffersByID[id]`.
  - Also replace the entry in `clipPool` (the authored `ClipPoolEntry`).
  - Return.
- `.phrase(id)`:
  - Copy `previous`.
  - Recompile just the one phrase buffer using `compilePhraseBuffer(for: state.phrase(id), state: state, trackPrograms: previous.trackProgramsByTrackID)`.
  - Replace `phraseBuffersByID[id]`.
- `.track(id)`:
  - Copy `previous`.
  - Replace the affected `tracks[i]` entry (position preserved by ID lookup).
  - If the mutation touched macros or destination, also recompile `trackProgramsByTrackID[id]` and every phrase buffer whose macros depend on this track. (Phrase buffers do — `compilePhraseBuffer` iterates over each track's macro bindings.) Note this interaction explicitly; it's the trickiest case.
- `.patternBank(id)`:
  - Recompile `trackProgramsByTrackID[id]`.
  - Phrase buffers reuse (slot indices are phrase-authored, not bank-content-dependent).
- `.generator(id)`:
  - Replace the entry in `generatorPool`.
  - Everything else reuses.
- `.selection` / `.routes`:
  - Replace the scalar field.
- `.layers`:
  - Recompile every phrase buffer (layer defs feed into mute/fill/macro resolution for every track in every phrase).
  - Reuse clipBuffers, trackPrograms, pools, tracks.
- `.trackStructure` / `.clipPool` / `.generatorPool`:
  - Fall back to `compile(state:)`.
- `.bulk(changes)`:
  - If any element forces a full rebuild → full.
  - Otherwise: apply each change in sequence on a working snapshot. Duplicate changes (two `.clip(sameID)`) rebuild once.

Tests from Phase 2 green. Equivalence test matrix is the blocker; do not accept a green CI without it.

### Phase 3 — session routing

- Every typed session method in `SequencerDocumentSession+Mutations.swift` reports a `SnapshotChange` when it calls `publishSnapshot`:
  - `mutateClip(id:)` → `.clip(id)`
  - `mutateTrack(id:)` → `.track(id)` (with a sub-flag or separate method for pattern-bank-adjacent mutations)
  - `mutatePhrase(id:)` → `.phrase(id)`
  - `mutatePatternBank(trackID:)` → `.patternBank(trackID)`
  - `mutateGenerator(id:)` → `.generator(id)`
  - `setSelectedTrackID` / `setSelectedPhraseID` → `.selection`
  - `setPatternSourceRef(for: trackID, ...)` → `.patternBank(trackID)`
  - `setPatternModifierBypassed(for: trackID, ...)` → `.patternBank(trackID)`
  - `setFilterSettings(for: trackID, ...)` → `.track(trackID)`
  - `setEditedDestination(for: trackID, ...)` → `.track(trackID)`
  - `setTrackMuted(trackID:)` → `.track(trackID)`
  - `writeStateBlob(for: trackID, ...)` → `.track(trackID)`
  - `applyMacroDiff(trackID:)` → `.bulk([.track(trackID), .layers])` (macros affect phrase buffer evaluation via layers)
  - `appendTrack` / `removeSelectedTrack` / `addDrumGroup` → `.trackStructure` (fall back to full)
  - `upsertRoute` / `removeRoute` → `.routes`
- `batch(impact:_:) { store in … }` collects per-call changes and emits a single `.bulk([...])` when dispatching.
- `activate()` and `ingestExternalDocumentChange(_:)` continue to call `apply(documentModel:)` which runs full compile internally — no incremental path for those.

Tests from Phase 3 green.

### Phase 4 — performance verification

- Run `StepGridTapLatencyTests` and enforce the 16 ms budget.
- If the budget is exceeded, diagnose which per-domain compiler is slow. Likely suspects: `.layers` rebuilding every phrase buffer is close to full-rebuild cost — acceptable but expect closer to 30 ms.
- Profile under Instruments; optimize any per-domain compiler that exceeds its sub-budget.
- Add `BulkMutationLatencyTests` for `.bulk` paths.

## Test Plan

Phase gates:

- Phase 1: API scaffolded; behaviour unchanged; existing tests green.
- Phase 2: `IncrementalCompileEquivalenceTests` green across the full mutation matrix. This is the contract.
- Phase 3: typed session methods route through the incremental path; spy-count tests verify each mutation goes through the intended `SnapshotChange`.
- Phase 4: `StepGridTapLatencyTests` passes the 16 ms budget. Regression fails CI.

Manual signals:

- After Phase 2: a crafted test that mutates 10 clips in a large project runs an order of magnitude faster in the benchmark than the full-compile baseline.
- After Phase 4: the step-toggle lag in the live view is subjectively instant. Tap → paint in one frame.

## Assumptions

- `PlaybackSnapshot`'s fields are value types (structs and dicts of structs). Copy is cheap because Swift COW keeps underlying storage shared until a mutation triggers a copy. Reference equality checks use buffer identity (`ObjectIdentifier` on dict values if they're classes; otherwise by-value `==`).
- `ClipBuffer`, `TrackSourceProgram`, `PhrasePlaybackBuffer` are Equatable and the equality is field-wise, not identity-based. The equivalence test relies on this.
- The typed session API is the only caller of `publishSnapshot`. If a future caller bypasses the typed path, it must supply its own `SnapshotChange` or use the full `publishSnapshot()` without a change.
- No hidden dependencies between domains. Specifically: no clip change affects phrase-buffer compilation; no phrase change affects clip-buffer compilation. If a hidden dependency exists, the equivalence test will catch it and we'll widen the rebuild.
- `.layers` being effectively a near-full rebuild is acceptable. Layer edits are rare (authoring-time) and users don't expect them to be instant.

## Out of scope

- Parallel compile (rebuilding independent buffers concurrently). Feasible but unnecessary if per-domain compile is already microseconds.
- Moving compile off the main thread. Main thread is where the publish happens and where the `@Observable` notification must fire; changing that is a separate concurrency plan.
- Incrementally maintaining the snapshot *between* publishes (i.e., mutating the snapshot in place as edits happen, eliminating the compile step entirely). That would fuse authored and compiled state — a bigger architectural change discussed in the UI read-path plan.
- Snapshot interning / structural sharing across documents. Each session has its own snapshot.
- Cache of "last snapshot produced" per mutation key — overkill.
