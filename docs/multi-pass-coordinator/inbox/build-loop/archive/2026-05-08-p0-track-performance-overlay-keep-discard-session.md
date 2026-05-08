---
created: 2026-05-08T08:53:30Z
source: multi-pass-coordinator
status: pending
priority: high
action: implement-work-item
worktree: .worktrees/p0-track-performance-overlay
branch: auto/p0-track-performance-overlay
base_commit: 3b50781aa6b6c1025f997aff8db0ebf8696bdbb3
plan: docs/plans/2026-05-06-track-performance-overlay.md
depends_on:
  architecture_review: docs/multi-pass-coordinator/inbox/architecture/archive/2026-05-08-p0-track-performance-overlay-playback-resolution-review.md
  testing_review: docs/multi-pass-coordinator/inbox/testing/archive/2026-05-08-p0-track-performance-overlay-playback-resolution-review.md
---

# P0 Track Performance Overlay - Keep/Discard Session Slice

## Request

Continue the P0 track performance overlay build in the existing clean worktree:

- Worktree: `.worktrees/p0-track-performance-overlay`
- Branch: `auto/p0-track-performance-overlay`
- Starting commit: `3b50781 feat(engine): apply track performance overlay in playback`

The playback-resolution slice has passed architecture and testing review. Build
the next bounded production slice: session-side Keep/Discard behavior and tests
for the runtime track performance overlay.

Do not implement Track Perform UI controls, overlay badges, transaction strip,
visual labels, or broad UX work in this request. Leave those for the next slice
after this persistence/restore contract has tests.

## Required Context

Read these before editing:

- `docs/plans/2026-05-06-track-performance-overlay.md`
- `docs/roadmap/agentic-loop/state.md`
- `docs/roadmap/agentic-loop/decisions/inferred-defaults.md`
- `docs/multi-pass-coordinator/evidence-log.md`
- `docs/multi-pass-coordinator/inbox/architecture/archive/2026-05-08-p0-track-performance-overlay-playback-resolution-review.md`
- `docs/multi-pass-coordinator/inbox/testing/archive/2026-05-08-p0-track-performance-overlay-playback-resolution-review.md`
- `wiki/pages/live-view.md`
- `wiki/pages/document-model.md`
- `wiki/pages/playback-data-path.md`

## Scope

Implement only the session persistence/restore slice:

- Add or complete `SequencerDocumentSession.keepPerformanceOverlay()`.
- Add or complete `SequencerDocumentSession.discardPerformanceOverlay()`.
- Keep writes active track overlay state to explicit authored destinations in
  the active Live editing phrase:
  - fill overlay writes the fill phrase layer;
  - step-order overlay writes the step-order phrase layer;
  - step-locked repeat writes both repeat intent and captured repeat source
    step.
- If any target repeat override is still pending capture, Keep must not clear
  that overlay or silently mutate authored phrase state for that pending target.
  Return or expose a testable failure/deferred result using the existing local
  command patterns.
- After a successful track Keep, clear the written track overlay state and
  invalidate already-prepared engine output.
- Discard clears track performance overlay state and master-bus performance
  overlay state without mutating authored phrase, scene, mixer, or document
  state.
- If existing master-bus scene macro or crossfader Keep paths can be reused
  safely in this slice, wire them through the existing session APIs. Do not
  invent new scene or mixer schema.

## Out Of Scope

- No Track Perform UI controls.
- No overlay badges.
- No Keep target label or Discard target label UI.
- No transaction strip.
- No sub-step note-repeat scheduling or UI promises.
- No mixer-route writes from track-level Keep.
- No broad refactor of Live workspace editing semantics.

## Tests

Add focused production tests that prove:

- applying fill, repeat, or step-order overlay leaves `Project`,
  `LiveSequencerStore.exportToProject()`, and document bindings unchanged until
  Keep;
- Keep writes expected phrase cells for fill, repeat, and step order, then
  clears the written track overlay;
- Keep for repeat writes both repeat intent and captured source step;
- pending repeat targets do not clear the overlay or mutate authored phrase
  state;
- Discard clears track and master-bus overlays and leaves authored phrase,
  scene, mixer, and document state unchanged;
- Keep/Discard invalidates prepared engine output so stale notes cannot leak
  after the command.

Keep tests narrow and deterministic. Prefer the existing
`TrackPerformanceOverlayTests`/session test style unless the codebase already
has a more specific home for session mutation tests.

## Reporting

When complete, report:

- commit created;
- files touched;
- tests added or changed;
- focused and full test commands/results;
- whether the worktree is clean;
- any Keep/Discard semantics intentionally deferred to the later UI slice.
