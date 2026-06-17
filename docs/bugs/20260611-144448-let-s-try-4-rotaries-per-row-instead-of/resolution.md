# Resolution

Branch: `feature/small-ui-sweep` (worktree `.worktrees/small-ui-sweep`), commit `66158768`.

## What changed

- **Four rotaries per row** — `performMacroSlots` in
  `Sources/UI/Mixer/ScenesWorkspaceView+Perform.swift` now uses four flexible
  grid columns (was two), so the eight macro slots fill two rows per scene
  slot instead of four half-empty ones.
- **Duplicate "Assign" labels removed** — the perform view passes
  `emptyLabel: ""` to `MacroSlotKnob`, and the shared knob component
  (`Sources/UI/TrackDestination/AUMacroSlotKnob.swift`) collapses an empty
  footer label entirely. The dashed "+" knob is the assign affordance; a
  "Assign a macro" tooltip names the action (ux-canon rule 1: one fact, one
  place). Other call sites (AU destination editor) pass nothing and keep
  their existing labels, and assigned knobs still show their macro names.

## Tests

- No presentation logic changed (layout-only column count and a view-level
  label suppression); existing suites cover the unchanged knob behaviour.

## Remaining verification

- Visual verification pending: no QA screenshot capture was run (console may
  be locked). Re-capture `06-scenes-perform.png` and confirm: 4 knobs per
  row in both Slot A and Slot B, no "Assign" text under unassigned knobs,
  knob labels for assigned macros still render, and the 4-up grid does not
  squeeze at the minimum window width (GridItem minimum is 58pt per column).
