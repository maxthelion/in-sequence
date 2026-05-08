# Process Health

Last process health observer review: 2026-05-08T09:53Z

## Purpose

Track whether the multi-pass loop is actually helping agents build, check, and
repair product work with low product-owner attention.

The process health observer updates this file. The coordinator/decider reads it
and decides whether to route work to process-fixer, process-improver, builders,
reviewers, or observers.

## Health Checklist

- [x] Builders are regularly doing product-code work rather than only process
      bookkeeping
- [x] Builder outputs are checked by relevant review/observer loops
- [x] Review failures are routed into concrete rework
- [x] Actor logs do not show repeated environment, permission, timeout, memory,
      or tooling failures
- [ ] Deterministic scripts provide enough cheap orientation for agents
- [ ] Inbox handoffs are clear and not duplicative
- [x] Coordinator decisions lead to action or deliberate waiting, not churn
- [x] Product-owner attention is protected from agent-detectable problems

## Builder Throughput

| Period | Product-code work | Evidence | Notes |
|---|---|---|---|
| 2026-05-07T11:20Z-2026-05-08T09:12Z | P0 track performance overlay advanced through pure model, engine/session ownership, evidence hardening, playback resolution, and Keep/Discard session behavior in `.worktrees/p0-track-performance-overlay`. | Commits `1ab2bc1`, `a3b8cfe`, `2d0e50b`, `3b50781`, `096ed01`; build finals under `.meta/project/actors/build/`; `docs/multi-pass-coordinator/evidence-log.md`. | Healthy product-code throughput. Work is still backend-heavy, but this follows the plan order and has not drifted into pure coordination. |
| 2026-05-08T08:18Z | Playback-resolution build actor timed out after leaving useful dirty partial work. | `docs/multi-pass-coordinator/inbox/coordinator/archive/2026-05-07T14-54-32-199Z-build-actor-blocked.md`; coordinator reran focused overlay tests with 22 passing tests, then scheduled continuation. | One timeout, handled well. No repeated timeout pattern seen in recent actor finals. |

## Review And Feedback Flow

| Work item | Builder output | Review/observer follow-up | Rework scheduled? |
|---|---|---|---|
| P0 track performance overlay model slice | `1ab2bc1` pure value model and focused tests. | Architecture and testing reviews passed. | No rework needed. |
| P0 track performance overlay engine/session slice | `a3b8cfe` plus evidence commit `2d0e50b`. | Initial testing review returned `needs-evidence`; build loop added focused tests; follow-up architecture/testing reviews passed. | Yes, completed via `docs/multi-pass-coordinator/inbox/build-loop/archive/2026-05-07-p0-track-performance-overlay-engine-session-evidence.md`. |
| P0 track performance overlay playback-resolution slice | `3b50781` overlay-aware playback resolution. | Architecture and testing reviews passed; current-work and holistic observers kept showability blocked on missing UI. | No rework needed. |
| P0 track performance overlay Keep/Discard session slice | `096ed01` session Keep/Discard behavior. | Architecture review passed; testing review returned `needs-evidence` for missing-target safe failure. Work and holistic observers agree UI should wait. | Yes, pending at `docs/multi-pass-coordinator/inbox/build-loop/2026-05-08-p0-track-performance-overlay-keep-discard-missing-target-evidence.md`. |

## Environment And Tooling Problems

| Actor | Evidence | Impact | Suggested response |
|---|---|---|---|
| build-loop | One playback-resolution actor exceeded a 25 minute timeout and left a dirty partial diff. | Temporary delay only; coordinator recovered by verifying the dirty diff and scheduling a narrower continuation, which committed `3b50781`. | No immediate process stop. Keep monitoring for repeat timeouts on similar build-loop requests. |
| all actors | Recent final artifacts exist for build, architecture-review, testing-review, work-observer, and holistic-observer. No recent stderr/stdout evidence of missing tools, permissions, memory pressure, or repeated environment failures was found. | Operationally healthy for the current P0 slice. | No product-owner attention needed. |

## Missing Observation Capability

| Need | Why it matters | Suggested deterministic script or actor change |
|---|---|---|
| Inbox/archive consistency check | Evidence scripts surfaced archived requests whose frontmatter still says `status: pending`, duplicate coordinator completion notes for the same observer run, and archive files with empty `last_git_commit`. These do not block product work, but they increase rereading cost and can make future actors distrust stale status fields. | Add a small deterministic consistency script that reports duplicate completion notes, archived files with pending status, pending notes for already-archived requests, and review/archive status mismatches. Route fixes to process-improver or process-fixer, not builders. |
| Actor completion de-duplication | The work observer cadence produced two observation notes and two completion notes for the same request, later archived by the coordinator. | The coordinator handled it, but duplicate notes create avoidable churn and can trigger redundant inspections. | Teach the ticker/coordinator to suppress or mark duplicate completion notes when the same actor/request/final tuple already exists. |

## Churn Or Handoff Problems

| Problem | Evidence | Suggested response |
|---|---|---|
| Duplicate observer handoffs | `docs/multi-pass-coordinator/inbox/coordinator/archive/2026-05-08T09-31-45Z-work-observer-p0-overlay-observation.md`, `2026-05-08T09-32-10Z-work-observer-p0-overlay-observation.md`, and duplicate work-observer completion notes were all for the same cadence request. | Coordinator already archived duplicates. Schedule a process-improver cleanup only if duplicates recur after the current tick. |
| Stale frontmatter in archives | Some archived actor requests retain `status: pending`, including observer cadence archive files and a keep/discard architecture archive whose final artifact says pass. | Low severity, but it weakens deterministic evidence. Add the consistency script above and let coordinator decide whether cleanup is worth a short process-fixer pass. |
| Second process-health request arrived during this bounded invocation | `docs/multi-pass-coordinator/inbox/process-health-observer/2026-05-08T09-51-34Z-process-health-warning-signs-pass.md` is pending while this actor is handling the earlier cadence request. | This actor did not handle it because the invocation contract names exactly one request. Coordinator/ticker should decide whether to run or archive it as covered by this pass. |

## Coordinator Recommendations

- Continue the current P0 overlay flow. The immediate useful work is still the
  pending build-loop missing-target evidence request; product-owner attention is
  not needed.
- Ask process-improver or process-fixer for a narrow inbox/archive consistency
  check if the coordinator wants to reduce stale-status and duplicate-note
  churn before the next long autonomous run.
- Do not treat the single handled build timeout as a systemic environment
  blocker yet. Escalate only if similar build-loop requests time out again.

## Coordinator Disposition 2026-05-08T09:57Z

Accepted this process-health pass as fresh. The overlapping warning-sign
request is already archived as covered by this pass, so no second observer pass
is scheduled. The inbox/archive consistency check is a valid narrow process
repair, but it is deferred for now because the high-priority product evidence
request is already pending and should remain the next build-loop action.
