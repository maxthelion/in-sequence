# Scenes In Phrases User Stories

## Stories

### 1. Assign scene slots per phrase

- **As a:** composer arranging a song out of phrases
- **I want:** each phrase in Scenes mode to store which scene is loaded into slot A and which scene is loaded into slot B
- **So that:** every phrase can recall its own scene pairing instead of relying on whichever live scene pair happened to be active before playback reached it
- **Done when:** a phrase row exposes editable Scene A and Scene B targets; changing either target persists with that phrase; revisiting the phrase restores the authored pair consistently

### 2. Set a static crossfader position for an entire phrase

- **As a:** composer shaping a section with one stable scene blend
- **I want:** to set one crossfader value that applies for the full duration of a phrase
- **So that:** I can author a phrase that leans toward Scene A, sits at a balanced midpoint, or lands fully on Scene B without drawing per-step automation
- **Done when:** the phrase row supports a whole-phrase crossfader value; playback applies that value from phrase start to phrase end unless a different automation mode is selected; the stored value is visible in the matrix

### 3. Author per-bar scene blend changes inside a phrase

- **As a:** composer building evolving transitions across a phrase
- **I want:** to specify different crossfader positions for different bars within the same phrase
- **So that:** the arrangement can move gradually between Scene A and Scene B as the phrase plays
- **Done when:** the phrase exposes a per-bar crossfader mode; each bar can store its own blend value; playback advances through those bar values deterministically as the phrase progresses

### 4. Switch the phrase matrix between track editing and scene editing

- **As a:** user already working in the existing phrase matrix
- **I want:** a clear way to toggle the phrase view between Tracks mode and Scenes mode
- **So that:** I can edit phrase-level scene behavior in the same overall workspace without confusing it with track/layer editing
- **Done when:** the phrase view exposes two explicit modes, Tracks and Scenes; switching modes changes the matrix columns accordingly; returning to Tracks mode leaves existing track data unchanged

### 5. Read scene intent quickly from the phrase row

- **As a:** performer or composer scanning an arrangement
- **I want:** each phrase row in Scenes mode to summarize the selected A scene, crossfader behavior, and selected B scene at a glance
- **So that:** I can understand how a phrase will sound before playback reaches it and compare neighboring phrases quickly
- **Done when:** the row shows the authored Scene A target, the crossfader state or automation pattern, and the Scene B target without opening a secondary editor; adjacent phrases can be compared visually in the matrix

## Acceptance Signals

- Scenes mode makes phrase-authored scene choices visible without being mistaken for the live Scene Perform pane
- A phrase can store both static and per-bar crossfader behavior, with an explicit mode telling the user which interpretation applies
- Phrase playback restores the authored scene pair and blend behavior repeatably when the arrangement revisits that phrase
- Switching between Tracks and Scenes modes does not overwrite or hide phrase data in a way that feels destructive or ambiguous

## Assumptions

- Scene A and Scene B refer to the same scene concept used by live scene performance, but this feature stores authored values on the phrase rather than only in temporary perform state
- Per-bar automation is the richest required control in this slice; finer-grained automation can be deferred unless later architecture work shows it is already cheap
- The phrase matrix remains the primary editing surface, so Scenes mode should fit as a variant of that grid rather than as a separate full-screen editor
- A phrase always has enough structural timing information for bar-level crossfader values to align with phrase playback
