# Clip History — Implementation Handoff

## Authoritative Context

| Artifact | When to open it |
|---|---|
| [spec.md](spec.md) | Primary build reference. Sections 3–8 define the complete feature contract. |
| [plan.md](plan.md) | Phase sequence, per-phase tasks, go/no-go gates, fallback decisions. Open this first when starting each phase. |
| [architecture.md](architecture.md) | Invariants and guardrails the implementation must preserve. Non-negotiable. |
| [architecture-review.md](architecture-review.md) | User-approved decisions. Overrides any ambiguity in architecture.md where the two differ. |
| [ux-review.md](ux-review.md) | UX direction summary — modal variant chosen, what failed. |
| [prototypes/clip-history-modal-v1.html](prototypes/clip-history-modal-v1.html) | The chosen prototype. Reference for modal structure and visual treatment. |
| [prototypes/clip-history-inline-v2.html](prototypes/clip-history-inline-v2.html) | Rejected direction. Do not use as a reference. |
| [existing-state.md](existing-state.md) | What the engine already provides, where the code lives, and what coverage already exists. |

---

Advisory: [feedback/2026-05-04-built-modal-ux-review.md](feedback/2026-05-04-built-modal-ux-review.md) reopens the Clip History UI direction. Treat the engine prerequisites below as still informative, but do not use this handoff as build-authoritative for the modal IA, click path, or save gating until the prototype rework loop updates the spec and handoff.

---

## Goal

Clip History lets a musician running a generator-driven track capture generated output they just heard and save it as a real clip in a pattern slot. The feature bridges live generative exploration and predictable authored arrangement without requiring the user to manually recreate a generated phrase. The primary user story is: open history from the generator view, see the last 16 bars of generated notes frozen in a modal, select a bar, audition it as a looping virtual clip, and save it to a chosen pattern slot in one clear click path.

---

## Chosen UX Direction

The modal variant (`prototypes/clip-history-modal-v1.html`) was chosen. The inline variant was rejected.

The modal has four stacked regions: title bar, 16-bar history strip, virtual clip preview row (with length selector and Audition/Stop), and a 16-slot pattern slot picker. The save action is in the modal footer. See spec section 3.2 for the full structural definition.

The click path from open to committed save for an empty slot is four actions. See spec section 3.1.

---

## Guardrails and Invariants

These are hard constraints from `architecture.md` and the architecture review. The implementation must preserve all of them.

**1. Document truth is never changed by audition.**
The pseudo-clip played during history review is a transient runtime object. It must not touch the document's pattern-slot array or any persisted model until the user explicitly confirms a save action.

**2. The rolling capture buffer is append-only and monotonically ordered.**
Steps are captured in playback order. No UI action may reorder, delete, or mutate captured history. Buffer reads always specify a length and produce a deterministic slice.

**3. Slot identity is stable during the modal session.**
Pattern slot indices observed when the modal opens are the authoritative save targets for the entire modal session. If a slot is occupied at open time, overwrite must be explicit. The modal must not silently reassign or auto-pick a different slot mid-session.

**4. Capture is post-modifier output.**
The rolling buffer records resolved note events after the source and modifier chain have been evaluated — what the user heard. This must be confirmed against the actual `capturedClipContent` implementation before UI is built (Phase 0-C in the plan). If the existing API captures pre-modifier output, escalate to PM before proceeding with the UI.

**5. Buffer size must cover 256 steps before any UI work begins.**
The current default of 64 steps is insufficient for a 16-bar window at 16th-note resolution. This is a hard prerequisite (Phase 0-A gate).

**6. The history modal shows a frozen snapshot, not a live feed.**
When the modal opens, the engine takes a point-in-time snapshot of the capture buffer. The modal displays this snapshot. While the modal is open, the engine continues capturing into the ring buffer, but the modal's displayed history must not update. Live-follow is deferred.

**7. The pseudo-clip state is scoped to the modal lifetime.**
`PseudoClipState` is created when the modal opens and discarded when the modal closes (cancel, save, or dismiss). It must not be stored on the document or any long-lived controller.

---

## Sequencing and Gates

The plan has five phases with two hard gates. Do not start later phases until gates pass.

### Phase 0 — Prerequisites (all three must complete before Phase 1)

**0-A. Buffer Size Gate (hard gate)**
Raise the capture buffer constant at `Sources/Engine/EngineController.swift:21` from 64 to 256 steps. Measure memory and timing at a realistic track count before making the change.
- GO: memory and timing are acceptable. Proceed.
- NO-GO: buffer expansion causes unacceptable memory growth or audio thread jitter. Escalate to PM. Options: smaller default window, lazy allocation per track, or compression. Do not proceed with UI work until PM confirms a path.

