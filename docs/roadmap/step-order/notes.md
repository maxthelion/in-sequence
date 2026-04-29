# Step Order Notes

## Raw Intent

```text
This is like note repeat. It basically overrides the sequential playhead for the track. It could be some sort of lookup so that step 0 in an array of 16 actually maps to 9. Whole sections of steps could be moved around, or notes added. In future we might want more messing around like adding layers. Example: [0,1,2,3,3,3,3,3,7,8,9,0,1,2,3]. The difficulty is that the actual layer modification needs to be selectable. Maybe there's one for the project, and it just gets toggled on or off.
```

## Clarified Concern

Captured from user clarification on 2026-04-29.

## Notes

This is like note repeat. It basically overrides the sequential playhead for the track. It could be some sort of lookup so that step 0 in an array of 16 actually maps to 9. Whole sections of steps could be moved around, or notes added. In future we might want more messing around like adding layers. Example: [0,1,2,3,3,3,3,3,7,8,9,0,1,2,3]. The difficulty is that the actual layer modification needs to be selectable. Maybe there's one for the project, and it just gets toggled on or off.

## Normalized Concept

Step Order is a playback-layer override for track playhead resolution.

Instead of changing the clip itself, the layer maps the current sequential step index to a source step index. For example, output step 0 can read source step 9, or multiple output steps can repeat source step 3.

This should be treated as related to Note Repeat:

- Note Repeat captures and holds one quantized source step temporarily.
- Step Order applies a selectable step-index lookup over a phrase/track/layer.

Open design questions:

- Where does the selectable step-order modification live: project-level, phrase-level, track-level, or layer-level?
- Is there one project-wide step-order map that can be toggled on/off, or multiple named maps?
- How does this interact with future layer-like transformations that add notes rather than only remap step indexes?
- Is the first pass strictly a 16-step lookup, or does it need to scale with clip/phrase length?
