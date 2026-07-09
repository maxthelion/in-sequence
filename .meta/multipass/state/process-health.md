# Process Health

- updated: 2026-07-06T11:35Z
- request: `.meta/multipass/runtime/inbox/claimed/2026-07-04T171510683Z-process-health-observer-cadence.md`
- observation artifact:
  `.meta/multipass/runtime/loops/project/observe/2026-07-06T11-35Z-process-health-observation.md`
- verdict: `yellow`
- scope: observation only; no inbox message, request lifecycle move, merge,
  rebase, cleanup, product-code edit, product test suite, visual automation,
  process repair, or product-owner question performed.

## Summary

The loop is producing useful product work, but its process health remains
yellow. Recent repair work created and advanced
`build/drum-kit-matrix-sound-prep`; builders produced exact-state seam evidence,
architecture passed, focused tests passed `18/0`, and UX canon lint passed with
`0` violations. Disk pressure also improved to roughly `30Gi` available.

The main throughput problem is cadence churn and slow follow-through on the
current concrete gate. Latest-24h token pressure is `21.06M` across `274` runs,
up `1.54x` from the previous 24h. The biggest spenders over 168h are
`pm-orienter` (`10.56M`), project `decider` (`8.53M`), and `pm-decider`
(`6.16M`). Meanwhile the build-loop testing-review continuation for
`build/drum-kit-matrix-sound-prep`, created at `2026-07-06T10:17Z`, remained
pending during the `11:28Z` scan.

## Top Risks

| Risk | Throughput impact | Evidence |
| --- | --- | --- |
| Cadence churn dominates token pressure | Product work exists, but PM/project orient-decide polling is the largest spend and repeats no-op conclusions. | `token-pressure --hours 168 --json`: `34.72M` total; top actors `pm-orienter`, project `decider`, `pm-decider`. |
| Concrete build-review follow-through is lagging | The next accepted gate for active drum-kit work waits while generic cadence continues. | Pending `.meta/multipass/runtime/inbox/pending/2026-07-06T101720296Z-testing-review.md` after about `70m`; capacity is full at `2/2`. |
| Stale/superseded state keeps reconstruction expensive | Observers must rerun live commands and qualify exact checkout state. | June report timestamps, active but superseded `pm/july-4-phrase-layers-global-apply`, root `main` at `c8f368d5c3c5` with `295` dirty/local paths. |

## KPI Snapshot

| KPI | Current read |
| --- | --- |
| Implementation time | Recent useful act work: drum-kit process-fixer `2.3m`, two drum-kit builders `4.3m`, plus July 5 integrations/closeouts. Over 168h, builder token pressure is much smaller than PM/project cadence. |
| Idle / blocked time | Inbox: `17` pending, `3` claimed, `714` blocked, `5004` done. No ordinary build slots open, but one active build review gate is pending. |
| Actor failures | 168h: `10` failures; latest 24h: `3` failures. Compact failures remain dominated by `usage_rate_limit`; recent failed project decider also appears in recent runs. |
| Token pressure | Latest 24h `21,063,472`; previous 24h `13,652,712`; ratio `1.54x`; 168h total `34,716,184`; failed/blocked pressure warning `11,409,979`. |
| High-priority time-to-claim | Drum-kit setup and builders were claimed; current testing-review continuation remained unclaimed about `70m` after creation. |
| Open build capacity | `0`; active ordinary loops are `build/au-runtime-safety` and `build/drum-kit-matrix-sound-prep`; locked loops are Observability and MIDI; ready candidates `none`. |

## Dumb-Loop Signals

- Repeated project decider no-op/full-capacity decisions are recorded through
  July 6 while the same drum-kit testing-review request remains pending.
- `pm/july-4-phrase-layers-global-apply` continues to receive cadence despite
  durable state saying it is resolved on `main` and should be no-op without new
  feedback.
- `pm/track-phrase-perform-interaction-prep` is also bouncing between
  orientation and decision around the same conclusion: let the existing pending
  PM readiness observer run.
- Coordinator CLIs still emit Ruby warning noise before useful output.

## Follow-Through

Repaired or improving:

- Stale routing/AU rescan capacity accounting was repaired on July 4.
- PM ready-buffer recovery produced the current drum-kit build loop.
- Disk pressure has improved from the July 5 `73Mi` post-merge failure state to
  about `30Gi` free.

Still repeating:

- Cadence runs continue to rediscover no-op/full-capacity facts faster than the
  exact pending build-review gate is claimed.
- Stale report artifacts from June remain unrepaired.
- Superseded PM lanes still appear active enough to spend tokens.
- Root dirt remains broad.

## Recovery Health

- `build/drum-kit-matrix-sound-prep`: healthy but waiting on testing-review
  continuation. Visual evidence remains `capture-permission-or-focus`.
- `build/au-runtime-safety`: deterministic checkpoint exists but full closure
  still needs human-present third-party AU validation or an accepted manual gap.
- `build/observability-log-issues` and `build/midi-interfaces`: correctly
  locked outside ordinary capacity.
- No product-code dirt from failed actors was observed as newly orphaned in this
  pass; compact failure evidence was sufficient.

## Suggested Repair Shape

- `cadence thinning`: process/prompt repair. Smallest success signal: no
  duplicate project/PM no-op decisions while a named pending build/review gate
  is waiting and no new evidence exists.
- `pending-gate priority`: coordinator scheduling repair. Smallest success
  signal: active build-loop review gates are selected before generic cadence
  when build capacity is full.
- `superseded PM closeout`: lifecycle/process repair for
  `pm/july-4-phrase-layers-global-apply`. Smallest success signal: inventory
  or scheduler no longer treats the lane as active cadence work.
- `report freshness`: report regeneration or stale labeling. Smallest success
  signal: token/swimlane/report files have current timestamps or inventory
  labels them stale.

## Checks Run

- Read compact state, build-loop summaries, PM summaries, actor-failure
  evidence, and relevant drum-kit decision/evidence artifacts.
- Ran Foreman Coordinator `inventory.ts`, `build-capacity.ts`,
  `recent-runs.ts --limit 60`, and `token-pressure.ts --hours 168 --json`.
- Ran `scripts/multi-pass/inbox-status.sh`.
- Checked report timestamps, root branch/HEAD/dirty count, and disk free space.
