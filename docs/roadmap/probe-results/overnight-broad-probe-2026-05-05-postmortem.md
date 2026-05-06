---
date: 2026-05-06
plan: overnight-broad-probe-2026-05-05
status: draft
related:
  - docs/roadmap/probes/overnight-broad-probe-2026-05-05.md
  - docs/roadmap/probe-results/overnight-broad-probe-2026-05-05-summary.md
  - docs/roadmap/probe-results/overnight-broad-probe-2026-05-05-morning-harvest.md
  - docs/roadmap/probe-results/visual-baseline-2026-05-06/ux-baseline.md
---

# Overnight Broad Probe Post-Mortem

## Context

The goal was to test a different product-development loop: instead of waiting
for all questions to be resolved up front, run several lane probes overnight,
let agents build broad reversible product shape, and harvest learning in the
morning. The danger we were trying to avoid was not simply "wrong code reaches
production"; it was losing momentum by spending too much human attention on
premature specification.

This run created six lane branches/worktrees, committed probe implementations,
ran focused checks, and produced harvest notes. It did not merge or push the
branches automatically.

## What Worked

- The scheduler/orchestrator model was good enough to run a multi-lane
  overnight build without filling the Codex UI with separate active crons.
- Six lanes reached committed branch state, which proves the loop can create
  morning-harvest material without asking for user decisions at every step.
- The lanes exposed holistic product questions more clearly than the old
  feature-by-feature artifact queue.
- The best probes produced visual product shape that would have been hard to
  reason about from prose alone, especially audio capture/looping/autoslice and
  track editor/source-chain work.
- Isolation worked: the branches stayed separate, no automatic merge happened,
  and wrong work remains cheap to discard or cherry-pick.

## What Failed Or Was Brittle

- The first Peekaboo visual pass accepted screenshots of document pickers,
  browser windows, and desktop state as if they were UX evidence.
- The worker prompt said visual capture was useful, but did not define what
  makes a capture valid.
- Peekaboo Accessibility was missing during the first visual pass, so the
  review degraded to static screenshot criticism rather than exercised UI-map
  review. It was confirmed granted later on 2026-05-06.
- Several probes regenerated project-file state, so cherry-picking will need
  care to avoid accidental broad churn.
- Full test runs hit existing CoreAudio/AVAudio sample playback failures, which
  means the overnight loop could not distinguish lane regressions from known
  environmental or pre-existing test noise.
- Some probes created convincing panels rather than convincing whole
  workspaces, so they are useful as evidence but should not become production
  UI by default.

## Root Causes

- The loop had a build gate and a commit gate, but not enough evidence-quality
  gates.
- "Visual evidence exists" was treated too much like a file-system condition
  and not enough like a claim with preconditions.
- The supervisor was still partly calibrated around asking for attention or
  producing artifacts, rather than reducing the user's attention burden by
  doing obvious second-pass analysis itself.
- The overnight plan used six lanes at once before the visual-review machinery
  had proven itself on one or two lanes.
- The system lacked a stable known-good fixture/scenario for opening the app
  into each lane surface, so visual capture depended on brittle launch behavior.

## Product Learning

- Building broadly first was useful. The morning now has real product shape to
  react to rather than an abstract list of unresolved decisions.
- The most valuable output is not the code as-is; it is the delta between
  desired holistic workflow and what the probes made visible.
- A reversible probe branch is a good place to be wrong. Git cost is low when
  the work is isolated, named, and not merged automatically.
- Human attention should be directed to decisions that unlock flow, not to
  validating that agents did routine evidence gathering.
- The next source of truth may need to be an interactive wireframe assembled
  from the best lane learnings before production cherry-picking accelerates.

## Process Changes For Next Time

- Require every visual capture to report `valid`, `invalid`, or `blocked`.
- Treat invalid screenshots as process findings, not UX findings.
- Mark visual probe plans with `requires_peekaboo: true` so the scheduler
  blocks before launch if Screen Recording or Accessibility is missing.
- Cap probe parallelism conservatively. The 2026-05-06 UX feedback pass showed
  that six simultaneous Codex workers can turn useful feedback into memory and
  disk pressure, leaving partial outputs that need human cleanup.
- Add a disk-space preflight before launching workers; low disk should block
  probes before Git/index writes begin failing.
- Add a deterministic scenario opener for each lane, such as a fixture document
  plus a known starting workspace, before overnight workers run.
- Have the supervisor run a post-capture sanity check before writing anything
  to user attention.
- Keep overnight probe lanes fewer and more integrated until the evidence gates
  are trusted.
- Separate harvest outputs into three buckets: cherry-pick now, wireframe first,
  discard.
- Record known test-suite noise before the run so workers can identify new
  regressions without treating existing CoreAudio failures as lane findings.
- Ask agents to reduce ambiguity before asking the user, especially when the
  answer can be derived from screenshots, code, or lane artifacts.

## Proposed Next Loop

1. Harvest the six branches without merging wholesale.
2. Build a holistic interactive UX wireframe from the strongest visible ideas.
3. Freeze only the behavior we actually want to keep with focused tests.
4. Run a smaller second overnight loop against that source-of-truth wireframe.
5. Require adversarial, architecture, test, and validated visual evidence before
   anything becomes a merge candidate.

## Attention Question

The useful user-attention question is not "should agents keep working?" They
should. The useful question is:

What should become the next source of truth for the integrated product shape:
the best current probe branch, a new holistic interactive wireframe, or a
production branch that cherry-picks model pieces first and delays UI structure?

Recommendation: create the holistic interactive wireframe first, using the
audio capture/looping/autoslice probe and track editor/source-chain probe as
the strongest visual anchors.
