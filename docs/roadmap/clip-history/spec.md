# Clip History Spec

## Status

Ready for build. Architecture review approved 2026-04-29. The build target was
reconciled on 2026-05-21 after the rejected merged modal UX review.

Authoritative UI direction:
[`prototypes/clip-history-dual-grid-v4.html`](prototypes/clip-history-dual-grid-v4.html).
The earlier merged modal on `main` is explicitly not accepted as complete
because it saved the latest buffer rather than letting the user choose a frozen
history region and commit it to a destination slot.

---

## 1. Purpose

Clip History lets a musician running a generator-driven track capture generated output they heard and save it as a real clip in a pattern slot. The workflow bridges live generative exploration and predictable authored arrangement without requiring the user to manually recreate a generated phrase.

---

## 2. User Stories And Acceptance Criteria

### 2.1 Capture A Good Generated Moment

- **As a:** musician running a generator on a track
- **I want:** to open clip history from the generator view in one action
- **So that:** I can reach recent generated output immediately after hearing something I like
- **Accepted when:** the generator-source panel contains a clearly labelled "Clip History" button that opens the history modal for the current track

### 2.2 Review Recent Generated Output

- **As a:** musician deciding whether generated material is worth keeping
- **I want:** to see notes produced by the track's generator chain over the recent 16 bars
- **So that:** I can choose from what actually played rather than guessing from memory
- **Accepted when:** the modal presents the frozen 16-bar history as a 4x4 source matrix with enough activity preview to choose a musical moment, and the view does not drift while the modal is open

### 2.3 Audition History As A Predictable Clip

- **As a:** musician moving from generative exploration to arrangement
- **I want:** playback to switch to a virtual clip made from the selected historical region
- **So that:** I can hear the captured material as a repeatable phrase before committing it
- **Accepted when:** pressing "Audition" with a bar selected causes the track to play the virtual clip repeatedly instead of running the live generator; stopping audition returns the track to live generator behavior

### 2.4 Adjust The Capture Length

- **As a:** musician shaping a captured phrase
- **I want:** to change the virtual clip length
- **So that:** I can capture a half-bar, one bar, two bars, or four bars without leaving the modal
- **Accepted when:** the length control updates the highlighted history range and the audition clip preview reflects the new length

### 2.5 Save History To A Pattern Slot

- **As a:** musician committing generated material
- **I want:** to choose a pattern slot and save the virtual clip there
- **So that:** the captured material becomes a real clip in the track's pattern workflow
- **Accepted when:** clicking an empty pattern slot with a virtual clip ready saves the clip and closes the modal with a toast confirmation; the slot is now marked as occupied

### 2.6 Avoid Accidental Loss Or Overwrite

- **As a:** musician saving into existing pattern structure
- **I want:** the modal to make slot state and save consequences explicit
- **So that:** I do not overwrite useful clips by accident
- **Accepted when:** occupied slots are visually distinct from empty slots; saving to an occupied slot requires an explicit replace action before the write occurs

---

## 3. Chosen UX Direction

The selected prototype is
[`prototypes/clip-history-dual-grid-v4.html`](prototypes/clip-history-dual-grid-v4.html).
The modal approach remains correct, but the accepted interaction is the v4
source-to-destination transfer model. `clip-history-modal-v1.html` and the
merged 2026-05-04 modal are historical references only.

### 3.1 Click Path

1. User is viewing the generator-source panel for a track with an active generator.
2. User presses "Clip History..." button in the generator-source panel (one action).
3. The Clip History modal opens, showing the frozen 16-bar history as a 4x4 source matrix for that track.
4. User clicks a history cell to select it (one action). The virtual clip preview populates.
5. User optionally changes the length control. The range highlight and preview update.
6. User presses "Audition" to hear the virtual clip looping (one action). The track plays the pseudo-clip instead of the live generator.
7. User presses "Stop" or clicks another bar to end audition.
8. User clicks a matching pattern-slot cell in the destination matrix (one action).
   - If the slot is empty: "Save to slot" button enables; user presses it.
   - If the slot is occupied: overwrite confirmation row appears; user presses "Replace" or cancels.
