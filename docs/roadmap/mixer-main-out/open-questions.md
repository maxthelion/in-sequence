# Mixer Main Out — Open Questions

Raised during `write-architecture` on 2026-04-30.
Three questions from the UX review cannot be resolved without user input.
Questions 3, 4, and 5 (unity position, empty-state affordance, narrow viewport policy)
are resolvable in spec and are not listed here.

---

## Questions For The User

### 1. Which scene's insert chain shows when the crossfader is mid-blend?

When the crossfader is positioned between Scene A and Scene B (i.e., both scenes are active at
partial weights), the master out panel in the mixer shows one scene's insert chain under the
"Inserts (Scene: X)" label. Which scene should that be?

Options:
- **A. Always the A-slot scene** — simple and predictable; the A scene is conventionally dominant.
- **B. The scene with the higher crossfader weight** — reflects the current blend; changes as the
  crossfader moves.
- **C. Both chains, with a separator** — maximum information; layout may be cramped.

This determines the view binding and the display label in the spec. It has no impact on the audio
model (inserts are already per-scene; no new model fields are required for any option).

---

### 2. Master fader: one global level or a per-scene level?

The master out section shows a fader that controls the final output gain. Should that fader be:

- **A. Global (one level for the whole project, applied after the A/B crossfade blend):**
  The most common DAW behavior. A new field `MasterBusState.masterOutputGain` would be added.
  The fader always shows the same position regardless of which scene is active.

- **B. Per-scene (a separate level for each scene, using the existing `MasterBusScene.outputGain`
  field that is currently hard-wired to 1.0):**
  A less common but possible approach. Different scenes could have different output levels. The
  fader position changes when the active or displayed scene changes.

The user story says "control the final output independently of individual tracks or busses," which
most naturally implies a single global control. Option A is the architectural recommendation, but
this is a product decision that affects the document model and audio graph.

---

### 3. Clip indicator: user-action-only reset, or also auto-reset after a hold period?

User story 3 states the clip indicator "stays latched until manually cleared." The acceptance
signal repeats: "it does not reset on its own until the user clears it."

This strongly implies that only pressing the "CLR" button should clear the indicator. However, the
UX review flagged this as a question in case an automatic hold-and-reset option is also wanted.

Please confirm one of:
- **A. User-action-only reset** (matches the user story as written; conventional DAW behavior).
- **B. User-action-only reset with an optional auto-clear timer** (additive; can be added later).

If the answer is A, this question is closed and the spec proceeds with a manual-clear-only
implementation. No architecture change is required for option B if it is deferred to a later
iteration.
