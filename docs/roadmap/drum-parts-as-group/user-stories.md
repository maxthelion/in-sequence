# Drum Parts As A Group User Stories

## Stories

### 1. Navigate between drum parts without leaving the part view

- **As a:** producer editing individual drum parts one at a time
- **I want:** left/right navigation controls at the top of the current part view so I can step through all parts that belong to the same drum track
- **So that:** I can quickly audition and adjust each part in sequence without hunting for it in the track list
- **Done when:** the part view header shows a previous/next control that moves to the adjacent part in the kit, the current part name is visible in the header, and the navigation wraps or is bounded at the kit edges

### 2. Open the full kit group view from a single part

- **As a:** producer working inside a single drum part
- **I want:** a button at the top of the part view that opens the drum kit group view for the whole kit
- **So that:** I can see the full picture of all parts and their step patterns at once, without losing my place in the current part
- **Done when:** the button is present in the part header, activating it opens the kit group view, and returning from it restores the previously selected part

### 3. See all drum parts as a step matrix

- **As a:** producer arranging or programming a drum kit
- **I want:** a matrix view that lists every part in the kit on the left with its step pattern running horizontally to the right
- **So that:** I can see at a glance which steps are triggered across all parts, spot gaps and conflicts, and understand the groove holistically rather than part by part
- **Done when:** each row shows the part name on the left and a read-legible representation of its active steps to the right; the view accounts for the fact that each part's pattern may have a different length or be independent

### 4. Understand which patterns are active for each part in the kit context

- **As a:** producer viewing the group matrix
- **I want:** each part row to show which pattern is currently selected for that part
- **So that:** I can tell whether the parts I see are actually what will play together, given that patterns per part are independent
- **Done when:** the matrix clearly indicates the active pattern for each part, and it is obvious when parts are not set to patterns that would be heard together in the current playback state

### 5. Assign a shared or alternative output destination for all parts in the kit

- **As a:** producer routing a drum kit to hardware or a DAW
- **I want:** to be able to set a group-level output destination that all parts in the kit use, as an alternative to their individual destinations
- **So that:** I can route an entire kit to a single MIDI port or bus without editing each part separately
- **Done when:** the kit group view has a destination field that, when set, applies to all parts; individual part destinations are still editable and override the group destination when set

### 6. Define how each part's trigger maps to the shared destination

- **As a:** producer using a shared or combined MIDI output for the whole kit
- **I want:** to specify whether each drum part maps to a separate MIDI channel or a separate MIDI note within the shared destination
- **So that:** the triggers reach the right instrument or drum machine slot for each part, whether I am targeting a multi-channel drum module or a GM-style MIDI receiver
- **Done when:** the kit group view lets me choose a trigger mapping mode (one part per MIDI channel, or one part per MIDI note) and shows the resulting channel or note assignment for each part row in the matrix

## Acceptance Signals

- A producer can move from kick to snare to hi-hat without leaving the step-editor page.
- The kit matrix view shows the whole kit in one screen; no horizontal scrolling is needed to see the part names.
- It is immediately obvious in the matrix when two parts are on different patterns and therefore may not play together as shown.
- Setting a shared destination in the kit group view does not require opening each part individually.
- The trigger mapping mode (channel vs. note) is visible and editable per kit, not buried in individual part settings.
- Parts that have generators or multiple layers are still represented in the matrix, even if they cannot be fully edited inline.

## Assumptions

- A "drum kit" or "drum track group" is a named collection of individual drum parts that belong together conceptually.
- Individual drum parts are already modelled as separate tracks or subtracks in the sequencer; the grouping layer is what is missing.
- Pattern independence per part is a first-class constraint: the group view must surface this rather than hide it.
- Full inline editing of generator or layered parts from the matrix is out of scope for this feature; those parts are shown read-only or with a link to their dedicated editor.
- The Drum Kit Group View (item 19) and Fill Applied To Whole Kit (item 20) are intentionally deferred until this grouped model is defined here.
- The routing and trigger model described here overlaps with item 19 but is owned here because it is a prerequisite for both that item and item 20.
