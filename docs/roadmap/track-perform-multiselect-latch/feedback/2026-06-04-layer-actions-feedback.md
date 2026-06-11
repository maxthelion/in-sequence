---
status: open
created: 2026-06-04T11:27:47Z
source: product-owner-review
applies_to: track-perform-multiselect-latch
---

# Track Perform Layer Action Feedback

The current track cards show persistent Fill and Note Repeat buttons at the
bottom of each individual card. That is not the intended model.

Intent to preserve:

- Fill and Note Repeat are track layers/modes, selected from the layer control
  area at the top-left of the Tracks surface.
- Track cards should render the active layer's state.
- Fill and Note Repeat should not be individual card buttons that are visible
  all the time.
- Avoid adding permanent card chrome for every performance mode; the layer
  grammar should carry this.

Suggested correction:

Remove the persistent `FILL` and `RPT` buttons from the track card footer and
move the interaction into the active layer model. When the Fill layer is
selected, cards show fill state. When the Note Repeat layer is selected, cards
show repeat state. Pattern mode remains focused on pattern selection/state.
