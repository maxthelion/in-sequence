In the automate modal there are basically two kinds: per bar values, and points on a graph with time in the phrase as the x axis. These should be the top level options. If automation is cleared, it reverts to default single value option. On per bar, you can define how many bars to loop over (defaults to same as phrase). Then show bar 1 2 3 etc as toggle values for the current layer (or draggable value bar). For the points version there should be a start point and end point. Possible to add more . Also pick from pre defined options like ramp up or down. Only one of the two uis should show, based on which option is chosen

Screenshots:
- 10a-phrase-layer-automation-modal.png

Capture references:
- 10a-phrase-layer-automation-modal.png (in-sequence/qa-surface-coverage; main @ 5795a331; run 20260711-191826-in-sequence-qa-surface-coverage-main-5795a331; ef5621ed5d2776d56b45204156665650)

Status: RESOLVED e543efa9

The modal now exposes Per Bar and Points automation surfaces; an unautomated cell has no selected automation mode and uses its ordinary single value. Per Bar defaults to the phrase length, loops over the chosen bar count, and presents eight compact layer-style value cells per row. Points provides draggable start/end points, add/remove controls, and curve presets. Clear removes automation, and legacy step automation requires an explicit sample-preserving conversion.

Refined: 31348884
