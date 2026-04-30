# Audio Looping User Stories

## Scope Note

Track-level audio looping (selecting an input, recording to a buffer, toggling live-input versus loop playback) is owned by `docs/roadmap/input-audio/`. This slug covers the **macro live-looping performance page** only — a separate surface that lets a performer control recording and playback across capable tracks at a high level.

If a future spec or state-inspection pass uncovers a genuinely separate track-level concern that is not already addressed by Input Audio, that finding should be recorded here before any story is added.

---

## Stories

### 1. Open the live-looping page

- **As a:** performer preparing for a live set
- **I want:** a dedicated page in the app that surfaces only tracks capable of looping
- **So that:** I can focus on macro-level loop control without the detail noise of the main sequencer view
- **Done when:** navigating to the live-looping page shows a list of tracks that have audio recording/playback capability, and tracks that lack that capability are absent from the view

### 2. Arm a track for recording from the looping page

- **As a:** live performer
- **I want:** to tap a single control per track to arm it for recording
- **So that:** I can prepare a track to capture input on the next pass without hunting through settings
- **Done when:** tapping the arm control puts the track into a visually distinct armed state; a second tap or a dedicated disarm action clears it

### 3. Trigger recording across armed tracks simultaneously

- **As a:** live performer
- **I want:** a single global action that starts recording on all currently armed tracks at once
- **So that:** multi-track loops stay in sync without me tapping each track individually
- **Done when:** activating the global record trigger begins recording on every armed track at the same moment; tracks not armed are unaffected

### 4. Toggle a track between loop playback and silence

- **As a:** live performer mid-set
- **I want:** to mute or unmute a recorded loop per track with a single tap
- **So that:** I can bring loops in and out of the mix in real time without stopping playback
- **Done when:** tapping the playback toggle on a track with a recorded loop starts or stops playback of that loop immediately; the visual state reflects the current playback state clearly

### 5. Clear a loop from a track

- **As a:** live performer who wants to re-record a loop
- **I want:** to discard the current recorded loop for a track and return it to an empty/ready state
- **So that:** I can record a new loop without reloading or restarting the session
- **Done when:** activating the clear control removes the recorded loop, returns the track to an unarmed/empty state, and stops any playback of that loop

---

## Acceptance Signals

- The looping page is reachable via a clear navigation action from the main sequencer
- All per-track controls (arm, record, playback toggle, clear) are operable with a single interaction — no multi-step modal flows
- The page is usable in low-light or high-pressure performance conditions: large touch targets, high-contrast state indicators
- Global record trigger is distinct enough from per-track controls to prevent accidental activation
- State transitions (empty → armed → recording → has-loop → playing) are always visually unambiguous

---

## Assumptions

- The underlying track audio model (input selection, buffer management, loop boundary logic) is provided by the Input Audio feature; this page consumes that model rather than defining it
- "Capable tracks" means tracks that have an audio input assigned and a loop buffer available — that capability check is defined in Input Audio
- Loop length is implicitly defined by the recording duration (record start → record stop); no step-sequencer-style quantised loop length is assumed here unless a future note adds it
- This page is intentionally a performance control surface, not an editor; fine-grained waveform editing or loop trimming is out of scope
- The feature remains lower priority than Input Audio and should not be specced or built until Input Audio's track model is stable
