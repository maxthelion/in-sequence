# Resolution — branch fix/ui-consistency-bugs

- Cell editor modal now uses StudioModal with the standard ✕ close.
- Boolean and pattern-index layers already offered only Inherit/Single/Bars;
  "Inherit" is now offered only when the cell follows a phrase whose same
  track/layer cell has an explicit value to inherit from.
- Scalar cells (e.g. volume) are now drag-editable directly in the phrase
  matrix — vertical drag like step velocity; dragging an inherited cell
  converts it to a single explicit value.

Noted as future work: deeper cell-mode rationalisation ("more optimisations
to be made here").
