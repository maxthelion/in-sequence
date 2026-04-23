# Resident Live Sequencer Store Plan

> **Canonical V2:** This is the implementation target. It is an expression of [2026-04-23-live-sequencer-store-v1-transcript.md](/Users/maxwilliams/dev/in-sequence/.claude/worktrees/main-recovery-integration/docs/plans/2026-04-23-live-sequencer-store-v1-transcript.md) updated for the current `main` baseline: `ClipContent.noteGrid` is canonical, the source/modifier pipeline is explicit, track macros exist, sampler filter exists, and AU preset browser/state flows already exist.

## Summary
Replace the current “edit the full `Project`, then let UI + engine diff it” model with a resident live sequencer store for the open document. The saved `Project` stays the serialization format, but it is no longer the hot interaction or hot playback model.

For the open document, keep all sequencer-authoring state resident in memory: note-grid clips, pattern banks, phrase layers, generator source/modifier descriptors, track macro state, sampler filter settings, and the destination/AU state required for runtime sync. The sequencer reads immutable compiled snapshots from that resident store on each tick, and the UI edits the same logical live state through focused buffer mutations. There is no windowed paging for playback data; the “current window” is just an index into precompiled per-step arrays.

## Guardrails
- Treat this plan and the corrected `main` baseline as the only design authority. Previous live-store branch code is not normative and should not be used to justify shape or semantics.
- The first migrated live-store version must be a real authored-state owner, not a thin wrapper around `document.project`. Import from `Project`, own live state, then project back.
- Do not allow dual hot mutation paths. Once a sequencer surface is migrated, all normal edits for that surface must go through `SequencerDocumentSession` / `LiveSequencerStore`, not directly through `document.project`.
- Do not reintroduce legacy clip/runtime assumptions on the hot path. `ClipContent.noteGrid`, the explicit source/modifier slot pipeline, phrase/clip macros, sampler filter state, and AU preset/state flows on `main` are the semantics to compile from.
- Lock runtime ownership before wiring more live editing into playback. `TrackMacroApplier`, `SamplerFilterNode`, `SamplePlaybackEngine`, and AU parameter/preset/window writes must each have one explicit owner/handoff model.
- Keep the implementation phase-gated:
  - session/store roundtrip and authority tests before snapshot compiler work
  - snapshot compiler tests before engine playback swap
  - engine playback and stale-event invalidation tests before broad UI migration
- Stop and revise if an implementation step requires mirroring the same hot state in both `Project` and `LiveSequencerStore`, or if it needs broad whole-project diff/apply to make a step edit feel correct.

## Early Guardrail Tests
- Add a `LiveSequencerStoreOwnershipTests` suite first.
  - Importing from `Project` must produce detached live state.
  - Mutating live state must not mutate the source `Project` instance before projection/flush.
  - `Project -> LiveSequencerStore -> Project` must roundtrip note-grid clips, source/modifier slot state, phrase data, macro data, sampler filter settings, and destination/AU preset state that belongs in the document model.
- Add a `SequencerDocumentSessionAuthorityTests` suite before broad UI migration.
  - A live clip edit must update session/store state immediately.
  - The same edit must publish fresh runtime state before the document flush boundary.
  - `document.project` must remain unchanged until the debounce or explicit flush fires.
  - Flush must project the exact live edit back into the document.
- Add a `SequencerSnapshotCompilerSemanticsTests` suite before engine playback migration.
  - Compilation must consume `ClipContent.noteGrid` rather than legacy runtime cases.
  - Source/modifier semantics must match the current baseline: source first, modifier second.
  - Phrase step buffers must resolve pattern/mute/fill/macro values at the exact authored step.
- Add an `EngineHotPathIsolationTests` suite before UI migration completes.
  - Live clip edits must publish snapshots without relying on whole-project apply/diff.
  - Clip-only edits must not trigger broad output/host resync behavior.
- Add an `EventQueueInvalidationTests` suite before transport/live-edit signoff.
  - Replacing the snapshot after a live edit must invalidate already-prepared future events that no longer match the latest state.
  - Toggling a step off while transport is running must not leak one extra stale note.