9. The clip is written to the chosen pattern slot. The modal closes with a toast.

Maximum click depth for the happy path (empty slot): 4 actions from the generator view to a committed save.

### 3.2 Modal Structure

The modal has four conceptual regions:

- **Modal title bar**: track name, close button.
- **Recent History source matrix**: 16 frozen history regions in a 4x4 grid. Empty regions are distinguished by dashed/quiet treatment; populated regions show note/activity previews. Selecting a cell marks the selected source and any in-range cells if clip length exceeds one bar.
- **Pattern Slots destination matrix**: 16 destination slots in a matching 4x4 grid with equal visual weight to the source matrix. Occupied slots display a distinct color and used/clip-name state.
- **Virtual clip preview**: shows the materialized temporary clip, length control (`8 steps`, `1 bar`, `2 bars`, `4 bars`), and Audition / Stop if the engine gate supports audition. It must clearly read as temporary and non-mutating until save.
- **Footer / confirmation**: Cancel and "Save to slot" controls. Save is disabled until a history source and destination slot are both selected and, for an occupied slot, replacement has been confirmed.

### 3.3 History Freeze Behavior

When the Clip History modal opens, the engine takes a snapshot of the current state of the capture buffer. The modal displays this snapshot. While the modal is open, the engine continues to capture incoming notes into the ring buffer, but the modal's displayed history does not update. The frozen snapshot remains stable throughout the modal session. Live-follow and refresh-to-latest behavior are deferred.

---

## 4. Model Changes

### 4.1 No New Document Model Types

The feature does not introduce new document schema types. The feature creates
standard `ClipContent.noteGrid` clips in existing pattern slots from the
selected frozen virtual clip. No document migration is required.

### 4.2 Pseudo-Clip Runtime State (New)

A transient `PseudoClipState` object must be defined in the engine or a modal-scoped view-model. It is not persisted.

```
PseudoClipState
  sourceTrackID: TrackID
  startStep: Int          // offset into the frozen capture snapshot
  lengthSteps: Int        // selected clip length in steps
  noteGrid: ClipContent   // materialized from the snapshot on demand
```

This object is created when the modal opens and is discarded when the modal closes (by cancel, save, or window dismiss). It must not be stored on the document or any long-lived controller.

### 4.3 Capture Semantics: Post-Modifier Output

The rolling capture buffer records resolved note events after the source and modifier chain have been evaluated. This is the "what the user heard" contract. The spec states this explicitly so the implementation does not need to resolve it at build time. If the existing `capturedClipContent` implementation does not match this contract, the discrepancy must be surfaced as a build-time finding before the UI is built.

---

## 5. Engine Changes

### 5.1 Buffer Size (Required Prerequisite)

**This is a prerequisite that must be completed before any Clip History UI work can ship.**

The current capture buffer defaults to 64 steps. A 16-bar history at 16th-note resolution requires 256 steps. The buffer size must be raised to at minimum 256 steps, or made configurable with 256 as the default.

Performance and memory implications of this change must be assessed by the implementation team before the change is made. If there is a cost, it must be acceptable before the feature moves forward.

The buffer size constant is at `Sources/Engine/EngineController.swift:21`.

### 5.2 Capture Buffer Snapshot API

The engine must expose a method to take a point-in-time snapshot of the capture buffer for a given track. The snapshot is a separate copy so that the modal can read it safely while the engine continues writing to the live ring buffer.

Conceptual interface:

```
captureSnapshot(trackID: TrackID) -> CaptureSnapshot
```

where `CaptureSnapshot` holds an ordered array of step buckets representing the most recent N steps of generated note output for that track. This read must follow the same thread/actor contract as the existing `capturedClipContent(trackID:lengthSteps:)` call.

### 5.3 Pseudo-Clip Audition Override

The engine must support a per-track audition override. When a `PseudoClipState` is set for a track, the engine plays that clip's `noteGrid` in a loop instead of running the track's live generator chain.

Conceptual interface:

```
setAuditionOverride(_ state: PseudoClipState?, for trackID: TrackID)
```

Setting the override to `nil` restores live generator behavior. This flag must not touch the document. It must be cleared whenever the modal closes.