**0-B. Pseudo-Clip Audition Override Gate (hard gate)**
Trace the playback dispatch path and confirm whether a thin per-track runtime flag (`setAuditionOverride(_:for:)`) is sufficient to substitute a pseudo-clip for the live generator, without touching the document.
- GO: thin flag confirmed. Implement it in Phase 1-C.
- NO-GO: broad dispatch refactoring required and cost is high. Escalate to PM. Fallback: ship Phase 3 without the Audition/Stop buttons. History browsing and save-to-slot still ship. Audition moves to a follow-on roadmap item.

**0-C. Capture Semantics Confirmation (read-only task)**
Read `Sources/Engine/EngineController.swift:607` and `:39`. Confirm whether `capturedClipContent` captures post-modifier or pre-modifier output. Write up the finding. If pre-modifier, notify PM before Phase 3 UI is built.

### Phase 1 — Engine API Layer
After Phase 0 gates pass. No UI work until Phase 1 is complete.
- 1-A: `captureSnapshot(trackID:) -> CaptureSnapshot` API.
- 1-B: `PseudoClipState` model object and `materialize(from:startStep:lengthSteps:)` helper.
- 1-C: `setAuditionOverride(_:for:)` engine flag (conditional on Phase 0-B GO).

### Phase 2 — Overwrite Copy UX Pass
No engine dependency. Can run in parallel with Phase 1. PM must confirm the exact label on the destructive action in the overwrite confirmation row ("Overwrite" / "Replace" / "Save anyway") and whether the "Save to slot" footer button is hidden or merely disabled while the confirmation row is visible. This decision must be recorded in spec section 9.1 before the save flow is built.

### Phase 3 — UI Build
After Phase 1 complete and Phase 2 resolved.
- 3-A: "Clip History..." button in `GeneratorParamsEditorView` (approx. `TrackSourceEditorView.swift:240`). Visible only on generator-driven tracks.
- 3-B: Clip History modal — all four regions, bar selection, length control, slot picker, overwrite confirmation row, save action, empty-history state.
- 3-C: Audition wiring to engine override (conditional on Phase 0-B GO).

### Phase 4 — Polish and Test Coverage
After Phase 3 functionally complete.
- 4-A: Missing test coverage from existing-state report.
- 4-B: Debounce check on length control (measure rematerialization cost at 256 steps; add debounce if perceptible lag).
- 4-C: Undo/redo assessment for the save action — confirm whether it integrates with the existing undo stack or must be excluded. Record the finding.

---

## Non-Goals (First Version)

Do not build any of the following:

- Persisting the capture buffer to disk. Clip history is a live-session convenience only.
- Exposing clip history for tracks without an active generator.
- Capturing parameter automation, pitch-bend, or non-note events.
- A new document model type for virtual clips requiring schema migration.
- Surfacing clip history outside the generator-view entry point.
- Live-follow mode (history strip refreshes while modal is open).
- Configurable history window length (16 bars is fixed in the first version).
- Scrollable or paginated history strip (fixed 16-column view only).
- Undo/redo for the save action (assess in Phase 4-C; defer if not trivial).

---

## Open Questions

**Blocking (must be resolved before the phase indicated):**

| Question | Blocks | Owner |
|---|---|---|
| Buffer expansion: is 256 steps safe for memory and audio thread? | Phase 0-A gate — before any other work | Implementation team |
| Is the audition override a thin runtime flag or does it require broad dispatch refactoring? | Phase 0-B gate — before audition UI | Implementation team |
| Does `capturedClipContent` capture post-modifier or pre-modifier output? | Phase 0-C — before Phase 3 UI | Implementation team |
| Overwrite confirmation copy ("Overwrite" vs "Replace" vs "Save anyway") and whether the footer "Save to slot" button is hidden or disabled during overwrite confirmation | Phase 2 — before save flow in Phase 3 | PM / UX |

**Deferrable (can ship without resolving):**

| Question | Notes |
|---|---|
| Default pre-selected bar when the modal opens | Treated as resolved: no pre-selection (user must click). Matches the prototype default. |
| Configurable history window length | Deferred. 16 bars is fixed. |
| Live-follow mode | Deferred. Frozen snapshot is the shipped behavior. |
| Rematerialization cost on length change | Measure in Phase 4-B; add debounce if needed. Does not block Phase 3 build. |

---

## Acceptance Criteria

Condensed from spec section 2.

