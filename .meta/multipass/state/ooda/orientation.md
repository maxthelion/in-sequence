---
updated: 2026-06-16T13:23Z
phase: orient
status: current
source_request: .meta/multipass/runtime/inbox/claimed/2026-06-16T130133892Z-orienter-cadence.md
loop_local_copy: .meta/multipass/runtime/loops/project/orient/2026-06-16T13-23Z-project-orientation.md
scope: project-cadence
---

# Project Orientation

Current read: stay in scoped `caution`. The product direction remains coherent:
performance-first sequencing, quick setup, recoverable live changes, and
capture of useful accidents. The immediate problem is not strategy; it is
finishing warm owner-feedback work while the PM ready buffer is empty and the
runtime continues to produce stale/noisy coordination evidence.

Two ordinary build slots are open, but there are no ready or near-ready PM
candidates. The most valuable next product movement is still the already-routed
routing source/mixer split follow-up. That branch is now clean and previously
gate-passing, but blocked by a precise mandatory-critic finding: the source
well still exposes old `destination` vocabulary through reused destination UI.

## Situation Matrix

| Slice / lane | Lowest unmet layer | Current evidence | Missing / risk | Loop / lock | Priority | Recommended action kind |
| --- | --- | --- | --- | --- | --- | --- |
| Routing source/mixer split | Layer 2: reliable, evidenced completion | Integrator artifact says `feature/routing-source-mixer-split` was rebased, gated, and critic-reviewed at `afbd875f`; `git diff --check`, focused routing tests, visual shell check, and full gate passed with standard HAL skips. Direct check now sees branch clean at `afbd875f`. | Mandatory critic blocked landing because `TrackDestinationEditor` / `AddDestinationSheet` / source labels still say destination. Branch was `0/1` against `e02ca899` during integration, but direct check after `main` advanced to `7d75c164` shows `1/1`; repair must re-coordinate with current `main`. Branch `resolution.md` is not landed. | Warm feature-follow-up branch outside active build registry; prior integrator request is done/blocked. | Highest. | `unblock active build`: repair the critic blocker in the existing branch, rerun focused/gate checks and critic, then integrate if green. |
| AU plug-in discovery/rescan | Layer 1/2: users can choose installed instruments/effects reliably | Fresh unresolved owner notes report missing effects after restart and request non-blocking AU rescan without relaunch. Bug intake groups this around `AudioInstrumentChoiceCache` / `AudioEffectChoiceCache`. | No route, branch, restart-time completeness check, runtime rescan behavior, scan-state evidence, or picker/menu evidence. Acceptance must prove both restart-time completeness and runtime rescan. | Unrouted feature-follow-up. | High functional bug. | `route scoped main fix` after routing split is unblocked or if it stalls again. |
| Mixer strip follow-up cluster | Layer 3 plus one Layer 1/2 runtime bug | Fresh owner notes cover master strip width, fader/level style, pan rotary placement, send-channel copy/plus-slot labeling, and frozen meters when transport stops. | No route, screenshots, or stopped-meter decay/reset evidence. Keep separate from the routing split because acceptance differs. | Unrouted feature-follow-up. | High owner-visible surface. | `route scoped main fix` as backup product work after AU, or before AU if surface polish is prioritized. |
| Track Perform pattern cells | Layer 3: performance interaction comfort | Fresh note requests direct mini-cell click targets instead of whole-cell incrementing. | No route or focused interaction evidence. Concrete, but lower urgency than AU and mixer. | Unrouted feature-follow-up. | Medium. | `route scoped main fix` later. |
| Observability Log Issues | Layer 1/2: scope-correct before more build work | `714fdb8` has exact-state builder and review evidence. Worktree is dirty in 7 files, 353 insertions / 1 deletion, after failed pipeline/lifecycle/bootstrap work. Scope lock says app diagnostics should feed OODA `log-observer`, not become a parallel issue-review workflow. | Dirty partial has no builder final, commit, focused tests, sample typed-event evidence, current source guard, or exact-state reviews. Branch is far behind and conflict-hinted. | Human-locked build outside ordinary capacity. | Parked. | `unblock active build` only after scope correction; otherwise `no action`. |
| MIDI Interfaces | Layer 2: hardware acceptance | Clean at `34d5c43`; software/source checks, Preferences MIDI screenshot evidence, and exact-output reviews exist. | Physical Launchpad Mini MK3 acceptance is missing. Branch is far behind/conflict-hinted; more autonomous software review will not clear the lock. | Human hardware lock outside ordinary capacity. | Parked. | `no action` until hardware acceptance or an explicit acceptance-limitation decision. |
| PM ready buffer | Layer 2: builder-ready reserve depth | Live `build-capacity.ts`: active ordinary slots `0`, locked build loops `2`, available slots `2`, ready candidates `none`, unpromoted ready candidates `none`. | PM reserve recovery remains blocked by `usage_rate_limit`; no completed reserve-candidate or no-candidate artifact exists. Deferred/thin PM rows have no accepted builder handoff. | Project flow. | High throughput risk. | `start or advance PM prep` after the warm product repair, or record a compact no-candidate artifact. |
| Scenes In Phrases PM | PM Layer 1/2: owner prototype approval | Prototype 03 is selected, prototype 04 remains comparison evidence. | Owner approval plus accepted architecture/spec/plan/handoff missing. | Locked PM. | Valuable future lane, not ready. | `no action` until owner answer. |
| Audio Looping PM | PM Layer 1/2: owner first-scope choice | Intent, prototype packaging, open-question reconciliation, and guardrails exist. | Scope lock remains one loop-capable Input Audio track now versus waiting for plural/shared input looping; no accepted spec/plan/handoff. | Locked PM. | Valuable future lane, not ready. | `no action` until owner answer. |
| Main/worktree coordination | Layer 5: maintainable integration baseline | Direct root check: `main` at `7d75c164`, `313` dirty/local-only paths, ahead of local `origin/main`; no root operation marker observed in recent observers. | Whole-app claims are exact-checkout dependent. Fresh merge status is stale because merge-observer failed with `usage_rate_limit`; routing branch drifted from `0/1` to `1/1` after `main` advanced. | Root plus worktrees. | High coordination risk. | `observe more evidence` only where needed; avoid broad cleanup as side effect. |
| Process health | Layer 2/5: reliable cadence and cheap evidence | Process health is red: last-24h act time was `0m` at observation, repeated `usage_rate_limit`, stale batch metadata, Ruby CLI warning noise, and observer fan-out before orient/decide consumption. | The loop can spend more effort reconstructing state than acting. Token-pressure saved report is stale; process-health carries fresher notes. | Project process. | High throughput risk. | `route process repair` after the warm product repair is not blocked. |
| Landed / terminal lanes | No unmet layer without fresh defect evidence | Lifecycle says complete build branches are contained in `main`; active PM residue remains for Autoslice, Note Repeat, Step Order; terminal PM pending residue remains for Song Mode and Track Fill. | Residue can mislead readiness/capacity, but is not product work by itself. | Process residue. | Low product priority. | `route process repair` later if residue keeps confusing routing. |

