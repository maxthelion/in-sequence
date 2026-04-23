# Live Sequencer Store V1 Archived Plan

> **Archived reference:** This plan was reconstructed from the design discussion in this thread. It was not previously written into `docs/plans/` and was never the final implementation target. It is preserved here as a historical reference only.

**Superseded by:** [2026-04-23-live-sequencer-store-v2.md](/Users/maxwilliams/dev/in-sequence/.claude/worktrees/main-recovery-integration/docs/plans/2026-04-23-live-sequencer-store-v2.md)

**Original framing from the thread:**
- implementation branch: `feat/live-sequencer-store`
- base branch: `feat/track-macro-parameters`
- dedicated worktree: `.claude/worktrees/live-sequencer-store`

**Why this is archived:** V1 captured the right broad architecture, but it was written before the corrected `main` baseline was re-established. In particular, it predated the recovery of the canonical `ClipContent.noteGrid` model onto `main`, and it did not fully encode the ownership/concurrency constraints later surfaced by adversarial review.

---

## Summary

The intent of V1 was to replace the document-driven hot path with a **resident live sequencer store** for each open document.

The saved `Project` would remain the persistence format, but it would no longer be the hot interaction or hot playback model.

For an open document, all sequencer playback data would stay resident in memory:

- clips as dense step buffers carrying note, velocity, length, chance, and clip-macro overrides
- pattern banks as resolved slot/source programs
- phrases as per-step playback buffers carrying pattern slot, mute, fill, and phrase-macro values
- immutable playback snapshots read directly by the tick path

The UI would edit the live store, not `document.project`. The engine would read immutable snapshots, not the document model. The document would be updated from the store on a debounce and flushed synchronously on save / close / terminate.

Macro automation was explicitly intended to be both **phrase-scoped and clip-scoped**:

- phrase layers provide arrangement-level per-step macro values
- clip macro lanes provide per-step local overrides
- clip macro override wins over phrase value; phrase value wins over macro default

---

## Architectural Intent

### 1. `SequencerDocumentSession`

Add a per-document runtime object to own live sequencer state and mediate between UI, engine, and persisted `Project`.

Intended responsibilities:

- hold the document binding
- own the `LiveSequencerStore`
- debounce projection back into `document.project`
- publish playback snapshots to the engine
- flush synchronously on save / close / terminate

### 2. `LiveSequencerStore`

Move hot authoring state out of the persisted `Project` value and into a focused mutable in-memory model.

Intended live state:

- track order
- clips by id
- pattern banks by track id
- phrases by id
- generator pool entries by id
- macro bindings by track id

### 3. Clip authoring and compiled clip buffers

V1 intended clip editing to be resident and step-based.

Planned authoring shape:

- `EditableClipState`
- `EditableClipStep`
- `EditableClipLane`
- `EditableClipNote`
- clip macro lanes stored as `[UUID: [Double?]]`

Planned compiled playback shape:

- `ClipBuffer`
- `ClipStepBuffer`
- `ClipLaneBuffer`
- `ClipNoteBuffer`

The tick path would index into clip-local step arrays instead of traversing `Project`.

### 4. Phrase-step playback buffers

Compile phrase-layer outputs per phrase, per track, per step into resident buffers carrying:

- pattern slot
- mute
- fill enabled
- macro values aligned to track macro binding order

This was intended to make phrase-driven pattern changes and macro automation O(1)-ish indexed reads at playback time.

### 5. Immutable `PlaybackSnapshot`

The engine-facing runtime would be one immutable compiled snapshot containing:

- track order / ordinals
- clip buffers
- track source programs
- phrase playback buffers
- generator pool data required at playback time

Edits would trigger incremental recompilation of only affected pieces.

### 6. Tick path migration

The engine tick path would:

1. read the current `PlaybackSnapshot`
2. compute the current phrase step
3. resolve the current track phrase state
4. resolve the active source slot
5. if clip source, compute clip-local step and read clip buffer directly
6. evaluate fill vs main lane
7. apply chance
8. emit stored notes
9. resolve macro values by precedence:
   - descriptor default
   - phrase value
   - clip override

### 7. Remove per-tick JSON note handoff

