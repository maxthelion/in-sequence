# Performance Layer Matrix Post-Merge Feedback

- captured: 2026-06-08
- source: product-owner screenshot review of the integrated Performance Layer Matrix
- related feature: `performance-layer-matrix`
- related prototype: `docs/roadmap/performance-layer-matrix/prototypes/tracks-layer-select-balsamiq.html`

## Problem

The integrated layer matrix carries some of the idea, but the shape is wrong:

- It appears mainly on the Phrase view, while the Tracks view still uses the old model.
- It does not respect the intended 8x8/grid-like performance surface. The visible matrix is only four cells wide and no longer resembles the interface it is meant to operate with.
- Note Repeat options are tiny sub-buttons. The individual repeat options should be first-class cells.
- A repeat option should behave like a toggle from the user's point of view: off is normal playback, on is the selected repeat value.
- Pattern does not need a nested P1-P16 chooser in this surface. Pattern can simply be a selectable layer.
- Cells should not contain a separate `Select` button. The whole cell should be the selectable control.
- `Latch` is not a layer. It describes UI behaviour/hold semantics and should not be one of the matrix layer choices.

## Desired Direction

Rework the layer selector as a shared Tracks/Phrase performance-layer mechanism:

- Use the same layer-selection grammar on Tracks and Phrase views.
- Make the selector visibly compatible with an 8x8 performance grid.
- Treat layer variants as full cells when the variant is the actual performance choice. For Note Repeat, this means cells such as `1/4`, `1/8`, `1/16`, `Trip`, `Roll`, etc.
- Keep Pattern as one layer choice; pattern numbers belong in the pattern-selection UI, not inside the layer matrix.
- Remove Latch from the layer list and represent latch/hold behaviour elsewhere if needed.
- Make every matrix cell a single clear button target.

## Acceptance Notes

- Tracks view no longer relies on the old separate Fill/RPT button model.
- Phrase view and Tracks view share the same mental model.
- The reviewer should compare the rebuilt surface against this feedback, the original raw intent, and the balsamiq prototype.
- A UX/visual review should explicitly check that note-repeat variants are full cells, Pattern is not a nested grid, and Latch is not treated as a layer.
