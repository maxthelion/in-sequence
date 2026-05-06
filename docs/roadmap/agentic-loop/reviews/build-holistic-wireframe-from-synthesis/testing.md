---
status: reviewed
verdict: needs-correction
reviewed: 2026-05-06T19:34:30+01:00
source_pass: docs/roadmap/agentic-loop/passes/build-holistic-wireframe-from-synthesis.md
scheduled_follow_up: docs/roadmap/agentic-loop/passes/correct-holistic-wireframe-commit-discard-evidence.md
---

# Testing Review

## Verdict

The focused fixture tests pass and the screenshot is valid. Coverage is enough
to prove the scenario exists, but not enough to prove the riskiest UX contract:
Keep and Discard have distinct, visible, testable consequences.

## Evidence Checked

- `node --test docs/roadmap/probe-results/holistic-wireframe-from-synthesis-2026-05-06/fixture.test.js`
  passed: 4 tests.
- `docs/roadmap/probe-results/holistic-wireframe-from-synthesis-2026-05-06/screenshot.png`
  is a 1440 x 960 PNG.
- `ui-map.json` names the intended first-viewport regions and interactions.

## Findings

### P0 - Interaction tests do not cover Keep versus Discard behavior

Tests assert that keep/discard target labels exist in fixture strings, but they
do not exercise the prototype behavior. In `app.js`, both buttons set
`state.overrideVisible = false` and rerender the same cleared state.

The correction should add focused validation for distinct post-action labels:
Keep should acknowledge committed phrase/scene targets; Discard should
acknowledge restored authored phrase/scene/mixer state.

### P1 - First-viewport assertions are fixture-level, not DOM-level

`firstViewportLabels()` proves expected strings are in data. It does not prove
those strings render visibly in the first viewport. This allowed the
Keep/Discard target labels to live in button `title` attributes while the
screenshot still lacked visible target detail.

The correction should add a DOM or static-render validation that inspects
visible text for the target labels and post-action acknowledgement.

### P1 - The UI map is useful but manually authored

`ui-map.json` is good evidence for review, but it is not generated or checked
against the rendered DOM. Future visual gates should treat it as a declared map
unless a script verifies the named labels against the page.

## Agent-Side Outcome

Schedule one correction pass with a small test expansion. No broad app test run
is required because the host is a disposable local HTML prototype.
