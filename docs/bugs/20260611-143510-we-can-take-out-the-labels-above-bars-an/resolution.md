# Resolution

Branch: `feature/small-ui-sweep` (worktree `.worktrees/small-ui-sweep`), commit `c226cae1`.

## What changed

- **Labels removed** — `PhrasePolicyStepperControl` no longer renders the
  "BARS" / "REPEAT" titles above the steppers (ux-canon rule 3). The titles
  now live in a `.help` tooltip and the accessibility label. Because a bare
  repeat number would be ambiguous without its label, the repeat value now
  renders with a multiplier mark ("4×", "Unlimited") via
  `PhraseButtonControlPresentation.repeatValueLabel`; the bars stepper already
  said "8 bars".
- **Cells align in height** — every cell in a phrase row (phrase box, layer
  cells, empty placeholder cells, row actions) now stretches to one shared
  fixed row height, `PhraseMatrixLayoutPresentation.matrixRowHeight` (118pt),
  instead of each cell picking its own minHeight (106 / 96 / 120 / content).
  The phrase box also got shorter by losing the two labels, so the boolean
  Muted/Live cells and the phrase box now share the same bounds (ux-canon
  rule 9).
- **Row actions contained** — the insert / duplicate / delete buttons on the
  right of each row sit in one bordered rounded container (subtle fill +
  border token) instead of three loose circled buttons; per-button border
  chrome dropped so the cluster reads as a single control.

Files: `Sources/UI/PhraseWorkspaceView.swift`,
`Sources/UI/PhraseButtonControlPresentation.swift`,
`Sources/UI/PhraseMatrixLayoutPresentation.swift`.

## Tests

- `PhraseButtonControlPresentationTests` updated for the "×" repeat label and
  extended with `test_repeatValueLabelCarriesMultiplierMark`.

## Remaining verification

- Visual verification pending: no QA screenshot capture was run (console may
  be locked). Re-capture `10-phrase-controls-open.png` and confirm: no labels
  above the steppers, all cells in a row share the same height, row actions
  read as one contained cluster, and nothing clips at the 118pt row height
  with long phrase names.
