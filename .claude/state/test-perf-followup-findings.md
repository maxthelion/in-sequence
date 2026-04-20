# Test Performance Follow-up Findings

## Decision

Stop here.

The investigation plan explicitly says to stop after Task 1 if the cold full-suite time is below `60s`. The current measurements are:

- cold: `18.58s`
- warm incremental: `8.86s`
- warm noop: `7.96s`

That is already comfortably fast for local development and for the overnight behaviour-tree loop. There is no evidence that a structural refactor such as an SPM logic split or test-target slicing would pay for its complexity right now.

## Recommendation

- Keep using the existing `xcodebuild test` path as the default verification route.
- Revisit this investigation only if:
  - full-suite cold time regresses above ~`60s`, or
  - a future plan starts paying the full-suite cost many times per iteration and the overnight loop becomes meaningfully slower.

## Notes

- XCTest execution itself is only about `3.6s`; most of the remaining wall-clock is normal Xcode harness overhead.
- No hotspot follow-up was warranted because the plan closed on its Task 1 stop condition.
