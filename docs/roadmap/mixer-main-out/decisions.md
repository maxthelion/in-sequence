# Mixer Main Out — Decisions

Resolved on 2026-05-03 from the holistic mixer policy:

- V1 mixer behavior should be conservative and DAW-standard.
- Scene-specific behavior is scoped to the master/performance layer.
- Ordinary buses and send buses stay global rather than scene-scoped.

## Decisions

1. **Mid-crossfade insert display:** show the scene with the higher crossfader weight.

   This keeps the master insert panel aligned with the currently dominant audible
   scene without trying to show both chains in the constrained master column.

2. **Master fader:** use one global final output level.

   The fader is a project-level final-output control applied after the A/B
   crossfade blend. Do not make the master fader per-scene in v1.

3. **Clip indicator reset:** manual clear only.

   The clip indicator latches until the user presses clear. No auto-clear timer
   in v1.
