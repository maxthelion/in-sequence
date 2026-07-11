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