## Pattern Read

| Pattern | Meaning |
| --- | --- |
| Warm owner bugs outrank stale PM promotion | Open build capacity is not promotion authority. Current value is in scoped follow-up work with concrete owner evidence. |
| Routing split should finish before broader mixer polish | It is branched, recent, gate-passing before critic, and blocked by a narrow acceptance issue. Mixer follow-up can build on it after the source vocabulary repair lands. |
| AU discovery is a functional workflow blocker | Missing plug-ins and no runtime rescan affect instrument/effect choice, not only UI polish. |
| Locked loops are scoped | Observability, MIDI, Scenes, and Audio Looping need specific human evidence. They do not stop unrelated bounded follow-ups. |
| Exact-state boundaries matter | `714fdb8` gates do not cover Observability dirty output; MIDI software evidence does not cover hardware; broad root dirt makes whole-app claims fragile. |
| Process health is red but not the sole next value | Status/cadence repairs matter, but there is a high-signal product branch to finish first. |

## Flow-Control Read

Recommendation: scoped `caution`, not `line-stop`.

Allowed under caution:

- Repair the existing routing source/mixer split branch, re-coordinate with
  current `main`, rerun checks and critic, then integrate if green.
- Route one bounded AU discovery/rescan or mixer follow-up once the routing
  split is not being starved.
