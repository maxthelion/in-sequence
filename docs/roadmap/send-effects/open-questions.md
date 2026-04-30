# Send Effects — Open Questions

Raised during `write-architecture` on 2026-04-30.
Three questions from the UX review and architecture pass cannot be resolved without user input.
Questions 4–9 (mixer placement, control type, zero-knob visual, reorder mechanism, bypass style, signal flow screen) are resolvable in spec and are not listed here.

---

## Questions For The User

### 1. Send bus insert scope: global or scene-scoped?

This question is **blocked on Mixer Busses open question 2** (bus insert scope), which asks the same thing for user-created buses. The answer for send buses must match the answer for user buses.

For context, the choice is:

- **A. Global (same inserts apply in all scenes):** `SendBusState.inserts` is a flat list. Send bus inserts always apply regardless of which master bus scene is active. Simpler model. This is what prototype P02 shows. Standard DAW behavior for send buses (Logic, Ableton, Pro Tools all have scene-independent send bus inserts).

- **B. Scene-scoped (each master scene has its own insert chain for each send bus):** `SendBusState` would need a `scenes: [SendBusScene]` collection, each containing its own insert list. Significantly more complex; the model mirrors `MasterBusState.scenes`. Enables different reverb settings per scene.

The architectural recommendation for send buses is **A (global)**. Send buses in hardware and software mixers almost universally have scene-independent insert chains. However, this feature will use whatever answer is chosen for Mixer Busses (item 5, Q2) to ensure the mixer surface is consistent.

Please answer Mixer Busses Q2 first; the answer automatically resolves this question.

---

### 2. Return path: does the send bus return connect to `finalOutputMixer` or `preMasterMixer`?

When Signal flows from a send bus (after its reverb/delay/effect chain), where should it re-enter the main mix?

- **A. `finalOutputMixer` (bypasses master insert chain) — recommended:** The wet reverb or delay signal is blended at the final output, after master compression and EQ. This is standard DAW behavior: send returns are post-master, so the master bus effects do not process the wet signal a second time. Reverb tails sound natural and uncompressed by the master limiter.

- **B. `preMasterMixer` (wet signal passes through master inserts):** Simpler wiring (one summing node fewer). The wet signal is processed by the master bus insert chain along with the dry tracks. This can cause reverb tails to be double-compressed or over-processed by the master limiter.

The architectural recommendation is **A (`finalOutputMixer`)**. This is what prototype P03 documents as the preferred path and what `existing-state.md` §3 recommends. Option B is acceptable if you want all signals — including send returns — to pass through the master chain.

---

### 3. Muted track and send taps: does muting a track silence its send contribution?

When a track is muted, should it still send signal to Send A and Send B?

- **A. Mute cuts the send tap — recommended:** A muted track contributes nothing to any send bus. Its dry signal is silent and its wet contribution (reverb tail, delay) is also silent. This is standard DAW behavior (Logic, Ableton, Pro Tools all behave this way). The prototype fixture data (a muted "Ağır Bass Synth" with full sends) was designed to surface this question.

- **B. Mute does not cut the send tap:** A muted track's dry signal is silent, but its signal still reaches the send bus and produces a wet effect return in the mix. The reverb or delay of a "muted" track would remain audible. This is an uncommon setting; some advanced DAWs allow it as an opt-in "send pre-mute" mode.

The architectural recommendation is **A (mute cuts the send tap)**. Option A is the natural result of placing the send tap after the track's output fader (which applies mute). If Option B is wanted, the tap point must be wired differently (before the mute stage), which is a substantially different audio graph topology.

If you later want an option to send pre-mute (for headphone cue mixes or special effects), that is related to the pre/post-fader toggle in user story 5 (stretch goal) and can be added as a follow-on without breaking the v1 design.
