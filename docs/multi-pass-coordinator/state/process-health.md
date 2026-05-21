# Process Health

- updated: 2026-05-21T18:46:00Z
- request: `.meta/multipass/inbox/claimed/2026-05-21T18-40-19-764Z-process-health-observer-cadence.md`
- loop-local copy: `.meta/multipass/loops/project/observe/process-health.md`
- scope: observation only; no inbox messages, decisions, lifecycle changes, merge, push, cleanup, or build-loop actions performed.

## Checklist

- [x] Builders are doing real product work, not only coordination bookkeeping.
- [x] Review failures are feeding back into focused rework, refreshed gates, or integration disposition.
- [ ] Builder and high-context actor runs are completing reliably without repeated resource/runtime interruption.
- [ ] Runtime inbox status is low-noise and not carrying stale blocked or duplicate signals.
- [ ] Deterministic observation scripts cover the state actors repeatedly need.
- [ ] Visual/UX review evidence is consistently backed by reproducible app-surface and runtime-log tooling.
- [x] Product-owner attention is not being used for agent-detectable process problems.

## Observations

| Area | Evidence | Health read |
| --- | --- | --- |
| Product progress | Mixer Busses recovered from the Send B / Master Out clipping failure, produced exact commit `1eaebf3d6226f39a2438143b192493f54739352d`, passed exact-state architecture, testing/build, UX/IA, and visual-economy gates, and was routed to project integration. Scene Perform was accepted at `ab6206004edd4d0b35c917e53ef85f147df47723`; the integrator rebased it cleanly onto `main` as `1b69d29e58edcc327f4f4996d10a90e13e480741` with focused tests passing. | The loop is producing useful product work through build, review, rework, and integration-prep, not just coordination churn. |
| Review follow-through | Earlier Mixer Busses visual-economy failures became a focused builder continuation; the successor state passed all four exact-state gates. Scene Perform product-owner crossfader correction became a focused SwiftUI rework, then current testing, UX/IA, and visual-economy passes plus accepted scoped architecture inheritance. | Review failures are being converted into bounded work and refreshed evidence. |
| Integration blocker | `.meta/multipass/loops/project/act/2026-05-21T18-38Z-scene-perform-integration-evidence.md` says Scene Perform is mechanically merge-ready after rebase but not merged because root `main` has broad pre-existing coordination/migration dirt. Mixer Busses integration is queued behind Scene Perform. | Root dirt has become a concrete integration blocker. This is process/repository hygiene, not product uncertainty. |
| Resource/runtime churn | `.meta/multipass/state/actor-failures.md` lists eleven 2026-05-21 failures: ten `usage_rate_limit` failures and one missing final artifact. No compact failure evidence appears after 2026-05-21T13:54:45Z; later Mixer Busses continuation, reviews, decisions, and Scene Perform integration-prep completed. | Resource churn remains the biggest historical reliability tax, but recent recovery shows the loop can finish when work is checkpointed and bounded. |
| Inbox/status noise | Inventory now reports only two pending messages, but blocked still mixes 2026-05-20 cadence/orienter files, superseded build/review attempts, and real runtime failures. A `build/mixer-busses` build-decider cadence is pending even though the loop has already accepted and routed its integration candidate. | Current-state inference is possible, but stale lifecycle signals still cost tokens and can route redundant no-op cadence work. |
| Missing or stale visibility helpers | `scripts/multi-pass/inbox-status.sh` and `scripts/multi-pass/evidence-inboxes.sh` still scan legacy `docs/multi-pass-coordinator/inbox/*` paths. Observers continue to cite absent `pairing-state.sh`, `feature-state.sh`, `runtime-log-scan.sh`, `merge-status.sh`, `rebase-status.sh`, and worktree-hygiene status helpers. Inventory emits Ruby gem extension warnings before useful output. | The v2 runtime works, but deterministic visibility is still split across old and new control paths, driving fallback scans and noisy evidence collection. |
| Visual/runtime evidence brittleness | Current visual gates inspected exact commits and screenshots, but runtime-log scanning depends on git-history fallback content; app launches still log `gitCommit=unknown gitBranch=unknown`; CoreAudio HAL errors remain unattributed. | Visual review quality is acceptable for active gates, but app-window/runtime-log attribution remains too brittle for fast regression routing. |
| Evidence packaging | Mixer Busses architecture PASS exists as an actor final rather than loop-local observe markdown, and `.meta/multipass/loops/build/mixer-busses/observe/batches/1eaebf3d6226f39a2438143b192493f54739352d/batch.yaml` still says `status: open` despite all expected requests being done and passing. | This did not block routing, but it is a recurring small mismatch between runtime facts and loop-local artifact shape. |
| Product-owner attention | Active risks are root dirt, stale helpers, lifecycle noise, evidence packaging, and queued integration. | Product-owner attention is not needed. These are agent/process issues. |

## Suspected Causes

- UI-heavy actor runs previously mixed code edits, checks, app launch,
  screenshots, review routing, and final evidence in high-context sessions,
  making them vulnerable to `usage_rate_limit` interruption.
- The runtime preserves blocked lifecycle files conservatively, which is useful
  evidence, but there is no compact current blocker view separating live
  blockers from superseded or historical blocked files.
- Some project-local scripts and prompts still straddle retired
  `docs/multi-pass-coordinator/inbox` paths and live `.meta/multipass` runtime
  paths.
- Build-loop cadence actors can still run after a merge candidate has already
  been accepted and routed, creating redundant status churn.
- Root `main` coordination/migration dirt has been tolerated as observation
  noise long enough that it now blocks a clean product merge.

## Suggested Repair Shape

- Treat root `main` coordination/migration dirt as the immediate process repair
  pressure because it now blocks otherwise merge-ready product work.
- Prefer prompt/actor-contract repair for post-disposition cadences: after a
  build loop has accepted and routed a merge candidate, later build-decider
  cadence actors should record no-op/stale evidence rather than reopen product
  routing.
- Keep the successful builder checkpointing pattern: exact commit, clean
  worktree, focused checks, and screenshots before longer review/disposition
  work.
- Replace or update legacy inbox helpers with a compact runtime-inbox/current
  blocker summary that marks active blockers, superseded failures, and
  historical blocked lifecycle files without deleting evidence.
- Restore only repeatedly needed observation helpers, especially
  `pairing-state.sh` and runtime-log/app-window readiness. Avoid a broad
  deterministic state machine for product judgment.
- Normalize review-batch bookkeeping after expected observer requests are done,
  or make the actor contract explicit that actor finals can satisfy batch
  evidence when no loop-local observe markdown was produced.

## Current Disposition

The loop is product-productive and integration-bound. Scene Perform is
mechanically merge-ready but blocked by broad root dirt. Mixer Busses is queued
behind Scene Perform with accepted exact-state PASS evidence. The active
process risks are repository hygiene, stale visibility helpers, redundant
cadence/lifecycle noise, and residual runtime-log attribution gaps. No
product-owner attention is needed.
