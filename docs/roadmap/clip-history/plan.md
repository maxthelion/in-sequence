# Clip History Plan

## Status

PM plan — ready for a fresh build-loop pass.

This plan was reconciled on 2026-05-21. The authoritative UI target is
[`prototypes/clip-history-dual-grid-v4.html`](prototypes/clip-history-dual-grid-v4.html).
The earlier merged modal on `main` and `clip-history-modal-v1.html` are
historical references only. Future implementation must build the v4
source-to-destination transfer model, not the rejected "save latest capture"
flow.

---

## Overview

This plan sequences the Clip History feature from engine prerequisites through UI shipping. The feature is built in four phases. Two prerequisites carry explicit go/no-go gates that must be resolved before downstream phases begin. Each phase lists the concrete tasks, artifacts touched, and acceptance signals that close it.

Resume strategy: the stale branch `auto/roadmap-1-clip-history` contains useful
work (`CaptureSnapshot`, `PseudoClipState`, frozen modal state, overwrite
confirmation, tests), but it is behind current `main` and contains legacy
build-loop artifacts. A new v2 build loop should harvest concepts and tests
from that branch onto a fresh current-main worktree rather than treating the old
branch as merge-ready.

---

## Phases

### Phase 0 — Prerequisites (gated)

Both prerequisites in this phase must pass their go/no-go gate before any UI work begins. The results of each gate must be written up as a build-time finding and shared with the PM before the next phase starts.

---

#### 0-A. Buffer Size Gate

**What it is.** Raise the rolling capture buffer from 64 steps to 256 steps (16 bars at 16th-note resolution) or make it configurable with 256 as the default.

**File.** `Sources/Engine/EngineController.swift:21` — the buffer size constant.

**Tasks.**

1. Read the existing ring buffer implementation to understand how the constant is used and whether changing it is a single-site change or requires allocation changes elsewhere.
2. Instrument or measure memory footprint per track at 256 steps versus 64 steps across a realistic track count.
3. Run a timing check on a large project (many tracks with active generators) to verify no playback regression.
4. Make the change if the performance and memory assessment confirms it is safe.
5. Write a unit test confirming the buffer holds at least 256 steps without data loss.

**Artifacts touched.**

- `Sources/Engine/EngineController.swift` (constant change only, if safe)
- `Tests/SequencerAITests/Engine/EngineControllerTests.swift` (new coverage)

**Acceptance signals.**

- Buffer holds 256 steps at a realistic track count without measurable memory regression.
- Existing engine tests pass unmodified.
- New test verifies 256-step capacity.

**Go / no-go.**

- GO: memory and timing are acceptable. Proceed to Phase 0-B.
- NO-GO: buffer expansion causes unacceptable memory growth or audio thread jitter. Record the finding. Revisit the 16-bar history window target — options are a smaller default window, lazy allocation per track, or compression. Escalate to PM before proceeding.

---

#### 0-B. Pseudo-Clip Audition Override Gate

**What it is.** Confirm that a thin per-track runtime flag is sufficient to substitute a pseudo-clip's note-grid for the live generator chain during audition, without touching the document.

**Conceptual interface.**

```
setAuditionOverride(_ state: PseudoClipState?, for trackID: TrackID)
```

Setting to `nil` must restore live generator behavior. This flag must not propagate to the document.

**Tasks.**

1. Trace the playback dispatch path from `EngineController` through to per-track note scheduling to understand where generator output is selected.
2. Identify the minimal injection point where a runtime flag can substitute a note-grid for generator output.
3. Write up the findings: is a thin flag sufficient, or does it require broader refactoring of the playback dispatch path?
4. If thin: implement the flag and write a test confirming audition override plays the pseudo-clip and clearing the flag restores live generator behavior, without any document mutation.
5. If broad changes are required: estimate the scope, document it as a build-time finding, and escalate to PM. The audition feature may need to be descoped from the first version.

**Artifacts touched.**

- `Sources/Engine/EngineController.swift` (runtime flag only, if thin)
- `Tests/SequencerAITests/Engine/EngineControllerTests.swift` (new coverage)

**Acceptance signals.**

- The playback dispatch path is understood and documented.
- A thin override flag is confirmed as sufficient, OR the scope of broader changes is estimated and documented.
- If proceeding: engine test confirms that setting the override flag plays the pseudo-clip and clearing it returns the track to live generator output, with no document mutation at any point.

**Go / no-go.**

- GO: thin flag is sufficient. Proceed to Phase 0-C then Phase 1.
- NO-GO: broad dispatch refactoring is required and cost is high. Record the finding. Descope audition from the first version. The save flow and history browsing can still ship without audition. PM must confirm descope decision before Phase 1 starts.

**Fallback if audition is descoped.** The first version ships without the Audition / Stop buttons. The modal supports bar selection, length control, and save-to-slot only. Audition is moved to a follow-on roadmap item.

