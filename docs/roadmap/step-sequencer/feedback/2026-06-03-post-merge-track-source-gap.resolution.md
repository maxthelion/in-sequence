# Resolution

Date: 2026-06-11. Branch: `feature/track-source-step-grid`.
Status: resolved in code; visual verification pending (console locked, no
QA captures taken).

Each observed issue, and where it was fixed:

## Pop-up inspection removed

`ClipStepInspectorSheet` and its double-click/context-menu entry points are
deleted (`Sources/UI/TrackSource/Clip/ClipContentPreview.swift`,
`Sources/UI/StepGridView.swift`). Nothing else used the sheet. Right-click /
long-press on a cell now toggles step selection (the `UnifiedStepCell`
`onSelect` path, same as the slicer); no UI pops up.

## Variant D rotary row inline above the grid

While steps are selected, the layer line above the Track Source grid becomes
the shared `StepLayerRotaryRow` (the exact component the slicer workspace
uses, `Sources/UI/Slicer/SliceTrackEditingControls.swift`) — one arc-dial per
editable layer (velocity, chance, assigned macros), absolute-value writes to
every selected step in one mutation, trigger-layer selections showing
velocity+chance rotaries per spec 4e. Tapping a rotary switches the active
editor layer. Escape or a background click clears the selection
(`StepGridEscapeKeyHandler`, also shared with the slicer).

Selection state lives in the shared `StepGridCoordinator`, threaded from
`TrackWorkspaceView`'s `TrackStepGridWorkspaceModel` through
`TrackSourceEditorView` → `TrackSourceSourceTabContent` →
`TrackSourceClipPanel` → `ClipContentPreview` — the same wiring the slicer
uses, so selection survives view recreation and clears on track/clip changes
(spec 2a lifetime rules). To support this without a `StepSequenceTrack`
reference (the Track Source editor only has macro bindings), the
coordinator's rotary/value APIs now resolve macro layers from a
`[TrackMacroBinding]` array (`Sources/StepGrid/StepGridCoordinator.swift`).

## Selected state composes in the generic grid

`StepGridView` takes `selectedStepIndexes` (absolute clip-step indexes, so
paged grids compose with `indexOffset`) and `onSelectStep`/`onBackgroundTap`
instead of hard-coding `isSelected: false` and the old `onDoubleTap`
inspector hook. Selected cells render the amber border composed with
active/playing/value state via `UnifiedStepCell`.

## Compact cells

The Track Source grid now uses the same 16-column bar-aligned compact cell
grammar as the slicer step strip (tighter padding, one bar per row) instead
of the spacious 8-column layout (ux-canon rule 5, "one grid grammar").

## Also

Selection-aware grid edits per spec 4a/4b/4c: tapping or dragging a cell
that is part of the selection applies the toggle/value/cycle to all selected
steps in a single commit (one `onChange`/`mutateClip` per gesture step).

## Tests

- `StepGridCoordinatorTests`: rotary controls and absolute macro writes
  resolve from the bindings array without a track.
- `UnifiedStepCellTests`: paged `StepGridView` selection composition
  (absolute indexes + `indexOffset`).
- `ClipEditorLayerMappingTests` (new): Track Source editor layer ↔ shared
  `StepGridLayer` mapping, including macro binding-index (not slot-position)
  resolution.

## Known gaps / follow-ups

- Batch action bar (clear/copy/paste) is not yet surfaced in the Track
  Source editor; the coordinator's copy/clear/paste APIs take a
  `StepSequenceTrack` and were not generalized in this slice. The slicer
  remains the only surface with the bar.
- The macro layer's old double-click "clear override" affordance was
  superseded by the selection gesture; clearing an override now requires
  cycling through values.
- Visual verification (rotary row appearance/spacing in the real app) is
  pending — QA capture scripts were not run because the console may be
  locked.
