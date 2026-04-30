# Step Order User Stories

## Stories

### 1. Remap step playback with a step-order lookup

- **As a:** producer building a looping phrase on a track
- **I want:** to define a step-order map — for example `[0,1,2,3,3,3,3,3,7,8,9,0,1,2,3]` — so the playhead resolves each output step to a source step index instead of advancing sequentially
- **So that:** I can create rhythmic variations (repeats, reorders, accent patterns) without actually editing the underlying clip data
- **Done when:** playback reads the step-order lookup and produces the expected note output, leaving the original clip unchanged

### 2. Toggle the step-order map on and off

- **As a:** performer playing a live set
- **I want:** to toggle the step-order map on and off while a track is running
- **So that:** I can switch between the raw clip sequence and the remapped playback at will without re-entering the data
- **Done when:** toggling the map in or out takes effect within the next phrase cycle and no clip content is modified

### 3. Select where the step-order map is applied

- **As a:** producer working across multiple tracks
- **I want:** to know — and control — whether the step-order map applies at the project level, phrase level, or track level
- **So that:** I can apply the same remap to all tracks or scope it narrowly to one track without accidental side-effects
- **Done when:** the scope of the map (project / phrase / track / layer) is visible and adjustable, and playback respects the chosen scope

### 4. Edit the step-order lookup in place

- **As a:** producer who wants to tweak a phrase's feel
- **I want:** to see and edit the step-index array as a named, saveable structure
- **So that:** I can iterate on the remap, compare named maps, and reuse them across sessions
- **Done when:** the map can be created, named, edited, and recalled without re-entering values each session

## Acceptance Signals

- A 16-step map like `[0,1,2,3,3,3,3,3,7,8,9,0,1,2,3]` plays back the correct source steps in the correct order
- Disabling the map restores normal sequential playhead behaviour with no clicks or glitches
- Toggling on/off during playback does not alter clip data
- The scope (project / phrase / track / layer) is unambiguous from the UI
- The map persists across save/load of a project

## Assumptions

- The first implementation targets a fixed 16-step lookup array; scaling with variable clip/phrase length is deferred
- The feature is non-destructive: the original clip/step content is never written when the map is active
- There is at most one active step-order map per scoped entity at a time (multi-map stacking is a future concern)
- The relationship to Note Repeat is conceptual; they do not need to share UI or data structures in the first pass
- Whether the scope is project-level, track-level, or something else remains an open design question (see `open-questions.md` if that question blocks implementation)
