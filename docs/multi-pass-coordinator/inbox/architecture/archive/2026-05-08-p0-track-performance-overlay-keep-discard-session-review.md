---
created: 2026-05-08T09:12:02Z
source: multi-pass-coordinator
status: pending
priority: high
action: review-diff
worktree: .worktrees/p0-track-performance-overlay
branch: auto/p0-track-performance-overlay
base_commit: 3b50781aa6b6c1025f997aff8db0ebf8696bdbb3
commit: 096ed0153c7b6741d95849fc5cb6c2f64b132840
plan: docs/plans/2026-05-06-track-performance-overlay.md
depends_on:
  build_request: docs/multi-pass-coordinator/inbox/build-loop/archive/2026-05-08-p0-track-performance-overlay-keep-discard-session.md
  completion_note: docs/multi-pass-coordinator/inbox/coordinator/archive/2026-05-08-p0-track-performance-overlay-keep-discard-session-ready.md
---

# Architecture Review - P0 Track Performance Overlay Keep/Discard Session

## Request

Review commit `096ed01` in `.worktrees/p0-track-performance-overlay` before
the coordinator promotes Track Perform UI controls, overlay badges,
Keep/Discard labels, or transaction-strip work.

Use:

- Worktree: `.worktrees/p0-track-performance-overlay`
- Branch: `auto/p0-track-performance-overlay`
- Base commit: `3b50781 feat(engine): apply track performance overlay in playback`
- Commit under review: `096ed01 feat(app): keep and discard performance overlays`
- Diff range: `3b50781..096ed01`

The build loop reported a clean worktree, focused
`SequencerDocumentSessionMasterBusTests` plus `TrackPerformanceOverlayTests`
passing with 33 tests and 0 failures, and full macOS `xcodebuild test` passing
with 830 tests, 3 skipped, and 0 failures.

## Required Context

- `README.md`
- `docs/plans/2026-05-06-track-performance-overlay.md`
- `docs/roadmap/agentic-loop/state.md`
- `docs/roadmap/agentic-loop/decisions/inferred-defaults.md`
- `docs/multi-pass-coordinator/evidence-log.md`
- `docs/multi-pass-coordinator/inbox/architecture/archive/2026-05-08-p0-track-performance-overlay-playback-resolution-review.md`
- `docs/multi-pass-coordinator/inbox/testing/archive/2026-05-08-p0-track-performance-overlay-playback-resolution-review.md`
- `wiki/pages/document-model.md`
- `wiki/pages/live-view.md`
- `wiki/pages/playback-data-path.md`

## Review Lens

Check whether this slice implements the intended session ownership boundary
without crossing into later UI responsibilities:

- session commands remain the user-facing authority for Keep and Discard;
- runtime overlay state remains owned by `EngineController` and is not persisted
  into `Project` until explicit Keep;
- Keep writes fill, step order, step-locked repeat intent, and captured repeat
  source step into explicit authored phrase-layer destinations;
- pending repeat capture returns a testable deferred result without clearing
  the pending overlay or mutating authored phrase state;
- Keep uses the active Live editing phrase rule from the plan and does not
  invent a different phrase target;
- successful Keep clears only the written runtime overlay state and invalidates
  prepared output;
- Discard clears track and master-bus overlays, invalidates prepared output,
  and does not mutate authored phrase, scene, mixer, or document state;
- master-bus scene macro and crossfader Keep reuse existing session/master-bus
  mutation paths without inventing new mixer or scene schema;
- the diff stays out of Track Perform UI, overlay badges, visible target
  labels, transaction-strip behavior, sub-step repeat scheduling, and unrelated
  refactors.

If this fails, write one concrete build-loop correction request. If it passes,
state whether the coordinator may proceed to the next reviewed slice after
testing review also passes.
