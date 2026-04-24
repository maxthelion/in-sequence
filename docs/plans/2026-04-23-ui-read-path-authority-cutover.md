# UI Read-Path Authority Cutover Plan

> **Continues:** [2026-04-23-live-store-v2-remediation.md](./2026-04-23-live-store-v2-remediation.md). The remediation migrated every UI **write** site off the `mutateProject { inout Project in ... }` bridge but left every UI **read** site going through `session.project`, a computed property that rebuilds the full `Project` value via `store.exportToProject()` on every access. This plan closes that other half of the authority cutover.
>
> **Driver:** step-toggle lag in the track step grid. Tap → store mutation → `@Observable` notification → every view reading `session.project.*` re-evaluates → each re-evaluation calls `exportToProject()`, which in turn runs `Project.init`'s `syncPhrasesWithTracks` normalization. A single tap triggers tens of `exportToProject()` calls across the visible view tree. Audio responds immediately; the UI is the slow path.

## Summary

After this plan lands:

- The UI reads directly from `LiveSequencerStore`'s resident per-domain fields (authored types: `StepSequenceTrack`, `ClipPoolEntry`, `PhraseModel`, `TrackPatternBank`, etc.). No view calls `session.project` for display. `exportToProject()` runs only at flush time or on `.fullEngineApply` dispatch.
- Views that need a compiled runtime shape (playhead visualisation, per-step computed buffers) read from a new `SessionSnapshotPublisher` — an `@Observable` wrapper whose only tracked field is the current `PlaybackSnapshot`. The snapshot the tick reads and the snapshot the UI reads are the same value.
- SwiftUI's observation system invalidates only the views whose specific fields changed. Editing clip A does not invalidate views rendering clip B.
- `Project` is a genuine persistence DTO: constructed at export for flush/save, parsed at import on load, and otherwise absent from runtime.
- The step grid's tap-to-redraw latency is under one frame (≈16ms) on a non-trivial project, verified by a benchmark test.

This is phase-gated. Each phase lands failing tests first.

## Guardrails

- **`session.project` is not a UI read API.** By end of Phase 4 it is deleted (not deprecated — deleted). Tests that need a full `Project` value call `store.exportToProject()` explicitly.
- **`exportToProject()` is called only from flush paths, `.fullEngineApply` dispatch, and tests.** Any UI-thread caller after this plan is a regression.
- **No view rebuilds `Project` on read.** The read path is: `@Observable` store/publisher → typed field → SwiftUI body.
- **Tick path untouched.** The authored store → snapshot compile → engine-held snapshot pipeline is the same as post-Phase-1b. This plan only changes how the UI reads.
- **Authored vs compiled separation is preserved.** Editing surfaces read and write authored types (`ClipContent`, `StepSequenceTrack`, `PhraseModel`). Visualisation surfaces read the compiled `PlaybackSnapshot`. Mixing the two shapes in the same view is allowed only with a doc comment explaining why.
- **Observation granularity is the goal, not an afterthought.** Each view reads the narrowest field it can. If a view reads `store.clipPoolByID` as a whole when it only needs one entry, fix it.
- **No per-cell `@Observable` objects.** SwiftUI's body diffing + Equatable cell views handle per-cell invalidation for free when the parent passes a dense buffer down as a value.
- **Performance contract.** After Phase 6, tap-to-invalidation on a step grid is under one frame on a reference project (spec'd below). A regression test enforces this.
- **1000-line file cap.** If a view file approaches the cap during migration, split it.

## Architecture

```
Main thread
-----------
  LiveSequencerStore  (@Observable, @MainActor)
    - tracks: [StepSequenceTrack]
    - clipPoolByID: [UUID: ClipPoolEntry]
    - generatorPoolByID: [UUID: GeneratorPoolEntry]
    - phrasesByID: [UUID: PhraseModel]   (+ phraseOrder: [UUID])
    - patternBanksByTrackID: [UUID: TrackPatternBank]
    - layers: [PhraseLayerDefinition]
    - routes: [RouteRule]
    - selectedTrackID: UUID?
    - selectedPhraseID: UUID
    - ...

  ┌──────────────── UI editing surfaces ──────────────┐
  │ read:  session.store.*                            │
  │ write: session.mutateClip / mutateTrack / batch   │
  └───────────────────────────────────────────────────┘

  SequencerDocumentSession.publishSnapshot()
    └─> compile(state: store.compileInput())
        └─> PlaybackSnapshot    (immutable struct, no @Observable overhead)
            ├─> engineController.apply(playbackSnapshot:)   [under stateLock]
            └─> SessionSnapshotPublisher.replace(...)        [@Observable]

  ┌──────────────── UI visualisation surfaces ───────────┐
  │ read:  session.snapshotPublisher.snapshot.clipBuffersByID[id].steps[i]
  │ write: (none — read-only)
  └──────────────────────────────────────────────────────┘

Clock thread
------------
  EngineController.prepareTick
    └─> reads currentPlaybackSnapshot under stateLock  (unchanged)
```

The publisher is an `@Observable` reference-type wrapper; replacing its `snapshot` field fires one observation notification to all UI visualisers. The clock thread reads the engine's own copy — the publisher is main-thread-only. Tick and UI ultimately consume the same compile output, but through two separate handles so UI observation doesn't touch the audio path.

## Early Guardrail Tests

Each phase lands its failing tests before the migration.

### Phase 1 — scaffolding

- `SessionSnapshotPublisherTests`
  - `replace` fires `@Observable` notifications to observers.
  - `publishSnapshot()` on the session updates both the engine's snapshot AND the publisher's snapshot to the same compiled value.
  - A fresh session has a publisher whose snapshot matches `compile(state: store.compileInput())` of the imported project (no empty/default leak).
- `StoreAccessorHelpersTests`
  - `store.selectedTrack` returns the currently selected track; `nil` if none.
  - `store.selectedPattern(forTrackID:)` returns the expected slot.
  - `store.patternBank(forTrackID:)` returns the track's bank (or default if absent).
  - `store.compatibleGenerators(forTrackID:)` matches `Project.compatibleGenerators(for:)` output for equivalent inputs.
  - `store.generatedSourceInputClips()` matches `Project.generatedSourceInputClips()`.
  - `store.harmonicSidechainClips()` matches `Project.harmonicSidechainClips()`.
  - Each helper is exercised on a store whose resident state matches a known `Project` fixture; assertions compare store output to project output. Once tests pass, the `Project` extension methods are marked internal-or-removed per Phase 4.

### Phase 2 — editing surfaces migrate off `session.project`

- `UIReadsStoreDirectlyTests`
  - A test harness renders each migrated view, mutates a specific field via the store, and asserts the view's rendered output reflects the new state without calling `exportToProject()` (spy on the store's `exportToProject` counter).
  - Cases, one per migrated view: `TrackSourceEditorView`, `LiveWorkspaceView`, `InspectorView`, `MixerView`, `PhraseWorkspaceView`, `PhraseCellEditorSheet`, `TrackDestinationEditor`, `MacroKnobRow`, `SidebarView`, `TracksMatrixView`, `WorkspaceDetailView`, `RoutesListView`, `TrackWorkspaceView` (plus any sub-views that currently read `session.project`).
  - For each view, assert `exportToProjectCallCount == 0` across an edit→redraw cycle.
