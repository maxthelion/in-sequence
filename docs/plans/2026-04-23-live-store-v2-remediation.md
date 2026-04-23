# Live Sequencer Store V2 Remediation Plan

> **Supersedes:** the implementation slice on `codex/live-sequencer-store-v2` (commits `ac11a2f`, `5b6df6f`).
> **Absorbs:** [2026-04-23-live-store-authority-cleanup.md](./2026-04-23-live-store-authority-cleanup.md) — the mixer / inspector authority cleanup folds into Phase 2d of this plan.
> **Driven by:** [docs/reviews/2026-04-23-adversarial-review-live-store-v2.md](../reviews/2026-04-23-adversarial-review-live-store-v2.md) and [docs/specs/2026-04-23-live-sequencer-store-v2-adversarial-review.md](../specs/2026-04-23-live-sequencer-store-v2-adversarial-review.md).

## Summary

The first V2 slice landed a `SequencerDocumentSession` / `LiveSequencerStore` scaffold, compiled dense playback buffers, and removed the per-tick `liveStepNotes` JSON path. Two adversarial reviews converge on the finding that the architectural core is not yet realized:

- `LiveSequencerStore` owns only a single `Project` struct — every mutation clones and rewrites the whole value. It is a thin `Project` wrapper, not authored-state ownership.
- The compiled `ClipBuffer` / phrase / source buffers are cosmetic. The tick path resolves notes through `playbackSnapshot.project.clipEntry(...)` / `.generatorEntry(...)` — it never reads the buffers.
- A single shared `EngineController` is used across every `DocumentGroup` window; per-document isolation is a runtime lie.
- `AudioInstrumentHost.parameterReadout` still crashes on `AUParameter.valueForKeyPath("ancestors")` (fixed on a sibling worktree, not merged here).
- `SeqAIDocument.fileWrapper` has no flush hook — Cmd-S within 150ms of an edit silently serializes stale state.
- `currentPlaybackSnapshot` is assigned on main and read on the clock thread without synchronization — torn-read race on a struct-valued field.
- Several migrated writers still use `.fullEngineApply` (phrase matrix, sampler filter) or `.documentOnly` (preset browser / AU state blob), either double-computing the snapshot or skipping it entirely.
- Mixer fader drag writes directly to `EngineController.setMix`; the live store's `track.mix` is untouched until release.
- `MacroCoordinator` is dead code with live test suites providing false coverage.

This plan re-does V2's core and then finishes the authority migration, phase-gated with failing tests first, as the original V2 plan prescribed.

## Guardrails

- Phase 1 must make `LiveSequencerStore` a real authored-state owner. `Project` becomes an import/export DTO. No Phase 2 work begins until Phase 1 tests pass against the new store shape.
- The tick path must consume compiled buffers for all note / pattern / generator resolution. `playbackSnapshot.project` is not an acceptable resolution path. The embedded `Project` reference is removed from `PlaybackSnapshot` by the end of Phase 1.
- Each migrated UI writer has exactly one authority path. No `.fullEngineApply` call on a surface that has a `.snapshotOnly` or scoped-runtime equivalent. No `.documentOnly` on a write that affects audible state.
- Engine ownership is per-document. A second open document cannot observe the first document's transport, snapshot, or macro dispatch state.
- Save, document close, terminate, and resign-active all flush live state synchronously.
- `currentPlaybackSnapshot` read/write is synchronized — either under `stateLock` or via atomic reference-swap of a boxed snapshot.
- Dead code is deleted in the same commit that removes its last caller. `MacroCoordinator` is removed in Phase 4.
- The five early-guardrail suites prescribed by the original V2 plan must actually exercise their stated invariants under the relevant preconditions (running transport, concurrent reads, debounce cancellation).

## Early Guardrail Tests

Each phase lands its failing tests first.

### Phase 1 — authored-state ownership + tick reads buffers + per-document engine

