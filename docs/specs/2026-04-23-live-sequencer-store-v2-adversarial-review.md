# Adversarial Review: codex/live-sequencer-store-v2

Reviewed commits: `b312e01..5b6df6f` on branch `codex/live-sequencer-store-v2` (worktree `.claude/worktrees/main-recovery-integration`). Plan reviewed against: [2026-04-23-live-sequencer-store-v2.md](../plans/2026-04-23-live-sequencer-store-v2.md). Cleanup follow-up acknowledged: [2026-04-23-live-store-authority-cleanup.md](../plans/2026-04-23-live-store-authority-cleanup.md).

## Verdict

This branch lands the scaffolding of V2 — a `SequencerDocumentSession`, a `LiveSequencerStore`, an immutable `PlaybackSnapshot`, and dense `ClipBuffer`/`PhraseStepBuffer`/`TrackSourceProgram` types — and the clip-only snapshot hot path does look plausibly realized. But several plan-level invariants are not. Most of the "phase-one hot path initial writers" (phrase edits, selection, bank slot/source, modifier changes) still round-trip through `engineController.apply(documentModel:)`. The save boundary does not flush the live store, so Cmd-S within 150ms of an edit loses the edit. `currentPlaybackSnapshot` is assigned outside `stateLock` while being read on the clock thread. `MacroCoordinator` is a zombie parallel implementation. The event-queue invalidation test is surface-level. Broadly: a believable V2 skeleton with genuine dual-authority and concurrency holes hiding under the wait-for-cleanup-plan framing.

## Plan-intent scorecard

| Intent | Status | Evidence |
|---|---|---|
| 1. Per-document session owns live store; Project is persistence DTO | Partial | `SequencerDocumentSession` exists but many views still mutate `document.project` directly (`RoutesListView`, `TracksMatrixView`, `SidebarView`, `TrackWorkspaceView`, `WorkspaceDetailView`). |
| 2. Resident dense buffers compiled at edit time | Realized | `ClipBuffer`, `PhraseStepBuffer` (as `TrackPhrasePlaybackBuffer`), `TrackSourceProgram` exist and are compiled. |
| 3. Playback reads `PlaybackSnapshot`, never `Project` | Partial | `resolvedStepNotes` reads `playbackSnapshot.project.*` (`EngineController.swift:1265, 1271, 1285, 1292, 1304, 1313`) — still `Project` traversal, just through the snapshot handle. `prepareTick` also iterates `documentModel.tracks` (l.666) and `documentModel.tracks` for sample dispatch (l.750). |
| 4. Remove per-tick JSON / command-queue note injection | Realized | `liveStepNotes` gone; typed `preparedNotesByBlockID` fast path in `NoteGenerator.tick` (l.59-61). Vestigial `noteProgram: .text("")` param set at `EngineController.swift:1240` is dead but untyped. |
| 5. Remove root `onChange(of: document.project)` playback hot path | Partial | Removed from `ContentView`. But `SequencerDocumentRootView.swift:24` still has `onChange(of: document.project) → session.ingestExternalDocumentChange` which calls `engineController.apply(documentModel:)` on every flush. Every 150ms debounce cycle = full engine apply. |
| 6. Clip editor + pattern slot/source/modifier + phrase layer writers migrated | Partial | Clip editor and source/modifier selection go through session. Phrase layer `setPhraseCell` goes through session with `.snapshotOnly`. BUT `PhraseWorkspaceView` `handleSingleTap`, `openCellEditor`, `insertPhrase`, `duplicatePhrase`, `removePhrase` use `.fullEngineApply` (l.227, 238, 343, 348, 353, 303, 274). |
| 7. Sampler filter + AU preset writers migrated | Partial | Sampler filter uses `.fullEngineApply` (`TrackDestinationEditor.swift:265`), AU state blob uses `.documentOnly` (l.312). Preset commit path writes with `.documentOnly` impact which never publishes a snapshot — new AU state is written to the document but never reflected in `PlaybackSnapshot.project` until a flush + external-change round trip. |
| 8. Phrase pattern automation per-step | Realized | `SequencerSnapshotCompiler.swift:156-171` compiles `patternSlotIndex[stepIndex]` per step. |
| 9. Snapshot replacement invalidates future events | Partial | `apply(playbackSnapshot:)` calls `eventQueue.clear()` and resets `preparedTickIndex`. But the test asserts at `tickIndex: 1` with `now: 0.1` against a stopped controller — the invariant "leak one extra stale note" is never actually exercised under a running transport. |
| — Save / terminate flushes | Partial | `applicationWillTerminate` flushes all. Document close flushes via `onDisappear`. **No explicit save hook** — `FileDocument.fileWrapper` will serialise the stale struct if Cmd-S beats the 150ms debounce. |

