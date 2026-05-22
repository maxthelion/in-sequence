# Process Health

- updated: 2026-05-21T22:47:21Z
- request: `.meta/multipass/inbox/claimed/2026-05-21T22-46-15-961Z-process-health-observer-cadence.md`
- loop-local copy: `.meta/multipass/loops/project/observe/process-health.md`
- observation artifact: `.meta/multipass/loops/project/observe/2026-05-21T22-47Z-process-health-observation.md`
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
| Product progress | Active build loops remain `build/scene-perform` and `build/mixer-busses`. Scene Perform is accepted and rebased at `d5b47500f4c7c08d704b89b30b2e27ceb0a00078`. Mixer Busses is accepted at `1eaebf3d6226f39a2438143b192493f54739352d` with exact-state architecture, testing/build, UX/IA, and visual-economy PASS evidence. | The loop is still producing real product work and review-disposition evidence, not only coordination churn. |
| Review follow-through | Scene Perform's product-owner crossfader observation became focused SwiftUI rework and refreshed tests/reviews. Mixer Busses visual-economy failures became the Master Out clipping continuation and exact-state review gates. | Review failures are feeding into bounded rework and refreshed evidence. This part of the loop is healthy. |
| Integration blocker | Process-fixer committed root coordination-state cleanup as `cec6d59ebb43fa8ec6fcb4a086ea3bc0bca4bf29`, but the latest orienter reports root `main` is dirty again with coordination-summary edits. Fresh `git status --short` shows `docs/multi-pass-coordinator/ooda/orientation.md` and `docs/multi-pass-coordinator/state/build-loops/mixer-busses.md` modified before this observation update. | The repeated blocker is narrower than the earlier broad root dirt, but the pattern remains: coordination-state writes can re-dirty `main` between hygiene repair and integration, delaying merge-ready product work. |
| Integration order | Latest orientation and build-loop summaries keep Scene Perform first; Mixer Busses waits behind it. The only pending message observed by inventory was a `build/scene-perform` build-orienter cadence, while this process-health request was claimed. | The ordering is clear. The loop needs a clean or explicitly accounted-for root before a follow-up Scene Perform integrator, then Mixer Busses merge-prep. |
| Resource/runtime churn | `.meta/multipass/state/actor-failures.md` still lists eleven 2026-05-21 failures: ten `usage_rate_limit` and one missing final artifact. No compact actor failure appears after 2026-05-21T13:54:45Z; later builders, reviewers, orienters, process-fixers, and integrators completed. | Rate-limit churn is historical for this pass, but still a real reliability tax for high-context UI actors. Checkpointed exact commits and compact evidence are enabling recovery. |
| Cadence churn | Activity shows many post-acceptance build-orienter/build-decider cadences completing no-op or disposition-preserving work after both build loops had accepted candidates. | Cadence work is mostly benign, but it burns tokens and can create fresh coordination-state dirt that blocks integration. |
| Inbox/status noise | Blocked inbox still mixes old 2026-05-20 cadence files, superseded build/review attempts, and real runtime failures. Done has a long useful history, but live status requires manual filtering. | Lifecycle preservation is useful evidence, but current-state inference remains noisy without a compact active-blocker view. |
| Deterministic visibility | `scripts/multi-pass/inbox-status.sh` and `scripts/multi-pass/evidence-inboxes.sh` still scan retired `docs/multi-pass-coordinator/inbox/*` paths. Observers still report missing or absent helpers such as `pairing-state.sh`, `feature-state.sh`, `runtime-log-scan.sh`, `merge-status.sh`, `rebase-status.sh`, and worktree hygiene status. Inventory/build-capacity emit Ruby gem extension warnings before useful output. | The v2 runtime is usable, but observation still pays a token and accuracy tax from stale helper paths and missing small state scripts. |
| Visual/runtime evidence | Active visual gates for Scene Perform and Mixer Busses had exact screenshots and passed. The latest runtime-log observation found no fresh crash/fatal app evidence, but had to recover the absent `runtime-log-scan.sh` from git history and still had no app launch commit/branch metadata. | Visual review quality is acceptable for current gates. Runtime-log attribution and app-surface helper reproducibility remain low-severity process debt. |
| Evidence packaging | Mixer Busses architecture PASS remains an actor final rather than loop-local observe markdown, and the `1eaebf3` batch manifest still says `status: open` despite completed PASS gates. | This did not block routing, but weakens fast machine-readable readiness and contributes to repeated manual evidence reconstruction. |
| Product-owner attention | Active issues are coordination-state hygiene, cadence/status noise, helper drift, and evidence packaging. | No product-owner attention is needed. These are agent/process issues. |

## Suspected Causes

- Durable coordination summaries are being edited on `main` by cadence actors while integrators require a clean root before landing product branches.
- Cadence actors keep running after a build candidate has been accepted and routed, which is useful for freshness but can produce new state dirt faster than integration consumes it.
- Project-local helper scripts still straddle retired coordinator paths and live `.meta/multipass` v2 runtime paths.
- High-context UI actors previously mixed implementation, app launch, screenshots, reviews, and evidence packaging, making them prone to `usage_rate_limit`; later exact-commit checkpointing reduced the impact.
- Runtime lifecycle state keeps all blocked evidence in one directory without a compact current-blocker classification.

## Suggested Repair Shape

- Treat recurring root coordination-state dirt as the immediate process risk because it repeatedly blocks otherwise merge-ready Scene Perform integration.
- Prefer actor-contract repair over a brittle state machine: after a merge candidate is accepted and routed, cadence actors should write compact no-op/freshness evidence and avoid unnecessary durable state churn unless facts changed materially.
- Add or restore a small v2 runtime-inbox/current-blocker summary helper that separates active blockers, superseded failures, and historical blocked lifecycle files without deleting evidence.
- Update legacy inbox helpers to read `.meta/multipass/inbox`, or clearly mark them retired so observers stop paying fallback-scan costs.
- Restore only repeatedly needed observation helpers, especially pairing/build-loop current state and checked-in runtime-log/app-window readiness.
- Normalize review-batch bookkeeping after all expected observer requests finish, or document that actor finals can satisfy batch evidence when loop-local observe markdown is absent.

## Current Disposition

The loop is product-productive and integration-bound. Scene Perform remains the
first integration candidate at `d5b4750`; Mixer Busses remains accepted at
`1eaebf3` and queued behind it. The strongest process risk is not product
quality but repeated coordination-state dirt on `main` between cleanup and
integration. Product-owner attention is not needed.
