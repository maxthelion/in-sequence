# Send Effects — Decisions

Resolved on 2026-05-03 from the holistic mixer policy:

- Send buses should match ordinary bus insert semantics unless there is a
  deliberate performance reason to differ.
- Send returns are special wet-return paths, not ordinary dry buses.

## Decisions

1. **Send bus insert scope:** global inserts.

   Send A and Send B each have one insert chain that applies in all master
   scenes. This matches the Mixer Busses decision.

2. **Return path:** send returns connect to `finalOutputMixer`.

   Wet send returns bypass the master insert chain. This avoids reverb/delay
   tails being compressed, limited, or EQ'd again by master scene effects.

3. **Muted track sends:** mute cuts send contribution.

   In v1, a muted track contributes neither dry signal nor wet send signal.
   Pre-mute sends can be considered later as an advanced routing option.
