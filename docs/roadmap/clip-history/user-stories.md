# Clip History User Stories

## Stories

### 1. Capture A Good Generated Moment

- **As a:** musician running a generator on a track
- **I want:** to open clip history from the generator view after hearing something I like
- **So that:** I can keep a useful generated phrase without manually recreating it
- **Done when:** the generator view has a clear Clip History entry point that opens a history modal for the current track.

### 2. Review Recent Generated Output

- **As a:** musician deciding whether generated material is worth keeping
- **I want:** to see the notes produced by the track's generator chain over the recent 16-bar history
- **So that:** I can choose from what actually happened instead of guessing from memory
- **Done when:** the modal presents generated note output across the recent history with enough timing and pitch information to identify candidate moments.

### 3. Audition History As A Predictable Clip

- **As a:** musician moving from generative exploration to arrangement
- **I want:** playback to switch to a virtual clip made from the selected historical output
- **So that:** I can hear the captured material as a repeatable phrase before committing it
- **Done when:** selecting a history region plays it as a virtual clip and the track no longer depends on live generator variation for that audition.

### 4. Adjust The Capture Length

- **As a:** musician shaping a captured phrase
- **I want:** to change the virtual clip length
- **So that:** I can capture a one-bar idea, a longer phrase, or a shorter fragment without leaving the modal
- **Done when:** the modal exposes a length control and playback updates to reflect the chosen virtual clip length.

### 5. Save History To A Pattern Slot

- **As a:** musician committing generated material
- **I want:** to choose a pattern slot at the bottom of the modal and save the virtual clip there
- **So that:** the captured material becomes a real clip in the track's pattern workflow
- **Done when:** selecting a pattern slot creates a new clip in that slot from the current virtual clip.

### 6. Avoid Accidental Loss Or Overwrite

- **As a:** musician saving into existing pattern structure
- **I want:** the modal to make slot state and save consequences clear
- **So that:** I do not overwrite useful clips or save to the wrong pattern by accident
- **Done when:** pattern slots show whether they are empty or occupied and any overwrite behavior is explicit before committing.

## Acceptance Signals

- A user can get from a running generator to recent generated output in one clear action from the generator view.
- The history modal can represent at least 16 bars of recent generated note output for the current track.
- A selected historical region can be auditioned as a repeatable virtual clip.
- The virtual clip length can be changed before saving.
- Pattern slots are visible in the modal as save targets.
- Saving creates a concrete clip in the chosen pattern slot.
- The workflow distinguishes temporary virtual playback from committed clip creation.
- Occupied pattern slots are visually distinct from empty slots.

## Assumptions

- The first pass focuses on generated note output, not parameter automation or non-note events.
- The 16-bar history is the initial target window unless later UX review argues for configurability.
- Saving to a pattern slot creates a new clip from the virtual clip state at save time.
- Overwrite behavior needs explicit design during the prototype/spec phase.
- The existing-state pass should determine whether history needs to capture pre-modifier generator output, post-modifier output, or both.
