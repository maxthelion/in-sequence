# Song Mode And Phrase Looping User Stories

## Boundary Note

The adjacent feature **Phrase Features** (item 10) owns per-phrase controls: bar length, repeat count, and the permanent-loop toggle that defines "free play vs song mode." This feature (item 11) owns the **transport-level live-performance behavior** that operates on top of those settings: what the top bar shows during free play, how the next phrase is queued, how switching is triggered, and how the Tracks UI basis phrase tracks the current/cued phrase.

---

## Stories

### 1. Current-phrase indicator in the transport bar

- **As a:** performer playing in free-play mode
- **I want:** the top bar to show which phrase is currently playing
- **So that:** I always know where I am in the arrangement without looking away from the Tracks UI or Phrase Matrix
- **Done when:** while a phrase is playing in free-play mode, the transport bar displays the identifier of the active phrase (e.g. "Phrase A"), updating immediately whenever the active phrase changes

### 2. Queue next phrase via dropdown

- **As a:** performer in free-play mode
- **I want:** a button in the top bar that opens a dropdown listing all available phrases, so I can select which phrase plays next
- **So that:** I can plan the next section of a performance without interrupting the current loop cycle
- **Done when:** tapping the queue button reveals a dropdown of phrases; selecting one marks it as the queued-next phrase; the queued phrase is visually distinct from the current phrase in the dropdown

### 3. End-of-cycle phrase switching

- **As a:** performer who has queued a next phrase
- **I want:** the queued phrase to begin automatically when the current phrase finishes its cycle
- **So that:** transitions happen on the musical beat without me needing to tap anything at the exact moment
- **Done when:** after the current phrase completes its last bar/repeat, playback seamlessly begins the queued phrase; the transport bar updates the current-phrase indicator

### 4. Immediate phrase switch from the dropdown

- **As a:** performer who needs to break from the current loop right now
- **I want:** each phrase option in the dropdown to have a dedicated "switch immediately" button
- **So that:** I can make unscheduled transitions that respond to the energy of a performance in real time
- **Done when:** pressing the immediate-switch button for a phrase causes playback to jump to that phrase at once, without waiting for the current cycle to end; the transport bar updates immediately

### 5. Tracks UI basis phrase follows free-play navigation

- **As a:** performer or arranger who edits during playback
- **I want:** the Tracks UI to always show the phrase that is currently active (or cued) in free-play mode
- **So that:** the step-sequencer grid reflects the section I am actually hearing, preventing edits to the wrong phrase
- **Done when:** whenever the current phrase changes — whether by end-of-cycle transition or immediate switch — the Tracks UI basis phrase updates to match; the same update occurs when a phrase is merely cued (so the performer can preview what comes next)

---

## Acceptance Signals

- A performer can navigate through multiple phrases during a live set using only the top bar, without touching the Phrase Matrix
- The current-phrase label in the transport bar never lags behind what is actually audible
- Queuing a phrase does not interrupt the current cycle; the queue is visually confirmed in the UI
- An immediate switch takes effect without waiting for end-of-cycle; the phrase indicator and Tracks UI both update
- If a performer cues a phrase, the Tracks UI reflects the cued phrase so edits land in the right place

---

## Assumptions

- "Free play mode" means the global playback mode in which a single phrase loops (as set by the permanent-loop toggle in Phrase Features, item 10); this feature's stories operate entirely within that mode
- "Phrase identifier" (e.g. "Phrase A") is already defined by the Phrase Matrix; this feature reuses that naming
- The dropdown is a temporary interaction pattern acceptable for MVP; a dedicated phrase-launch pad may follow later
- Cuing a phrase should update the Tracks UI basis phrase (not just the active phrase) — this is explicit in the 2026-04-29 clarification
- Whether the immediate-switch button dismisses the dropdown automatically is an open UX detail to resolve during prototyping
- Song Mode (fully scripted linear arrangement) is referenced in the raw intent but not fully described; the stories above address the free-play phrase-navigation behavior, which appears to be the primary intent for this item
