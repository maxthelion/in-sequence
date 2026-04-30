# Input Audio User Stories

## Stories

### 1. Select An Audio Interface

- **As a:** producer setting up a session
- **I want:** to open preferences and pick my audio interface from a list of available devices
- **So that:** the app routes live audio through the correct hardware before I start recording or monitoring
- **Done when:** after selecting an interface in preferences, the chosen device is used for all subsequent audio input and output without requiring a restart

### 2. Create An Audio Input Track

- **As a:** producer working with external instruments or a microphone
- **I want:** to add an audio input track to my session that captures signal from the selected interface
- **So that:** I can route a live audio source into the mixer alongside my sequenced tracks
- **Done when:** an audio input track exists in the session, signal flows from the hardware input through the track and into the mixer, and levels are visible on the track

### 3. Record A Loop From Live Input

- **As a:** live performer or producer capturing a phrase
- **I want:** to record the incoming audio signal into a loop buffer on the track
- **So that:** I can loop a live take in sync with the session without leaving the sequencer
- **Done when:** pressing record captures audio into the buffer, the recording stops automatically at the chosen bar length (1, 2, 4, or 8 bars), and the resulting loop plays back in time with the session

### 4. Choose Recording Length In Bars

- **As a:** performer about to record a loop
- **I want:** to select how many bars the recording will last (1, 2, 4, or 8) before I arm the track
- **So that:** the loop length is musically predictable and I do not have to manually stop recording mid-phrase
- **Done when:** a bar-length control is visible on the track page with those four options, the selection persists until changed, and the recording stops exactly at that boundary

### 5. Schedule A Record Trigger (Quantized Arm)

- **As a:** live performer who wants hands-free, on-beat recording starts
- **I want:** to arm the track so that recording begins automatically at the next bar boundary, the way the Octatrack does it
- **So that:** my loops start on the beat without me having to time a button press precisely during a performance
- **Done when:** arming the track queues a pending record trigger, a visual indicator shows the trigger is pending, and recording starts exactly at the next bar boundary once the sequence reaches it

### 6. Toggle Between Live Input And Recorded Loop

- **As a:** performer monitoring or performing with a recorded loop
- **I want:** to switch the track between listening to the live input and playing back the recorded loop
- **So that:** I can audition the incoming signal before recording, confirm the capture sounds right, and blend or replace it during a set
- **Done when:** the track page has a clear toggle for "input" versus "loop" mode, switching is immediate, and the active mode is visually obvious at a glance

### 7. See A Waveform On The Track Page

- **As a:** producer or performer working with recorded audio
- **I want:** the track page to show a waveform of the recorded loop, similar to the slicer track view
- **So that:** I can visually confirm what was captured and understand the shape of the phrase without playing it back
- **Done when:** after recording, a waveform representation of the buffer is drawn on the track page and updates when a new recording is made

## Acceptance Signals

- Selecting a different audio interface in preferences is reflected immediately in routing without crashing or requiring an app restart.
- Creating an audio input track adds it to the session and the mixer; removing it cleans up routing.
- Recording starts on the exact bar boundary when a quantized trigger is armed, and stops automatically at the chosen bar length.
- The input/loop toggle changes the monitored signal with no audible dropout between the two modes.
- The waveform on the track page is drawn from the actual record buffer, not a placeholder.
- All four bar lengths (1, 2, 4, 8) can be selected and produce recordings of the correct duration.
- The track page layout is recognizably similar to the slicer track in terms of waveform presence and general control placement.

## Assumptions

- The session already has a concept of a mixer; the audio input track feeds into it as a standard channel.
- "Scheduled record trigger" means quantized to the next bar boundary, matching the Octatrack behaviour described in the notes.
- The record buffer holds one loop at a time per track; replacing it with a new recording is acceptable for this first pass.
- Bar length defaults to some reasonable value (e.g., 1 or 4 bars) when the track is first created.
- The waveform display does not need editing capabilities in this pass; read-only visual feedback is sufficient.
- Audio interface selection lives in app preferences, not per-session settings.