- `LiveSequencerStoreResidentStateTests`
  - a clip edit recompiles only the affected `ClipBuffer` (spy on compiler entry points)
  - a pattern / slot / source edit recompiles only the affected `TrackSourceProgram`
  - a phrase-layer edit recompiles only the affected `PhraseStepBuffer`
  - roundtrip `Project → store → Project` preserves: note-grid clips, source/modifier slot state, phrase data, macro data, sampler filter, destination/AU preset state
  - store mutation does not require rewriting the full `Project` value (no `var next = project; next.x = y; self.project = next` shape)
- `PlaybackSnapshotBuffersOnlyTests`
  - `PlaybackSnapshot` exposes no `project` field
  - tick resolution for a note-grid clip reads only `ClipBuffer`
  - tick resolution for a generator source reads only compiled generator descriptors
  - assert via a panic-on-read wrapper that no snapshot-level `Project` access occurs during a tick
- `MultiDocumentEngineIsolationTests`
  - opening two `SequencerDocumentSession`s yields two distinct `EngineController` instances
  - a clip edit in document A does not mutate document B's snapshot
  - transport start in A leaves B stopped
- `AudioInstrumentHostTests` (class name; file is `AudioInstrumentHostTests.swift`)
  - `parameterReadout` returns a valid structure when `AUParameter` does not respond to `valueForKeyPath("ancestors")`
  - no crash on a mock parameter without KVC-compliant ancestors
  - Note: the suite was not renamed to `AudioInstrumentHostParameterReadoutTests` because the file also covers stale-async-instrument-completion and pre-attached-AU-fallback scenarios. The parameterReadout regression lives in `test_parameterDescriptors_walks_group_tree_without_kvc`.

### Phase 2 — authority completion

- `PhraseMatrixAuthorityTests` — tap / insert / duplicate / remove publish a snapshot without calling `engineController.apply(documentModel:)`
- `SamplerFilterAuthorityTests` — cutoff / resonance / drive edits update the live store and the sampler runtime via a scoped path, without `apply(documentModel:)`
- `PresetBrowserAuthorityTests` — AU preset commit republishes the snapshot inside the mutation call, not on the next debounce flush
- `MixerDragLiveWritesTests` — every drag update writes `session.project.tracks[..].mix` (not only on commit)
- `FullEngineApplyNoDoubleCompileTests` — a `.fullEngineApply` call compiles the snapshot exactly once

### Phase 3 — concurrency and flush

- `PlaybackSnapshotConcurrencyTests` — 10k interleaved writes (main) and reads (bg) under thread-sanitizer produce no partial reads
- `SaveFlushTests` — a mutation followed immediately by `fileWrapper(...)` serializes the mutated state
- `TerminateFlushTests` — `applicationWillTerminate` flushes all active sessions; `applicationDidResignActive` flushes too
- `DebounceSemanticsTests` — a second mutation within 150ms cancels the first debounce task; no spurious flush after cancellation

### Phase 4 — test hardening and dead-code removal

- Rewrite `EventQueueInvalidationTests` to exercise a running transport: start clock, prepare tick N, mutate to silence step N+1, step the transport, assert no note leaks.
- Rewrite `EngineHotPathIsolationTests` to spy on `apply(documentModel:)` invocations, not downstream side effects like `destinationCallCount`.
- Expand `SequencerSnapshotCompilerSemanticsTests` with: `.generator` source resolution, modifier chain, `modifierBypassed == true`, clip-step macro override beats phrase-step which beats default.
- Expand `SequencerDocumentSessionAuthorityTests` to assert snapshot publication on the mutation call (not just document staleness).
- Delete `MacroCoordinatorTests` and `MacroCoordinatorMacroParamTests`.

## Implementation Changes

### Phase 1 — Architectural core

#### 1a. Make `LiveSequencerStore` a real authored-state owner
- Replace `private(set) var project: Project` with resident per-domain fields holding the *authored* document-model types (not compiled snapshot buffers — the compiler owns those). As shipped:
  - `tracks: [StepSequenceTrack]` (order-significant array)
  - `clipPoolByID: [UUID: ClipPoolEntry]`
  - `generatorPoolByID: [UUID: GeneratorPoolEntry]`
  - `phrasesByID: [UUID: PhraseModel]`, plus `phraseOrder: [UUID]`
  - `layers: [PhraseLayerDefinition]`
  - `routes: [RouteRule]`
  - `patternBanksByTrackID: [UUID: TrackPatternBank]`
  - `trackGroups: [TrackGroup]`
  - metadata: `version`, `selectedTrackID`, `selectedPhraseID`, project-level scratch
