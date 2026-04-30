# Modifier Chain Placement User Stories

## Stories

### 1. Remove a clip source and replace it with a generator

- **As a:** producer who has built a track around a clip and now wants to experiment with a generative source
- **I want:** to remove the current clip from the track's source slot and immediately see an option to place a generator in its place
- **So that:** I can switch the track's driving voice mid-session without navigating away from the track view or wading through unrelated options
- **Done when:** the source slot shows a clear remove action; after removal, a plus button appears in the same slot; tapping the plus presents an option to add a new blank generator as the first, most prominent choice

### 2. Add a source to an empty track slot from a set of options

- **As a:** producer starting a new track or working with a track that has just had its source cleared
- **I want:** the empty source slot to offer four distinct options — add new blank clip, select clip from pool, new blank generator, select generator — without leaving the current screen
- **So that:** I can get a sound source placed quickly and keep my working context
- **Done when:** tapping the plus in an empty source slot reveals the four options in a contained UI element (modal or panel) that stays within the same screen; selecting any option closes the picker and populates the slot with the chosen source

### 3. Identify at a glance whether a track is driven by a clip or a generator

- **As a:** producer arranging or performing
- **I want:** the source and modifier areas of a track to be visually distinct labelled slots, similar to tabs, so I can tell what type of source is loaded and whether any modifiers are attached
- **So that:** I do not have to interpret ambiguous controls or hunt for a "switch to generator source" affordance buried in a menu
- **Done when:** the track UI presents a clearly labelled source slot and a clearly labelled modifier slot; each slot's current content (clip, generator, or empty) is legible at a glance

### 4. Manage the modifiers slot with the same interaction model as the source slot

- **As a:** producer who chains modifiers onto tracks (such as arpeggiators, transposers, or rhythm gates)
- **I want:** the modifier well to support the same add/remove interaction as the source slot — a plus to add when empty, a remove action when occupied — so there is a consistent mental model across both slot types
- **So that:** I do not need to learn a separate interaction pattern for modifiers
- **Done when:** the modifier slot behaves symmetrically with the source slot for add and remove; the specific options in the modifier picker may differ from the source picker but the trigger/dismiss flow is identical

### 5. Perform the most common swap (clip to generator) with minimal steps

- **As a:** producer under time pressure or performing live
- **I want:** the fastest path to replace a clip with a generator to require the fewest taps and no screen navigation
- **So that:** I can restructure a track's source on the fly without breaking my creative momentum
- **Done when:** a user can remove an existing clip source and place a new blank generator in two or three interactions that stay within the current track view; the generator option is the most prominent choice after the source slot is cleared

## Acceptance Signals

- A track loaded with a clip shows a remove control on the source slot; no "switch to generator source" label or separate button is present
- After removing the source, a plus button appears in the same slot location without a layout shift that disorients the user
- The source picker (opened via the plus) presents four options and does not navigate to a new screen
- The modifier slot has a visually analogous empty/occupied/add/remove treatment to the source slot
- The swap flow (clip removed, generator placed) takes no more than three taps and never leaves the track view

## Assumptions

- The application model already supports both clip and generator source types on a track; the gap is in the UI surface, not the underlying model
- "Select clip from pool" and "select generator" imply an existing pool/library picker that can be invoked in-context; if that picker does not exist, those two options may be deferred or replaced with a placeholder
- "Modifiers" in this context are the chain of event-transformation objects (e.g. arpeggiator, transposer) that sit after the source; the stories do not prescribe a maximum chain length
- A modal that stays within the same screen is acceptable for progressive disclosure; a full-screen navigation push is explicitly undesirable
