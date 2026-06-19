# Kit Pattern Linking: Slot-Only, Explicit, Break On Divergence

Raw product-owner clarification:

> patterns should be linked for a drum kit so that all of the parts switch at the
> same time, but that might cause problems with the layer/performance views, so
> make the linking and unlinking more explicit, and potentially have drum kits as
> individual cells where their pattern can be changed as a single unit.

Interpretation for build:

- Linking is an **explicit toggle** in the persistent Patterns row (not the
  implicit "MIXED" badge).
- Linking locks **pattern slot selection only** — all parts switch slots
  together. **Mute, fill, and macros stay per-part** even when linked (those are
  the performance gestures you don't want ganged).
- A **linked kit collapses to one cell** in the track/perform matrix and **Song
  mode**; unlinked expands to per-part cells. Pairing: linked↔collapsed,
  unlinked↔expanded. **Scenes deferred** (different model).
- Editing a part's **step content** within the shared slot is always allowed (no
  contradiction). **Structural divergence** — a part given a different length or
  moved to a different slot — resolves by **break**: that part auto-unlinks, the
  kit flags MIXED, with one-click re-link. No modal block, no pattern fork.
</content>
