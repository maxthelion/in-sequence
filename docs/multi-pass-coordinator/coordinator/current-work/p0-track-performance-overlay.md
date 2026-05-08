# P0 Track Performance Overlay

Status: active
Branch/worktree: `.worktrees/p0-track-performance-overlay` on `auto/p0-track-performance-overlay`
Last coordinator review: decided 2026-05-08T12:50Z
Last work-observer update: observed 2026-05-08T12:38Z

## Intent

Let a performer use track-level performance overlay controls in a way that
supports live play, can be kept or discarded intentionally, and fits the broader
in-sequence workspace.

## Current Claim

The backend model, engine/session ownership, playback-resolution,
session-side Keep/Discard, minimal visible Track Perform transaction,
Keep-result feedback correction, card-legibility correction, and
transaction-button legibility correction have landed in the dedicated
worktree. Visual review passed
`d36c78b fix(ui): keep transaction strip actions legible`, with evidence at
`.meta/project/actors/visual-review/p0-track-performance-overlay-transaction-button-legibility.png`.
Architecture review then passed the UI transaction commits
`d818d8d..d36c78b`, confirming the visible transaction stays on existing
session/engine/document ownership boundaries. The P0 workflow is ready for a
product-owner checkpoint.

## Readiness Pyramid

- [x] User can do the intended thing
- [x] Important behaviour is evidenced
- [x] UX/IA has been reviewed
- [x] Visual/product coherence has been reviewed
- [x] Architecture is acceptable
- [x] Testing/performance/data risks are acceptable
- [x] Fits the project philosophy

## Lens Evidence

| Lens | Status | Evidence | Next action |
|---|---|---|---|
| Build | passed for latest correction | `d36c78b fix(ui): keep transaction strip actions legible` finalized the prior dirty partial after the visual blocker on `1b826ba`. Build reported focused transaction tests, capture test, `git diff --check`, and full `xcodebuild test` passing with 841 tests, 4 skipped, and 0 failures. | No duplicate build this tick |
| UX/IA | passed for correction | UX/IA review of `0d026e6` passed. Pending repeat is visible before Keep, stale/direct deferred-repeat results map to waiting copy, missing authored phrase cells leave the overlay active with an explanation, and Keep/no-active/Discard paths clear stale transaction state. Residual copy risk: `authored phrase cells` is acceptable for P0 but should later move toward performer language. | No duplicate UX/IA pass this tick unless visual review finds a workflow clarity regression |
| Visual | passed for latest correction | Visual review passed `d36c78b` in `.meta/project/actors/visual-review/2026-05-08-p0-track-performance-overlay-transaction-button-legibility-review.final.md`. The capture covers the active pending-repeat state and confirms readable `Waiting`/`Discard` transaction actions while preserving accepted compact card badges and card-level icon controls. | Mark visual/product coherence passed; do not request another visual pass unless later work changes the surface |
| Architecture | passed for latest UI commits | `.meta/project/actors/architecture-review/2026-05-08-p0-track-performance-overlay-ui-transaction-review.final.md` passed `d818d8d..d36c78b`; the transaction delegates through the existing session command API, reads runtime overlay state from `EngineController`, and keeps result/status state local to presentation. | No duplicate architecture pass this tick |
| Testing | accepted by coordinator for bounded UI correction | Archived review `docs/multi-pass-coordinator/inbox/testing/archive/2026-05-08-p0-track-performance-overlay-keep-discard-missing-target-reconsideration.md` passed with focused 34-test evidence; UI commits through `d36c78b` have build-reported focused transaction tests, capture-test evidence, and full-suite passes. | No duplicate testing-review pass this tick |
| Holistic | fresh and product-positive | `docs/multi-pass-coordinator/coordinator/holistic-status.md` was refreshed at 2026-05-08T11:45Z and has a coordinator disposition at 11:59Z. The product direction still coheres; the former transaction-action legibility blocker has now passed visual review. | No duplicate holistic observer request this tick |

## Open Problems

- Testing review is stale for the latest UI transaction commits, but the
  coordinator accepted current build-reported focused transaction, capture, and
  full-suite evidence as enough for this bounded UI correction.
- Product-owner attention is now requested. The only known product issue is
  residual copy polish around `authored phrase cells`, accepted by UX/IA as
  non-blocking for the internal P0 gate.

## Next Coordinator Move

Do not schedule duplicate build, testing-review, visual, UX/IA, architecture,
holistic, work-observer, or process-repair work. The next action is
product-owner review of the checkpoint requested in
`docs/multi-pass-coordinator/product-owner-attention.md`. If the product owner
accepts it, checkpoint/tag/cherry-pick discipline can proceed in the relevant
roadmap flow; if they reject it, route the smallest focused follow-up.

## Product Owner Attention

Requested at 2026-05-08T12:50Z.

## Coordinator Disposition 2026-05-08T12:27Z

Build-loop finalized the transaction-button legibility correction at
`d36c78b`. The coordinator scheduled fresh visual review and kept
product-owner attention blocked until that review accepts the committed
surface and the stale architecture/testing lens question is resolved.

## Coordinator Disposition 2026-05-08T12:41Z

Visual review passed `d36c78b`, and the work-observer marked architecture as
the lowest unmet gate. The coordinator scheduled one architecture review for
the UI transaction commits and accepted build-reported focused/full test
evidence as sufficient without a duplicate testing-review pass.

## Coordinator Disposition 2026-05-08T12:50Z

Architecture review passed `d818d8d..d36c78b`, closing the final stale lens
gate for the UI transaction surface. The coordinator requested product-owner
attention for the P0 Track Performance Overlay checkpoint and scheduled no
additional actor work.
