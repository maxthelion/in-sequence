It doesn’t look like the step repeat cells are actually toggle. Also, atep order is missing

Screenshots:
- 13-phrase-global-apply.png

Capture references:
- 13-phrase-global-apply.png (in-sequence/qa-surface-coverage; main @ 2d6fac37; run 20260711-083413-in-sequence-qa-surface-coverage-main-2d6fac37; 9520025fbbd2de87a8e35d0f39b2c96d)

## ROOT CAUSE + FIX

Global Apply reused selector-style variant cards for Note Repeat, so their
runtime toggle state was not explicit. Step Order options were generated only
from valid saved maps and only for 16-step phrases, causing the entire control
to disappear when either condition was unmet.

- Note Repeat and Step Order action cards now use solid accent fill when active
  and an outline-only body when inactive, matching Mute and Fill.
- Clicking a Note Repeat card dispatches its own interval directly instead of
  relying on a just-mutated selection state.
- A 16-step phrase with no saved maps exposes a functional Identity option and
  materializes the pooled map on first use.
- Unsupported phrase lengths retain a readable, inert Step Order card labelled
  `16 steps only` instead of silently hiding the feature.

Verification:
- `TrackPerformSelectionStateTests`: 26 passed, 0 failed.
- `scripts/diagnostics/ux-canon-lint.sh`: 0 violations.
- Fresh focused `13-phrase-global-apply` visual capture confirms the clean
  outline-only inactive state and the visible Step Order constraint.

Status: RESOLVED

## FOLLOW-UP: GROUPED VALUES + PINS

Pattern, Note Repeat, and Step Order now share a grouped value-picker grammar:

- With no pins, each layer collapses to its first value.
- With pins, collapsed mode shows only the pinned values.
- Every value card's layer header expands or collapses the whole group.
- Expanded mode shows every backed value as a full cell.
- Every available value has an independent pin toggle while expanded; pins are
  hidden in collapsed mode.
- Collapsed groups show only pinned values, or the first value when none are pinned.
- Applying a value changes only its toggle fill; it never changes which cells
  are visible.
- Pattern exposes P1-P16 and applies the chosen slot exactly across the active
  track scope, including through the quantised pattern-selection path.

Acceptance evidence is covered by the QA rows:

- `13-phrase-global-apply` (default collapsed state)
- `13d-phrase-global-apply-pattern-expanded-pinned` (P1-P16, P1/P2/P3 pinned)
- `13e-phrase-global-apply-pattern-pinned-collapsed` (P1/P2/P3 retained)

## FOLLOW-UP: PHRASE LAYER SELECTION

- Right-click now toggles direct cell selection without opening a context menu.
- Shift-click adds or removes cells through the same shared selection contract.
- Selected cells use a white border and track-accent title text; ordinary track
  focus is no longer drawn as selection.
- An `Automate` action appears in the Layer bar for a selection and edits every
  selected cell in one automation sheet.
- QA row `10-phrase-layer-selected-cells` records two selected cells and the
  visible batch Automation action.

Verification:
- 62 focused selection, grouped-value, and shared-step tests passed.
- `scripts/diagnostics/ux-canon-lint.sh`: 0 violations.