- `importFromProject(_:)` builds resident state from a persisted `Project`.
- `exportToProject()` reconstructs a `Project` for flush.
- Mutation API is focused — `mutateClip(id:_:)`, `mutateTrack(id:_:)`, `mutatePhrase(id:_:)`, `mutateGenerator(id:_:)`, `setPatternBank(trackID:bank:)`, `setSelectedTrackID(_:)`, `setSelectedPhraseID(_:)`. Each edit mutates only the affected sub-state and bumps revision.
- No mutation path rewrites the entire `Project` value.
- `exportToProject()` is called only at flush and during `.fullEngineApply` dispatch. `publishSnapshot()` takes a `LiveSequencerStoreState` via `store.compileInput()` and never calls `exportToProject()`.
- Compiled types (`ClipBuffer`, `TrackSourceProgram`, `PhrasePlaybackBuffer`) are built by `SequencerSnapshotCompiler` and live on `PlaybackSnapshot`, not on the store. Evaluator-facing types (`ClipPoolEntry`, `GeneratorPoolEntry`, `StepSequenceTrack`) are carried through to the snapshot as typed arrays — refactoring `GeneratedSourceEvaluator` to consume compiled descriptors is out of scope for V2 and is flagged with a `// TODO(future)` on the snapshot.

#### 1b. Tick reads compiled buffers, not `Project`
- Remove the embedded `Project` from `PlaybackSnapshot`. As shipped, the snapshot carries:
  - typed authored arrays: `tracks: [StepSequenceTrack]`, `clipPool: [ClipPoolEntry]`, `generatorPool: [GeneratorPoolEntry]`
  - compiled buffers: `clipBuffersByID: [UUID: ClipBuffer]`, `trackProgramsByTrackID: [UUID: TrackSourceProgram]`, `phraseBuffersByID: [UUID: PhrasePlaybackBuffer]`
  - navigation: `selectedPhraseID: UUID`, `trackOrder: [UUID]`
  - lookup helpers: `clipEntry(id:)`, `generatorEntry(id:)`
- `EngineController.resolvedStepNotes` reads `snapshot.clipEntry(id:)` and `snapshot.generatorEntry(id:)` (which consult the typed authored arrays on the snapshot). The compiled buffers drive per-step resolution through `phraseBuffersByID` / `trackProgramsByTrackID`.
- `EngineController.prepareTick` iterates `playbackSnapshot.tracks`, not `documentModel.tracks`. `flushRoutedNotes` takes the snapshot as a parameter and reads its tracks field too.
- `currentDocumentModel` is removed from the tick path (verified by `grep -n "documentModel.tracks\|currentDocumentModel.tracks" Sources/Engine/EngineController.swift` — remaining hits are all in non-tick handoff code: `apply(documentModel:)`, `writeStateBlob`, `setMix`, `prepareAudioUnit`, `buildPipeline`, `effectiveDestination`, etc.).
- The `layerSnapshot` continues to come from the compiled phrase-step buffer.

#### 1c. Per-document `EngineController`
- Remove `@State private var engineController` from `SequencerAIApp`.
- `SequencerDocumentSession` creates and owns its own `EngineController` at init.
- `SequencerDocumentSessionRegistry` maps `DocumentID → {session, engineController}`.
- `SequencerDocumentRootView` reads the engine controller from the session it looks up, not from an app-level `@State`.
- Audio device ownership stays app-level (one output device). Transport and snapshot state are per-document.

#### 1d. Merge AU crash fix
- Port `AudioInstrumentHost.parameterReadout` fix from `codex/fix-au-parameter-readout-crash` (commit `521b29d fix(au-host): avoid KVC crash in parameter readout` and the follow-up `88f79bc fix(au-presets): harden preset browser launch path`). Cherry-picked onto this branch as `86f79f3` + `2932c46`.
- Add regression in `AudioInstrumentHostTests` (`test_parameterDescriptors_walks_group_tree_without_kvc`).
  The class was kept as `AudioInstrumentHostTests` (not renamed to `AudioInstrumentHostParameterReadoutTests`)
  because the file covers additional scenarios (stale-async instrument, pre-attached AU fallback).
