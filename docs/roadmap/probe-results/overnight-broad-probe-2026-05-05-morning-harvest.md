---
generated: 2026-05-06T08:25:00Z
plan: overnight-broad-probe-2026-05-05
status: complete
---

# Overnight Broad Probe Morning Harvest

## Executive Summary

The overnight broad-probe model worked. Six independent lane workers launched,
created worktrees, built broad interactive probes, ran focused validation, wrote
reviews/harvest notes, and committed their work without merging to main.

The main product learning is that a holistic pass is more useful than the old
feature-level approval queue. The probes exposed several lane-level decisions
that now matter more than isolated prototype review.

## Branches

| Lane | Branch | Probe Commit | Main Implementation Commit |
|---|---|---|---|
| Track Editor Foundation | `codex/probe-overnight-broad-probe-2026-05-05-track-editor-foundation` | `75c29dd` | `0e3ba5c` |
| Phrase, Scene, And Song Performance | `codex/probe-overnight-broad-probe-2026-05-05-phrase-scene-song-performance` | `6ca658e` | `79d6bcf` |
| Mixer Routing And Sends | `codex/probe-overnight-broad-probe-2026-05-05-mixer-routing-and-sends` | `cf3d3c8` | `6991918` |
| Audio Input, Looping, And Autoslice | `codex/probe-overnight-broad-probe-2026-05-05-audio-input-looping-autoslice` | `238894d` | `99834b3` |
| Performance Overrides And Pattern Manipulation | `codex/probe-overnight-broad-probe-2026-05-05-performance-overrides-pattern-manipulation` | `4898a06` | `3a1d15d` |
| External Control And Automation | `codex/probe-overnight-broad-probe-2026-05-05-external-control-and-automation` | `d5d94d5` | `a9bdbc4` |

## What Was Built

### Track Editor Foundation

Built a probe-only track editor surface combining:

- clip history rail;
- source/modifier slot wells;
- step editing surface;
- selected history/play marker coupling.

Harvestable learning: clip history, source placement, modifier placement, and
step editing want a shared selected-slot context.

Primary decision: should clip history become an always-nearby history rail tied
to the selected pattern slot, or stay a modal launched from a generator source?

### Phrase, Scene, And Song Performance

Built a new `Perform` workspace showing:

- Free/Song mode;
- basis phrase;
- phrase rows;
- queued phrase wireframe state;
- Scene A/B rows;
- scene library summary;
- live crossfader state.

Harvestable learning: phrase rows and scene rows need to be judged together; a
single performance workspace is a strong candidate.

Primary decision: can queued phrases be edited immediately as the basis phrase,
or does queued editing need a staging/confirmation model?

### Mixer Routing And Sends

Built a probe-only mixer routing model and panel with:

- track output routing;
- busses;
- sends;
- master post-blend strip;
- additive solo;
- bus deletion confirmation and rerouting;
- manual clip clearing.

Harvestable learning: the safer default is return-style sends into the master,
with broad routing visible in one mixer surface.

Primary decision: are sends always return-style busses feeding the master in
v1, or is arbitrary bus-to-bus routing required?

### Audio Input, Looping, And Autoslice

Built a `Capture` workspace with:

- input track rows;
- stub recording into shared runtime buffers;
- waveform display;
- loop range;
- autoslice regions;
- buffer-user panel proving that input, looping, and slicing must share buffer
  identity.

Harvestable learning: the shared buffer vocabulary is the important product
object; final engine ownership can come later.

Primary decision: is audio input primarily a first-class track type, a global
capture/looping page, or both views over the same buffers?

### Performance Overrides And Pattern Manipulation

Built a transient override layer and Track Perform probe with:

- multi-track selection;
- fill override;
- note repeat intent;
- step-order presets;
- visible active override badges;
- clear-on-exit transient behavior.

Harvestable learning: the runtime override model should remain separate from
phrase mutation.

Primary decision: in Perform mode, should tapping track cards select targets by
default, with editing behind an explicit affordance?

### External Control And Automation

Built an `Automation` workspace focused on observability:

- structured observed event model;
- fingerprint normalization;
- redaction;
- routing recommendation;
- issue draft generation;
- MIDI endpoint counts as status, not mapping design.

Harvestable learning: observability can proceed independently and would help
future overnight loops; MIDI mapping should still wait for stable performance
surfaces.

Primary decision: what is the first authoritative log source and queue target?
Recommendation from the probe: app-owned JSONL diagnostics plus a repo-side
collector that writes reviewed markdown issue drafts.

## Validation Pattern

Good:

- Focused lane tests passed across all lanes.
- Branches are isolated and clean.
- No auto-merge happened.
- Each lane wrote adversarial, architecture, UX, and harvest notes.
- A corrected Peekaboo baseline now exists at
  `docs/roadmap/probe-results/visual-baseline-2026-05-06/ux-baseline.md`.
- A process post-mortem now exists at
  `docs/roadmap/probe-results/overnight-broad-probe-2026-05-05-postmortem.md`.

Limitations:

- Full test runs hit existing CoreAudio/AVAudio sample playback failures:
  `player did not see an IO cycle`.
- The first Peekaboo attempt captured open panels and desktop/browser state.
  Treat that as invalid evidence; only the `validated-*` captures count.
- Peekaboo Accessibility is still unavailable, so the visual baseline is static
  screenshot criticism rather than an exercised UI-map review.
- Several probes regenerated `SequencerAI.xcodeproj/project.pbxproj`, causing
  broad project-file churn that should not be cherry-picked blindly.

## Recommended Next Move

Do not merge any broad probe wholesale.

Run a harvest pass in this order:

1. Review the Track Editor and Phrase/Scene probes visually first, because they
   decide the biggest UX source-of-truth questions.
2. Use the visual baseline to decide which probe ideas belong in the holistic
   interactive wireframe before judging any branch as ready.
3. Cherry-pick pure model/test pieces where they are clean:
   `TrackPerformanceOverrideLayer`, observability models/tests, mixer reducer
   semantics, and audio buffer vocabulary tests.
4. Convert the six user decisions above into a short lane-decision review.
5. Schedule a second overnight pass against the accepted source-of-truth shape,
   with fewer lanes and stronger visual capture.
