---
status: accepted
stage: implementation-handoff
updated: 2026-06-04
---

# Track Perform Multi-Select And Latch Implementation Handoff

## Builder Objective

Implement the accepted inline Track Perform multi-select and latch workflow
without merging authored phrase edits and runtime performance overlays into one
state model. The Track Perform layer grammar is part of the handoff contract:
Pattern, Fill, and Note Repeat are peer modes selected from the top-left layer
control area.

The builder should treat `spec.md` and `architecture-test-guardrails.md` as the
handoff contract. The PM-approved prototype is
`prototypes/01-inline-matrix-editing.html`.

## Suggested Build Slices

1. Add Track Perform selected-set state.
   - Introduce a temporary selected track ID set for the Track Perform surface.
   - Preserve the existing single focused `selectedTrackID`.
   - Add clear/reconcile behavior for context changes and removed tracks.

2. Wire authored linked matrix edits.
   - Feed selected track IDs into the existing authored phrase-cell fan-out path.
   - Apply fan-out only when the source row is selected and multiple tracks are
     selected.
   - Keep unselected source-row edits local to that row.

3. Add runtime binary performance overlay.
   - Represent per-track binary runtime states for Fill and Note Repeat.
   - Add page/session latch mode shared by binary controls.
   - Track active momentary press captures so release targets the original
     recipient set.

4. Implement pointer lifecycle behavior.
   - Momentary mode: engage on pointer down, release on pointer up/cancel/exit.
   - Latched mode: toggle on activation, release has no state effect.
   - Release active momentary state on view/session teardown.

5. Update the Track Perform UI.
   - Keep row-level selection controls inline with the matrix.
   - Expose Pattern, Fill, and Note Repeat as top-left layer modes.
   - Keep Pattern-mode cards focused on pattern selection/state without
     permanent `FILL`/`RPT` footer controls.
   - Render and control per-track runtime state in the Fill and Note Repeat
     layer views.
   - Keep selected-set summary and latch mode visible in the header.
   - Make selected rows, active binary state, and momentary pressed state
     visually distinct.

6. Add tests and review evidence.
   - Cover selected-set behavior, authored fan-out scope, runtime overlay
     semantics, pointer lifecycle, and cleanup.
   - Provide focused visual or screenshot evidence for the top-left layer modes
     and dense header/latch visibility requirements.

## Implementation Notes

- Reuse existing phrase mutation APIs for authored matrix values instead of
  creating a parallel document mutation path.
- Prefer a small shared binary-control model that future Track Perform controls
  can opt into.
- Treat Fill and Note Repeat as active layer views over runtime binary state,
  not as permanent buttons appended to Pattern-mode card chrome.
- Capture recipient IDs at pointer down for momentary presses. Do not recompute
  recipients from the current selection on release.
- Momentary state should layer over latched state carefully: releasing a
  momentary press should only remove the press contribution, not clear a
  separate latched-on contribution.
- If Note Repeat lacks full audio/sequencing behavior in the current codebase,
  build the shared runtime overlay and UI contract in a way that can host it
  without faking authored phrase persistence.

## Acceptance Review Checklist

- Multi-select edit set can be built and cleared from the Track Perform matrix.
- Selected rows and selected count/summary are visible before editing.
- Pattern, Fill, and Note Repeat are selectable from the top-left layer control
  area.
- Pattern-mode cards do not show permanent Fill/Repeat footer controls.
- Fill and Note Repeat layer views render and control runtime binary state.
- Authored matrix edits fan out only to selected tracks when the source row is
  selected.
- Unselected source-row edits remain single-track.
- Fill and Note Repeat share one latch mode.
- Momentary mode engages on pointer down and releases on pointer up, cancel,
  pointer exit, view disappearance, and teardown.
- Latched mode toggles runtime state and persists after release.
- Runtime binary state is not written to phrase cells.
- Tests cover the authored/runtime split and pointer lifecycle edge cases.

## Promotion Read

This lane is builder-ready from the PM artifact perspective after this handoff
package is present. Build-loop promotion remains a project-loop decision and
should wait for the PM readiness observer/orienter/decider to consume this
evidence.

## Product-Owner Attention

No product-owner question is required for v1. The accepted prototype direction
is direct inline matrix editing, the layer-action feedback resolves Fill/Repeat
placement as active layer views, and the remaining UX review follow-ups are
resolved as defaults in `spec.md`.
