---
created: 2026-05-07T12:04:28Z
source: multi-pass-coordinator
status: pending
priority: high
action: implement-work-item
worktree: .worktrees/p0-track-performance-overlay
branch: auto/p0-track-performance-overlay
base_commit: 1ab2bc131b72c8604bf2cef1ad5d660bd201efc8
plan: docs/plans/2026-05-06-track-performance-overlay.md
depends_on:
  architecture_review: docs/multi-pass-coordinator/inbox/architecture/archive/2026-05-07-p0-track-performance-overlay-model-review.md
  testing_review: docs/multi-pass-coordinator/inbox/testing/archive/2026-05-07-p0-track-performance-overlay-model-review.md
---

# P0 Track Performance Overlay - Engine/Session Ownership Slice

## Request

Continue the P0 track performance overlay build in the existing clean worktree:

- Worktree: `.worktrees/p0-track-performance-overlay`
- Branch: `auto/p0-track-performance-overlay`
- Starting commit: `1ab2bc1 Add track performance overlay model`

The pure model slice passed architecture and testing review. Implement the next
bounded production slice: authored repeat/order layer definitions plus
engine/session ownership for setting, reading, and clearing the runtime track
performance overlay.

Do not implement Track Perform UI, Keep/Discard writes, or full overlay-aware
playback resolution in this request. Leave those for follow-up reviewable
slices after this foundation is tested.

## Required Context

Read these before editing:

- `docs/plans/2026-05-06-track-performance-overlay.md`
- `docs/roadmap/agentic-loop/state.md`
- `docs/roadmap/agentic-loop/synthesis/production-cherry-pick-candidates.md`
- `docs/roadmap/agentic-loop/decisions/inferred-defaults.md`
- `docs/multi-pass-coordinator/inbox/architecture/archive/2026-05-07-p0-track-performance-overlay-model-review.md`
- `docs/multi-pass-coordinator/inbox/testing/archive/2026-05-07-p0-track-performance-overlay-model-review.md`
- `wiki/pages/playback-data-path.md`
- `wiki/pages/document-model.md`
- `wiki/pages/live-view.md`

## Scope

Implement only the next foundation slice:

- Add range-aware authored phrase layer definitions or equivalent typed layer
  targets for P0 repeat/order state:
  - repeat intent: `off` / `step-locked repeat`
  - repeat source step: captured source step index
  - step order: `forward` / `reverse` / `pingPong`
- Ensure older documents decode with those layers absent and compile to
  off/forward behavior.
- Add `EngineController` ownership for `trackPerformanceOverlay` adjacent to
  the existing runtime overlay patterns.
- Add engine commands for setting fill, repeat, and step order, clearing target
  tracks, clearing all track performance state, checking whether an overlay is
  active, and reading one track's overlay state.
- Normalize stale track IDs against the current playback snapshot, compact
  inactive entries, and treat `.forward` step order as inactive.
- Every engine setter/clearer must clear already-prepared output and reset the
  prepared tick index so stale notes cannot leak after a command.
- Add `SequencerDocumentSession` command methods for fill, repeat, step order,
  `clearTrackPerformance(trackIDs:)`, and `clearAllTrackPerformance()` that
  delegate to the engine without mutating authored phrase/document state.

## Out Of Scope

- No visible Track Perform controls, overlay badges, transaction strip, or
  Keep/Discard labels.
- No Keep writes to phrase cells, repeat/order layers, master-bus scenes, or
  crossfader state.
- No Discard coordinator beyond the track overlay clear command unless the
  existing engine API needs a harmless clear helper.
- No sub-step note-repeat scheduling or UI/API promise for 1/32 or 1/64 repeat.
- No probe UI or broad probe branch cherry-pick.
- Do not store runtime overlay data inside `Project`, `LiveSequencerStoreState`,
  or `PlaybackSnapshot`.

## Tests

Add focused production tests for this slice:

- Repeat/order layer definitions clamp to their own ranges and are not
  normalized as pattern-slot indexes.
- Older document/store defaults compile to repeat off and step order forward.
- Session fill, repeat, and step-order overlay commands leave `Project`,
  `LiveSequencerStore.exportToProject()`, and document bindings unchanged.
- Engine/session overlay setters do not replace the current authored playback
  snapshot or call the document-model apply path.
- Engine setters normalize stale track IDs, compact inactive entries, and keep
  duplicate target IDs idempotent.
- Clearing one target does not affect another target's overlay.
- Clearing all removes the track overlay.
- Every set/clear command invalidates already-prepared tick output.
- The production command API cannot construct unsupported 1/32 or 1/64
  repeat behavior.

Run the narrowest reliable focused test command while developing. Before
reporting the slice as integration-ready, run:

```text
xcodebuild test -project SequencerAI.xcodeproj -scheme SequencerAI -destination 'platform=macOS'
```

If the broad test run is blocked by environment rather than failures, record
the exact blocker and the focused tests that did run.

## Reporting

When complete, leave the worktree clean or clearly describe any remaining dirty
files. Report:

- commits created;
- files changed;
- test commands and results;
- any reason this slice had to widen or stop short;
- the next recommended review request.
