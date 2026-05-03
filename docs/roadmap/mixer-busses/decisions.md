# Mixer Busses — Decisions

Resolved on 2026-05-03 from the holistic mixer policy and approved by the user:

- V1 mixer behavior should be conservative and DAW-standard.
- Scene-specific behavior is scoped to the master/performance layer.
- User-created buses are ordinary mix-routing objects, not scene variants.

## Decisions

1. **Solo convention:** additive solo set.

   Multiple tracks/buses may be soloed simultaneously. When any solo exists,
   unsoloed strips are muted by the solo state machine.

2. **Bus insert scope:** global inserts.

   A user-created bus has one insert chain that applies in all master scenes.
   Do not create per-scene bus insert chains in v1.

3. **Deleting a routed bus:** require confirmation.

   If tracks are routed to the bus, show a confirmation prompt listing the
   tracks that will be re-routed to master before deleting the bus.
