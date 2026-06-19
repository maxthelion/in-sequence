# Kit History: All Parts Together, Scrubber, Save As Clip Set

Raw product-owner clarification:

> for a drum kit, I think you want to see the history of all of the parts
> together and to save those as a set of clips.
> [re clip history] there should be a way of moving through the history that is
> missing.

Interpretation for build (references capture `22-track-history-tab`):

- History is lifted out of the per-track tabs to an altitude-aware surface; for a
  kit it shows **all parts' live buffers together** and saves the lot as **one
  coordinated clip set** (not part by part).
- Add the **missing navigation**: a shared **scrubber/timeline** that moves the
  selection window back through the rolling buffer **in lockstep across all
  parts**, with a **live** anchor to jump to now. (Today's history only grabs the
  live window or a recent-output slot — there is no way to scrub back.)
- Save writes the **windowed** history (wherever scrubbed) into the clip set,
  assignable to a Pattern slot above.
- The same Capture→history surface applies at the single-track altitude (the
  1-part case).
</content>