## Findings

### 1. [High] Save-on-Cmd-S does not flush the live store — user can lose edits
Location: `Sources/Document/SeqAIDocument.swift:25` (`fileWrapper(configuration:)`) + `Sources/App/SequencerDocumentSession.swift:50-59` (150ms debounce).
SwiftUI's `DocumentGroup` calls `fileWrapper` on the `SeqAIDocument` **struct value** at save time. Between a live edit and the debounce firing, `document.wrappedValue.project` is stale. If the user types, then presses Cmd-S within 150ms, the save writes the pre-edit project. The plan explicitly says: "Save/close always flush live state synchronously into `document.project`." There is no save hook calling `session.flushToDocument()` before serialization.
Fix: observe `NSDocument`'s save notification, override through a `ReferenceFileDocument`, or make `SeqAIDocument.fileWrapper` pull from the session registry.

### 2. [High] `currentPlaybackSnapshot` is written from main thread, read from clock thread, without synchronization
Location: `Sources/Engine/EngineController.swift:115, 330, 651`.
`apply(playbackSnapshot:)` assigns `currentPlaybackSnapshot = playbackSnapshot` **outside** `withStateLock`. `prepareTick` reads it at line 651 also outside the lock. `PlaybackSnapshot` is a struct with `[UUID: ClipBuffer]` and nested dictionaries — non-atomic assignment of a ~many-word struct from main thread while the clock thread reads it is a torn-read race. The stateLock protects the invalidation flags but not the snapshot itself.
Fix: move `currentPlaybackSnapshot` read/write into `withStateLock` or box it in a `ManagedAtomic<PlaybackSnapshotBox>` (reference swap).

### 3. [High] Mixer level/pan drag bypasses the live store entirely
Location: `Sources/UI/MixerView.swift:215, 244`; `Sources/UI/InspectorView.swift:217, 241`.
During a drag (`updateLevel`/`updatePan`), the code calls `engineController.setMix(trackID:mix:)` directly — the live store's `track.mix` is NOT touched until `commitLevel()` / editing-ended. Any snapshot compiled during a drag (e.g. triggered by an unrelated edit) carries stale mix state. The cleanup plan requires "Level and pan writes update the live store immediately" — this is exactly the opposite.
Fix: call `session.setTrackMix` on every update, not just on commit. The cleanup plan's "scoped live mix" was supposed to be wired through the session.

### 4. [High] Phrase matrix taps do a broad engine rebuild on every click
Location: `Sources/UI/PhraseWorkspaceView.swift:227, 238, 274, 303, 343, 348, 353`; `Sources/Document/ProjectDelta.swift:30`.
Every click on a phrase row, cell, or pagination action calls `session.mutateProject(impact: .fullEngineApply)`. The session then calls `engineController.apply(documentModel:)`, which detects `.phrasesChanged` / `.selectedTrackChanged`. `.phrasesChanged` is NOT in the phase-one hot path (`ProjectDelta.swift:30`), so it falls through to `applyBroadSync` — pipeline-shape check + `syncAudioOutputs` + route re-snapshot on every click. And after the `apply(documentModel:)`, the session calls `publishSnapshot()` on top — double work. The plan says phrase-layer edits are a phase-one hot-path writer.
Fix: use `.snapshotOnly` for phrase cell/select/insert/duplicate/remove. Add `.phrasesChanged` to `isPhaseOneHotPath` (the snapshot compiler already absorbs it).

### 5. [High] Preset browser commits with `.documentOnly` and never refreshes the snapshot
Location: `Sources/UI/TrackDestinationEditor.swift:311-335`, `makePresetBrowserViewModel` (l.295-309).
`writeStateBlob` uses `impact: .documentOnly`, which in `mutateProject` case `.documentOnly` (l.95-97) does nothing to runtime. The store is updated and a debounced flush is scheduled, but the snapshot is NOT republished. When the flush eventually writes to `document.project`, the `onChange` handler calls `ingestExternalDocumentChange`, which DOES call `apply(documentModel:)` — so it's eventually consistent, but the engine keeps serving stale AU-state semantics for up to 150ms. The plan requires "AU preset application and AU state writes go through the canonical mutation path and survive save/reopen" — the snapshot compiler's `PlaybackSnapshot.project` will not reflect the new blob during that window.
Fix: either `.fullEngineApply` (to invoke `setDestination` on the host), or extend the LiveMutationImpact with a scoped "AU state refresh" path.

