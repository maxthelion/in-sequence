---
id: correct-holistic-wireframe-commit-discard-evidence
mode: build-wireframe-correction
status: complete
created: 2026-05-06T18:34:30.000Z
completed: '2026-05-06T18:45:18.318Z'
objective: Correct Happy Accident Workbench Keep/Discard and ownership evidence gaps
max_parallel: 1
requires_context_pack: true
requires_visual_validation: true
source_review: docs/roadmap/agentic-loop/reviews/build-holistic-wireframe-from-synthesis/
---
# Correct Holistic Wireframe Commit/Discard Evidence

## Objective

Update the probe-scoped Happy Accident Workbench so live performance changes
have distinct visible Keep and Discard consequences, with test evidence proving
the target labels and owner transitions are visible rather than only stored in
fixture strings or button tooltips.

This is an agent-side correction. Do not ask the user to review raw output.

## Required Inputs

- `README.md`
- `docs/roadmap/context-pack.md`
- `docs/roadmap/agentic-loop/synthesis/current-product-shape.md`
- `docs/roadmap/agentic-loop/reviews/build-holistic-wireframe-from-synthesis/ux-ia.md`
- `docs/roadmap/agentic-loop/reviews/build-holistic-wireframe-from-synthesis/architecture.md`
- `docs/roadmap/agentic-loop/reviews/build-holistic-wireframe-from-synthesis/testing.md`
- `docs/roadmap/probe-results/holistic-wireframe-from-synthesis-2026-05-06/`
- relevant wiki pages linked from the context pack

## Expected Outputs

Update:

- `docs/roadmap/probe-results/holistic-wireframe-from-synthesis-2026-05-06/fixture.js`
- `docs/roadmap/probe-results/holistic-wireframe-from-synthesis-2026-05-06/app.js`
- `docs/roadmap/probe-results/holistic-wireframe-from-synthesis-2026-05-06/fixture.test.js`
- `docs/roadmap/probe-results/holistic-wireframe-from-synthesis-2026-05-06/ui-map.json`
- `docs/roadmap/probe-results/holistic-wireframe-from-synthesis-2026-05-06/screenshot.png`
- `docs/roadmap/probe-results/holistic-wireframe-from-synthesis-2026-05-06.md`
- `docs/roadmap/agentic-loop/state.md`
- `docs/roadmap/agentic-loop/attention-ledger.md`
- this pass file, marking it complete only after valid evidence exists

## Correction Requirements

- Keep and Discard must have visible first-viewport target labels, not only
  button titles.
- Keep must produce a visibly different acknowledgement than Discard:
  - Keep: committed to active phrase cells and Scene A/B blend.
  - Discard: session overlay cleared and authored phrase/scene/mixer restored.
- The fixture should model owner transitions explicitly:
  - runtime-session overlay source;
  - document/scene destination for Keep;
  - authored state restoration target for Discard;
  - runtime audio buffer versus document reference for loop capture.
- Tests should assert both fixture invariants and rendered/interaction-visible
  labels for the distinct outcomes.
- Keep the host disposable. Do not change production Swift schema, playback, or
  audio graph contracts.

## Validation Requirements

- Run focused node tests.
- Recreate the screenshot and confirm it is valid.
- Update the result note with `visual-capture-status: valid|invalid|blocked`
  and a short correction summary.

## Result

Complete. The Happy Accident Workbench probe now renders visible first-viewport
Keep and Discard target labels, models runtime-session/document/audio-graph
owner transitions in the fixture, and exposes distinct post-click
acknowledgements for committed versus discarded live changes.

Validation:

- `node --test docs/roadmap/probe-results/holistic-wireframe-from-synthesis-2026-05-06/fixture.test.js`
  passed 7 tests.
- Recreated
  `docs/roadmap/probe-results/holistic-wireframe-from-synthesis-2026-05-06/screenshot.png`.
- Confirmed screenshot is a valid 1440 x 960 PNG.
- Updated `docs/roadmap/probe-results/holistic-wireframe-from-synthesis-2026-05-06.md`
  with `visual-capture-status: valid` and the correction summary.

## Stop Conditions

- Visual evidence cannot be recreated and no blocked/invalid note can be
  written.
- The correction expands beyond the Happy Accident Workbench probe into
  production app architecture.
