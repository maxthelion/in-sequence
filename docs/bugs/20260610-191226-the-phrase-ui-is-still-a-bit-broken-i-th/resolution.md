# Resolution: phrase edit panel — bars/repeat into the box, step order out

Date: 2026-06-10

## What changed

The below-the-row phrase edit panel is gone entirely.

- **Bars, Repeat, and Loop now edit in place inside the left phrase box.**
  Clicking the box still selects the phrase and expands it; the expanded box
  holds compact − / value / + steppers for Bars and Repeat and the Loop
  toggle. The "plays once, then advances…" and "0 is unlimited" explainer
  prose died with the panel.
- **The step-order workflow UI (map list, creation, value editor, rename,
  delete) is removed from the phrase page.** Step order remains toggleable
  as a perform layer (same grammar as note repeat); the model and session
  APIs are untouched.
- **Step-order creation/presets are now a library concern**, recorded in
  `docs/roadmap/library-pools/README.md` (§2026-06-10 step order maps) and
  `docs/roadmap/intent.md` — global step-order presets live in the library
  alongside kits and pattern templates (roadmap items 26/27).

## Files

- `Sources/UI/PhraseWorkspaceView.swift` — `PhraseButtonControlsPanel` and
  `StepOrderPhraseWorkflowPanel` deleted (~770 lines); `PhraseMatrixPhraseCell`
  gains inline Bars/Repeat/Loop controls; `PhrasePolicyStepperControl` made
  width-flexible for the narrow box.
- `scripts/visual-scenarios/qa-surface-coverage.sh` — captures 32/33 now
  select the step-order perform layer (the panel they captured no longer
  exists).
- Roadmap: library-pools README + intent.md entries.

## Notes

`StepOrderPhraseSurfacePresentation` and the step-order session/model APIs
are kept — they back the perform layer, the visual fixtures, and the future
library surface.
