# Process Health

- updated: 2026-06-16T15:34Z
- request: `.meta/multipass/runtime/inbox/claimed/2026-06-16T152226580Z-process-health-observer-cadence.md`
- observation artifact:
  `.meta/multipass/runtime/loops/project/observe/2026-06-16T15-34Z-process-health-observation.md`
- verdict: `yellow`
- scope: observation only; no inbox message, request lifecycle move, merge,
  rebase, cleanup, product-code edit, PM artifact action, build action,
  process repair, test suite, visual capture, or product-owner question
  performed.

## Summary

The loop improved from red to yellow. The prior routing failure did not leave
abandoned product-code dirt: project/build orienters and deciders routed
recovery, the continuation builder completed a clean exact checkpoint
`babe91e0856c54b9c37710bfe4c4542e5fb81947`, and the build decider opened the
required exact-state review batch.

The loop is still unhealthy on cost and reserve depth. Latest-24h token
pressure is `6.30M` across `52` runs with `11` failures and `1.96M`
failed/blocked pressure. One ordinary build slot is open, ready/unpromoted
ready candidates remain `none`, and repeated observer cadence plus stale
reports/Ruby warning noise still make process-health reconstruction expensive.

## Top Risks

| Risk | Throughput impact | Evidence |
| --- | --- | --- |
| Observer cadence and rate-limit failures still dominate cost | Product work is moving, but observers are still the largest spend and failure surface. | `token-pressure --hours 168`: `52` latest-24h runs, `11` failures, `6,296,573` token pressure, `1,964,715` failed/blocked pressure. |
| Capacity and reserve remain thin | Routing consumes one ordinary slot; the other slot is open with no ready PM supply. | `build-capacity.ts`: active ordinary build loops `1`, locked build loops `2`, available slots `1`, ready candidates `none`, unpromoted ready candidates `none`. |
| Runtime/status visibility remains noisy | Stale reports and lifecycle residue force repeated manual interpretation. | Saved reports are stale (token pressure June 8, swimlanes June 4); Foreman CLIs emit Ruby warnings; root `main` is `abc9adf6` with `315` dirty/local-only paths. |

## KPI Snapshot

| KPI | Current read |
| --- | --- |
| Implementation time | Completed act time returned: integrator `17.7m`, process-fixer `4.6m`, successful routing builder `4.0m` (`26.3m` total). A failed routing builder attempt burned `24.4m`. |
| Idle / blocked time | Inbox status: `8` pending, `4` claimed, `671` blocked, `3608` done. One ordinary build slot open. |
| Actor failures | `11` latest-24h failures, mostly `usage_rate_limit`; compact failure evidence includes repeated project observers and the first routing builder. |
| Token pressure | `6.30M` latest-24h token pressure; failed/blocked pressure `1.96M`; largest hour 13:00Z with `1.84M`. |
| High-priority time-to-claim | Recovery claims were prompt: integrator about `2.6m`, process-fixer about `5.5m`, continuation builder about `3.7m`. New high-priority review requests were just queued and still pending at the scan. |
| Open build capacity | `1` ordinary slot open; `build/routing-source-mixer-split` active; Observability and MIDI locked outside capacity. |

## Follow-Through

Repaired or improving:

- Prior "no act time" risk is repaired for this window.
- The failed routing builder was converted into a clean committed checkpoint
  and queued exact-state review batch.
- Project orienter/decider cadence is no longer stale; it produced concrete
  action on June 16.

Still repeating:

- `usage_rate_limit` remains the dominant failure mode.
- PM reserve recovery remains blocked and no ready-buffer candidate exists.
- Observability remains human-locked with dirty partial work beyond the
  reviewed checkpoint; MIDI remains hardware-locked.
- Broad root dirt, stale reports, lifecycle residue, and Ruby warning noise
  continue to tax observers.

## Recovery Health

- `build/routing-source-mixer-split`: healthy recovery so far; clean at
  `babe91e0`, `0` behind / `2` ahead of local `main`, exact-state reviews
  pending, mandatory critic still required.
- `build/observability-log-issues`: still human-locked; dirty partial remains
  unpaired beyond reviewed `714fdb8`.
- `build/midi-interfaces`: clean at `34d5c43`; missing hardware acceptance.
- PM reserve recovery: still blocked by `usage_rate_limit`.

## Suggested Repair Shape

- `cadence thinning`: prompt/actor-contract repair. Smallest success signal:
  after a concrete build-loop action, do not launch another broad project
  observer wave until the active high-priority review batch resolves.
- `ready-buffer recovery`: project process-fixer or PM-prep recovery. Smallest
  success signal: one compact candidate/no-candidate artifact for the next
  unlocked PM lane.
- `report freshness`: coordinator/report repair. Smallest success signal:
  regenerated June 16 swimlane/token reports with clear stale labels.
- `rate-limit contract`: coordinator failure-artifact repair. Smallest success
  signal: future `usage_rate_limit` artifacts include branch, HEAD, dirty
  counts, and completed checks automatically.

## Checks Run

- Read the claimed request, process-health prompt/actions, project README,
  Foreman Coordinator README, Foreman config, prior process-health, decision
  log, current-work, feature-readiness, holistic status, flow status,
  lifecycle status, active build-loop summaries, compact actor-failure
  evidence, routing builder final, routing build summary, routing
  decision/batch evidence, and report freshness.
- Ran Foreman Coordinator `inventory.ts`, `recent-runs.ts --limit 40`,
  `recent-runs.ts --limit 20`, `build-capacity.ts`, and
  `token-pressure.ts --hours 168 --json`.
- Ran `scripts/multi-pass/inbox-status.sh` and
  `scripts/multi-pass/process-evidence-status.sh`.
- Checked direct root and routing worktree branch/HEAD/dirty relation.
- No broad raw actor transcript scan was performed; evidence came from compact
  state, deterministic scripts, loop-local artifacts, and actor finals.
