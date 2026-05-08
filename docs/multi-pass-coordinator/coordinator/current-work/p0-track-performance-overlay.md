# P0 Track Performance Overlay

Status: active
Branch/worktree: `.worktrees/p0-track-performance-overlay` on `auto/p0-track-performance-overlay`
Last coordinator review: decided 2026-05-08T10:22Z

## Intent

Let a performer use track-level performance overlay controls in a way that
supports live play, can be kept or discarded intentionally, and fits the broader
in-sequence workspace.

## Current Claim

The backend model, engine/session ownership, playback-resolution, and
session-side Keep/Discard slices have landed in the dedicated worktree. The
latest Keep/Discard session commit has passed architecture review, and testing
review has now passed after the missing-target safe-failure evidence landed at
`d818d8d`. The next build-loop request is the minimal visible Track Perform
transaction. No Track Perform UI controls, badges, Keep/Discard labels, or
transaction strip have been built yet.

## Readiness Pyramid

- [ ] User can do the intended thing
- [ ] Important behaviour is evidenced
- [ ] UX/IA has been reviewed
- [ ] Visual/product coherence has been reviewed
- [x] Architecture is acceptable
- [x] Testing/performance/data risks are acceptable
- [x] Fits the project philosophy

## Lens Evidence

| Lens | Status | Evidence | Next action |
|---|---|---|---|
| Build | next UI slice queued | `096ed01 feat(app): keep and discard performance overlays` landed with focused session/master-bus plus overlay tests passing with 33 tests and full `xcodebuild test` passing with 830 tests, 3 skipped. Follow-up `d818d8d test(app): cover missing overlay keep target` added `SequencerDocumentSessionMasterBusTests.test_keepPerformanceOverlayFailsSafelyWhenAuthoringTargetIsMissing`; focused verification passed with 34 tests and the worktree is clean. | Build-loop request `docs/multi-pass-coordinator/inbox/build-loop/2026-05-08-p0-track-performance-overlay-minimal-ui-transaction.md` should add the minimal visible Track Perform transaction |
| UX/IA | implementation not reviewed | Original build-plan UX/IA review remains planning evidence, but no review covers the implemented session behavior or the still-missing UI controls | After the UI slice lands, route UX/IA review of the visible transaction |
| Visual | missing for user-facing slice | No Track Perform controls, overlay badges, Keep/Discard labels, or transaction strip exist yet | Visual review should wait until the minimal UI slice exists |
| Architecture | passed for latest slice | `.meta/project/actors/architecture-review/2026-05-08-p0-track-performance-overlay-keep-discard-session-review.final.md`; coordinator archive `2026-05-08-p0-track-performance-overlay-keep-discard-session-architecture-pass.md` | No architecture rework requested for `3b50781..096ed01` |
| Testing | passed for backend/session slice | Archived review `docs/multi-pass-coordinator/inbox/testing/archive/2026-05-08-p0-track-performance-overlay-keep-discard-session-review.md` returned `needs-evidence`; follow-up `d818d8d` added the missing safe-failure test; testing-review reconsideration `docs/multi-pass-coordinator/inbox/testing/archive/2026-05-08-p0-track-performance-overlay-keep-discard-missing-target-reconsideration.md` passed with focused 34-test evidence. | Next test evidence should cover the UI command/transaction contract after the build slice lands |
| Holistic | observed | `docs/multi-pass-coordinator/coordinator/holistic-status.md`; observer final `.meta/project/actors/holistic-observer/2026-05-08T09-27-08Z-holistic-observer-cadence.final.md` says the backend story coheres and fits the Happy Accident Workbench direction, but the visible transaction is still missing | Build the minimal Track Perform UI/transaction slice before broader performance or lane work |

## Open Problems

- Users still cannot complete the intended visible workflow because the app has
  backend/session semantics but no Track Perform UI controls, overlay badges,
  Keep/Discard labels, or transaction strip.
- Holistic/product-fit evidence now supports the direction, but showability is
  still blocked on the missing visible transaction.

## Next Coordinator Move

Do not schedule duplicate review or rework. The minimal Track Perform
UI/transaction build request is now queued at
`docs/multi-pass-coordinator/inbox/build-loop/2026-05-08-p0-track-performance-overlay-minimal-ui-transaction.md`.
After that build lands, route UX/IA plus visual review before broader
performance controls or product-owner attention. The 2026-05-08T09:53Z
process-health pass is fresh and does not change the product path; its optional
consistency cleanup remains deferred unless duplicate/stale handoffs recur.

## Product Owner Attention

None yet. Agent-side observation and review should happen first.
