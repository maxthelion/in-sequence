# Clip History Inline History Tab Feedback

- date: 2026-06-02
- source: product-owner live check and follow-up sketch/notes
- prototype: `docs/roadmap/clip-history/prototypes/clip-history-inline-history-tab-v5.html`
- target loop: `build/clip-history`

## Raw Direction

The third tab in the Tracks source interface should be called `History`, not
`Clip History`.

It should work whether the source is a clip or a generator. The feature should
not be gated behind a generator-only source state.

The history workflow should be inline inside the tab, not a modal. The two main
elements should be:

- a virtual clip preview on the left, expanded to feel more like a piano roll
  than a step sequencer;
- the history chooser as a horizontal strip/minibar below the preview, rather
  than a 4x4 matrix. It should fit all 16 history regions in one row; the
  cells do not need to contain much text and should mainly show lightweight
  piano-roll-like previews.

The preview should show the length in bars of the selected history region.
Selecting a potential clip from history should automatically loop/audition that
selection. Clearing the selection should leave audition mode.

Pattern/destination clips should be removed from this interface. If `Save Clip`
is pressed, the existing pattern cells at the top of the track should pulse and
be reused as the destination picker. It is wasteful and confusing to render a
second pattern-slot grid inside the history UI.

## Builder Intent

This feedback invalidates the current modal/dual-grid destination direction for
the next build pass. Do not build this as a parallel surface beside the existing
modal. Rework the current Clip History implementation so the wrong elements are
removed:

- remove or retire the modal entry path for this track-source workflow;
- remove the duplicate pattern-slot destination matrix from the Clip History UI;
- remove generator-only access as a product constraint for opening History;
- rename the tab to `History`;
- keep recent-history source selection;
- keep virtual preview/audition, but make the preview spatially richer and more
  piano-roll-like;
- show selected history length in bars in/near the preview;
- make history selection drive audition automatically, with unselect exiting
  audition mode;
- prefer a horizontal history minibar below the preview over a 4x4 history
  matrix, fitted as 16 compact cells in one row;
- keep history cells visually light: label, optional bar length, and a tiny
  piano-roll thumbnail are enough;
- route save-destination choice through the existing pattern row.

## Open Implementation Judgment

The exact save-destination interaction can be designed by the builder, but the
principle is that pressing `Save Clip` should put the existing pattern row into
a temporary destination-picking state. Occupied pattern cells can still require
replace confirmation, but that confirmation should be attached to/reuse the
pattern-row destination interaction rather than appearing in a second modal grid.