- Manual check: opening the macro picker on a non-KVC-compliant AU (or the mock) no longer crashes.

### Phase 2 — Authority completion

#### 2a. Phrase matrix becomes `.snapshotOnly`
- `PhraseWorkspaceView.handleSingleTap`, `openCellEditor`, `insertPhrase`, `duplicatePhrase`, `removePhrase`: switch from `.fullEngineApply` to `.snapshotOnly`.
- Add `.phrasesChanged` to `ProjectDelta.isPhaseOneHotPath`.
- The snapshot compiler already consumes phrase-layer state — no compiler change.

#### 2b. Sampler filter moves off `.fullEngineApply`
- Introduce `LiveMutationImpact.scopedRuntime(update: ScopedRuntimeUpdate)` where `ScopedRuntimeUpdate` is a typed enum (`mix(TrackID, TrackMix)`, `filter(TrackID, SamplerFilterSettings)`, `auState(TrackID, Data)`, etc.).
- `session.mutateProject(impact: .scopedRuntime(.filter(...)))` recompiles the single affected `DestinationRuntimeDescriptor` / filter buffer and calls the scoped engine dispatch (analogous to `setMix`).
- `TrackDestinationEditor.swift:262-269` uses `.scopedRuntime(.filter(...))`.
- `SamplerDestinationWidget` stops calling `sampleEngine.applyFilter` directly — the session owns scoped dispatch. The UI only calls `session.*`.

#### 2c. Preset browser republishes snapshot
- Eliminate `LiveMutationImpact.documentOnly` as an option for audible-state writes. Retain it only for genuinely non-audible metadata; assert at the mutation call site.
- `writeStateBlob` commits via `.scopedRuntime(.auState(trackID, blob))` — recompiles the destination descriptor and republishes the snapshot inside the mutation call, not after the debounce flush.
- Destination swap (different AU component) uses `.fullEngineApply` because it requires `setDestination`.

#### 2d. Mixer / inspector authority (absorbs the cleanup plan)
- Add `session.setTrackMix(trackID:mix:)` — writes the live store immediately AND calls the scoped `engineController.setMix`. Schedules the normal debounce flush.
- `MixerView.updateLevel`, `updatePan`: call `session.setTrackMix` on every drag tick. Remove direct `engineController.setMix` calls from UI.
- `InspectorView` mixer section: identical migration.
- `session.setTrackMute(trackID:mute:)`: writes the live store; may use a broader engine path initially.
- `commitLevel` / `commitPan` become no-ops (or are removed if only UI state cleanup remains).
- The cleanup plan's mixer-authority test requirements fold into `MixerDragLiveWritesTests`.

#### 2e. `.fullEngineApply` stops double-compiling
- `SequencerDocumentSession.mutateProject(impact: .fullEngineApply)` calls exactly one of `apply(documentModel:)` or `publishSnapshot()`. `apply(documentModel:)` is the canonical path for `.fullEngineApply` because it already compiles a snapshot internally.
- `EngineController.apply(documentModel:)` is audited: no redundant snapshot compile on a path about to replace the snapshot.

#### 2f. Self-origin flush guard
- `SequencerDocumentSession` sets a `selfOriginatedFlushInFlight` flag across `flushToDocument`.
- `ingestExternalDocumentChange` early-returns when the flag is set.
- Removes reliance on `replaceProject` returning `false` for equal values.

### Phase 3 — Concurrency and flush

#### 3a. Fix `currentPlaybackSnapshot` race
- Preferred: wrap the snapshot in `final class PlaybackSnapshotBox` and hold it in `ManagedAtomic<PlaybackSnapshotBox>` — reference-swap on publish, atomic load on tick.
- Fallback if swift-atomics is unavailable: guard all reads and writes with `withStateLock`. Acceptable on the clock thread for the granularity involved.
- Add `PlaybackSnapshotConcurrencyTests` run under thread-sanitizer.

