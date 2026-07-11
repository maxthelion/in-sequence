The layers available by track are more extensive than the ones by value. What's more when a note repeat or step order layer is selected, there is no ui element for toggling on or off for the chosen value. Note repeat in particular needs to capture the last played step and then repeat it according to the value that's been selected, like 1/32 or 1/16.

Status: RESOLVED 3da0f246

Layer and Values share the backed layer inventory. Note repeat has whole-cell
runtime toggles using the prepared step and selected interval; step order has
phrase-wide toggles and remains boundary-quantised while playing.
