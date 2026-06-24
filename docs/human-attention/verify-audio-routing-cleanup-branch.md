# Verify: audio-routing-cleanup branch (real-audio pass before merging to main)

The `audio-routing-cleanup` branch reworks live audio routing (the
fixed-superset plan). Every change is gated by build + offline tests, but the
offline tests **never start a real audio engine** (CoreAudio in a unit test
risks a ~990s stall), so they verify *logic/geometry only*. Before this branch
merges to `main`, do one **real-audio pass** with the app actually playing.

This list grows as more phases land. Check each with audio running.

## R0 — persistent send nodes (commit 2104ad5c)
- Play a track routed to a send (A/B) with an FX insert on that send bus.
- **Drag the send amount through 0 and back, repeatedly, mid-playback.**
  - PASS: no click/dropout; send fades smoothly; no audible glitch as it
    crosses zero (this used to tear down + recreate the send nodes per crossing).
- Confirm dry signal is unaffected while the send moves.

## R1 — no engine stop/start for track output (commit f80f312d)
- While audio plays, **change a track's output bus** (e.g. route a track to a
  mixer bus, then back to master).
  - PASS: no full-engine silence gap; only that track may briefly blip; the rest
    keep playing; **no crash/hang** (this used to stop+start the whole engine).
- Add a new track while playing → it starts cleanly with no global gap.
- KNOWN FOLLOW-UP (not yet implemented): reassigning a *sounding* track's bus
  may click at the reconnect instant — the ramp-to-silence-then-reconnect step
  is planned. Note whether the click is objectionable.

## R2 — bus topology without full restart (commit b14f0afe)
- While audio plays, **add/remove an insert on a send bus AND on a mixer bus**.
  - PASS: no global silence gap; the affected bus's send/insert path may blip;
    everything else keeps playing; no crash/hang.
- Add and remove a whole mixer bus while playing → tracks routed to it fall back
  to master cleanly; no crash.
- While audio plays, **add/remove/reorder a track's FX inserts** (a melodic
  track AND a drum part) — commit e5daf845.
  - PASS: no global silence gap; the track's signal may briefly blip as its
    chain re-splices; everything else keeps playing; no crash/hang.

## Pass results so far (2026-06-24, partial)

- **R0/R1/R2 routing — provisionally OK:** with an Arturia Analog Lab preset
  loaded, the lead sounded and routed through the sends — i.e. the dry path
  through the fanout reaches master (R0 not broken). Not yet exhaustively
  exercised (see the interaction-matrix harness plan).
- **CRASH — add an AU FX insert to a track.** Graph-lock re-entrancy in
  `rebuildTrackInsertChainAfterLoad` (the AU-load completion re-enters the lock
  inline; the send-bus path async-hops, the track path doesn't). Filed:
  `docs/bugs/20260624-170000-add-track-fx-graphlock-reentry-crash`. Likely
  PRE-EXISTING (that path was not modified by R0–R2) — **verify on `main`**.
- **No sound from the sample-drum fixture build (`masterPeak=-inf` while
  playing).** Under investigation — likely the meter publisher not updating
  headlessly OR transport-via-command not triggering steps, vs a real silence
  regression. Tracked as step 0 of the interaction-matrix harness plan
  (`docs/plans/2026-06-24-routing-interaction-matrix-harness.md`).

## How to run
1. `git switch audio-routing-cleanup`, build + run the app (real output device).
2. Load a project with ≥2 tracks, at least one send with an insert, at least one
   mixer bus.
3. Walk each check above with audio playing. Note any click/dropout/crash.
4. If all pass, the branch is safe to merge to `main`. If a reconnect clicks,
   that's the ramp follow-up (R1/R2), not a blocker for correctness — record it.

## Why this can't be automated here
The build machine can't run `SEQUENCER_AI_ALLOW_VISUAL_AUTOMATION` audio
sessions reliably and starting a real engine in CI risks a CoreAudio stall.
Offline tests prove the graph is wired correctly; only ears confirm it doesn't
glitch live.
