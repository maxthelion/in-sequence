---
created: 2026-05-08T11:58:01Z
source: visual-review
status: pending
priority: high
worktree: .worktrees/p0-track-performance-overlay
commit: 1b826ba
evidence:
  - .meta/project/actors/build/p0-track-performance-overlay-perform-card-legibility.png
  - .meta/project/actors/visual-review/crops/build-card.png
  - .meta/project/actors/visual-review/crops/build-strip-left.png
  - .meta/project/actors/visual-review/crops/build-strip-right.png
blocker_reason: "actor exited with status 143"
---

# Correct Track Perform Transaction Button Legibility

Visual review did not pass for
`1b826ba fix(ui): keep track perform card controls legible`.

The card-level correction appears to address the previous blocker:

- transient badges now read as coherent tokens: `FILL ON`, `REPEAT WAIT`,
  and `ORDER REV`;
- per-track controls no longer collapse to ellipses; the icon buttons are
  visible and stable at the current card width.

Blocking visual issue: the transaction-strip action controls are not legible in
the corrected capture. In
`.meta/project/actors/build/p0-track-performance-overlay-perform-card-legibility.png`,
the right side of the strip renders as two unlabeled yellow blocks with
red "not allowed" icons rather than readable `Waiting`/`Keep` and `Discard`
actions. This means the requested Keep/Discard legibility check cannot pass.

Smallest requested correction:

- Keep the existing Tracks perform surface and current transaction-strip
  placement.
- Make the transaction-strip actions render as readable controls at the current
  strip width in visual evidence. `Waiting`/`Keep` and `Discard` must be
  legible text or unmistakable icon+text controls, not placeholder-looking
  colored blocks.
- Preserve the now-readable compact per-card controls and badges.
- Preserve transaction behavior for pending Repeat, failed Keep, successful
  Keep, Discard, and Clear.

If this turns out to be an offscreen capture artifact rather than production UI,
the next build-loop pass should still provide trustworthy visual evidence from
the real Tracks perform surface. Product-owner attention should stay blocked
until visual review can inspect readable transaction action controls.

Suggested implementation scope:

- `Sources/UI/TracksMatrixView.swift`
- any render harness or capture setup used to produce the visual evidence, if
  the production UI is already correct but the capture path is not

Expected evidence:

- A fresh visual capture of the existing Tracks perform surface with active
  Fill, pending Repeat, and Order overlay state.
- The capture must show readable card badges, readable card controls, readable
  transaction target/status copy, and readable transaction action controls.

## Coordinator Continuation 2026-05-08T12:18Z

The first build-loop run exited with status 143 before writing a final summary
or committing. Do not restart from scratch. Continue from the dirty partial in
`.worktrees/p0-track-performance-overlay`:

- `Sources/UI/TracksMatrixView.swift`
- `Tests/SequencerAITests/LiveWorkspaceViewTests.swift`

The partial also produced
`.meta/project/actors/build/p0-track-performance-overlay-transaction-button-legibility.png`,
which appears to show readable `Waiting` and `Discard` transaction actions.
Finish the request by validating the partial, making only the smallest needed
adjustments, running focused transaction/UI checks plus any required full-suite
or diff checks, committing the production/test changes, writing the build final,
and notifying the coordinator. Product-owner attention remains blocked until a
fresh visual review accepts the committed correction.
