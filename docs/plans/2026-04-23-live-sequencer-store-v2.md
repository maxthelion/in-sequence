# Live Sequencer Store V2 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rebuild the live sequencer runtime on top of the corrected `main` baseline: `ClipContent.noteGrid` is canonical, clip notes are the source material, phrase/clip macro automation are first-class, sampler-filter and AU preset features already exist on `main`, and the new runtime must provide low-latency editing and playback without reintroducing split-authority or thread-ownership bugs.

**Architecture:** A per-document `SequencerDocumentSession` owns a single mutable `LiveSequencerStore` for hot editing. The store compiles immutable playback snapshots from the canonical `noteGrid` clip model plus phrase layers, pattern banks, macros, sampler filter settings, and AU destinations. The engine reads snapshots only; UI mutates live state only; the persisted `Project` is a debounce/flush target rather than the hot interaction model. Runtime handoffs across audio/main/tick threads are explicit and single-owner.

**Tech stack:** Swift 5.9+, SwiftUI, AVAudioEngine, CoreMIDI, XCTest, xcodegen.

**Parent spec:** `docs/specs/2026-04-18-north-star-design.md`

**Recovery context (completed before this plan):**
- rescued note-grid clip/source baseline from dirty `main`
- harvested `feat/track-macro-parameters` onto that baseline
- harvested `feat/sampler-filter` onto that baseline
- harvested AU preset browser + hardening onto that baseline
- validated the corrected baseline with `xcodebuild test`

**Status:** Not started. This plan replaces the earlier live-store attempt as the implementation target.

**Reference-only prior work (do not merge directly):**
- `feat/live-sequencer-store` at `54a0f12`
- `fix/snapshot-event-queue-drain` at `018e034` (use the invalidation idea, not the old model assumptions)

**Non-negotiables carried forward from recovery and review:**
- `LiveSequencerStore` must compile from `ClipContent.noteGrid`, not legacy `stepSequence` / `pianoRoll` runtime assumptions.
- Clip playback semantics remain “clip emits source notes first; modifier/pitch processing happens after source resolution.”
- Snapshot swaps must invalidate already-prepared future events so toggling a step off cannot leak one stale trigger.
- Hot sequencer editing must have one authority. Normal edits may not go `UI -> document.project -> import back into live store`.
- Runtime ownership must be explicit for:
  - `TrackMacroApplier`
  - `SamplerFilterNode`
  - `SamplePlaybackEngine`
  - AU parameter writes / preset writes / AU window lifecycle
- AU preset and AU window writes must travel through the same canonical live-state mutation path as other destination edits.

---

## Corrected Baseline Assumptions

Before starting implementation, assume the following are already true on `main` and must be preserved:

- `ClipContent.noteGrid(lengthSteps:steps:)` is the canonical authored clip format.
- Compatibility decode from legacy `stepSequence` / `pianoRoll` payloads remains in place at the document boundary.
- `StepAlgo` has already been simplified to the current Euclidean-only model.
- `GeneratedSourceEvaluator` already treats clip material as source notes, not as a trigger-mode special case.
- Track macros exist and include phrase-layer automation plus clip macro lanes.
- Sampler filter settings live on `StepSequenceTrack`, not on `Destination`.
- AU preset browser and related AU hardening exist on `main`.

If code encountered during implementation contradicts these assumptions, stop and reconcile the baseline before continuing.

---

## File Structure

Expected major additions / modifications for V2:

