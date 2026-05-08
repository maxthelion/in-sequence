---
created: 2026-05-08T11:16:18Z
source: visual-review
status: pending
priority: high
worktree: .worktrees/p0-track-performance-overlay
commit: 0d026e6
evidence:
  - .meta/project/actors/visual-review/p0-track-performance-overlay-pending-repeat.png
  - .meta/project/actors/visual-review/p0-track-performance-overlay-missing-target-before-keep.png
---

# Correct Track Perform Card Control And Badge Legibility

Visual review did not pass for
`0d026e6 fix(ui): surface track performance keep feedback`.

The transaction strip itself is readable in the captured Tracks perform surface:
Keep/Discard target copy fits, pending-repeat status is visible, and the Keep
button correctly becomes a disabled `Waiting` affordance while Repeat is
pending.

Blocking visual issue: the per-track perform card becomes unreadable at the
current Tracks matrix card width.

- The Fill, Repeat, Order, and Clear controls collapse to `...`, `...`, `Or`
  plus a chevron, and `...`, so the performer cannot tell what each control
  does.
- Transient badges wrap mid-word into fragments such as `REPE / AT / PEN /
  DING` and `ORD / ER / REVE / RSE`, which makes active runtime state look
  broken rather than intentional.

Smallest requested correction:

- Keep the existing Tracks perform surface and transaction strip placement.
- Make the per-card Fill, Repeat, Order, and Clear controls legible at the
  current one-card minimum width. A two-row control layout, fixed-width icon
  buttons with tooltips, or another compact existing-style layout is fine as
  long as visible labels/icons no longer collapse to ellipses.
- Make transient overlay badges readable without mid-word wrapping. Prefer
  labels that fit, a vertical list, or a controlled wrapped layout where each
  badge remains a coherent token.
- Preserve the current transaction-strip behavior for pending Repeat, failed
  Keep, successful Keep, Discard, and Clear.

Suggested implementation scope:

- `Sources/UI/TracksMatrixView.swift`
- focused presentation/view tests if available; otherwise existing
  `TrackPerformanceTransactionTests` plus a fresh visual capture after the
  correction

Expected evidence:

- A new visual capture of the existing Tracks perform surface with active Fill,
  pending Repeat, and Order overlay state showing readable per-card controls and
  badges.
- Existing focused transaction/session/overlay tests and the project test
  command still pass.