---

#### 0-C. Capture Semantics Confirmation

**What it is.** Confirm that `capturedClipContent(trackID:lengthSteps:)` records post-modifier note output, not pre-modifier generator output.

**Tasks.**

1. Read the implementation at `Sources/Engine/EngineController.swift:607` and the capture step collection at `Sources/Engine/EngineController.swift:39`.
2. Trace whether captured events are drawn from the generator's raw output or from the resolved note events that pass through the modifier chain.
3. Write a build-time finding: post-modifier (matching spec intent) or pre-modifier (spec must be revisited).

**Artifacts touched.** None — this is a read-and-confirm task. If there is a discrepancy, it becomes an open finding for PM review before Phase 2.

**Acceptance signals.** The semantic is confirmed in writing. If pre-modifier, PM is notified before UI is built.

---

### Phase 1 — Engine API Layer

Phase 1 begins after Phase 0 gates have passed (or after the fallback decisions are confirmed). No UI work starts until Phase 1 is complete.

**Prerequisite.** Phase 0-A (buffer at 256 steps) and Phase 0-C (capture semantics confirmed) must both be done. Phase 0-B (audition override) must be either done (thin flag confirmed) or explicitly descoped.

---

#### 1-A. Capture Snapshot API

**What it is.** Expose a method that takes a point-in-time snapshot of the capture buffer for a given track. The snapshot is an independent copy so the modal can read it while the engine continues writing.

**Conceptual interface.**

```
captureSnapshot(trackID: TrackID) -> CaptureSnapshot
```

where `CaptureSnapshot` holds an ordered array of step buckets (up to 256 steps) representing the most recent generated note output for that track.

**Tasks.**

1. Implement `captureSnapshot` following the same actor/thread contract as the existing `capturedClipContent(trackID:lengthSteps:)`.
2. Write unit tests covering:
   - snapshot is a stable copy (engine continues writing; snapshot does not change after the call returns);
   - snapshot on a track with no history returns an empty snapshot without crashing;
   - snapshot when fewer than 256 steps have been captured returns a partial snapshot.

**Artifacts touched.**

- `Sources/Engine/EngineController.swift`
- `Tests/SequencerAITests/Engine/EngineControllerTests.swift`

**Acceptance signals.**

- All three test cases pass.
- Snapshot is confirmed stable: a concurrent engine write does not mutate the returned snapshot.

---

#### 1-B. PseudoClipState Model Object

**What it is.** Define the transient `PseudoClipState` runtime object used by the modal view-model.

**Shape.**

```
PseudoClipState
  sourceTrackID: TrackID
  startStep: Int         // offset into the frozen capture snapshot
  lengthSteps: Int       // selected clip length in steps
  noteGrid: ClipContent  // materialized from snapshot on demand
```

**Tasks.**

1. Define `PseudoClipState` in the engine or a modal-scoped view-model file. It must not be added to any document model type.
2. Implement a `materialize(from snapshot: CaptureSnapshot, startStep: Int, lengthSteps: Int) -> PseudoClipState` helper.
3. Write unit tests covering:
   - materialization from a full snapshot produces the expected step range;
   - materialization from a sparse snapshot produces a valid note grid without crashes;
   - rematerialization on length change (different `lengthSteps`) produces the correct updated grid.

**Artifacts touched.**

- New engine or view-model file for `PseudoClipState` (location to be chosen by implementation team)
- `Tests/SequencerAITests/Engine/EngineControllerTests.swift` or a new test file

**Acceptance signals.**

- Unit tests pass for all three cases.
- `PseudoClipState` is not referenced by any document model type.

---

#### 1-C. Audition Override (conditional on Phase 0-B GO)

**If Phase 0-B was a NO-GO (audition descoped), skip this task entirely.**

**Tasks.**

1. Implement `setAuditionOverride(_ state: PseudoClipState?, for trackID: TrackID)` as confirmed in Phase 0-B.
2. Write unit tests confirming:
   - override plays the pseudo-clip note-grid instead of running the live generator;
   - clearing the override (setting `nil`) restores live generator output;
   - neither action mutates the document.

**Artifacts touched.**

- `Sources/Engine/EngineController.swift`
- `Tests/SequencerAITests/Engine/EngineControllerTests.swift`

**Acceptance signals.**

- Tests pass. No document mutation at any point during override set or clear.

---

### Phase 2 — UX Pass (overwrite copy)

**Prerequisite.** Can run in parallel with Phase 1, or immediately before Phase 3. No engine dependency.

**What it is.** Resolved on 2026-05-21 in spec section 9.1.

**Tasks.**

1. Use `Replace` as the destructive confirmation label.
2. Keep the footer "Save to slot" button visible but disabled while replacement is unconfirmed.
3. Cancel clears the destination selection and hides the confirmation row.

