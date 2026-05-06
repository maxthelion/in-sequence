---
status: reviewed
verdict: pass
reviewed: 2026-05-06T20:27:00+01:00
source_pass: docs/roadmap/agentic-loop/passes/write-p0-performance-overlay-build-plan.md
reviewed_output: docs/plans/2026-05-06-track-performance-overlay.md
scheduled_follow_up: docs/plans/2026-05-06-track-performance-overlay.md
---

# UX/IA Review

## Verdict

Pass after one plan clarification made in this review: repeat Keep must show
and write a captured source-step destination, not only a generic repeat-active
intent.

No user attention is required before production build work starts. The plan
preserves the Happy Accident Workbench flow by treating the overlay as a
visible performance transaction with explicit Keep and Discard targets.

## Evidence Checked

- `README.md`
- `docs/roadmap/context-pack.md`
- `docs/roadmap/agentic-loop/decisions/inferred-defaults.md`
- `docs/roadmap/agentic-loop/synthesis/production-cherry-pick-candidates.md`
- `docs/plans/2026-05-06-track-performance-overlay.md`
- `docs/roadmap/agentic-loop/passes/write-p0-performance-overlay-build-plan.md`
- `docs/roadmap/portfolio-plan.md`
- `docs/roadmap/probe-results/holistic-wireframe-from-synthesis-2026-05-06.md`
- `docs/roadmap/probe-results/visual-baseline-2026-05-06/ux-baseline.md`
- `wiki/pages/live-view.md`
- `Sources/UI/LiveWorkspaceView.swift`
- `Sources/UI/TracksMatrixView.swift`
- `Sources/UI/Mixer/ScenesWorkspaceView+Perform.swift`
- `3a1d15d:Sources/Engine/TrackPerformanceOverrideLayer.swift`

## What Passed

- The plan keeps performance overrides inside the existing Live/Tracks perform
  surfaces and explicitly rejects the sparse probe panel as production UI.
- The transient-state badge and transaction strip requirements make the
  currently sounding consequence visible enough for safe performance.
- Keep and Discard are visible product actions, not hidden persistence side
  effects. Their labels name active phrase cells, scene A/B state, and authored
  restore targets.
- The plan avoids promising 1/32 or 1/64 note repeat in the UI before sub-step
  scheduling exists.
- The Song-mode phrase target is grounded in the current Live/Tracks editing
  resolver, with a label guard added so the UI does not overclaim "audible
  phrase" before engine song playback uses the same resolver.

## Caught And Fixed

The original plan let Keep write `repeat-intent = step-locked` without also
persisting which source step was captured. That would make the saved
consequence ambiguous and could create a Keep button that appears safe but does
not preserve what the user heard.

The plan now requires a `repeat-source-step` authored destination, requires
pending repeat captures to stay transient, and requires visible failure instead
of silently clearing the overlay when a captured source step is unavailable.

## Residual UX Risk

The first P0 UI still needs careful visual hierarchy. The minimum bar is:
selected target tracks, active phrase/editing phrase, current step, overlay
labels, and Keep/Discard targets must be visible together when an overlay is
active. If those labels fall below the fold, the build should be treated as
incomplete.