```text
Sources/App/
  SequencerDocumentSession.swift            NEW
  SequencerAIApp.swift                      MODIFIED
  SequencerAIAppDelegate.swift              MODIFIED (flush / shutdown hooks only if needed)

Sources/Engine/
  LiveSequencerStore.swift                  NEW
  PlaybackSnapshot.swift                    NEW
  SequencerSnapshotCompiler.swift           NEW
  ClipBuffer.swift                          NEW
  PhrasePlaybackBuffer.swift                NEW
  TrackSourceProgram.swift                  NEW
  EngineController.swift                    MODIFIED
  EventQueue.swift                          MODIFIED
  Executor.swift                            MODIFIED if typed prepared-note path is retained
  Block.swift                               MODIFIED if typed prepared-note path is retained

Sources/Audio/
  TrackMacroApplier.swift                   MODIFIED
  SamplePlaybackEngine.swift                MODIFIED
  SamplerFilterNode.swift                   MODIFIED
  AudioInstrumentHost.swift                 MODIFIED if AU ownership/handoffs need reshaping

Sources/UI/
  ContentView.swift                         MODIFIED
  TrackDestinationEditor.swift              MODIFIED
  TrackSource/TrackSourceEditorView.swift   MODIFIED
  TrackSource/Clip/ClipContentPreview.swift MODIFIED
  PhraseWorkspaceView.swift                 MODIFIED
  LiveWorkspaceView.swift                   MODIFIED

Tests/SequencerAITests/
  App/SequencerDocumentSessionTests.swift           NEW
  Engine/LiveSequencerStoreTests.swift              NEW
  Engine/SequencerSnapshotCompilerTests.swift       NEW
  Engine/EngineControllerSnapshotPlaybackTests.swift NEW
  Engine/EventQueueInvalidationTests.swift          NEW
  Audio/TrackMacroApplierOwnershipTests.swift       NEW
  Audio/SamplePlaybackEngineThreadingTests.swift    NEW
```

---

## Task 1: Lock runtime ownership before introducing new live state

**Why first:** The adversarial review was right that the old attempt blurred ownership across main/tick/audio paths. V2 must define those rules before adding another live-state layer.

- [ ] Define the single-writer rule for each hot subsystem in code comments and implementation:
  - `TrackMacroApplier`
  - `SamplerFilterNode`
  - `SamplePlaybackEngine`
  - AU parameter / preset / window writes
- [ ] Replace “implicit main-thread assumption” patterns with explicit handoff helpers or isolated owners.
- [ ] Remove or redesign any fake/self-invented AU observer-token behavior that exists only to placate the API.
- [ ] Ensure `SamplerFilterNode` only mutates `AVAudioUnitEQ` from its chosen owner context.
- [ ] Ensure `SamplePlaybackEngine` graph mutation, track allocation, and filter-node insertion/removal all happen on one declared execution context.
- [ ] Ensure AU preset loads and AU window close/reopen behavior do not bypass the canonical destination mutation path.

**Validation:**
- `TrackMacroApplier` tests still pass.
- sampler filter tests still pass.
- AU preset browser tests still pass.
- no new runtime path directly mutates AU / sample-engine state from both main and tick threads.

---

## Task 2: Introduce `SequencerDocumentSession` and make it the hot-state owner

**Goal:** Replace root-level `document.project` observation as the normal sequencer hot path.

- [ ] Add `SequencerDocumentSession` as a reference-type runtime owner for each open document.
- [ ] Initialize one session per document scene in `SequencerAIApp`.
- [ ] Move hot sequencer writes behind the session.
- [ ] Add debounce-based projection from live state back into `document.project`.
- [ ] Add synchronous flush hooks for save, close, and app termination.
- [ ] Keep non-hot surfaces document-backed only where intentionally deferred.

**Important constraint:** There must not be two normal mutation paths for the same hot state. If a clip edit or phrase macro edit goes through the live store, the UI must not also write the same change straight into `document.project`.

**Validation:**
- session initialization from an existing document produces valid live state
- save / close flushes persist pending edits
- there is no root `.onChange(of: document.project)` driving the normal sequencer hot path anymore

---

## Task 3: Build `LiveSequencerStore` from the corrected note-grid model

**Goal:** Move hot authoring state into one mutable in-memory store that mirrors the real current model.

- [ ] Add `LiveSequencerStore` with resident mutable authoring state for:
  - tracks
  - pattern banks
  - clip pool
  - phrases
  - generator pool descriptors needed for playback
  - macro bindings
  - sampler filter settings
  - destination metadata required for runtime routing
- [ ] Model clip authoring state around the canonical `noteGrid` shape:
  - per-step `ClipStep`
  - main/fill `ClipLane`
  - note payloads
  - clip macro lanes keyed by binding id
- [ ] Preserve compatibility only at import/export boundaries; do not reintroduce runtime dependence on legacy clip cases.
- [ ] Add projection back to `Project` from live state.

**Validation:**
- `Project -> LiveSequencerStore -> Project` roundtrip preserves note-grid clips, clip macro lanes, phrase layers, and pattern source refs
- clip updates do not require whole-project diffing to be visible in the editor

---

## Task 4: Compile immutable playback snapshots from live state

**Goal:** Make playback O(1)-ish indexed reads from compiled resident buffers.