#### 3b. Save flush hook
- Migrate `SeqAIDocument` to `ReferenceFileDocument` if its `FileDocument` value-type shape is incompatible with synchronous flush.
- `fileWrapper(snapshot:configuration:)` (on `ReferenceFileDocument`) or an AppDelegate observer on `NSDocument` save calls `session.flushToDocumentSync()` before encoding.
- `applicationWillTerminate` and `applicationDidResignActive` walk the session registry and flush each session.
- Add `SaveFlushTests` and `TerminateFlushTests`.
- Add `DebounceSemanticsTests` for cancel-on-re-edit.

### Phase 4 — Dead code removal and test hardening

#### 4a. Delete `MacroCoordinator`
- Any behaviour exercised by `MacroCoordinatorTests` / `MacroCoordinatorMacroParamTests` is first ported into `SequencerSnapshotCompilerSemanticsTests`.
- Delete `Sources/Engine/MacroCoordinator.swift`.
- Remove the instantiation in `EngineController` (constructor + property).
- Delete both test files.

#### 4b. Delete `noteProgram` text-param vestige
- `EngineController.sourceParams(for:in:)` drops the `"noteProgram": .text("")` entry.
- `NoteGenerator.apply` drops the text-param decode branch; remove the `noteProgram` field.
- Verify `ExecutorPreparedNotesTests` still exercises the typed injection path.

#### 4c. Rewrite thin test suites
- `EventQueueInvalidationTests`: running-transport leak scenario.
- `EngineHotPathIsolationTests`: spy on `apply(documentModel:)` via a counting/ logging `EngineController` stand-in.
- `SequencerSnapshotCompilerSemanticsTests`: add generator / modifier / bypass / override-precedence cases.
- `SequencerDocumentSessionAuthorityTests`: add snapshot-publication assertion and debounce-cancel assertion.
- `LiveSequencerStoreResidentStateTests`: replaces the prior single-case `LiveSequencerStoreOwnershipTests`; verify full roundtrip matrix (1a list).

## Test Plan

Phase gates:

- Phase 1 ships with all Phase 1 guardrail suites green and the tick path panic-on-`Project`-read wrapper active in test builds.
- Phase 2 ships with Phase 1 + Phase 2 suites green, including the absorbed cleanup-plan mixer authority cases.
- Phase 3 ships with Phase 1/2/3 suites green plus a clean thread-sanitizer run over `PlaybackSnapshotConcurrencyTests`.
- Phase 4 ships with the full suite, `MacroCoordinator` removed, and prior thin suites rewritten to assert their stated invariants.

Manual signals at the end of each phase:

- Phase 1: open two documents, edit each, confirm transport in one does not affect the other; macro picker on the AU that previously crashed.
- Phase 2: rapid phrase taps under Instruments show no `apply(documentModel:)` call; fader drag shows live-store writes every update; preset apply reflects in playback without a debounce delay.
- Phase 3: save within 150ms of an edit and confirm the edit is on disk; force-quit; relaunch; confirm no lost work.
- Phase 4: full build passes with dead code removed.

## Assumptions

- This remediation supersedes the prior V2 implementation slice. Work is landed as new commits on `codex/live-sequencer-store-v2`; prior commits are not rebased or reverted.
- The authority cleanup plan (`2026-04-23-live-store-authority-cleanup.md`) is absorbed into Phase 2d.
- `MacroCoordinator` has no behaviour the snapshot compiler cannot express. If that proves false, port the behaviour before deletion.
- `ReferenceFileDocument` migration is acceptable. If it introduces `DocumentGroup` regressions, the flush hook moves to an AppDelegate `NSDocument` save observer.
- Per-document `EngineController` does not change the audio device model — one output device per app session. Multi-document mix routing is out of scope.
- swift-atomics (`ManagedAtomic`) is an acceptable dependency. If not, use `os_unfair_lock` / `withStateLock` with a measured overhead budget on the clock thread.
- `LiveMutationImpact.documentOnly` can be removed without breaking non-audible metadata paths; if a genuinely non-audible path needs it, retain the case with a compile-time assertion at the call site.