- Record PM reserve/no-candidate evidence if no scoped product follow-up is
  routed.
- Resume Observability only if its scope-correction lock clears.
- Run MIDI hardware acceptance if the Launchpad Mini MK3 is available.
- Route small process repair for rate-limit evidence, stale batch status,
  cadence gating, lifecycle residue, or Ruby warning noise.

Held under caution:

- New roadmap feature promotion from stale or thin PM rows.
- Treating open ordinary capacity as sufficient reason to promote a feature.
- Autonomous Observability continuation, merge, or dirty-partial review while
  the human scope lock remains.
- Treating MIDI as accepted without physical hardware evidence.
- Grouping the already-routed routing split with the newer mixer follow-up in a
  way that muddies acceptance.
- Broad root cleanup or reopening landed loops from lifecycle residue alone.

Clear condition:

- Routing source/mixer split is landed or explicitly parked with blocker
  evidence; plus either AU/mixer follow-up is routed or PM reserve recovery
  produces a real candidate/no-candidate artifact. Separately clear or narrow
  Observability/MIDI locks only when their specific evidence appears.

## Decider Brief

1. Most valuable next action: repair the `feature/routing-source-mixer-split`
   critic blocker in the existing branch, re-check against current `main`,
   rerun focused/gate checks and mandatory critic, then integrate if green.
2. Best backup action: route AU plug-in discovery/rescan as a bounded
   functional fix; mixer strip follow-up is the next owner-visible backup if AU
   is deferred.
3. Work that should not be started yet: new feature promotion from stale PM
   rows, autonomous Observability continuation, software-only MIDI acceptance,
   independent Fill Clip work, broad root cleanup, and landed-loop reopenings
   from stale lifecycle residue.
4. Main/worktree coordination risks: root `main` is dirty at `7d75c164` with
   `313` dirty/local-only paths; routing split is clean but now `1/1`
   behind/ahead current `main`; Observability is dirty/diverged; MIDI is clean
   but far behind and hardware-locked.
5. Flow-control recommendation: `caution`.
6. Process repair that would improve throughput: after the warm product repair,
   gate broad observer fan-out behind orient/decide consumption, enrich
   usage-limit failure artifacts, and clear stale batch/lifecycle metadata that
   misleads readiness.

## Product-Owner Attention

No new product-owner question is needed from this orienter pass. Existing
narrow human locks remain:

- Observability scope correction.
- MIDI physical Launchpad Mini MK3 acceptance.
- Scenes In Phrases prototype approval.
- Audio Looping first-scope choice.
- Legacy F1 QA capture card-height taste call.

## Change Notes

- Consumed June 16 compact current-work, feature-readiness, holistic,
  bug-intake, flow, lifecycle, process-health, rebase, worktree-hygiene,
  actor-failure, token-pressure, active build-loop, PM-loop, integration-log,
  and routing integration evidence.
- Ran Foreman Coordinator `inventory.ts` and `build-capacity.ts`, direct root /
  routing / Observability / MIDI git checks, and
  `scripts/multi-pass/inbox-status.sh`.
- Preferred fresh June 16 observations over stale June 8 merge/status
  artifacts where they disagreed, and preferred direct git checks where `main`
  advanced after compact state generation.
- No inbox messages, request lifecycle moves, product-code edits, tests, visual
  capture, merge, rebase, cleanup, PM artifact action, build action, process
  repair, or product-owner question were performed by this orienter.
