# Resolution

Branch: `feature/small-ui-sweep` (worktree `.worktrees/small-ui-sweep`), commit `46d58ea5`.

## What changed

- **Add-track cell matches the others** — the add card now uses
  `StudioAddCard(label: "", minHeight: 210, ...)`, the same content
  min-height + comfortable padding as `TrackMatrixCard`, so it sits flush in
  the grid (ux-canon rule 5). It renders no text; the "+" carries the
  affordance and the help/accessibility string ("Add a track") names the
  action. `StudioAddCard` (Sources/UI/Theme/StudioCards.swift) collapses an
  empty label so other grids (scenes, busses) keep theirs.
- **One layer changer, shared with perform mode** — the edit-mode chevron
  cycler in `Sources/UI/TracksMatrixView.swift` was deleted. Both modes now
  use the perform-mode selector button (icon + "TRACK LAYER" eyebrow + active
  layer + chevron) which opens the shared performance-layer matrix
  (`PerformanceLayerOptionCell` grid), the same component the perform mode
  and the Phrase page use. One `PerformanceLayerSelectionState` drives the
  matrix in both modes:
  - modes that map to a phrase layer (Pattern, Mute, Fill, Volume) show that
    layer's cells in edit mode exactly as before;
  - runtime trigger surfaces (Fill/Note Repeat HELD/LATCHED cells) remain
    perform-only — in edit mode those cards stay tappable to open the track;
  - the shared `selectedLayerID` binding (Live page) is kept in sync when a
    chosen mode maps to a phrase layer, and the matrix follows an externally
    selected layer on appear.

Behaviour note: layers that only existed in the old edit-mode cycler
(transpose, intensity, density, tension, register, variance, fx-send,
brightness, swing, per-track macro layers) are no longer reachable from the
Tracks page selector — this mirrors the Phrase page, which already moved to
the performance-layer matrix. They remain editable from the Live page.

## Tests

- No presentation struct changed; the build-time `UIReadsStoreDirectlyTests`
  read-path contract for TracksMatrixView is unaffected. Full suite run on
  the branch (see sweep report).

## Remaining verification

- Visual verification pending: no QA screenshot capture was run (console may
  be locked). Re-capture `02-tracks-edit.png` and confirm: the add cell is
  the same height as track cards with no text, the layer changer is the
  selector-button component in edit mode, opening it shows the layer matrix,
  and choosing Pattern/Mute/Volume updates the cards in edit mode.
