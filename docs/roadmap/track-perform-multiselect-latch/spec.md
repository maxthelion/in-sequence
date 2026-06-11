---
status: accepted
stage: implementation-spec
updated: 2026-06-04
source_prototype: prototypes/01-inline-matrix-editing.html
---

# Track Perform Multi-Select And Latch Spec

## Goal

Make the Track Perform screen fast enough for live multi-track edits while
keeping binary performance controls predictable under both momentary and
latched use.

This feature has two separate v1 behaviors:

- authored multi-select linked editing, where a temporary selected track set
  causes one matrix edit to write the same authored perform value to the same
  cell on selected tracks only;
- runtime-only binary performance overlay state, where Fill, Note Repeat, and
  future binary perform controls share one latch-versus-momentary press model.

The accepted UX direction is `prototypes/01-inline-matrix-editing.html`.
`prototypes/02-edit-set-sidecar.html` remains rejected comparison evidence and
should not drive the v1 build.

The accepted layer-action clarification is binding for implementation:
Pattern, Fill, and Note Repeat are active track layers/modes selected from the
top-left layer control area. Pattern-mode track cards render pattern
selection/state and must not carry permanent `FILL` or `RPT` footer controls.
When the Fill or Note Repeat layer is active, track cards render and control
that layer's runtime binary on/off state.

## V1 Scope

Build the inline Track Perform workflow:

- each track row has an explicit selected/unselected affordance;
- the current selected set is visible in the Track Perform header;
- editing an authored matrix cell on a selected row applies that same value to
  the corresponding cell on every selected row;
- editing an authored matrix cell on an unselected row affects only that row;
- Pattern, Fill, and Note Repeat are selectable top-left layer modes;
- Pattern mode stays focused on authored pattern selection/state;
- Pattern-mode cards do not show permanent Fill/Repeat footer controls;
- Fill and Note Repeat layer views expose each track's runtime binary state and
  controls;
- one visible page-level latch mode controls binary perform press behavior for
  all supported binary controls;
- latch off means momentary press: pointer down engages, release disengages;
- latch on means toggle: activation flips the runtime on/off state and leaves it
  active until toggled again.

## Non-Goals

- Do not create persistent track groups.
- Do not make multi-select a global app selection model.
- Do not move the happy path into a modal or side inspector.
- Do not persist momentary or latched binary performance state into phrase cell
  data.
- Do not solve hardware-controller mapping in v1, beyond keeping the state model
  reusable.
- Do not implement continuous-control latch behavior; v1 applies only to binary
  controls.

## Multi-Select Behavior

The Track Perform surface owns a temporary edit set of track IDs. It is separate
from the app's single focused `selectedTrackID`.

Selection rules:

- selecting a row adds that track to the edit set;
- selecting an already selected row removes that track from the edit set;
- clearing selection removes all selected tracks;
- the selected set may contain zero, one, or many tracks;
- selected rows must remain visually distinct from unselected rows before and
  after edits;
- the header must show the selected count and enough selected-track identity for
  the performer to predict edit scope.

Linked edit rules:

- if the edited source row is selected and at least two tracks are selected, the
  edit fans out to the corresponding authored cell on every selected track;
- if the source row is not selected, the edit affects only the source row;
- if exactly one track is selected and it is the source row, the edit affects
  only that row;
- unselected tracks are never modified by a linked authored edit;
- the UI should provide immediate feedback that a linked edit has affected the
  selected set.

The builder should reuse the existing phrase-cell fan-out primitive for authored
matrix values where possible.

## Binary Latch Behavior

Binary performance controls are runtime performance controls, not authored
phrase-cell edits. V1 controls are Fill and Note Repeat where those controls are
available on the Track Perform surface. They are exposed through their active
layer views, not as always-visible controls on every Pattern-mode track card.

Latch mode is page-level:

- `Latch Off / Momentary`: pointer down engages the selected binary control
  immediately; release disengages it.
- `Latch On / Toggle`: activation toggles the runtime binary state; release does
  not change it.

The same selection fan-out rule applies to binary runtime controls:

- pressing a binary control on a selected source row applies the runtime state
  change to all selected tracks;
- pressing a binary control on an unselected source row applies only to that row.

Layer-view rules:

- selecting the Fill layer shows per-track Fill runtime state and Fill controls;
- selecting the Note Repeat layer shows per-track Note Repeat runtime state and
  Note Repeat controls;
- selecting the Pattern layer restores pattern-focused cards without permanent
  Fill/Repeat footer chrome;
- changing layers does not persist runtime binary overlay state into authored
  phrase cells.

Momentary lifecycle defaults:

- pointer down sets the runtime state on for the target recipient tracks;
- pointer up sets that same runtime state off for the active press recipients;
- pointer cancel, pointer exit while pressed, view disappearance, track removal,
  document switch, or transport/session teardown must release any active
  momentary press;
- repeated release/cancel events must be idempotent;
- a momentary release must not clear independently latched runtime state that
  was not created by that press.

## Visibility Requirements

The latch mode control must stay visible and understandable when the matrix is
dense. The v1 default is a Track Perform header control that remains in view
with the selected-set summary. If the existing layout cannot keep both visible,
prefer preserving latch mode visibility and compressing the selection summary
to count plus abbreviated track names.

The top-left layer control area must expose Pattern, Fill, and Note Repeat as
peer layer modes. The active layer must be clear before the performer touches a
track card.

Selected rows need both row-level and control-level signals where practical:

- row background or border communicates selected membership;
- the row selector communicates add/remove state;
- active binary controls communicate runtime on/off state;
- momentary press state is visually distinct from latched on state.

## Acceptance Criteria

- A performer can select multiple tracks on the Track Perform screen without
  leaving the matrix.
- Pattern, Fill, and Note Repeat are selectable from the top-left layer control
  area.
- Pattern-mode cards render pattern selection/state without permanent
  Fill/Repeat footer controls.
- Fill and Note Repeat layer views render and control each track's runtime
  binary on/off state.
- The selected set remains visible before a linked edit is committed.
- Editing an authored cell on a selected row writes the same value to selected
  tracks only.
- Editing an authored cell on an unselected row does not fan out.
- Fill and Note Repeat share the same page-level latch mode.
- In momentary mode, pointer down engages and pointer up releases without
  mutating authored phrase values.
- In latched mode, activation toggles runtime binary state and keeps it active
  after release.
- Pointer cancel, pointer exit, view disappearance, track removal, document
  switch, and teardown release active momentary presses.
- Runtime binary overlay state and authored phrase-cell fan-out remain separate
  in code and tests.

## Product-Owner Questions

No product-owner question blocks v1. The dense-header and pointer-exit questions
from the UX review are resolved here as v1 defaults: keep latch mode visibly in
the Track Perform header, and treat pointer exit/cancel as release for
momentary presses. The layer-action question is also resolved by owner feedback:
Fill and Note Repeat are active layer modes, not permanent Pattern-card footer
controls.
