# Note Repeat User Stories

## Stories

### 1. Enable note repeat on a track from the perform page

- **As a:** performer working in perform mode
- **I want:** a Note Repeat toggle on each track (alongside the existing Fill toggle)
- **So that:** I can engage repeat playback for a specific track during a live performance without leaving the perform page
- **Done when:** A Note Repeat control is visible per track on the perform page; pressing it activates repeat mode for that track and deactivating it returns the track to normal playback

### 2. Repeat plays the quantized step until the control is released

- **As a:** performer who has toggled Note Repeat on a track
- **I want:** the sequencer to capture the current quantized step at the moment I engage repeat, then loop that step continuously for as long as the toggle is held
- **So that:** I get a locked, rhythmically-exact stutter effect without the repeat drifting off the grid
- **Done when:** The captured step plays back repeatedly on the beat until the toggle is released, at which point the track resumes normal sequence playback from where the transport is

### 3. Set the repeat interval per track layer

- **As a:** performer shaping a track's sound
- **I want:** to configure the repeat interval in the track's layer settings (e.g. repeat/16, repeat/32, repeat/64)
- **So that:** I can dial in a coarse or fine stutter rate independently for each track without affecting others
- **Done when:** The layer exposes a repeat-interval control with at least the three named divisions; the chosen interval determines how often the captured step is re-triggered while Note Repeat is active

### 4. Sub-step repeat intervals fire within a single sequencer step

- **As a:** performer wanting fast rhythmic stutters
- **I want:** repeat intervals smaller than one step (sub-step) to fire multiple times inside a single step's duration
- **So that:** I can achieve rapid-fire repeats (e.g. 32nd-note triplets inside a 16th-note step) without the sequencer advancing to the next step between hits
- **Done when:** A sub-step interval causes the captured step's note to re-trigger at the correct intra-step timing; the sequencer does not advance its step counter between those sub-step firings

## Acceptance Signals

- The Note Repeat toggle appears on the perform page beside the Fill toggle for each track and is clearly labelled
- Engaging the toggle immediately locks onto the quantized step that is active (or was most recently active) at the moment of engagement
- The captured step re-triggers at the exact interval configured in the layer, with no perceptible drift against the sequencer clock
- Releasing the toggle within a bar causes the track to re-join normal sequence playback at the next step boundary, with no stuck notes
- Sub-step intervals produce the correct number of retriggers within a step (e.g. repeat/32 on a 16th-step grid fires twice per step)
- The interval setting persists in the layer when the performer navigates away and returns to the perform page

## Assumptions

- "Like fill" means the Note Repeat toggle follows the same per-track, momentary-hold-or-latch model already used by the Fill toggle on the perform page
- The interval is stored on the track layer, not on a global or scene level — each track independently remembers its repeat rate
- The three intervals named in the notes (16, 32, 64) refer to note-length divisions (1/16, 1/32, 1/64); repeat/16 is the coarsest, repeat/64 the finest
- repeat/32 and repeat/64 are sub-step relative to a 1/16-step grid, so sub-step scheduling support is required for those values
- When Note Repeat is disengaged the track resumes at the next natural step boundary rather than immediately mid-step to avoid clicks or out-of-grid notes
- The captured step is the note content (pitch, velocity, length) of the step that was quantized at engage time; pitch bend or other continuous data is not re-triggered per repeat unless the step contains it