### 6. [High] `MacroCoordinator` is a zombie parallel implementation
Location: `Sources/Engine/MacroCoordinator.swift`; `Sources/Engine/EngineController.swift:96`.
`EngineController` still instantiates a `MacroCoordinator` but never calls it — the layer snapshot now comes from `playbackSnapshot.layerSnapshot`. The class and its ~130 LOC of phrase-walking / per-tick Project traversal are unused dead code, but `MacroCoordinatorTests` (and `MacroCoordinatorMacroParamTests`) continue to exercise it, providing false test coverage. Any behaviour change in the snapshot compiler's phrase-layer evaluation will silently diverge from MacroCoordinator, hiding regressions.
Fix: delete `MacroCoordinator` and its tests, or replace the tests with equivalent `SequencerSnapshotCompilerSemanticsTests` cases.

### 7. [Medium] `EventQueueInvalidationTests` does not prove the stated invariant
Location: `Tests/SequencerAITests/Engine/EventQueueInvalidationTests.swift:5-24`.
The test calls `processTick(0)` with `stepPattern: [false, true]` and asserts no notes at tick 0 (which is trivially true, step 0 is off). Then it swaps the project to all-empty and asserts no notes at tick 1. It never asserts the actual plan invariant: "Toggling a step off while transport is running must not leak one extra stale note." Under the current `processTick` flow, `prepareTick(N+1)` is called at the end of `processTick(N)` — so the future tick's events are ALREADY enqueued. The test never exercises the "user toggles off between prepareTick(N+1) and dispatchTick(N+1)" window. It also never starts the clock, so nothing runs.
Fix: write a test that calls `processTick(N)`, then mutates the snapshot so the next step would be silent, then calls `processTick(N+1)` and asserts that the clip-derived note from the pre-mutation snapshot did NOT leak into `sink.playedEvents`.

### 8. [Medium] `SequencerSnapshotCompilerSemanticsTests` covers only one case, none of modifier/bypass/clip-override
Location: `Tests/SequencerAITests/Engine/SequencerSnapshotCompilerSemanticsTests.swift`.
Plan §3 lists three invariants for this suite: (a) compiler consumes `ClipContent.noteGrid`, (b) source-then-modifier semantics, (c) per-step phrase resolution. Only (a) and (c) are exercised. Source-then-modifier resolution (plan §4 of implementation) and modifier bypass are untested at the compiler level. The test also does not verify the "clip-step override wins over phrase/default" macro precedence claim.
Fix: add cases for `.generator` slot, modifier chain, `modifierBypassed == true`, and clip macro override precedence.

### 9. [Medium] `SequencerDocumentSessionAuthorityTests` does not test the debounce boundary
Location: `Tests/SequencerAITests/App/SequencerDocumentSessionAuthorityTests.swift`.
Test asserts that (1) `document.project` is stale after mutation, (2) `session.project` is fresh, (3) `flushToDocument` projects the change. It does NOT verify: "The same edit must publish fresh runtime state before the document flush boundary" (plan §Early Guardrail Tests, second suite, second bullet) — there is no assertion on `engineController`'s snapshot/runtime at all. The debounce is never tested (no `Task.sleep`, no cancellation check).
Fix: assert on `publishSnapshot` via a spy EngineController; assert that a second rapid mutation cancels the first debounce task.

### 10. [Medium] `mutateProject(.fullEngineApply)` does engine apply AND snapshot publish — double work on every selection
Location: `Sources/App/SequencerDocumentSession.swift:89-97`.
`engineController.apply(documentModel:)` already compiles a snapshot internally (l.320) and clears `preparedTickIndex`. The session then calls `publishSnapshot()` which compiles AGAIN and clears AGAIN. Two snapshot compilations, two `eventQueue.clear()` calls, two `preparedTickIndex = nil`. On every selection click (from `.fullEngineApply` usages in PhraseWorkspaceView, TracksMatrixView, MixerView, TrackDestinationEditor) this is measurable waste.
Fix: `.fullEngineApply` should not call `publishSnapshot()` (apply already compiles); or `apply(documentModel:)` should not compile the snapshot when it's about to be replaced.

### 11. [Medium] Many non-trivial writers still bypass the session
Location: `Sources/UI/TracksMatrixView.swift:58, 86, 93, 99, 136, 348`; `Sources/UI/SidebarView.swift:16, 31, 36`; `Sources/UI/Track/TrackWorkspaceView.swift:116`; `Sources/UI/WorkspaceDetailView.swift:35`.
Direct `document.project.*` mutations in TracksMatrixView for `appendTrack`, `addDrumGroup`, `selectTrack`; in SidebarView for `appendTrack`, `removeSelectedTrack`, `selectTrack`; in TrackWorkspaceView for track-name edit. These edits update the document (which then roundtrips via `onChange` → `ingestExternalDocumentChange` → broad engine apply). The cleanup plan lists "Track selection / add-remove / grouping surfaces" as follow-on, so these are partially fenced, but the plan also says "Do not allow dual hot mutation paths." Track name edits and drum-group creation are not scoped out by the cleanup plan explicitly.
Fix: route these through `session.mutateProject`. At minimum verify they're documented as deferred.

