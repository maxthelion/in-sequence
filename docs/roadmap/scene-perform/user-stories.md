# Scene Perform User Stories

## Stories

### 1. Hard-switch between scenes at a song point

- **As a:** performer stepping through a live set
- **I want:** to click or tap once on Scene B and have it become the active scene immediately
- **So that:** I can make clean, decisive transitions at the right musical moment without dragging a fader across the whole pane
- **Done when:** a single interaction (click/tap) on the off-side scene card commits the full crossfade to that scene (fader snaps to that end); the active scene card state updates instantly

### 2. Blend two scenes live with the crossfader

- **As a:** performer who wants a smooth, continuous morph between two scene states
- **I want:** to drag a crossfader that sits physically between the two scene cards
- **So that:** the fader travel distance maps directly to the blend range and I do not have to reach across the pane to move it
- **Done when:** the fader lives in the centre cell between Scene A and Scene B; dragging it end-to-end covers only the width of that centre cell; the blend percentage readout updates in real time during the drag

### 3. Cue the off-side scene before committing to it

- **As a:** performer who rehearses transitions
- **I want:** to inspect and adjust the Scene B (or Scene A) parameters while Scene A is still live
- **So that:** I can verify the off-side scene is set up correctly before I bring it in
- **Done when:** the non-active scene card is fully visible, readable, and shows current macro slot values; interacting with it does not affect the live audio until the crossfade is advanced; there is a clear visual indicator of which scene is currently live

### 4. Recover from an accidental partial blend

- **As a:** performer who overshoots or undershoots the fader mid-set
- **I want:** to reset the blend back to the last full-scene state with a single action
- **So that:** I can recover quickly without hunting for the right parameter values
- **Done when:** a Reset action is reachable from the fader area without moving to a distant part of the pane; pressing it snaps the fader to the nearest full end (whichever scene was most recently fully active) and restores the exact blend state at that end

### 5. Save a live blend as a new scene state

- **As a:** performer who discovers a satisfying mix mid-performance
- **I want:** to commit the current blended state to one of the scene slots
- **So that:** that blend becomes reproducible later
- **Done when:** a Save Blend action is reachable from the fader area; activating it stores the current blended macro values into the designated scene slot; a confirmation affordance prevents accidental overwrites

### 6. Read both scenes at a glance

- **As a:** performer managing a set under stage lighting and time pressure
- **I want:** to see both scene cards and the fader simultaneously in a single unscrolled viewport
- **So that:** I always know the state of both sides without switching views
- **Done when:** Scene A card, the centre fader cell, and Scene B card all fit side by side in the perform pane without horizontal scrolling; each card shows all eight macro slots (M1–M8) with their current values

## Acceptance Signals

- Moving the crossfader from end to end requires a short drag (roughly the width of one scene card) rather than a full-pane sweep
- The active/inactive scene is immediately distinguishable by visual treatment (colour, label, border, or similar) with no ambiguity
- Hard-switch, live blend, cue-then-commit, and reset-to-clean all work without navigating away from the perform pane
- The blend readout (percentage or equivalent) remains visible during a drag
- Reset and Save Blend remain reachable with a short pointer movement from wherever the fader currently sits

## Assumptions

- The current three-element row (Scene A card, crossfader, Scene B card) covers the full scope of perform interaction; no additional controls (e.g., record or automation triggers) are needed in this area for this feature
- "Cueing" is purely visual inspection of the off-side card; live audio preview of the off-side scene is out of scope for this item
- The target environment is desktop (mouse/trackpad); touch or hardware-controller mappings are not a constraint here, though the layout should not preclude them
- Scenes-in-phrases (item 22) is explicitly out of scope; no story here covers triggering scenes from phrase sequencing
- The Save Blend action replaces the in-place "Save Blend" button currently at the right end of the fader row; it moves closer to the fader in the new layout
- Eight macro slots per scene card is the current model; this feature does not change that count
