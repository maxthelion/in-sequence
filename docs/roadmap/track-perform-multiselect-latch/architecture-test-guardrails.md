---
status: accepted
stage: architecture-test-guardrails
updated: 2026-06-04
---

# Track Perform Multi-Select And Latch Architecture And Test Guardrails

## Required Architecture Split

This feature must keep two state domains separate.

Authored domain:

- owns phrase-cell data and any saved perform matrix values;
- may reuse `setPhraseCell(... trackIDs:)` style fan-out for linked
  multi-select edits;
- must remain deterministic, undoable, and document-backed according to the
  existing phrase mutation model.

Runtime domain:

- owns Fill, Note Repeat, and future binary performance on/off overlays;
- stores transient momentary press state and latched runtime toggles outside
  phrase data;
- exposes Fill and Note Repeat through their active Track Perform layer views,
  not through authored Pattern-mode card chrome;
- releases momentary state on pointer lifecycle exits and session/context
  cleanup;
- should follow the existing scene performance overlay pattern rather than
  encoding live press state as authored phrase edits.

Do not satisfy latch/momentary behavior by cycling phrase cells. That would make
press-and-release gestures persist into authored arrangement state and would
break the performance model described in the README.

## Selection Ownership

The Track Perform multi-select edit set is local performance UI/session state,
not a replacement for the single focused track selection.

Guardrails:

- preserve `selectedTrackID` as the focused track concept unless a broader
  feature explicitly changes it;
- store selected perform track IDs in a dedicated state path owned by Track
  Perform or the live performance store;
- do not serialize the temporary edit set into the project document;
- clear or reconcile the selected set when selected tracks disappear, the
  document changes, or the performance surface is torn down.

## Binary Overlay Shape

The runtime overlay should represent:

- latched binary states per track and control kind;
- active momentary press captures keyed by press identity, track recipients, and
  control kind;
- one page/session latch mode used by all supported binary controls.

The press capture matters because release must turn off the same recipient set
that pointer down engaged, even if the visible selection changes before release.

## Cleanup Rules

The implementation must release or reconcile runtime state on:

- pointer up;
- pointer cancel;
- pointer exit while pressed;
- view disappearance;
- track removal;
- document/session switch;
- engine/session teardown.

Cleanup should be idempotent. Calling release twice for the same press must not
toggle state back on or clear unrelated latched state.

## UI Guardrails

- Keep the inline matrix as the happy path; do not introduce a required modal or
  sidecar for ordinary linked edits.
- Keep Pattern, Fill, and Note Repeat as top-left active layer modes.
- Keep Pattern-mode cards focused on pattern selection/state; do not add
  permanent `FILL`/`RPT` footer controls to every card.
- Render and control Fill runtime state in the Fill layer view.
- Render and control Note Repeat runtime state in the Note Repeat layer view.
- Keep latch mode visible near the selected-set summary.
- Keep selected rows visually legible in dense layouts.
- Make active runtime binary state distinct from selected membership and
  momentary pressed state.
- Keep direct edits possible in one interaction after the edit set has been
  assembled.

## Test Plan

Model and store tests:

- selected edit set can add, remove, clear, and reconcile removed track IDs;
- authored cell edit on a selected source row fans out to selected track IDs
  only;
- authored cell edit on an unselected source row affects only that row;
- existing phrase-cell fan-out behavior remains covered;
- runtime binary overlay can set, clear, and query per-track Fill/Repeat state;
- latch mode toggle changes press semantics without mutating phrase data.

Pointer lifecycle tests:

- momentary pointer down engages the captured recipient set;
- pointer up releases the captured recipient set;
- pointer cancel releases the captured recipient set;
- pointer exit while pressed releases the captured recipient set;
- selection changes between down and up do not change the captured release
  recipients;
- duplicate release/cancel is idempotent;
- latched mode toggles state on activation and ignores release for state
  changes.

Integration/UI tests:

- selected rows are visually distinguishable from unselected rows;
- selected count/summary updates as tracks are added and removed;
- clearing selection prevents linked fan-out;
- the top-left layer control exposes Pattern, Fill, and Note Repeat modes;
- Pattern mode does not render permanent Fill/Repeat footer controls;
- Fill layer renders and controls per-track Fill runtime state;
- Note Repeat layer renders and controls per-track Note Repeat runtime state;
- Fill and Note Repeat use the same latch mode;
- view disappearance releases active momentary state.

Regression checks:

- authored phrase data does not change during momentary binary presses;
- latched runtime binary state does not create phrase-cell edits;
- unselected tracks are untouched by linked authored edits and binary runtime
  fan-out.

## Review Evidence Expected From Builder

- unit test output covering authored fan-out and runtime overlay behavior;
- focused UI/store evidence that the selection set is visible and scoped;
- a short note or screenshot confirming the top-left layer modes and latch mode
  remain visible in the implemented dense Track Perform layout;
- explicit confirmation that Pattern-mode track cards do not include permanent
  Fill/Repeat footer controls;
- explicit confirmation that no product code path persists momentary/latch
  runtime state into phrase data.
