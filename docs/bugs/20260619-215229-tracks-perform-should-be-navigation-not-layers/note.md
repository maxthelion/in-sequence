Tracks Perform view should be navigation + selection, not a bespoke layer-perform surface

Screenshots:
- 03-tracks-perform.png
- 14-tracks-perform-layer-selector.png

The tracks Perform view carries its own TRACK LAYER selector ("CHOOSE TRACK
LAYER": Mute, Pattern, Fill, Note-Repeat 1/4-1/64, Step-Order tools, Volume,
Pan) + per-track grids — a duplicate of layer-perform, which now belongs to
phrase perform (project-wide) and scoped track/kit perform (per selection).

Target:
- Tracks view = navigation + selection: card grid (pattern preview + per-card
  mute), click card -> track detail, click kit cell -> kit matrix, multi-select.
- Perform button launches the scoped phrase-perform UI for the selection
  (reuse, no bespoke surface).
- Project-wide layer perform stays in phrase perform only.

See docs/roadmap/track-view-ia/feedback/2026-06-19-tracks-perform-navigation-not-layers.md
and docs/roadmap/tracks-perform-navigation/goal.md.

---

## RESOLVED (2026-06-20) — tracks view reshaped into a plain navigator

The product owner's most-recent clarification superseded the original target
(which still kept a pattern preview + an Edit Set + a Perform button on the
matrix): the tracks view "shouldn't have perform and layers" — it should be a
plain NAVIGATOR of track tiles you click to open the single-track detail, plus
an add-track tile.

What changed in `Sources/UI/TracksMatrixView.swift`:
- `TrackMatrixCard` is now a tile showing ONLY the type/instrument icon + the
  track name + type label, with a tiny mute toggle. The per-card pattern/layer
  step-grid preview is gone (removed `TrackCardCellPreviewLeaf`,
  `TrackCardStrokeOverlay`, `AudioInputRuntimeBadge`).
- Removed the perform chrome entirely: the BASIS PHRASE banner, the EDIT SET
  selection bar, the PERFORM SCOPE chip, and the Perform launcher button — plus
  the `performSelection` / `performScope` / `previewLayer` / `editingPhrase`
  state and the `isPerforming` Edit/Perform split. The tracks view is now ONE
  navigator in every workspace mode.
- Navigation wiring preserved: clicking a normal tile opens that track's
  single-track detail; a linked drum kit still collapses to one cell that opens
  the kit matrix; the add-track "+" tile is kept.
- The scoped-perform engine API (`session.enterScopedPerform` etc.) is
  untouched — it is simply no longer launched from the tracks matrix. Layer /
  scoped perform now lives in phrase perform and on the single-track detail.

QA harness (`scripts/visual-scenarios/qa-surface-coverage.sh`): row
`02-tracks-edit` renamed to `02-tracks-navigator` (drops the `tracksMode=edit`
command); rows `03-tracks-perform` and `03a-tracks-scoped-perform` retired (the
old tracks-perform shape no longer exists). Invalidation tests updated: the
navigator reads no tick-rate state, so the playhead-leaf positive controls now
assert zero leaf evaluations.

Verified by capture `02-tracks-navigator.png`: track tile (icon + name +
mute) + add tile, no BASIS PHRASE banner, no per-card step grid, no EDIT SET /
Perform chrome.
