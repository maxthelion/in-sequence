The actual matrix has regressed here into the old "phrases" form that should now only be present in song view (which seems to be missing from captures). Instead of a set of columns, it should be a matrix of cells, either by track (with the layer value on it), or layer values (which get applied to all the tracks in the selection. It should fill the whole width. We had versions of this.

Screenshots:
- 01-phrase.png

## Decision (2026-06-23, user)
Restore from history: find the prior cell-matrix phrase implementation in git history and restore/adapt it (full-width matrix of cells, by track with the layer value on each / layer values applied across the selection). Reuse the proven version rather than rebuilding fresh.
