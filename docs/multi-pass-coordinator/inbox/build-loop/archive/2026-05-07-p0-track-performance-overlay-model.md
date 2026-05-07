---
created: 2026-05-07T11:20:09Z
source: multi-pass-coordinator
status: pending
priority: high
action: implement-work-item
worktree: .worktrees/p0-track-performance-overlay
branch: auto/p0-track-performance-overlay
plan: docs/plans/2026-05-06-track-performance-overlay.md
---

# P0 Track Performance Overlay - Pure Model Slice

## Request

Promote the P0 track performance overlay plan into implementation by completing
the first bounded production slice: port the pure runtime value model and its
focused tests only.

Create or use this dedicated worktree and branch:

- Worktree: `.worktrees/p0-track-performance-overlay`
- Branch: `auto/p0-track-performance-overlay`
- Base: current project HEAD unless the build-loop policy says otherwise

Do not implement engine/session/UI wiring in this request. Leave those as
follow-up build-loop requests after the model/test slice is committed.

## Required Context

Read these before editing:

- `docs/plans/2026-05-06-track-performance-overlay.md`
- `docs/roadmap/agentic-loop/state.md`
- `docs/roadmap/agentic-loop/synthesis/production-cherry-pick-candidates.md`
- `docs/roadmap/agentic-loop/decisions/inferred-defaults.md`
- `wiki/pages/playback-data-path.md`
- `wiki/pages/document-model.md`
- `wiki/pages/live-view.md`

Probe source to inspect read-only:

- `3a1d15d:Sources/Engine/TrackPerformanceOverrideLayer.swift`
- `3a1d15d:Tests/SequencerAITests/Engine/TrackPerformanceOverrideLayerTests.swift`

## Scope

Implement only a production-owned, renamed pure value model equivalent to the
plan's `TrackPerformanceOverlay`, `TrackPerformanceOverride`,
`TrackRepeatIntent`, and `TrackStepOrderIntent` concepts.

The model must:

- be `Equatable` and `Sendable` where local conventions allow;
- apply fill overrides across multiple tracks;
- preserve authored fallback by representing inactive values as absent overlay
  state;
- compact inactive entries, including `forward` step order;
- support clearing one target set without affecting others;
- support clearing all;
- represent note repeat as pending capture or step-locked capture;
- express that repeat takes precedence over step-order for source-step choice;
- avoid any 1/32 or 1/64 sub-step scheduling promise in this P0 slice;
- avoid mutating `Project`, `LiveSequencerStoreState`, `PlaybackSnapshot`, or
  phrase cells.

## Tests

Add focused tests for the pure model behavior named in the build plan:

- fill override applies to multiple tracks and authored fallback remains
  recoverable;
- repeat source-step capture wins over step-order source remapping;
- step-order remaps playhead steps and clearing restores sequential playback;
- clearing one track compacts inactive state and does not affect other tracks;
- clearing all removes the overlay;
- unsupported sub-step repeat behavior is not represented or scheduled.

Run the focused test target if practical. If the full `xcodebuild test` run is
too expensive for this slice, run the narrowest reliable test command and record
the exact command/output in the final build-loop note.

## Guardrails

- Do not cherry-pick a broad probe branch.
- Do not copy probe UI panels or local SwiftUI state.
- Do not edit `docs/specs/**`.
- Do not start the engine/session/UI tasks from the plan in this request.
- Commit tightly scoped code/test changes when complete.

## Expected Follow-Up

After this slice lands, the coordinator should schedule the next build-loop
request for engine-owned overlay state, normalization, clear accessors, and
prepared-tick invalidation.