**Artifacts touched (roadmap only).**

- `docs/roadmap/clip-history/spec.md` — close section 9.1 with the confirmed copy and button state.

**Acceptance signals.**

- Section 9.1 of the spec is no longer listed as open. The decision is written in plain language.

---

### Phase 3 — UI Build

Phase 3 begins after Phase 1 is complete and Phase 2 is resolved.

**Prerequisite.** Engine API (Phase 1) complete. Overwrite copy confirmed (Phase 2). Audition descope decision finalized if applicable.

---

#### 3-A. Generator-Source Panel Entry Point

**What it is.** Add or preserve the Clip History entry point in the track-source
editor. In the current app this may be a peer tab/action rather than a button
inside `GeneratorParamsEditorView`; preserve the app's current tabbed source
well direction if it remains the surrounding IA.

**Tasks.**

1. Add the button to the generator-source panel.
2. Button is visible only for tracks with an active generator source.
3. Button tap opens the Clip History modal for the current track.
4. Button does not appear on non-generator tracks.

**Acceptance signals.**

- Button visible on a generator-driven track.
- Button absent on a non-generator track.
- Tapping the button opens the modal scoped to the correct track.

---

#### 3-B. Clip History Modal — Core Structure

**What it is.** Build the modal shell and v4 source-to-destination transfer
regions described in spec section 3.2.

**Subcomponents to build.**

- Modal title bar with track name and close button.
- `HistoryMatrixView`: 4x4 frozen recent-history source matrix, history-cell selection, in-range highlight for multi-bar clip lengths, note/activity previews derived from the capture snapshot. Empty cells use quiet/dashed treatment.
- `VirtualClipPreviewView`: note-blob display for the materialized pseudo-clip; length selector (½ bar, 1 bar, 2 bars, 4 bars); Audition / Stop buttons (or absent if audition was descoped); playback state badge.
- `PatternSlotDestinationView`: matching 4x4 destination matrix, occupied / empty visual states, selected-save highlight, inline overwrite confirmation row (triggered only for occupied slots).
- Modal footer: Cancel button and "Save to slot" button (disabled until bar and slot are selected and any overwrite is confirmed).

**Tasks.**

1. Build each subcomponent independently against fixture data before wiring to live engine state.
2. Wire the modal view-model to the `captureSnapshot` API on open. The snapshot is taken once and not refreshed during the modal session.
3. Implement bar selection: clicking a bar sets the `PseudoClipState` start step and triggers rematerialization.
4. Implement length control: changing length triggers rematerialization and updates the range highlight.
5. Implement the overwrite confirmation row: visible when an occupied slot is selected, hidden otherwise. Confirmation required before "Save to slot" enables.
6. Implement the save action: write the selected materialized virtual clip to the chosen slot, close the modal, and show a toast. Do not re-read latest rolling capture at save time.
7. Implement modal close (Cancel and close button): clears audition override if active, discards `PseudoClipState`, leaves document unchanged.
8. Implement empty history state: all bars show as empty, Audition and Save buttons disabled.

**Acceptance signals (map to spec section 8.3).**

- Modal opens from the generator-source panel for a generator track; does not open for non-generator tracks.
- Clicking a bar selects it and updates the virtual clip preview.
- Changing the length control updates the range highlight and preview.
- Audition button is disabled until a bar is selected (or absent if descoped).
- Save button is disabled until both a bar and a slot are selected and any overwrite is confirmed.
- Clicking an occupied slot shows the overwrite confirmation row; clicking an empty slot does not.
- Cancelling the overwrite confirmation deselects the slot and hides the confirmation row.
- Closing with Cancel or the close button clears audition state and leaves the document unchanged.
- Saving to an empty slot creates the clip, closes the modal, shows a toast.
- Saving via the overwrite path replaces the clip, closes the modal, shows a toast.
- History strip does not update while the modal is open.
- Empty history state: strip displayed, Audition and Save disabled.

---

#### 3-C. Audition Wiring (conditional on Phase 0-B GO)

**If audition was descoped, skip.**

**Tasks.**

1. Wire the Audition button to `setAuditionOverride(_:for:)` on the engine.
2. Wire the Stop button to `setAuditionOverride(nil, for:)`.
3. Confirm the engine returns to live generator behavior immediately on stop.
4. Confirm the override is cleared when the modal closes regardless of how it closes.

**Acceptance signals.**

- Pressing Audition causes the track to play the virtual clip repeatedly.
- Pressing Stop or closing the modal returns the track to live generator behavior.
- No document mutation occurs at any point during audition.

---

### Phase 4 — Polish and Test Coverage

Phase 4 runs after Phase 3 is functionally complete.

---

#### 4-A. Missing Test Coverage

