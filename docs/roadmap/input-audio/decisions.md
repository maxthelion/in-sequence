# Input Audio — Decisions

Resolved on 2026-05-03 from the conservative v1 live-audio policy:

- Avoid topology expansion in v1 unless it is essential to the core workflow.
- Timing-sensitive live audio should be musical and phrase/bar aligned.

## Decisions

1. **Maximum audio input tracks:** one audio input track per session in v1.

   The UI should disable creating another audio input track once one exists.
   Multiple input tracks and shared input distribution can be revisited later.

2. **Loop playback timing:** bar-locked at the next bar boundary.

   After recording, switching to Loop mode should start playback on the next
   bar boundary rather than immediately. This keeps live loops musically phased
   with the sequencer.
