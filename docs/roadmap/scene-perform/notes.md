# Scene Perform Notes

## Raw Intent

```text
the cross fader is a bit too wide. The UI should probably be 3 cells side by side, with the fader in between the scene cells. There's a separate need to address scenes in phrases. Is that captured as another item?
```

## Clarified Concern

Captured from user clarification on 2026-04-29.

## Notes

the cross fader is a bit too wide. The UI should probably be 3 cells side by side, with the fader in between the scene cells. There's a separate need to address scenes in phrases. Is that captured as another item?

## Clarification 2026-04-29

Current Perform mode (screenshot referenced):

- Header `Scenes` with `Browse/Edit | Perform` mode toggle.
- A horizontal A↔B crossfader spanning the full pane width.
- Below: two scene cards side by side (`Slot A — Scene A`, `Slot B — Scene B`), each with eight macro slots (M1–M8) and per-slot Revert / Save to Scene buttons.
- A blend percentage readout and `Reset` / `Save Blend` buttons at the right end of the fader row.

Concrete UX problem: the fader is visually and physically decoupled from the two scene cards. Crossfading A↔B means a long mouse drag across the full width of the pane while the cards it controls sit underneath rather than at its endpoints.

Proposed layout: three cells side by side — `Scene A | crossfader | Scene B` — so the fader sits **between** the two scene cells and its travel distance is the gap between them.

Workflow scope: treat this as Octatrack-style. Performers may hard-switch A↔B, blend live with the fader as a continuous control, cue ahead, or anything in between. The redesign should support all of those equally rather than optimising for one. The reason the fader needs to be repositioned is ergonomic, not workflow-specific.

Out of scope here: scenes-in-phrases. That stays as its own roadmap item (`docs/roadmap/scenes-in-phrases/`, item 22). Do not draft stories for it under Scene Perform.

Target window: not driven by a specific device or screen size. The "long reach" complaint applies on the current desktop layout in general — there is no small-display or hardware-controller constraint shaping this. The current crossfader is just a big mouse drag.
