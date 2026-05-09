# Mixer Main Out — Decisions

Resolved on 2026-05-03 from the holistic mixer policy and approved by the user:

- V1 mixer behavior should be conservative and DAW-standard.
- Scene-specific behavior is scoped to the master/performance layer.
- Ordinary buses and send buses stay global rather than scene-scoped.

## Decisions

1. **Master Out insert ownership:** edit the post-blend master-bus insert chain.

   Product-owner correction on 2026-05-09 superseded the earlier dominant-scene
   insert display decision. Master Out inserts are stored on
   `MasterBusState.masterInserts` and run after the Scene A/B blend and before
   final output gain/metering. Master Out must not expose Scene A/B insert
   editing affordances.

2. **Master fader:** use one global final output level.

   The fader is a project-level final-output control applied after the A/B
   crossfade blend. Do not make the master fader per-scene in v1.

3. **Clip indicator reset:** manual clear only.

   The clip indicator latches until the user presses clear. No auto-clear timer
   in v1.
