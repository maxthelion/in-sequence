# Resident Live Sequencer Store Plan

## Summary
Replace the current “edit the full `Project`, then let UI + engine diff it” model with a resident live sequencer store for the open document. The saved `Project` stays the serialization format, but it is no longer the hot interaction or hot playback model.

For the open document, keep all sequencer-authoring state resident in memory: clips, pattern banks, phrase layers, and generator source/modifier descriptors. The sequencer reads immutable compiled snapshots from that resident store on each tick, and the UI edits the same logical live state through focused buffer mutations. There is no windowed paging for playback data; the “current window” is just an index into precompiled per-step arrays.

## Implementation Changes
### 1. Introduce a document session and live store
- Add a per-document reference-type session, e.g. `SequencerDocumentSession`, created at the `DocumentGroup` boundary.
- The session owns:
  - the bound `SeqAIDocument`
  - a `LiveSequencerStore`
  - a debounced projector from live state back into `document.project`
- `Project` becomes a persistence DTO plus import/export format, not the primary live state container while a document is open.
- The live store is authoritative during editing; projection back to `Project` happens on:
  - a 150 ms debounce after sequencer edits
  - explicit save
  - document close / app terminate flush
- Hot sequencer views stop binding directly to `document.project`. They read/write through the session/store.

### 2. Use resident dense buffers, not per-tick project traversal
- `LiveSequencerStore` keeps all authored sequencer data resident for the open document:
  - `ClipBuffer` for every clip
  - `TrackPatternProgram` for every track
  - `PhraseStepBuffer` for every phrase
  - generator/modifier descriptors for every referenced source
- `ClipBuffer` is a dense step array, normalized at compile time.
  - Store main/fill lane presence, chance, and note payloads in fixed step arrays.
  - No `.normalized`, `first(where:)`, or clip lookup on the tick path.
- `PhraseStepBuffer` is compiled per phrase and per step.
  - Include at minimum: `patternSlotIndex`, `mute`, `fillEnabled`
  - Include generic macro values in a keyed per-target buffer shape so future macro targets stay on the same architecture
- `TrackPatternProgram` resolves slot-to-source references once and holds direct references/IDs into resident clip/generator buffers.

### 3. Make playback read snapshots, not `Project`
- The engine gets an immutable `PlaybackSnapshot` reference from the live store.
- Tick flow becomes:
  - read current snapshot reference
  - compute `stepInPhrase`
  - index `PhraseStepBuffer`
  - resolve each track’s active slot/source from `TrackPatternProgram`
  - read notes directly from resident clip/generator buffers
- Publishing a live mutation recompiles only affected buffers and swaps the immutable snapshot reference.
- Mutation granularity:
  - clip edit: recompile only that `ClipBuffer`
  - pattern source/slot edit: recompile only the affected track program
  - phrase layer edit: recompile only the affected phrase buffer and dependent track programs
  - generator param edit: recompile only generators/tracks that reference that entry

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

### 6. Change engine/UI wiring
- Remove the root `onChange(of: document.project)` playback hot path for sequencer edits.
- Engine sync for hot sequencer edits becomes revision/snapshot driven from the live store, not whole-project diff driven.
- Keep whole-project apply/diff only for coarse document loads or non-sequencer subsystems that are not yet migrated.
- Initial migrated writers/readers:
  - clip editor
  - pattern slot/source selection that affects playback
  - phrase-layer edits that affect pattern/mute/fill
  - engine tick path
- Non-hot subsystems like routing/mixer/inspector can remain document-backed until a later pass.

## Interfaces / Types
- Add `SequencerDocumentSession`
- Add `LiveSequencerStore`
- Add immutable `PlaybackSnapshot`
- Add dense resident buffer types:
  - `ClipBuffer`
  - `PhraseStepBuffer`
  - `TrackPatternProgram`
- Add typed per-tick source injection into executor/block graph
- Keep `Project` / `SeqAIDocument` as import/export types; they are no longer the primary live editing interface

## Test Plan
- Clip toggle updates the visible step state immediately without requiring a `document.project` root change first.
- Step toggles do not trigger whole-project engine apply/diff on each click.
- Tick path performs no JSON encode/decode for live note transfer.
- Tick path reads from `PlaybackSnapshot`, not from `Project` traversal helpers.
- Phrase pattern automation changes slot selection at the correct step/bar, not only from step 0.
- Fill and mute still resolve correctly from compiled phrase buffers.
- Saving flushes pending live edits into `Project`, and reopening reproduces the same live buffers.
- Add focused performance checks:
  - repeated clip-step toggles stay within a fixed budget
  - repeated `prepareTick` calls do not allocate/serialize per track

## Assumptions and Defaults
- All sequencer-resident data stays in memory for the open document; no paging/window cache is introduced.
- UI paging remains presentation-only; it does not affect playback residency.
- Main thread is the single writer to live sequencer state.
- Engine reads immutable snapshots only; it never mutates authoring buffers.
- Snapshot publication is incremental and pointer-swapped, not full-project rebuilt on every edit.
- Save/close always flush live state synchronously into `document.project`.
- This plan covers sequencer core performance only; AU/sample-host internals stay out of scope except for removing the typed-note handoff bottleneck in the core tick path.