## Implementation Changes
### 1. Introduce a document session and live store
- Add a per-document reference-type session, e.g. `SequencerDocumentSession`, created at the `DocumentGroup` boundary.
- The session owns:
  - the bound `SeqAIDocument`
  - a `LiveSequencerStore`
  - a debounced projector from live state back into `document.project`
  - publication of compiled snapshots and explicit runtime updates to the engine/audio owners
- `Project` becomes a persistence DTO plus import/export format, not the primary live state container while a document is open.
- The live store is authoritative during editing; projection back to `Project` happens on:
  - a 150 ms debounce after sequencer edits
  - explicit save
  - document close / app terminate flush
- Hot sequencer views stop binding directly to `document.project`. They read/write through the session/store.
- Runtime consumers of live state (`EngineController`, `TrackMacroApplier`, `SamplePlaybackEngine`, AU host/preset application) must read from session/store outputs or explicit commands, not ad hoc direct document writes.

### 2. Use resident dense buffers, not per-tick project traversal
- `LiveSequencerStore` keeps all authored sequencer data resident for the open document:
  - `ClipBuffer` for every `ClipContent.noteGrid` clip
  - `TrackPatternProgram` for every track
  - `PhraseStepBuffer` for every phrase
  - generator/modifier descriptors for every referenced source
  - track macro bindings/defaults plus clip-step and phrase-step macro values
  - sampler filter settings and destination/AU preset state needed for runtime sync
- `ClipBuffer` is a dense step array, normalized at compile time.
  - Store main/fill lane presence, chance, note payloads, and clip-step macro overrides in fixed step arrays.
  - No `.normalized`, `first(where:)`, or clip lookup on the tick path.
- `PhraseStepBuffer` is compiled per phrase and per step.
  - Include at minimum: `patternSlotIndex`, `mute`, `fillEnabled`
  - Include phrase-step macro values in a stable keyed/order-preserving buffer shape.
- `TrackPatternProgram` resolves slot-to-source references once and holds direct references/IDs into resident clip/generator buffers.
  - Model the current explicit slot pipeline: one source (`clip` or `generator`) plus an optional modifier (`modifierGeneratorID`, `modifierBypassed`).
  - Source notes are produced first; modifier processing happens after source resolution.
- Destination and AU preset/state data remain authored live state, but host internals are still owned by dedicated runtime controllers.

### 3. Make playback read snapshots, not `Project`
- The engine gets an immutable `PlaybackSnapshot` reference from the live store.
- Tick flow becomes:
  - read current snapshot reference
  - compute `stepInPhrase`
  - index `PhraseStepBuffer`
  - resolve each track’s active slot/program from `TrackPatternProgram`
  - resolve source notes directly from resident clip/generator buffers
  - apply modifier processing after source resolution when present
  - apply macro/filter/runtime updates through their dedicated owners
- Publishing a live mutation recompiles only affected buffers and swaps the immutable snapshot reference.
- Mutation granularity:
  - clip edit: recompile only that `ClipBuffer`
  - pattern source/slot/modifier edit: recompile only the affected track program
  - phrase layer edit: recompile only the affected phrase buffer and dependent programs/views
  - generator param edit: recompile only generators/tracks that reference that entry
  - sampler filter or AU preset/state edit: update the affected runtime descriptors without broad sequencer rebuild
- Snapshot replacement must invalidate any already-prepared future events that no longer match the latest live state.

### 4. Remove per-tick JSON and command-queue note injection
- Eliminate the `liveStepNotes` JSON encode/decode path from tick preparation.
- Replace per-tick `setParam(... .text(JSON))` note transfer with typed source-output injection.
- Preferred shape:
  - `Executor.tick` accepts typed source-output overrides for source blocks for the current tick, or an equivalent typed prepared-frame input
  - note/source blocks consume typed `[GeneratedNote]`/`[NoteEvent]`, not text params
- This keeps the block graph architecture, but removes the current encode -> queue -> decode loop from the hot path.

### 5. Fix the “current window” model explicitly
- Do not implement windowed residency.
- Playback data is fully resident; the runtime “window” is only:
  - current phrase ID
  - current step in phrase
  - per-track active slot index for that step
