# Resolution: note-repeat/fill cells — state only, no wasted space

Date: 2026-06-10

The runtime perform cells (note repeat and fill) dropped the icon and the
per-cell layer label ("REPE…") — the layer header already names the layer.
The cell now shows only the state word ("READY" / "HELD" / "LATCHED" /
"ACTIVE" / "No Clip"), centered and filling the full cell height (the empty
bottom half is gone), with the captured step + rate ("STEP 5 · 1/8") as a
second line while a repeat is engaged. This matches the mute layer's
whole-cell Muted/Live grammar.

File: `Sources/UI/TracksMatrixView.swift`
(`TrackPerformRuntimeLayerControl.label`).
