# Mixer Busses Open Questions

The architecture direction is coherent on ownership, graph mutation, and persistence shape, but the feature should not advance to `spec.md` until these product decisions are confirmed.

## Questions For The User

1. Which solo model should the mixer use for tracks and buses: exclusive solo (one strip at a time, matching the prototype) or additive solo (multiple strips can remain soloed together, matching most DAWs)?
2. Should bus inserts be global for each bus, or scene-scoped like the master bus inserts?
3. When the user deletes a bus that still has tracks routed to it, should the app silently reroute those tracks to master, or show a confirmation step that lists the affected tracks before rerouting?