- [ ] Generator-source panel has a clearly labelled "Clip History..." button visible only on generator-driven tracks.
- [ ] Pressing the button opens the history modal for the current track.
- [ ] Modal shows a 16-bar history strip frozen at the moment the modal opened.
- [ ] The history strip does not update while the modal is open.
- [ ] Empty bars display with a dashed outline; bars with content show note blobs.
- [ ] Clicking a bar selects it and populates the virtual clip preview.
- [ ] Length control exposes ½ bar, 1 bar, 2 bars, and 4 bars options. Changing it updates the range highlight and preview.
- [ ] Audition button is disabled until a bar is selected (or absent if audition was descoped in Phase 0-B).
- [ ] Pressing Audition causes the track to loop the virtual clip instead of running the live generator. No document mutation occurs.
- [ ] Pressing Stop or closing the modal returns the track to live generator behavior immediately.
- [ ] Pattern slot picker shows all 16 slots. Occupied slots display a distinct color and "USED" label (and clip name if available).
- [ ] Clicking an empty slot enables the "Save to slot" footer button.
- [ ] Clicking an occupied slot shows the inline overwrite confirmation row; clicking an empty slot does not.
- [ ] Cancelling the overwrite confirmation deselects the slot and hides the row.
- [ ] "Save to slot" footer button is disabled until both a bar and a slot are selected and any required overwrite has been confirmed.
- [ ] Saving to an empty slot creates the clip in that slot, closes the modal, and shows a toast confirmation.
- [ ] Saving via the overwrite path replaces the existing clip in the slot, closes the modal, and shows a toast.
- [ ] Cancelling or closing the modal with the close button leaves the document unchanged and clears any active audition override.
- [ ] Empty history state: all bars show as empty; Audition and Save buttons remain disabled.
- [ ] Modal does not open for non-generator tracks.

---

## Testing Expectations

### Engine Layer (Phases 0 and 1)
- Buffer holds at least 256 steps without data loss or measurable memory regression.
- `captureSnapshot` returns a stable copy: a concurrent engine write does not mutate the returned snapshot.
- `captureSnapshot` on a track with no history returns an empty snapshot without crashing.
- `captureSnapshot` when fewer than 256 steps are captured returns a partial snapshot.
- `setAuditionOverride` set: engine plays pseudo-clip note-grid instead of running the live generator.
- `setAuditionOverride` cleared: track returns to live generator output; no document mutation.
- `saveRollingCapture` called from the modal save path writes the expected `ClipContent` to the chosen slot.

### Model Layer (Phase 1)
- `materialize(from:startStep:lengthSteps:)` with a full snapshot produces the expected step range.
- `materialize` from a sparse snapshot produces a valid note grid without crashes.
- Rematerialization on length change produces the correct updated grid.

### UI Layer (Phase 3)
All items in spec section 8.3. Key cases: modal opens only for generator tracks; bar selection updates preview; length control updates range and preview; audition button disabled until bar selected; save button disabled until bar and slot both selected and overwrite confirmed; occupied-slot confirmation row shows and hides correctly; Cancel leaves document unchanged; save to empty slot and save via overwrite both create/replace clip and show toast; history strip frozen during modal.

### Missing Coverage to Add (Phase 4-A)
- Rolling window size holds 256 steps.
- Saving multi-step and sparse generated history.
- Clipping/padding when requested length exceeds available history.
- Post-modifier versus pre-modifier capture semantics.
- Full UI flow: open, change length, audition, save.
- Occupied-slot overwrite: confirm, save, verify old clip replaced.
- Occupied-slot cancel: confirm row, cancel, verify no save and no state change.

See spec section 8.4 for the full list.

---

## Key Source Locations

| What | Location |
|---|---|
| Capture buffer constant (64 → 256) | `Sources/Engine/EngineController.swift:21` |
| Capture step collection | `Sources/Engine/EngineController.swift:39` |
| `capturedClipContent(trackID:lengthSteps:)` | `Sources/Engine/EngineController.swift:607` |
| `saveRollingCapture(to:trackID:destinationSlotIndex:lengthSteps:name:)` | `Sources/Engine/EngineController.swift:617` |
| Capture destination slot selection | `Sources/Document/Project+CapturedClips.swift:4` |
| Pattern slot palette (existing UI reference) | `Sources/UI/TrackSource/TrackSourceEditorView.swift:154` |
| Generator-source panel / entry point location | `Sources/UI/TrackSource/TrackSourceEditorView.swift:240` |
| Existing engine capture test | `Tests/SequencerAITests/Engine/EngineControllerTests.swift:502` |
