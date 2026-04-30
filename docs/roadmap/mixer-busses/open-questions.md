# Mixer Busses — Open Questions

Raised during `write-architecture` on 2026-04-30.
Three questions from the UX review and architecture pass cannot be resolved without user input.
Questions 4–8 (bus chaining scope, routing-change visual, track rename scope, auto-focus, insert
zone height) are resolvable in spec and are not listed here.

---

## Questions For The User

### 1. Solo convention: exclusive or additive?

When a bus or track is soloed, should:

- **A. Exclusive solo (one at a time):** Soloing any strip clears all other solos. Only one
  strip can be soloed at once. The prototype implements this model. Common in hardware-style
  and small-format mixers.

- **B. Additive solo (multiple simultaneous):** Soloing a strip adds it to an audible set.
  Multiple strips can be soloed simultaneously. All unsoloed strips are muted. The standard
  DAW model (Logic, Ableton, Pro Tools). More flexible; slightly more complex in the UI.

This determines the solo state machine design. The exclusive model requires tracking a single
`activeSoloID`; the additive model requires computing a "soloed set" across all tracks and buses.
Both are feasible.

---

### 2. Bus insert scope: global or scene-scoped?

Should a bus's insert chain be:

- **A. Global (same inserts apply in all scenes):** `MixerBus.inserts` is a flat list. Bus
  inserts always apply regardless of which master bus scene is active. Simpler model. This is
  what the prototype shows. Most hardware group buses work this way.

- **B. Scene-scoped (each master scene can have different bus inserts):** `MixerBus.scenes`
  mirrors the `MasterBusState.scenes` architecture. Each scene has its own bus insert chain.
  Significantly more complex model; the bus data structure would need to grow from one insert
  list to a list of scenes each containing an insert list.

Cross-feature note: the Mixer Main Out (item 4) architecture assumes master inserts are
per-scene. If bus inserts are global (option A), the mixer surface will show two different
insert semantics side by side: "Inserts" (global) for buses and "Inserts (Scene: X)" (per-scene)
for master. This difference should be visually explicit. The architectural recommendation is
global inserts (option A), consistent with the prototype and simpler to build.

---

### 3. Delete bus: silent auto-reroute or confirmation?

When the user deletes a bus that has tracks routed to it, should the app:

- **A. Silently re-route orphaned tracks to master** and delete the bus immediately. No warning.
  Simple. Potentially surprising if the user does not notice that their routing changed.

- **B. Show a confirmation prompt** listing the tracks that will be re-routed to master, then
  delete and re-route on confirm. One extra interaction step. Standard DAW behavior (Logic,
  Ableton both warn before deleting a bus with routed tracks).

This determines whether the delete action is a single mutation or a two-step confirm flow. Either
option is straightforward to implement once the decision is made.
