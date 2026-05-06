---
id: synthesize-current-probes
mode: synthesize
status: complete
created: 2026-05-06T12:55:54.902Z
completed: '2026-05-06T13:20:32.107Z'
objective: Synthesize Current Probes Into Whole-App Shape
max_parallel: 1
requires_context_pack: true
---
# Synthesize Current Probes Into Whole-App Shape

## Objective

Use the README/context-pack north star and the current probe evidence to line up
the next round of product improvements.

The output should not be another pile of lane notes. It should produce one
coherent app-shaped direction that lets agents build the next skeleton/wireframe
iteration with much less user input.

Product spirit to preserve:

```text
play -> generate -> notice -> capture -> arrange -> perform -> preserve/discard
```

The synthesis should ask: how do the current probes help a user turn a happy
accident into durable musical structure without the app becoming a set of
disconnected feature panels?

## Required Inputs

- `docs/roadmap/context-pack.md`
- `README.md`
- current lane files under `docs/roadmap/lanes/`
- `docs/roadmap/portfolio-plan.md`
- `docs/roadmap/probe-results/visual-baseline-2026-05-06/ux-baseline.md`
- `docs/roadmap/probe-results/overnight-broad-probe-2026-05-05-morning-harvest.md`
- completed UX feedback-pass lane results in probe worktrees, especially audio
  capture and mixer routing
- current wiki pages linked from the context pack

## Expected Outputs

Write:

- `docs/roadmap/agentic-loop/synthesis/current-product-shape.md`
- `docs/roadmap/agentic-loop/passes/build-holistic-wireframe-from-synthesis.md`

The synthesis should include:

- one paragraph product-shape summary;
- a whole-app user journey from generation/capture to arrangement/performance;
- a lane harvest matrix: keep, discard, retry, and why;
- a list of shared concepts that must be unified across lanes;
- a proposed app-shaped interactive wireframe/skeleton pass;
- UX/IA, architecture, and testing review questions for that pass;
- agent-side follow-up work that does not need user attention;
- at most 2-3 user decisions, only if they genuinely unlock multiple lanes.

Prefer diagrams, flow bullets, and tables over long prose.

## Review Lenses Required

- UX/IA
- architecture
- testing

## Product Checks

- Does the proposed next pass feel like a musical instrument/workbench rather
  than an admin dashboard?
- Does it show what is sounding, what is generated, and what can be captured?
- Does performance editing feel safe, reversible, and commit-able?
- Does each lane connect to the whole journey?
- Are failed or invalid probes routed to agent-side work instead of user
  attention?

## Stop Conditions

- resource gate fails;
- context pack is missing;
- output would be lane-local without explaining whole-app fit.
- the pass asks the user to inspect raw probe branches instead of reducing them.
