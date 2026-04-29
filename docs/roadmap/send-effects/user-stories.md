# Send Effects User Stories

## Stories

### 1. Route a track to Send A or Send B

- **As a:** producer arranging a track
- **I want:** to dial in how much of any track's signal is sent to Send A and Send B
- **So that:** I can blend wet effect returns (reverb, delay, etc.) without affecting the dry signal level
- **Done when:** each track in the mixer shows a send-amount knob (or equivalent control) for Send A and a separate one for Send B; adjusting the knob audibly changes the amount of signal arriving at that send bus

### 2. Add insert effects to a send bus

- **As a:** producer shaping the wet sound of a send
- **I want:** to place effects (e.g. a reverb or delay plugin) as inserts on Send A or Send B
- **So that:** all signals routed to that bus pass through the same shared effect, saving CPU and keeping the mix cohesive
- **Done when:** Send A and Send B each expose an insert-effect chain; I can add, reorder, bypass, and remove effects; the processed signal is audible at the send bus output

### 3. Hear send bus output in the mix

- **As a:** producer monitoring a mix
- **I want:** the processed output of Send A and Send B to be mixed back into the main output automatically
- **So that:** the wet return blends with the dry tracks without requiring manual routing beyond enabling the send
- **Done when:** with at least one effect on a send bus and a non-zero send amount on any track, the effect return is audible in the main mix output

### 4. Control send-level independently per track

- **As a:** mixing engineer balancing wet/dry ratios per instrument
- **I want:** each track to remember its own send-amount value for Send A and Send B independently
- **So that:** I can, for example, send drums heavily to reverb and vocals lightly, without coupling their wet levels
- **Done when:** changing the send amount on one track does not alter the send amount on any other track; values persist across session save/reload

### 5. Send post- or pre-fader (stretch goal)

- **As a:** mixing engineer doing a headphone cue mix or a special effect
- **I want:** to choose whether each track's send taps the signal before or after the channel fader
- **So that:** I can build an independent headphone mix (pre-fader) or keep wet levels proportional to the dry level (post-fader)
- **Done when:** a pre/post toggle is available per send; toggling it changes whether fader moves affect the send level

## Acceptance Signals

- Turning up a send knob on a track with a reverb inserted on that bus results in audible reverb in the output
- Two tracks can have different send amounts to the same bus simultaneously
- A session with non-zero send amounts and effect inserts on Send A/B loads correctly and sounds the same as before save
- Removing all effects from a send bus passes signal through silently (unity) or the bus is otherwise inert
- Send A and Send B are always present; the user does not need to create or name them

## Assumptions

- There are exactly two send busses: Send A and Send B. They are fixed and always present — the user cannot add more send busses (user-added submix busses are handled by Mixer Busses, item 5).
- Send amount is a single continuous knob value (not a matrix of gain stages). Whether it maps to a pre- or post-fader tap is initially post-fader; pre-fader is a stretch goal.
- Effects on send busses are inserts in series, matching the same insert-effect model used on tracks and user busses (item 5).
- Send bus output routes automatically to the master output; no user-side return routing is required.
- The sends knobs are surfaced in the mixer view alongside existing track controls.
- This feature depends on there being a mixer view (Mixer Main Out, item 4) and an insert-effect chain mechanism; if neither exists yet, those are prerequisites.