This capability is architecturally unconfirmed. The implementation team must verify that a thin runtime flag is sufficient or flag the cost if broader changes to the playback dispatch path are required.

### 5.4 No Changes To Save API

The save path must persist the materialized virtual clip chosen from the frozen
snapshot. It must not re-read "latest" rolling capture at save time. If the
existing `saveRollingCapture(...)` API only saves the latest buffer window, add
or reuse a session/document mutation that writes the selected `ClipContent`
into the chosen pattern slot.

---

## 6. UI Changes

### 6.1 Generator-Source Panel Entry Point

Add a "Clip History..." button to the generator-source panel inside `GeneratorParamsEditorView` (approximate location: `Sources/UI/TrackSource/TrackSourceEditorView.swift:240`). The button is only shown for tracks with an active generator source. It opens the Clip History modal.

### 6.2 Clip History Modal (New)

A new modal view must be built according to the v4 structure described in
section 3.2.

The modal is scoped to a single track and displays that track's frozen history snapshot.

Subcomponents:

- **HistoryMatrixView**: 4x4 frozen source matrix, history-cell selection, in-range highlight, and note/activity previews derived from the capture snapshot.
- **VirtualClipPreviewView**: note-blob display for the materialized pseudo-clip, length selector, Audition / Stop buttons, playback state badge.
- **PatternSlotDestinationView**: matching 4x4 destination matrix, occupied / empty visual states, selected-save highlight, inline overwrite confirmation row.
- **Modal footer**: Cancel and Save actions.

### 6.3 Occupied-Slot Visual Treatment

Pattern slot chips in the modal's slot picker must show:
- a distinct border color for occupied slots (green in the prototype)
- a "USED" label or equivalent on occupied chips
- the clip name if a name is available

This treatment must not affect slot chips outside the modal.

---

## 7. Persistence And Migration

| What | Persisted | When |
|------|-----------|------|
| Rolling capture buffer | No | Memory only; cleared on transport stop or document load |
| Capture snapshot (modal session) | No | Modal lifetime only; discarded on close |
| Pseudo-clip state | No | Modal lifetime only; discarded on close |
| Pattern slot assignment | Yes | Only on explicit user save action |
| New clip content | Yes | Created in the document at save time via existing API |

No new document schema. No migration required. The feature creates standard clips in existing pattern slots.

---

## 8. Testing Requirements

### 8.1 Engine Layer

- Buffer can hold at least 256 steps of captured output per track.
- `captureSnapshot` returns a stable copy that does not update after the call.
- Requesting a snapshot on a track with no capture history returns an empty snapshot without crashing.
- Requesting a snapshot when fewer than 256 steps have been captured returns a partial snapshot.
- Setting and clearing the audition override for a track causes the engine to play the pseudo-clip and to return to the live generator respectively, without touching the document.
- The modal save path writes the selected materialized `ClipContent` to the chosen destination slot.

### 8.2 Model Layer

- A `PseudoClipState` with a given start step and length materializes a note grid matching the expected steps from the snapshot.
- Materializing from a sparse (mostly-empty) snapshot produces a valid note grid without gaps or crashes.

### 8.3 UI Layer

- History modal opens from the generator-source panel for a generator-driven track.
- History modal does not open for non-generator tracks.
- Clicking a bar selects it and updates the virtual clip preview.
- Changing the length control updates the range highlight and virtual clip preview.
- Audition button is disabled until a bar is selected.
- Save button is disabled until both a bar and a slot are selected and (if occupied) the replace action has been confirmed.
- Clicking an occupied slot shows the overwrite confirmation row; clicking an empty slot does not.
- Cancelling the overwrite confirmation deselects the slot and hides the confirmation row.
- Closing the modal with Cancel or the close button clears audition state and leaves the document unchanged.
- Saving to an empty slot creates the clip, closes the modal, and shows a toast.
- Saving via the overwrite path replaces the clip in the occupied slot, closes the modal, and shows a toast.
- The history matrix does not update while the modal is open (frozen snapshot behavior).
- Empty history state is handled: all source cells show as empty, the matrix is still displayed, Audition and Save buttons remain disabled.

