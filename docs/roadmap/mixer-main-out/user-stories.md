# Mixer Main Out User Stories

## Stories

### 1. Dedicated master-out section in the mixer

- **As a:** producer mixing a live performance or arrangement
- **I want:** a clearly separated master out section in the mixer (distinct from individual track channels and bus channels)
- **So that:** I can understand at a glance how the full signal chain is organised and control the final output independently of individual tracks or busses
- **Done when:** the mixer UI renders a master out column/panel that is visually distinct from track and bus sections, and any change to the master fader affects only the main output gain

### 2. Insert effects on the master out

- **As a:** producer shaping the final mix
- **I want:** to add, reorder, enable/disable, and remove insert effects on the master out channel
- **So that:** I can apply compression, limiting, EQ, or other processing to the full mix without routing to a separate bus
- **Done when:** the master out section exposes an insert effects chain UI; effects can be added from the available effects list; bypass and remove work per insert; the chain processes audio in slot order before the main output

### 3. Decibel metering with clip indication on the master out

- **As a:** producer monitoring output levels
- **I want:** a calibrated dB level meter on the master out that lights a visible clip indicator when the signal exceeds 0 dBFS
- **So that:** I can catch clipping immediately and adjust gain or inserts before the output is distorted
- **Done when:** the master out meter displays real-time peak levels in dBFS; a clip indicator activates when any sample exceeds 0 dBFS and stays latched until manually cleared; the meter scale shows at least the range from -∞ to 0 dBFS with labelled tick marks

### 4. Scene A / B crossfader in the master out section

- **As a:** performer transitioning between scenes during a live set
- **I want:** to see the scene A and scene B assignment and the crossfader position directly in the master out section
- **So that:** I can monitor and adjust the A/B blend from the same place where I watch my output levels, without switching to a separate perform view
- **Done when:** the master out section shows which scenes are assigned to A and B slots; the crossfader position is displayed and controllable inline; moving the crossfader blends the two scene outputs as expected by the Scene Perform feature (roadmap item 2)

## Acceptance Signals

- Opening the mixer shows a master out section that is unambiguously separate from track channels and bus channels
- Dragging the master fader changes the loudness of the final audio output without affecting individual track or bus fader levels
- Adding a limiter as a master insert processes the full mix at the end of the signal chain
- Sustained loud audio causes the clip indicator to light; it does not reset on its own until the user clears it
- The dB meter updates smoothly during playback without flickering or stalling
- The crossfader widget in the master out matches the state shown in the Scene Perform view

## Assumptions

- The mixer already has or is gaining distinct sections for tracks and busses (roadmap items 5 and 6); this feature covers only the master out section
- Insert effects on the master out use the same effect types available elsewhere in the project (no new effect types are required by this story)
- The Scene A/B crossfader in the master out is a view onto the same underlying crossfader state owned by the Scene Perform feature (item 2); master out does not own the crossfader model, it surfaces it
- "Clip indicator stays latched" is the conventional behaviour; if the engine does not yet support per-sample peak detection that is an existing-state gap to note, not a blocker for this story
- Decibel scale and ballistics (peak hold duration, meter refresh rate) are implementation decisions deferred to the spec stage
