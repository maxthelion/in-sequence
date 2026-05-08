---
created: 2026-05-08T10:22:33Z
source: multi-pass-coordinator
status: pending
priority: high
action: implement-work-item
worktree: .worktrees/p0-track-performance-overlay
branch: auto/p0-track-performance-overlay
base_commit: d818d8d1c00c222457fc025fe2bb7f967ae22e3e
plan: docs/plans/2026-05-06-track-performance-overlay.md
depends_on:
  architecture_review: docs/multi-pass-coordinator/inbox/architecture/archive/2026-05-08-p0-track-performance-overlay-keep-discard-session-review.md
  testing_review: docs/multi-pass-coordinator/inbox/testing/archive/2026-05-08-p0-track-performance-overlay-keep-discard-missing-target-reconsideration.md
---

# P0 Track Performance Overlay - Minimal UI Transaction Slice

## Request

Continue the P0 track performance overlay build in the existing clean worktree:

- Worktree: `.worktrees/p0-track-performance-overlay`
- Branch: `auto/p0-track-performance-overlay`
- Starting commit: `d818d8d test(app): cover missing overlay keep target`

The backend/session Keep/Discard slice has now passed architecture review and
testing-review reconsideration. Build the next bounded production slice: make
the existing track performance overlay usable from the app through a minimal
Track Perform UI transaction.

This advances the current-work blocker in
`docs/multi-pass-coordinator/coordinator/current-work/p0-track-performance-overlay.md`:
users still cannot do the intended thing because there are no visible Track
Perform controls, overlay badges, Keep/Discard target labels, or transaction
strip.

## Evidence That Caused This Request

- Backend/session implementation: `096ed01 feat(app): keep and discard performance overlays`.
- Missing safe-failure evidence: `d818d8d test(app): cover missing overlay keep target`.
- Architecture pass:
  `docs/multi-pass-coordinator/inbox/architecture/archive/2026-05-08-p0-track-performance-overlay-keep-discard-session-review.md`.
- Testing pass after reconsideration:
  `docs/multi-pass-coordinator/inbox/testing/archive/2026-05-08-p0-track-performance-overlay-keep-discard-missing-target-reconsideration.md`.
- Current holistic status says the backend story coheres, but showability is
  blocked until the visible Track Perform transaction exists.

## Required Context

Read these before editing:

- `docs/plans/2026-05-06-track-performance-overlay.md`
- `docs/multi-pass-coordinator/evidence-log.md`
- `docs/multi-pass-coordinator/coordinator/current-work/p0-track-performance-overlay.md`
- `docs/multi-pass-coordinator/coordinator/holistic-status.md`
- `docs/roadmap/agentic-loop/decisions/inferred-defaults.md`
- `wiki/pages/live-view.md`
- `wiki/pages/information-architecture-ux.md`
- `wiki/pages/document-model.md`
- `wiki/pages/playback-data-path.md`

## Scope

Implement the smallest user-facing Track Perform transaction that makes the
already-built session commands reachable and understandable:

- Add Fill, Repeat, Order, and Clear performance controls for the selected
  track or visible track scope in an existing production surface.
- Prefer the existing Tracks perform surface (`TracksWorkspaceMode.perform` /
  `TracksMatrixView`) unless the code structure clearly points to
  `LiveWorkspaceView`.
- Controls must call `SequencerDocumentSession` performance-overlay commands:
  `setTrackPerformanceFill`, `setTrackPerformanceRepeat`,
  `setTrackPerformanceStepOrder`, `clearTrackPerformance`, `keepPerformanceOverlay`,
  and `discardPerformanceOverlay`. Do not mutate phrase cells directly for this
  Track Perform transaction.
- Show an active transient-state badge per affected track or affected visible
  scope, with labels for active Fill, Repeat, and Order overlay state.
- Show a persistent transaction strip when either track or master-bus
  performance overlay state is active.
- The strip must expose Keep and Discard actions and name the targets:
  - Keep target: live editing phrase cells, plus scene A/B state when master-bus
    overlay state is active.
  - Discard target: authored phrase/scene/mixer restore.
- Keep and Discard must produce visible state changes by clearing the strip only
  after relevant overlays are actually clear.
- The UI must not promise 1/32 or 1/64 repeat, sub-step scheduling, broad
  performance-control redesign, or mixer-route writes.

## Out Of Scope

- No broad redesign of Live, Tracks, Phrase, or Mixer workspace layout.
- No new scene, mixer, or document schema.
- No sub-step repeat scheduling.
- No route, mute, pattern-slot, macro, or mixer-send performance overlays.
- No probe UI cherry-pick or `TrackPerformanceOverrideProbePanel` copy.
- No product-owner checkpoint; this is still an agent-side build slice.

## Tests

Add focused tests where the existing test style allows it. At minimum, cover
the view/command contract without relying on screenshots:

- Fill, Repeat, Order, Clear, Keep, and Discard controls are wired through
  session commands rather than direct phrase-cell mutation from the view.
- Active overlay state produces a visible transient label/badge in the relevant
  production view model or view helper.
- The transaction strip appears while an overlay is active and its target labels
  name the Keep and Discard destinations.
- After Keep or Discard clears the overlay, the strip disappears.
- No UI label promises unsupported sub-step repeat intervals.

If direct SwiftUI control testing is too brittle in this codebase, extract a
small testable presentation/intent helper near the UI code and cover that helper
with unit tests while keeping production views thin.

## Expected Next Verification

When complete, report:

- commit created;
- files touched;
- UI surface chosen and why;
- tests added or changed;
- focused test commands/results;
- full `xcodebuild test` result if practical;
- whether the worktree is clean;
- any UI polish intentionally deferred.

The next coordinator action after this build should be UX/IA plus visual review
of the visible transaction before broader performance controls or product-owner
attention.