### 8.4 Missing Coverage From Existing-State Report

The following coverage is absent and must be added:

- Rolling window size for 16-bar history.
- Saving multi-step and sparse generated history.
- Clipping or padding behavior when requested length exceeds available history.
- Post-modifier versus pre-modifier capture semantics.
- UI flow for opening history, changing length, auditioning, and saving.
- Occupied-slot overwrite and cancel.

---

## 9. Open Questions And Unresolved Decisions

### 9.1 Overwrite Semantics

The architecture review approved the following policy:
- empty slots save immediately on "Save to slot";
- occupied slots require an explicit replace action.

The destructive confirmation label is **Replace**. When an occupied slot is
selected, show an inline confirmation row identifying the existing clip where
possible. Keep the footer "Save to slot" button visible but disabled until the
user confirms replacement. Cancel clears the destination selection and hides the
confirmation row.

### 9.2 Pseudo-Clip Audition Override Interface

The old `auto/roadmap-1-clip-history` branch reports a thin runtime override as
feasible and has tests for it. A fresh build loop should re-validate this
against current `main` before wiring production UI.

### 9.3 Default Selected Bar

The notes and stories do not specify which bar is pre-selected when the modal opens: the most recent bar, the currently playing bar, or no bar (user must click). The prototype defaults to no selection. That is likely the right default, but it has not been explicitly confirmed. The implementation should treat no pre-selection as the default.

### 9.4 History Window Configurability

The 16-bar window is fixed in the first version. The notes flag that the user may want a configurable window. This is deferred.

### 9.5 Capture Semantics Confirmation

Section 4.3 states that capture records post-modifier note output. This should be confirmed against the actual `capturedClipContent(trackID:lengthSteps:)` implementation before the UI is built. If the existing API captures pre-modifier output, the spec's intent must be revisited.

### 9.6 Scrollable vs Fixed 16-Bar Strip

The architecture questions list whether the 16-bar history region selector should be scrollable or fixed. The prototype uses a fixed 16-column strip. For the first version, the fixed strip is the correct choice. Scrollable or paginated views are deferred.

---

## 10. Non-Goals (First Version)

- Persisting the capture buffer to disk. Clip history is a live-session convenience.
- Exposing clip history from tracks without an active generator.
- Capturing parameter automation, pitch-bend, or non-note events.
- A new document model type for virtual clips requiring schema migration.
- Surfacing clip history outside the generator-view entry point.
- Live-follow mode: history matrix does not refresh while the modal is open.
- Configurable history window length (16 bars is fixed).
- Undo/redo for the save action in the first version (deferred to be assessed in the build plan).

---

## 11. Risks

1. **Buffer size change is a hard prerequisite.** Raising the capture buffer from 64 to 256 steps may have performance or memory implications. This must be assessed and confirmed safe before any other work begins.

2. **Pseudo-clip audition override cost is unknown.** The engine change required to substitute a pseudo-clip for a live generator during audition has not been verified as a thin change. If it requires broad playback dispatch refactoring, it may need to be scoped out of the first version.

3. **Rematerialization cost on length change.** When the user moves the length control, the pseudo-clip's note grid must be rematerialized from the snapshot. If this is expensive, the UI will need debouncing. This is unknown until buffer read cost is measured.

4. **Empty and partial history.** The modal may open when the buffer has fewer steps than 256 (transport just started, or history was cleared). The modal must handle this state explicitly. An explicit empty-state design is required.

5. **Thread safety of snapshot read.** The capture snapshot must be read safely across the engine's thread boundary. The implementation must follow the same actor contract as the existing `capturedClipContent` call.

---

## 12. Dependencies And Prerequisite Work

| Prerequisite | Owner | Notes |
|---|---|---|
| Raise capture buffer from 64 to 256 steps | Engine team | Must be complete and assessed before UI work begins |
| Confirm post-modifier capture semantics in `capturedClipContent` | Engine team | Must be confirmed before audition spec is finalized |
| Confirm pseudo-clip audition override feasibility | Engine team | Must be confirmed before audition UI is built |
| Overwrite confirmation copy and button state | PM / UX | Minor UX pass needed before save-flow implementation |
