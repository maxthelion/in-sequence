---
id: build-holistic-wireframe-from-synthesis
mode: build-wireframe
status: complete
created: 2026-05-06T13:16:45.000Z
completed: '2026-05-06T16:31:49.138Z'
objective: Build Holistic Happy Accident Workbench Wireframe
max_parallel: 1
requires_context_pack: true
requires_visual_validation: true
---
# Build Holistic Wireframe From Synthesis

Completion evidence:

- Result note:
  `docs/roadmap/probe-results/holistic-wireframe-from-synthesis-2026-05-06.md`
- Interactive probe:
  `docs/roadmap/probe-results/holistic-wireframe-from-synthesis-2026-05-06/index.html`
- Valid screenshot:
  `docs/roadmap/probe-results/holistic-wireframe-from-synthesis-2026-05-06/screenshot.png`
- Focused tests:
  `node --test docs/roadmap/probe-results/holistic-wireframe-from-synthesis-2026-05-06/fixture.test.js`

## Objective

Build one app-shaped, interactive wireframe/skeleton from
`docs/roadmap/agentic-loop/synthesis/current-product-shape.md`.

The result should reduce the current lane pile into one coherent product shape:

```text
play -> generate -> notice -> capture -> arrange -> perform -> preserve/discard
```

This is a product-direction probe. Keep it reversible and do not merge broad
probe branches wholesale.

## Required Inputs

- `README.md`
- `docs/roadmap/context-pack.md`
- `docs/roadmap/agentic-loop/synthesis/current-product-shape.md`
- `docs/roadmap/probe-results/visual-baseline-2026-05-06/ux-baseline.md`
- `docs/roadmap/probe-results/overnight-broad-probe-2026-05-05-morning-harvest.md`
- completed feedback-pass results for audio capture and mixer routing in their
  probe worktrees
- `wiki/pages/application-overview.md`
- `wiki/pages/information-architecture-ux.md`
- `wiki/pages/live-view.md`
- `wiki/pages/document-model.md`
- `wiki/pages/playback-data-path.md`
- `wiki/pages/routing.md`

## Expected Outputs

Write:

- `docs/roadmap/probe-results/holistic-wireframe-from-synthesis-2026-05-06.md`
- visual artifacts under
  `docs/roadmap/probe-results/holistic-wireframe-from-synthesis-2026-05-06/`

Update:

- `docs/roadmap/agentic-loop/state.md`
- `docs/roadmap/agentic-loop/attention-ledger.md`, only if user attention or
  next action changes
- this pass file, marking it complete only after valid evidence exists

## Build Requirements

- Add a clearly probe-scoped **Happy Accident Workbench** surface. It may be a
  SwiftUI in-app probe, a local prototype host, or another repo-native
  interactive skeleton that agents can validate.
- Seed a realistic scenario fixture with:
  - drum/group, melodic generator, audio input/loop, and bass clip tracks;
  - one active phrase and one queued phrase;
  - one captured generated clip in history;
  - one shared audio buffer with loop range and slice cues;
  - one transient performance override across a selected track set;
  - one mixer route through a bus plus delay/reverb returns;
  - Scene A/B state and a visible live crossfader override.
- First viewport must show what is sounding, what was generated or captured,
  what can be captured next, and what is transient until committed.
- Include visible **Keep** and **Discard** affordances for live performance
  changes. They can be probe-only interactions, but their target must be clear.
- Reuse probe lessons, not probe-local architecture. Do not copy local `@State`
  models as production truth unless the output explicitly labels them as a
  disposable fixture.

## Validation Requirements

- Run focused tests for the fixture/model labels and identity invariants.
- Run a build or equivalent local validation for the chosen host.
- Produce valid visual evidence:
  - screenshot of the intended app/prototype surface;
  - UI map or interaction evidence when available;
  - `visual-capture-status: valid|invalid|blocked` in the result note.
- Invalid screenshots are process findings, not UX findings.

## Review Lenses

- UX/IA: instrument/workbench feel, primary action clarity, visible consequence,
  whole-app journey, safe commit/discard behavior.
- Architecture: clear ownership boundaries for document, runtime/session,
  engine, audio graph, probe fixture, and visual-only state.
- Testing: scenario invariants, capture/buffer identity, transient overlay
  labels, routing defaults, and visual evidence gates.

## Stop Conditions

- context pack or synthesis file is missing;
- resource gate prevents building/capturing the selected host;
- output becomes lane-local instead of an integrated product shape;
- no valid visual evidence can be produced and no blocked/invalid evidence note
  is written.
