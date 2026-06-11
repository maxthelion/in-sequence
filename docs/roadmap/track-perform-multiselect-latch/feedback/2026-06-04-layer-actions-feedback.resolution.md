# Resolution
Date: 2026-06-11 (foreman triage). Status: fixed.
Fill and Note Repeat are perform LAYERS selected from the layer control
(TrackPerformLayerMode + the full-grid selector), not persistent per-card
buttons. The 2026-06-10/11 perform-cell rework went further: with a layer
selected, the whole cell is the single toggle (state word only, no inner
controls). Loop complete; verified in QA captures 14-17 and the perform
cell code (TrackPerformRuntimeLayerControl).