V1 explicitly intended to eliminate the encode -> queue -> decode `liveStepNotes` path.

The replacement idea was a typed prepared-note payload passed through the tick path so live playback would no longer serialize notes into JSON every step.

### 8. Hot UI migration

The clip editor, phrase editing surfaces, and relevant live views would mutate resident state first.

Expected flow:

- mutate the live store
- recompile the affected buffer(s)
- publish a fresh playback snapshot
- schedule a debounced document flush

---

## Intended Major Types

V1 was aiming toward these key runtime types:

- `SequencerDocumentSession`
- `LiveSequencerStore`
- `PlaybackSnapshot`
- `ClipBuffer`
- `PhrasePlaybackBuffer`
- `TrackSourceProgram`

---

## Planned Tasks

### Task 1: `SequencerDocumentSession`

- create one session per document
- own live sequencer state
- publish snapshots to the engine
- debounce projection back into the document
- flush on save / close / terminate

### Task 2: Resident mutable authoring store

- move hot authoring state out of `Project`
- keep tracks, clips, pattern banks, phrases, generators, and macros resident
- support clip macro lane editing directly in the live store

### Task 3: Compiled phrase-step playback buffers

- compile phrase pattern, mute, fill, and macro layers into per-step arrays
- remove step-0-style pattern selection assumptions from the hot path

### Task 4: Immutable playback snapshot and incremental compilation

- compile immutable engine-facing snapshots
- rebuild only affected clip / phrase / track-source pieces on edits

### Task 5: Tick path migration and macro resolution

- stop traversing `Project` on the hot path
- resolve clip and generator sources from compiled resident structures
- apply macro precedence `default < phrase < clip`

### Task 6: Remove per-tick JSON note handoff

- stop serializing notes into text/JSON for live note flow
- use typed prepared-note delivery instead

### Task 7: Hot UI migration

- move clip editing to the live store
- move phrase-layer hot edits to the live store
- stop using root `document.project` changes as the normal sequencer hot path

---

## Test Intent

V1 also had a clear testing story.

Planned coverage included:

- live store mutation tests
- snapshot compiler tests
- snapshot playback tests
- typed prepared-note tests
- session debounce / flush tests
- performance checks for repeated clip-step toggles
- performance checks for repeated clip macro-lane edits
- performance checks for repeated `prepareTick`

Manual smoke goals included:

- rapid clip step toggling
- immediate clip macro lane response
- phrase pattern changes at exact step boundaries
- fill behavior on the correct steps
- clip macro overrides beating phrase defaults
- save / close / reopen preserving live-edited state

---

## Where V1 Was Strong

V1 already had the right broad architectural ideas:

- resident hot authoring state
- immutable playback snapshots
- compiled clip and phrase-step buffers
- typed playback data instead of JSON note handoff
- explicit clip-macro and phrase-macro precedence

These ideas carried forward into V2.

---

## Why V1 Was Superseded

V1 differed from V2 in three important ways:

### 1. Wrong implementation baseline

V1 was written before the corrected `main` baseline was re-established.

It did not explicitly anchor itself to:

- `ClipContent.noteGrid` as canonical authored clip data
- the rescued clip-as-source semantics in `GeneratedSourceEvaluator`
- the recovered `main` integration of macros, sampler filter, and AU preset browser

### 2. Insufficient ownership rules

V1 described the architecture, but it did not put runtime ownership first.

V2 adds an explicit first task around ownership and handoff rules for:

- `TrackMacroApplier`
- `SamplerFilterNode`
- `SamplePlaybackEngine`
- AU parameter / preset / window writes

### 3. Not explicit enough about stale future events

V1 assumed the snapshot approach, but it did not foreground the prepared-event invalidation problem strongly enough.

V2 explicitly requires snapshot replacement to invalidate already-prepared future events so edited steps cannot leak one stale trigger.

---

## Practical Reading

Treat V1 as:

- a useful record of the original resident-store architecture
- evidence that the broad design direction was already understood
- not the implementation target

Treat V2 as:

- the real plan to execute
- the version aligned with the recovered `main` baseline
- the version that incorporates adversarial-review ownership concerns