Add all test coverage listed in spec section 8.4 that was not already added in earlier phases.

**Coverage to add (if not already present).**

- Rolling window size holds 256 steps per track.
- Saving multi-step and sparse generated history produces a valid note-grid clip.
- Clipping or padding behavior when the requested length exceeds available history.
- Post-modifier versus pre-modifier capture semantics (confirmed in Phase 0-C; the test locks it in).
- UI flow: open history, change length, audition (if not descoped), save to slot.
- Occupied-slot overwrite flow: show confirmation row, confirm, save, verify old clip replaced.
- Occupied-slot cancel flow: show confirmation row, cancel, verify no save and no state change.

---

#### 4-B. Debounce / Performance Check On Length Control

When the user moves the length control, the pseudo-clip's note-grid rematerializes from the snapshot. If rematerialization has measurable cost at 256 steps, the UI must debounce or defer the preview update.

**Tasks.**

1. Measure rematerialization time at 256 steps under realistic note density.
2. Add debounce to the length control if needed.

**Acceptance signals.**

- Length control responds without perceptible lag at 256 steps.
- If debounce is added, the preview still updates within 150 ms of the user releasing the control.

---

#### 4-C. Undo / Redo Assessment

Spec section 10 defers undo/redo for the save action. Before shipping, the implementation team must confirm whether the save action integrates naturally with the existing undo stack or requires explicit exclusion. This must be recorded as a build-time finding.

**Acceptance signals.**

- Finding written: undo/redo either works correctly without extra work, is explicitly excluded from the undo stack, or is flagged for a follow-on item.

---

## Dependency Map

| What | Depends On |
|------|-----------|
| Phase 0-B (audition override gate) | none — runs in parallel with 0-A and 0-C |
| Phase 0-C (capture semantics) | none — read-only confirmation |
| Phase 1-A (snapshot API) | Phase 0-A (buffer at 256 steps) |
| Phase 1-B (PseudoClipState) | Phase 0-A, Phase 0-C |
| Phase 1-C (audition override impl) | Phase 0-B GO decision |
| Phase 2 (overwrite copy) | no engine dependency — can run in parallel |
| Phase 3 (UI build) | Phase 1 complete, Phase 2 resolved |
| Phase 4 (polish and tests) | Phase 3 functionally complete |

**Other roadmap dependencies.** No other roadmap items have been identified as prerequisites. The feature does not depend on any in-flight work. Confirm this at build-queue handoff by checking whether any items in the roadmap that touch `EngineController` are actively being built — concurrent edits to that file may cause conflicts.

---

## Deferred Items

The following items are explicitly out of scope for the first version and should not be built during this plan's execution. They are candidates for follow-on roadmap items.

- Configurable history window length (fixed at 16 bars).
- Live-follow mode (history matrix updates while modal is open).
- Audition feature, if Phase 0-B produces a NO-GO.
- Scrollable or paginated history browser (fixed 4x4 source matrix only).
- Capturing parameter automation, pitch-bend, or non-note events.
- Persisting the capture buffer to disk.
- Surfacing clip history from non-generator tracks.
- A new document model type for virtual clips.
- Undo/redo for the save action (assess in Phase 4-C; defer if not trivial).

---

## Testing Strategy

| Layer | What Is Tested | When |
|-------|---------------|------|
| Engine unit tests | Buffer capacity, snapshot stability, partial snapshot, audition override, document non-mutation | Phases 0 and 1 |
| Model unit tests | PseudoClipState materialization, sparse history, length change rematerialization | Phase 1 |
| UI unit / preview tests | Each subcomponent against fixture data before live wiring | Phase 3 |
| Integration tests | Full modal flow: open, select, length change, audition, save (empty and occupied slot) | Phase 3 and 4 |
| Manual sanity | Happy path (generator track → open modal → select bar → audition → save to empty slot), overwrite path, cancel path, empty history state, modal close during audition | Phase 4 |

Manual sanity tests should be run against a project with at least one active generator track, at least one occupied and one empty pattern slot, and in both a transport-running and transport-stopped state.

---

## Open Questions Carried Forward

The following questions from the spec are unresolved and must be answered before or during the phase indicated.

| Question | Phase When It Blocks | Owner |
|----------|---------------------|-------|
| Overwrite confirmation copy and footer button state during overwrite flow | Resolved 2026-05-21: label `Replace`; footer save remains visible but disabled until replacement is confirmed | PM / UX |
| Pseudo-clip audition override interface — confirmed thin or requires broad refactoring | Phase 0-B gate | Implementation team |
| Capture semantics — post-modifier confirmed or discrepancy found | Phase 0-C (before Phase 3 UI is built) | Implementation team |

The question of which bar is pre-selected when the modal opens (spec section 9.3) is treated as resolved: no pre-selection (user must click). This is the default behavior from the prototype and requires no further decision.
