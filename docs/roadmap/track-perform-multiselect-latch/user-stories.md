# Track Perform Multi-Select And Latch User Stories

## Stories

### 1. Select an edit set of tracks on the Track Perform screen

- **As a:** performer adjusting several tracks during a live pass
- **I want:** to select multiple tracks on the Track Perform screen before editing perform values
- **So that:** I can treat those tracks as one temporary edit set instead of repeating the same gesture on each track
- **Done when:** the screen lets me place more than one track into a selected state; the selected set remains active while I make perform edits; unselected tracks are clearly outside the edit set

### 2. Apply one perform-cell change to every selected track

- **As a:** performer who has selected multiple tracks
- **I want:** changing one perform cell on one selected track to copy that same value into the corresponding cell on the other selected tracks
- **So that:** I can make synchronized performance edits quickly without opening each track individually
- **Done when:** editing a cell on one selected track updates the same cell/value on every other selected track in the selection; tracks outside the selection are unaffected

### 3. Understand which tracks will be changed before I commit a linked edit

- **As a:** performer working quickly under playback
- **I want:** the Track Perform screen to show selected-track state clearly while multi-select is active
- **So that:** I do not accidentally overwrite perform values on the wrong tracks
- **Done when:** selected tracks are visually distinct from unselected tracks before and after an edit; the UI makes it obvious that linked edits apply only within the current selection

### 4. Use momentary behavior for on/off performance controls

- **As a:** performer using transient effects such as Fill or Note Repeat
- **I want:** latch-off mode to turn an on/off performance feature on while I hold it and turn it back off when I release it
- **So that:** I can punch effects in rhythmically for a brief gesture without manually toggling them back off
- **Done when:** pointer down engages the feature immediately in momentary mode; pointer up disengages it; the control returns to its prior off state without requiring a second click

### 5. Use latched behavior for on/off performance controls

- **As a:** performer who wants a performance feature to stay enabled
- **I want:** latch-on mode to toggle the current state of an on/off performance feature instead of behaving momentarily
- **So that:** I can leave a perform effect active across multiple beats or bars until I decide to change it
- **Done when:** activating the control in latch mode flips its persisted on/off state; the feature remains active after release until I toggle it again

### 6. Expect the same latch model across binary perform features

- **As a:** performer switching between Track Perform controls
- **I want:** Fill, Note Repeat, and other binary performance features to follow the same latch-versus-momentary interaction model
- **So that:** I do not have to relearn press behavior for each feature during a performance
- **Done when:** the same latch setting yields the same pointer-down and pointer-up behavior across the supported binary perform controls on the page

## Acceptance Signals

- Multi-select can be enabled for more than one track without leaving the Track Perform screen
- Editing one selected perform cell copies the same value to the corresponding cell on every selected track and never touches unselected tracks
- The screen always makes the selected edit set visible enough that a performer can predict the scope of a linked edit before interacting
- The initial multi-select interaction uses direct cell editing on the matrix rather than requiring a modal or side inspector for ordinary linked edits
- In latch-off mode, binary perform controls behave momentarily: press engages, release disengages
- In latch-on mode, the same controls behave as toggles and keep their state after release
- Fill and Note Repeat share the same latch semantics in v1, with room for additional binary perform controls to opt into the same model later

## Assumptions

- The v1 multi-select rule is the simplest one described in [[feature:track-perform-multiselect-latch]] notes: editing one selected cell writes that same value into the corresponding cell for every other selected track
- Multi-select is scoped to the Track Perform surface only; it does not imply persistent track grouping elsewhere in the app
- The first usable version favors direct matrix interaction over a modal or side-panel editor, unless later prototype work shows that direct editing is too ambiguous
- "Performance features that are on or off" refers to binary controls such as Fill and Note Repeat, not continuous controls that would need a different gesture model
- The notes define pointer-down and pointer-up semantics for mouse or trackpad input; keyboard and hardware-controller interaction can be refined in later artifacts
