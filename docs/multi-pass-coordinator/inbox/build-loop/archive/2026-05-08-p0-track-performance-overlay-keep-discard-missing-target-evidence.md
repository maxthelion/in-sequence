---
created: 2026-05-08T09:45:00Z
source: testing-review
status: pending
priority: high
action: add-evidence
worktree: .worktrees/p0-track-performance-overlay
branch: auto/p0-track-performance-overlay
base_commit: 096ed0153c7b6741d95849fc5cb6c2f64b132840
plan: docs/plans/2026-05-06-track-performance-overlay.md
critique: docs/multi-pass-coordinator/inbox/testing/archive/2026-05-08-p0-track-performance-overlay-keep-discard-session-review.md
review_result: .meta/project/actors/testing-review/2026-05-08-p0-track-performance-overlay-keep-discard-session-review.final.md
---

# Add Missing-Target Keep Evidence For P0 Track Performance Overlay

## Request

Add focused test evidence for the missing safe-failure path identified by
testing review of commit `096ed01`.

Use the existing worktree and branch:

- Worktree: `.worktrees/p0-track-performance-overlay`
- Branch: `auto/p0-track-performance-overlay`
- Starting commit: `096ed01 feat(app): keep and discard performance overlays`

Do not add Track Perform UI controls, overlay badges, Keep/Discard labels,
transaction-strip behavior, sub-step repeat scheduling, or broad Live workspace
refactors.

## Missing Evidence

Add a narrow production test that proves `SequencerDocumentSession.keepPerformanceOverlay()`
fails safely when an authoring target is missing.

The test should assert the returned result is `.failedMissingAuthoringTarget`
and that:

- authored phrase state is unchanged;
- `LiveSequencerStore.exportToProject()` is unchanged;
- document binding state is unchanged;
- the active runtime track overlay remains active and readable;
- prepared engine output is not treated as successfully committed by clearing
  the overlay.

Prefer the existing `SequencerDocumentSessionMasterBusTests` style unless a more
specific session mutation test home already exists. A missing fill, repeat, or
step-order layer is sufficient; the test does not need to cover every possible
missing-target shape.

## Required Context

- `docs/plans/2026-05-06-track-performance-overlay.md`
- `docs/multi-pass-coordinator/inbox/testing/archive/2026-05-08-p0-track-performance-overlay-keep-discard-session-review.md`
- `.meta/project/actors/testing-review/2026-05-08-p0-track-performance-overlay-keep-discard-session-review.final.md`
- `docs/multi-pass-coordinator/evidence-log.md`
- `wiki/pages/live-view.md`
- `wiki/pages/document-model.md`
- `wiki/pages/playback-data-path.md`

## Reporting

When complete, report:

- commit created;
- tests added;
- focused test command and result;
- whether the worktree is clean;
- whether the testing review can be treated as resolved.
