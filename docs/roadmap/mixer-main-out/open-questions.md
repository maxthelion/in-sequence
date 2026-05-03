# Mixer Main Out Open Questions

The architecture draft is coherent on runtime shape, threading, and ownership, but three product decisions should be confirmed before the feature advances to spec.

## Questions For The User

1. When the scene A/B crossfader sits between scenes, which insert chain should the master-out panel display?
   Options considered in `architecture.md`: always scene A, whichever scene has greater weight, or both scenes together.

2. Should the master fader be a single global output control for the final mixed signal, or a per-scene value that changes with the active scene?
   The architecture draft strongly leans toward one global post-blend master fader, but this should be confirmed explicitly before spec.

3. Should the clip indicator reset only when the user presses `CLR`, or should there be any automatic hold-and-reset behavior?
   The user story text implies manual clear only; this question is mainly a confirmation that no auto-reset timer is wanted.
