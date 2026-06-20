this view seems very crammed to the left leaving a big area on the right. Needs sorting out.

Screenshots:
- 23e-track-slicer-slice-tab.png

RESOLVED 2026-06-20: Changed SliceSamplerCard's outer frame from maxWidth: 560 to maxWidth: .infinity so the card stretches to the panel width and the waveform (already maxWidth: .infinity) fills the freed right-hand space while the controls column stays capped at 360.
