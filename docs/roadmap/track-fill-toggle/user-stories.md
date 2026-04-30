# Toggle Fill On A Track User Stories

## Architecture Boundary (Required Context)

Fill today is a **phrase-authored boolean layer**, not a runtime state. Each track's fill status is compiled into `PhrasePlaybackBuffer.TrackPhrasePlaybackBuffer.fillEnabled: [Bool]` before playback begins. There is no `setLiveFill(trackID:)` or equivalent runtime override path. The engine reads `fillEnabled` from the precompiled buffer at tick time.

This means the toggle described in these stories cannot be wired into the existing compiled fill path without either:

1. A new live runtime override that shadows the compiled value during playback (new engine state), or
2. A phrase mutation that writes to the `"fill-flag"` boolean layer cells directly (persisted edit, not a preview toggle).

Which of these two models is chosen is the central open design question. The stories below are written in terms of the observable user goal; the boundary is called out explicitly in the Assumptions section.

---

## Stories

### 1. Preview fill pattern while editing a track

- **As a:** producer editing a track in the track editor
- **I want:** a fill toggle I can flip without leaving the editor
- **So that:** I can immediately hear how the fill variation of this track sounds against the rest of the arrangement without navigating to the perform page
- **Done when:** activating the toggle causes the track to play its fill lane content (instead of its main lane content) in real time; deactivating it returns to main lane content; no other tracks are affected

### 2. Know at a glance whether fill is active during editing

- **As a:** producer editing a track in the track editor
- **I want:** the fill toggle to have a clear active/inactive visual state
- **So that:** I never lose track of whether I am listening to the fill variant or the main variant while making edits
- **Done when:** the toggle shows a visually distinct active state when fill is on and a clearly neutral state when fill is off; the state persists for the duration of the editing session or until I change it

### 3. Fill preview does not permanently alter the phrase

- **As a:** producer auditioning fill behavior
- **I want:** the preview toggle to be a transient playback state, not a phrase edit
- **So that:** toggling fill to preview it does not dirty the document or change what the sequencer will do in a normal performance where fill is phrase-controlled
- **Done when:** toggling the fill preview on and off leaves the phrase's `"fill-flag"` layer cells unchanged; the document is not marked as modified as a result of the toggle alone

### 4. Fill toggle is scoped to the track being edited

- **As a:** producer working on one track in a drum group
- **I want:** the fill toggle to affect only the track currently open in the editor
- **So that:** I can isolate and audition the fill variation of a single part without accidentally forcing fill on sibling drum parts
- **Done when:** toggling fill for track A does not change playback behavior of track B, even if A and B share a drum group

---

## Acceptance Signals

- Flipping the toggle mid-playback is audibly reflected within at most one phrase step (no full restart required)
- The toggle state is clearly visible in the track editor at all times the editor is open
- Closing the track editor or switching to a different track resets the toggle to its default off state (no fill preview bleeds into normal performance)
- The phrase grid and the document dirty flag are unaffected by toggling the preview
- Generator-backed tracks surface a clear affordance or message if fill preview cannot apply (fill is currently only wired into clip steps, not generator steps — see existing-state.md for note-repeat)

---

## Assumptions

- **Story 3 ("transient, not a phrase edit")** assumes the feature is implemented as a runtime override that shadows the compiled fill state, not as a phrase mutation. If the implementation team chooses phrase mutation instead, Story 3 must be revisited.
- The toggle lives in the track editor UI, not on a perform-page button strip. The exact placement (relative to lane controls, clip header, or a dedicated toolbar row) is deferred to the UX review stage.
- Fill preview applies only to clip-backed steps. Generator-backed steps ignore fill today (`EngineController` only passes `fillEnabled` into the clip branch). If generator fill support is added, it is out of scope for this feature.
- Grouped drum part behavior (Story 4) defaults to isolated/per-track until a design decision is made otherwise.