### 12. [Medium] `ingestExternalDocumentChange` triggers a full engine apply on every debounced flush
Location: `Sources/App/SequencerDocumentRootView.swift:24-26`; `Sources/App/SequencerDocumentSession.swift:70-77`.
When the session's own debounce writes `document.wrappedValue.project = store.project`, SwiftUI triggers `onChange(of: document.project)`. The handler calls `session.ingestExternalDocumentChange(newProject)`, which runs `store.replaceProject`. That returns `false` because `store.project == newProject` — but by then `ingestExternalDocumentChange` has already been on a hot path. Worse: if `replaceProject` ever returned `true` here (e.g. sub-struct identity hash differs), it would do `engineController.apply(documentModel:)` on EVERY debounce. The guard is load-bearing but fragile.
Fix: track "self-originated flush" to bypass the `onChange` handler; or remove the `onChange` entirely and have the session be the only authority on ingest.

### 13. [Low] Lingering `"noteProgram": .text("")` param and `JSONDecoder` path in NoteGenerator
Location: `Sources/Engine/EngineController.swift:1239-1242`; `Sources/Engine/Blocks/NoteGenerator.swift:127-141`.
`sourceParams(for:in:)` returns `["noteProgram": .text("")]` — the block is built with an empty-string program, which is benign (NoteGenerator treats empty as "no program"). But both the text param case and the `JSONDecoder` still exist in `NoteGenerator.apply`. The plan says "note/source blocks consume typed `[GeneratedNote]`/`[NoteEvent]`, not text params" — the typed path exists but the untyped fallback was not deleted.
Fix: delete the `noteProgram` text-param case and the `noteProgram` field from `NoteGenerator`. Delete `sourceParams` or at least drop the `noteProgram` entry.

### 14. [Low] `LiveSequencerStoreOwnershipTests` is a single trivial case
Location: `Tests/SequencerAITests/Engine/LiveSequencerStoreOwnershipTests.swift`.
One case. The plan demands: detached import, no mutation of source, AND roundtrip for note-grid clips, source/modifier slot state, phrase data, macro data, sampler filter, destination/AU preset state. Only the "does not mutate source project" part is covered, and only for clip content.
Fix: expand to cover the explicit roundtrip matrix.

### 15. [Low] `EngineHotPathIsolationTests` asserts a thin proxy for "no broad resync"
Location: `Tests/SequencerAITests/Engine/EngineHotPathIsolationTests.swift:25-27`.
The assertion is `sink.destinationCallCount` unchanged. That proves `setDestination` wasn't called — but not that `apply(documentModel:)` wasn't called, nor that `syncAudioOutputs` wasn't called. A regression that calls `applyBroadSync` on a clip edit but happens to short-circuit on pipeline-shape equality would pass this test.
Fix: inject a counting `EngineController` (or spy on `apply(documentModel:)` invocations) rather than asserting on a downstream side effect.

## Test adequacy

- **LiveSequencerStoreOwnershipTests**: one case. Covers ~15% of what the plan lists.
- **SequencerDocumentSessionAuthorityTests**: one case. Does not assert snapshot publication, does not assert debounce semantics, does not assert cancel-on-second-edit.
- **SequencerSnapshotCompilerSemanticsTests**: one case. Covers `.noteGrid` consumption and per-step pattern resolution. Missing: generator source, modifier chain, modifier bypass, clip-step macro override precedence.
- **EngineHotPathIsolationTests**: proxy assertion (`destinationCallCount`) rather than measuring the actual isolation invariant.
- **EventQueueInvalidationTests**: does not exercise a running transport, does not construct a scenario where a note would leak. Asserts "empty stays empty."
- **ExecutorPreparedNotesTests**: proves the typed injection reaches NoteGenerator — genuinely useful, passes for the right reason.

## Deferred by cleanup plan (not findings)

The follow-up `2026-04-23-live-store-authority-cleanup.md` explicitly scopes out: mixer values (level/pan/mute) in MixerView and InspectorView's mixer section; track selection / add-remove / grouping; routes editor/list; remaining document-backed inspector/sidebar helpers. So `RoutesListView`, the drag-time `engineController.setMix` calls, `MixerView.onToggleMute`, `SidebarView.selectTrack/appendTrack/removeSelectedTrack`, and most of `TracksMatrixView` are acknowledged deferred work. They still indicate real dual-authority surface area, and finding #3 (mixer drag bypasses the live store) IS called out as required behaviour in the cleanup plan — so it's both "deferred" and "regressed from the cleanup plan's own requirements."
