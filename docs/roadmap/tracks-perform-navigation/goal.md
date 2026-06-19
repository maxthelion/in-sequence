# Goal: Tracks Perform = navigation + selection (remove bespoke layer surface)

Source: `docs/roadmap/track-view-ia/feedback/2026-06-19-tracks-perform-navigation-not-layers.md`
and bug `docs/bugs/20260619-215229-tracks-perform-should-be-navigation-not-layers`.

The tracks Perform view currently duplicates layer-perform (its own TRACK LAYER
selector + per-track grids). Layers now belong to phrase perform (project-wide)
and scoped track/kit perform (per selection). Make the tracks view about
navigating to tracks and selecting them for actions; launch layer perform scoped
from the selection.

**Process:** worktree off main; build green before each commit; one logical
change per commit with the standard trailers; restore Info.plist after any
xcodegen. Do NOT regress the verified-clean engine classes (graphLock,
Performance-Time Mutation Rule, document-truth-vs-transient state).

## AC1 — Remove the bespoke layer surface from Tracks Perform
- The `TRACK LAYER` selector and the "CHOOSE TRACK LAYER" popup are removed from
  the tracks Perform view (find in the tracks perform/matrix view; likely
  `Sources/UI/.../TracksMatrixView` / performance-layer-matrix-tracks code).
- Per-track layer mini-grids tied to the chosen layer are removed.
- No regression to the underlying engine layer model (phrase/scoped perform
  still drive layers).

## AC2 — Tracks Perform is navigation + selection
- Card grid: each card shows a pattern preview + a per-card mute toggle.
- Clicking a normal card opens that track's single-track detail; clicking the
  collapsed kit cell opens the kit matrix (linked) or expands to part cells
  (unlinked) — matches prototype `03-track-matrix.html`.
- Multi-select ("Edit Set") is preserved (the `track-perform-multiselect-latch`
  selection model); selection state is transient runtime, not persisted.

## AC3 — Perform from selection -> scoped phrase-perform UI
- A `Perform` action launches the existing scoped Track/Kit Perform overlay
  (the AC22 scoped perform that reuses phrase perform) for the current selection
  (single track, multi-select, or kit).
- No bespoke layer UI is reintroduced; the scoped overlay is the reused surface.

## AC4 — Tests + build
- Build green; existing tracks/perform tests still pass.
- Add/adjust a test for the selection -> scoped-perform entry (e.g. selecting
  cards then Perform sets `performTrackScope` and enters scoped perform), and a
  test that the tracks Perform view no longer exposes the track-layer selector
  state.

## Out of scope (handled in the bug sweep)
- Phrase global-apply interactivity / track-selector mode (bugs 213713, 213834).
- Scenes-perform page removal (bug 212935).
- Phrase perform layout density (bug 213241).
