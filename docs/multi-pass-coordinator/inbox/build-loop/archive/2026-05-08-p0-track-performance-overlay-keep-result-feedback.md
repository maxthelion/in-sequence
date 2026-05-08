---
created: 2026-05-08T10:50:12Z
source: ux-ia-review
status: pending
priority: high
worktree: .worktrees/p0-track-performance-overlay
commit: 3ec4b13
---

# Correct Track Perform Keep Result Feedback

UX/IA review did not pass for
`3ec4b13 feat(ui): add track performance transaction controls`.

The visible Track Perform transaction mostly fits the existing Tracks perform
surface: Fill, Repeat, Order, and Clear live on each track card; transient
badges name active runtime-only state; and the transaction strip appears only
when a track or master-bus overlay is active.

Blocking issue: the Keep affordance is not predictable when the session refuses
to commit the overlay. `SequencerDocumentSession.keepPerformanceOverlay()`
returns `.deferredPendingRepeat(trackIDs:)` while any track has
`.pendingStepLock`, and `.failedMissingAuthoringTarget` when the authored target
cannot be written. The current UI calls Keep and ignores the result, so the
performer sees a green Keep button but may get no keep, no clear, and no
explanation.

Smallest requested UI/IA correction:

- In the Track Perform transaction strip, make non-kept Keep outcomes visible
  and predictable.
- Before pressing Keep, if any visible track override has `Repeat Pending`,
  show inline strip copy such as `Repeat pending: wait for the source step to
  lock before Keep`, and disable or retitle the Keep action so it no longer
  promises an immediate commit.
- If Keep returns `.failedMissingAuthoringTarget`, leave the overlay active and
  show an inline strip message that the live change cannot be kept because the
  authored phrase cells are unavailable; keep Discard available as the clear
  escape hatch.
- Preserve the current passing behaviour for `.kept`, `.noActiveOverlay`, and
  Discard.

Suggested implementation scope:

- `Sources/UI/TrackPerformanceTransaction.swift`
- `Sources/UI/TracksMatrixView.swift`
- focused tests in `Tests/SequencerAITests/LiveWorkspaceViewTests.swift`

Expected evidence:

- Presentation tests prove pending repeat changes the Keep affordance/copy.
- Action/result tests prove non-kept Keep outcomes do not silently disappear.
- Existing transaction, session, overlay, and full test commands still pass.