- [ ] Add compiled `ClipBuffer` types derived from `noteGrid`.
- [ ] Add compiled phrase-step buffers carrying:
  - selected pattern slot
  - mute
  - fill
  - phrase macro values
- [ ] Add resolved per-track source programs that point at clips/generators/modifiers without per-tick document traversal.
- [ ] Add `PlaybackSnapshot` as the immutable engine-facing product of the compiler.
- [ ] Compile only the affected pieces on mutation:
  - clip change -> affected clip buffer
  - phrase cell change -> affected phrase buffer
  - pattern source change -> affected track source program
  - macro binding change -> affected track/clip/phrase buffers

**Validation:**
- phrase pattern changes apply at the exact authored step, not only at step 0
- clip macro lane overrides resolve on the correct clip-local step
- snapshot compiler tests cover clip, phrase, and modifier/source resolution

---

## Task 5: Migrate engine playback to snapshots and invalidate stale prepared events

**Goal:** The engine hot path reads snapshots only and cannot leak stale future events after edits.

- [ ] Update `EngineController` to read from `PlaybackSnapshot` instead of traversing `Project`.
- [ ] Integrate snapshot publication from `SequencerDocumentSession`.
- [ ] On snapshot replacement, invalidate or drain any already-prepared future events that no longer match the latest live state.
- [ ] Ensure toggling a step off while transport is running cannot produce one extra stale note.
- [ ] Keep prepared-note transfer typed; do not reintroduce JSON note handoff on the hot path.

**Validation:**
- restore / rewrite the snapshot playback regression test that motivated `fix/snapshot-event-queue-drain`
- repeated step toggles under transport do not emit stale extra notes
- no hot-path `Project` traversal helpers are used during prepare/tick playback

---

## Task 6: Migrate hot UI surfaces to the live store

**Goal:** Hot editing surfaces mutate resident live state immediately.

- [ ] Migrate clip editing UI to `SequencerDocumentSession` / `LiveSequencerStore`.
- [ ] Migrate phrase-layer editing for pattern/mute/fill/macro values to the live store.
- [ ] Migrate track source selection and relevant destination-side AU preset writes to the live mutation path.
- [ ] Keep track destination changes, preset loads, and AU stateBlob writes aligned with the same authoritative write path.
- [ ] Ensure clip macro lane editing is driven from live clip state, not a document rebound.

**Validation:**
- rapid clip step toggles reflect immediately
- clip macro lane edits reflect immediately
- phrase pattern/fill/mute changes reflect immediately
- AU preset application updates both live runtime state and persisted document state through one path

---

## Task 7: Performance gates and review-driven cleanup

**Goal:** Prove that V2 is not only correct, but materially better than the document-driven path.

- [ ] Add targeted `XCTMeasure` coverage for repeated clip-step edits.
- [ ] Add targeted `XCTMeasure` coverage for repeated clip macro-lane edits.
- [ ] Add targeted `XCTMeasure` coverage for repeated `prepareTick` on a representative multi-track phrase.
- [ ] Confirm the editor path does not broad-diff the whole `Project` for each step toggle.
- [ ] Confirm the engine path does not broad-sync audio outputs for clip-only edits.
- [ ] Triage remaining warnings from the adversarial review into:
  - fixed by V2
  - fixed during recovery
  - explicitly deferred

**Validation:**
- `xcodebuild test` green
- no failing snapshot-playback regression
- manual smoke:
  - rapid clip editing while stopped
  - rapid clip editing while playing
  - phrase pattern automation mid-phrase
  - clip macro override over phrase macro default
  - sampler filter macro automation while transport runs
  - AU preset load while switching tracks and reopening the editor window

---

## Explicitly Out of Scope

- paging or windowed residency of clip/pattern data
- a new document schema beyond what the corrected baseline already introduced
- full mixer/routing/library state migration if those surfaces are not part of the hot sequencer edit path
- solving every current concurrency warning unrelated to hot playback/edit ownership

---

## Suggested Implementation Order

1. ownership/handoff rules
2. session + single-authority hot-state boundary
3. live store from `noteGrid`
4. snapshot compiler
5. engine snapshot playback + stale-event invalidation
6. UI migration
7. performance verification and remaining review cleanup

This order is intentional. The previous live-store branch proved that building the snapshot layer before the baseline model and ownership rules are correct leads to a fast architecture tied to the wrong semantics. V2 must keep the architecture benefits while anchoring them to the real current model.