- Compile phrase pattern selection per step, not only at step 0.
  - Current pattern selection must come from the phrase step buffer, so automated pattern changes across bars/steps are both correct and O(1).
- Clip page selection in the editor remains presentation-only. It never changes playback residency.

### 6. Change engine/UI wiring
- Remove the root `onChange(of: document.project)` playback hot path for sequencer edits.
- Engine sync for hot sequencer edits becomes revision/snapshot driven from the live store, not whole-project diff driven.
- Keep whole-project apply/diff only for coarse document loads or non-sequencer subsystems that are not yet migrated.
- Initial migrated writers/readers:
  - clip editor and clip macro lanes
  - pattern slot/source/modifier selection
  - phrase-layer edits that affect pattern/mute/fill/macro values
  - sampler filter controls that affect playback
  - AU preset browser / AU state writes
  - engine tick path
- Track destination changes, preset loads, and AU `stateBlob` writes that affect runtime behavior must travel through the same authoritative mutation path as the rest of the live state.
- Non-hot subsystems like routing/mixer/inspector can remain document-backed until a later pass.

## Interfaces / Types
- Add `SequencerDocumentSession`
- Add `LiveSequencerStore`
- Add immutable `PlaybackSnapshot`
- Add dense resident buffer types:
  - `ClipBuffer`
  - `PhraseStepBuffer`
  - `TrackPatternProgram`
- Add compact compiled macro/filter/destination runtime descriptors as needed
- Add typed per-tick source injection into executor/block graph
- Keep `Project` / `SeqAIDocument` as import/export types; they are no longer the primary live editing interface

## Test Plan
- Clip toggle updates the visible step state immediately without requiring a `document.project` root change first.
- Step toggles do not trigger whole-project engine apply/diff on each click.
- Tick path performs no JSON encode/decode for live note transfer.
- Tick path reads from `PlaybackSnapshot`, not from `Project` traversal helpers.
- Phrase pattern automation changes slot selection at the correct step/bar, not only from step 0.
- Source/modifier resolution behaves correctly:
  - clip source emits stored note-grid notes first
  - generator source emits generator output first
  - modifier processing happens after source resolution
  - modifier bypass behaves correctly
- Phrase and clip macro automation resolve correctly together:
  - phrase values compile per step
  - clip-step overrides apply on the correct clip-local step
  - clip override wins over phrase/default where both exist
- Sampler filter settings and macro-driven filter changes update the live runtime without whole-project diff/apply.
- AU preset application and AU state writes go through the canonical mutation path and survive save/reopen.
- Snapshot replacement invalidates stale future events so live edits cannot leak one extra trigger.
- Fill and mute still resolve correctly from compiled phrase buffers.
- Saving flushes pending live edits into `Project`, and reopening reproduces the same live buffers.
- Add focused performance checks:
  - repeated clip-step toggles stay within a fixed budget
  - repeated clip macro-lane edits stay within a fixed budget
  - repeated `prepareTick` calls do not allocate/serialize per track

## Assumptions and Defaults
- All sequencer-resident data stays in memory for the open document; no paging/window cache is introduced.
- `ClipContent.noteGrid` is canonical; legacy clip formats are compatibility-only at the document boundary.
- UI paging remains presentation-only; it does not affect playback residency.
- Main thread is the single writer to live sequencer state.
- Engine/tick paths read immutable snapshots only; audio owners consume explicit commands/state handoffs rather than mutating authored state.
- Snapshot publication is incremental and pointer-swapped, not full-project rebuilt on every edit.
- Source mode is explicit: each slot has one source (`clip` or `generator`) and may have one optional modifier.
- Phrase and clip macros both exist; clip-step override wins over phrase-step value, which wins over track/default value.
- Sampler filter settings and AU preset/state are part of the authored live model where they affect runtime behavior, but host internals remain owned by dedicated runtime controllers.
- Save/close always flush live state synchronously into `document.project`.
- This plan covers sequencer core performance and the runtime-adjacent features already on `main`; it does not redesign unrelated app state.