- `ObservationGranularityTests`
  - Mutate clip A; assert a view bound to clip B does not re-evaluate its body. Use a body-evaluation counter (`.onChange` stand-in or a test-only `@State` increment-and-assert pattern).
  - Mutate the selected phrase's cells; assert an unrelated track's step grid view does not re-evaluate.

### Phase 3 — visualisation surfaces migrate to the publisher

- `VisualisationSnapshotConsumerTests`
  - A visualisation view bound to `session.snapshotPublisher.snapshot` updates exactly when `publishSnapshot()` runs — not on every store mutation that didn't cause a publish.
  - Playhead-like state (current `stepInPhrase` for a transport-running session) reads from the publisher, not the store.
  - Tick-thread snapshot reads and main-thread publisher reads cannot return different values within the same publish cycle (shape-level invariant; tested by compile-and-compare within a publish).

### Phase 4 — `session.project` deletion

- `NoSessionProjectAccessorTests`
  - Compile-time negative: `session.project` is not a member (can be a `Mirror` check or a `#if` gate asserting the file doesn't declare it). OR the accessor is internal-scoped and marked `@available(*, unavailable)` for UI-module consumption.
  - Grep-level CI check (or equivalent): no file under `Sources/UI/` contains `session.project` after this phase.

### Phase 6 — performance verification

- `StepGridTapLatencyTests` (benchmark, not correctness)
  - Reference project: 8 tracks, each with 4 patterns, 1 note-grid clip of 32 steps per pattern; 4 phrases of 64 steps with pattern/mute/fill layers populated.
  - Simulate a step tap via the public mutation API.
  - Assert that SwiftUI observation invalidation (signalled by a body-evaluation counter on the target view) completes in under 16ms. Use `XCTPerformanceMetric` or `Clock.measure`.
  - Separate case: assert the number of body evaluations triggered by a single-step tap is bounded (≤ 2 for the target view, 0 for unrelated views).

## Implementation Phases

### Phase 1 — Scaffolding

No UI migration yet. Just the infrastructure.

#### 1a. Introduce `SessionSnapshotPublisher`

- New file `Sources/App/SessionSnapshotPublisher.swift`:
  ```swift
  @Observable
  @MainActor
  final class SessionSnapshotPublisher {
      private(set) var snapshot: PlaybackSnapshot
      init(initial: PlaybackSnapshot) { self.snapshot = initial }
      func replace(_ next: PlaybackSnapshot) { snapshot = next }
  }
  ```
- `SequencerDocumentSession` owns one, created at init with `compile(state: store.compileInput())`.
- `publishSnapshot()` calls `publisher.replace(newSnapshot)` alongside `engineController.apply(playbackSnapshot:)`. Both consume the same compiled value.
- `activate()` and `ingestExternalDocumentChange` install fresh snapshots via `apply(documentModel:)` (which installs on the engine internally) AND `publisher.replace(...)` with the same compiled output.

#### 1b. Port `Project` helper methods to the store

Current `Project` extensions used by the UI (grep `project\.\w+(` / `project\.\w+[^(]`):

- `project.selectedTrack` → `store.selectedTrack` (computed on `LiveSequencerStore`)
- `project.patternBank(for: trackID)` → `store.patternBank(for: trackID)`
- `project.selectedPattern(for: trackID)` → `store.selectedPattern(for: trackID)`
- `project.selectedPatternIndex(for: trackID)` → `store.selectedPatternIndex(for: trackID)`
- `project.clipEntry(id:)` → already implicitly available via `store.clipPoolByID[id]`; add a convenience `store.clipEntry(id:)` matching the project signature
- `project.generatorEntry(id:)` → `store.generatorEntry(id:)`
- `project.compatibleGenerators(for: track)` → `store.compatibleGenerators(for: track)`
- `project.generatedSourceInputClips()` → `store.generatedSourceInputClips()`
- `project.harmonicSidechainClips()` → `store.harmonicSidechainClips()`
- `project.isPhaseOneHotPath` etc. — not UI-relevant, leave.

For each helper, the store extension implements the same logic by reading its resident fields rather than `Project`. Unit tests compare store-output to project-output on a shared fixture.

#### 1c. Add test spies

- `LiveSequencerStore` gains an internal-scoped `exportToProjectObserver: (() -> Void)?` and an `exportToProjectCallCount` counter (may already exist from the remediation — audit and reuse).
- A test helper `assertNoExportDuring { ... }` that zeros the counter, runs a block, asserts the counter is still zero.

#### 1d. Documentation

- `wiki/pages/live-sequencer-store.md` (or equivalent) describes: "UI reads from the store (editing) or the publisher (visualisation). UI does not call `session.project`."

### Phase 2 — Editing surfaces migrate off `session.project`

Migrate each view one at a time. Each view's migration is its own commit for reviewability. Per view:

1. Remove `private var project: Project { session.project }`.
2. Replace every `project.X` read with a store accessor (`session.store.X` or a helper from Phase 1b).
3. Where the view has multiple computed properties all reading `project`, restructure into a `let track = session.store.selectedTrack` binding at the top of `body`, or use `@Bindable` on the store. Avoid re-reading the store for every derived property.
4. Run the `UIReadsStoreDirectlyTests` case for that view: assert `exportToProjectCallCount == 0` through an edit→redraw cycle.

Views in migration order (smallest blast radius first):

- `MixerView`, `InspectorView` (already partially typed; small surface)
- `SidebarView`, `TracksMatrixView`, `WorkspaceDetailView`, `TrackWorkspaceView`
- `MacroKnobRow`, `PhraseCellEditorSheet`
- `RoutesListView`
- `PhraseWorkspaceView` (big; split the migration into subviews if needed)
- `TrackSourceEditorView` + its subviews (`TrackPatternSlotPalette`, `TrackSourceEditorView` main body, `GeneratorAttachmentControl`, the clip preview harness)
- `TrackDestinationEditor` + its widgets
- Any small remaining views the grep catches

Per view, the commit shape:

```
refactor(ui): <viewname> reads store directly, drops session.project dependency
```

At the end of Phase 2, `grep -rn "session.project\b" Sources/UI/` returns zero matches.

### Phase 3 — Visualisation surfaces migrate to the publisher

Identify views that display compiled-state visualisation (playhead, running-transport highlight, macro value readout tied to `layerSnapshot`, etc.). Many of these currently read from `EngineController` directly via `@Environment(EngineController.self)` — not from `session.project`, so they may already be fine. Audit each:

- If a view reads `engineController.transportPosition`, `currentBPM`, `isRunning`, `lastNoteTriggerCount`, etc., leave as-is. These are engine-level observable state.
- If a view reads `engineController.currentPlaybackSnapshot` (via test-only accessor), migrate to `session.snapshotPublisher.snapshot`. The engine's snapshot is not for UI.
- If a view computes a derived visualisation (e.g. step-column highlight based on current step-in-phrase), read the inputs from the publisher, not from the store.

Commit shape:

```
refactor(ui): <viewname> reads visualisation from SessionSnapshotPublisher
```

### Phase 4 — Delete `session.project`

- Delete the `var project: Project` computed property on `SequencerDocumentSession`.
- Any remaining internal caller is fixed to use `store.exportToProject()` directly (flush paths, `.fullEngineApply` dispatch) or a store accessor (display paths).
- Run `NoSessionProjectAccessorTests`.

Commit:

```
chore(sequencer): delete session.project; Project is a persistence DTO only
```

### Phase 5 — Observation granularity audit

For each migrated view, audit its observation footprint:

- Does it read `store.clipPoolByID` when it only needs one clip? If yes, read `store.clipPoolByID[id]` so the tracked access is narrower.
- Does it loop over `store.tracks` when it only needs the selected track? Narrow to `store.selectedTrack`.
- Does it read a derived computed property that ends up touching many store fields? Compute it once at the top of `body` and pass the result down as a value.

Where narrowing is blocked by Swift Observation's dictionary-level tracking (dict reads register the whole dict, not the key), document it in a comment and revisit in a later phase.

Not every view needs narrowing — only the ones whose body-evaluation counter exceeds the budget in `ObservationGranularityTests`. Fix those.

Commit shape:

```
perf(ui): narrow observation footprint in <viewname>
```

### Phase 6 — Performance verification

- Add `StepGridTapLatencyTests` on a reference project.
- Run under Instruments' SwiftUI Body Timing to confirm view-body evaluation costs. Record a baseline and enforce it.
- If any view still fails the budget, iterate on Phase 5 for that view.
- Final commit: the benchmark harness + baseline.

```
test(perf): step-grid tap-to-redraw under one frame
```

## Test Plan

Phase gates:

- **Phase 1** — scaffolding tests (`SessionSnapshotPublisherTests`, `StoreAccessorHelpersTests`) green. No UI migration yet.
- **Phase 2** — every migrated view has a `UIReadsStoreDirectlyTests` case asserting zero `exportToProject` calls on edit→redraw. Full suite green.
- **Phase 3** — visualisation views verified to read from the publisher; `VisualisationSnapshotConsumerTests` green.
- **Phase 4** — `session.project` deletion ships with `NoSessionProjectAccessorTests` preventing regression. Full suite green.
- **Phase 5** — `ObservationGranularityTests` enforce the per-view body-evaluation budget.
- **Phase 6** — benchmark baseline committed.

Manual signals:

- After Phase 2: step-toggle lag gone in the most-common editing surfaces (mixer, inspector, tracksmatrix, trackdestination, tracksource). Subjectively instant.
- After Phase 4: project is a DTO; nothing in the UI compiles if it accidentally tries to read `session.project`.
- After Phase 6: benchmark number printed in CI; regressions fail the build.

## Assumptions

- The authored types (`ClipContent`, `StepSequenceTrack`, `PhraseModel`, `TrackPatternBank`, etc.) are the correct UI read shape for editing. They're already dense-indexed where it matters (step arrays, slot arrays, cell arrays). No domain-model refactor is needed.
- Swift's `@Observable` on a dictionary property tracks dict-level access, not per-key access. This caps achievable observation granularity. Where that cap is reached, SwiftUI's body diffing + Equatable child views provide per-cell invalidation via view identity, which is sufficient in practice. If it turns out to be insufficient for a specific view, a per-key `@Observable` wrapper can be added locally.
- `GeneratedSourceEvaluator`'s signatures are not changed by this plan. The plan only affects UI reads, not the tick-path evaluator.
- `Project` remains the serialisation format for `.seqai` files; `SeqAIDocument` continues to hold a `project: Project` value updated by the debounced flush. The UI does not read it directly after Phase 4.
- Per-document `EngineController`, snapshot publication under `stateLock`, and the self-origin flush guard from the remediation remain unchanged.
- Benchmark hardware: the developer's dev machine (M-series Mac). Budget is relative to current baseline; if the current baseline is already close to one frame, the absolute number is less important than the relative improvement. Record both.

## Out of scope

- Refactoring `GeneratedSourceEvaluator` to consume compiled generator descriptors (still a future pass).
- Splitting `EngineController.swift` into smaller files (the 1000-line-cap violation is preexisting and orthogonal).
- Per-document audio output device routing (Phase 1c baseline decision stands).
- Replacing `Project` with a more compact on-disk format. `Project` stays as the DTO until a serialisation pass is explicitly planned.
