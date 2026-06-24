# Plan: Routing Interaction-Matrix Harness

**Status:** Proposed — 2026-06-24
**Goal:** A scripted, combinatorial "monkey" over live routing/graph mutations,
driven through the app command channel ([[app-command-channel]]), that presses
play, keeps audio running, and exercises every node/routing operation while
**monitoring for crashes and silence**. Catches exactly the class of bug just
hit manually (add-track-FX graph-lock crash) — automatically and repeatably.

## Why

Manual real-audio passes are slow and miss combinations. The engine work
(fixed-superset routing, R0–R3) changes live-graph behaviour whose failure modes
are crashes/clicks/dropouts under specific operation orderings. A driver that
walks the operation matrix while watching `masterPeak` + process liveness finds
these far better than a human clicking.

## Mechanism

- **Drive:** write commands to the watched command file (`transport=play`,
  mutations…); see [[app-command-channel]].
- **Monitor output:** poll `<command-file>.status` `masterPeak` (dBFS) after each
  op — `-inf` when it should be sounding = a silence regression.
- **Detect crashes:** check the app pid after each op; a death = crash. Diff
  `~/Library/Logs/DiagnosticReports/SequencerAI*` for the new report and capture
  the faulting frame.
- **Fixture:** `docs/fixtures/audio-rich-routing.seqai` (AU mono + slicer + drum
  group + sends + bus), launched with `SEQUENCER_AI_MATERIALIZE_FIXTURE_SAMPLES=1`.

## Operation matrix (what to combinatorially exercise)

While playing, in randomized/round-robin sequences:
- add / remove tracks (each type: mono AU, slice, drum part)
- add / remove **track** FX inserts (the path that just crashed)
- add / remove **send-bus** inserts (A and B)
- add / remove **master-out** inserts
- route a track's output to a mixer bus / back to master
- set per-track sends (A / A+B / B — drives R4 too), sweep send levels through 0
- switch scenes (A/B crossfade), assign scene slots
- toggle mute/fill, change master gain
After each op: assert alive + read `masterPeak` (expect > -inf while playing).

## Command-vocabulary gaps to fill first

Existing keys cover transport, workspace nav, `sendAInserts`/`sendBInserts`,
`scenesMode`/`scenesAddFXModal`/`scenesSelectInsert`, `masterGain`, `addTrack`,
drum-kit inserts. **Missing** command keys (extend `VisualScenarioCommandRunner`,
each small + testable):
- per-**track** FX insert add/remove/reorder (the crash action — highest priority)
- **master-out** insert add/remove
- track output bus routing (`routeTrackToBus=<trackIdx>:<busIdx|master>`)
- per-track scene-send selection (A / A+B / B)
- remove track / remove bus
- status: keep `masterPeak`; add per-track or per-bus peak if useful

## Prerequisite: trustworthy `masterPeak`

Current wired runs read `masterPeak=-inf` even with `transport=play` (the drum
fixture should sound). Resolve whether that's (a) the meter publisher not
updating when unfocused/headless, (b) transport-via-command not actually
triggering steps, or (c) a real silence regression — `masterPeak` must reflect
true output before it can gate the harness. (Likely (a) or (b); investigate as
step 0.)

## Shape

`scripts/visual-scenarios/routing-stress.sh` (sibling to
`qa-surface-coverage.sh`): launch wired → `transport=play` → loop the matrix,
logging per-op `PASS / SILENCE / CRASH(frame)` to a report. Bounded iterations
or budget-driven. No silent truncation — log coverage.

## Sequencing

0. Make `masterPeak` trustworthy (investigate the -inf).
1. Extend the command vocabulary for the missing mutations (start with track FX
   inserts — drives the known crash).
2. Build the driver script + crash/silence reporting.
3. Run it; triage findings (the add-FX graph-lock crash is finding #1, see
   docs/bugs/20260624-170000-add-track-fx-graphlock-reentry-crash).
