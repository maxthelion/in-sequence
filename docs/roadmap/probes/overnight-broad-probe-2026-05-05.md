---
id: overnight-broad-probe-2026-05-05
status: scheduled
run_after: "2026-05-05T22:00:00+01:00"
max_parallel: 6
auto_merge: false
requires_peekaboo: true
lanes:
  - id: track-editor-foundation
    title: Track Editor Foundation
    focus: Build a broad visible track-editor probe where clip history, modifier/source placement, and step editing coexist in one coherent surface.
  - id: phrase-scene-song-performance
    title: Phrase, Scene, And Song Performance
    focus: Build or wireframe the holistic phrase/scene performance surface with free/song transport, phrase rows, scene rows, basis phrase, and crossfader state visible together.
  - id: mixer-routing-and-sends
    title: Mixer Routing And Sends
    focus: Build the broad routing-model probe for tracks, busses, sends, master, meters, and deletion/rerouting behavior using safe defaults from the lane note.
  - id: audio-input-looping-autoslice
    title: Audio Input, Looping, And Autoslice
    focus: Build the shared waveform/buffer model probe across input tracks, live looping, and autoslice, stubbing engine behavior where useful.
  - id: performance-overrides-pattern-manipulation
    title: Performance Overrides And Pattern Manipulation
    focus: Build the transient performance override layer for multi-track targeting, fill, repeat, and step-order without mutating source phrases.
  - id: external-control-and-automation
    title: External Control And Automation
    focus: Build observability improvements that help future overnight loops, and only touch MIDI mappings where target concepts are already stable.
---

# Overnight Broad Probe - 2026-05-05

## Objective

Run the roadmap in broad product-probe mode tonight. The goal is to wake up with
working or semi-working lane branches that reveal the holistic shape of the app,
not polished production commits.

## Operating Mode

- Build broadly in probe worktrees.
- Commit freely on probe branches for traceability.
- Do not merge or push.
- Do not block on feature-level prototype approval.
- Prefer visible interaction shape over perfect internals.
- Keep probe scaffolding clearly named so it can be discarded.
- Write harvest notes in each worktree under
  `docs/roadmap/probe-results/overnight-broad-probe-2026-05-05/<lane>.md`.

## Validation Matrix

Each lane worker should attempt:

- useful tests, especially smoke/domain/contract tests;
- self-adversarial review;
- architecture review;
- UX review, using Peekaboo or screenshots if feasible;
- a morning harvest recommendation.

## Morning Harvest Rule

No broad lane probe may auto-merge to main. Morning output should identify:

- what to cherry-pick;
- what to discard;
- what to keep as a follow-up branch;
- what user decision, if any, unlocks the next pass.

## Expected Worktrees

The scheduler will create worktrees under:

```text
.worktrees/probe-overnight-broad-probe-2026-05-05-<lane-id>/
```

Branches use:

```text
codex/probe-overnight-broad-probe-2026-05-05-<lane-id>
```

## Schedule

Start after `2026-05-05T22:00:00+01:00`. Launch all six lane probes in
parallel; each lane stays in its own worktree and branch.
