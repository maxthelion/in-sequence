---
updated: 2026-05-21T20:37:27Z
phase: orient
source_request: .meta/multipass/inbox/claimed/2026-05-21T20-35-47-137Z-orienter-cadence.md
status: current
---

# Project Orientation

Current interpretation: the project is integration-bound, not blocked on
product intent or build-loop evidence. Scene Perform is still the first
integration candidate and is mechanically ready, but root `main` hygiene is the
active blocker. Mixer Busses is accepted and has now produced waiting evidence
because it correctly cannot integrate before Scene Perform lands. Build
capacity remains full until these loops close.

## Current State Matrix

| Slice / lane | Lowest unmet layer | Status and evidence | Loop / lock | Orientation |
|---|---|---|---|---|
| Scene Perform | 5. Maintainable integration state | Active build loop `build/scene-perform`; accepted at `ab6206004edd4d0b35c917e53ef85f147df47723` and rebased cleanly to `1b69d29e58edcc327f4f4996d10a90e13e480741`. Integration evidence `.meta/multipass/loops/project/act/2026-05-21T18-38Z-scene-perform-integration-evidence.md` records no merge-tree conflicts, `git diff --check` pass, preserved `effectiveCrossfader` / `setLiveMasterCrossfader`, and focused `EngineControllerScenePerformTests` pass. Latest build orientation `.meta/multipass/loops/build/scene-perform/orient/2026-05-21T20-25Z-cadence-evidence-pairing.md` says no new build-loop work is needed. | Agent/process lock: root-hygiene process-fixer remains pending at `.meta/multipass/inbox/pending/2026-05-21T19-11-16-835Z-process-fixer.md`. The original Scene Perform integrator request completed with blocked-by-root-dirt evidence. | P0 and first in integration order. Treat root hygiene as the useful project-level pressure, then route follow-up Scene Perform integration if hygiene evidence says `main` is merge-safe. Do not reopen Scene Perform builder or review work unless integration changes product output. Accepted residual risks: no filled macro-label screenshots and no automated SwiftUI drag/card hard-switch coverage. |
| Mixer Routing And Sends / Mixer Busses UI | 5. Maintainable integration order | Active build loop `build/mixer-busses`; branch `auto/roadmap-5-mixer-busses-ui-finish` is clean at `1eaebf3d6226f39a2438143b192493f54739352d`. Architecture, testing/build, UX/IA, and visual economy all PASS for exact state `1eaebf3`. Latest build orientation `.meta/multipass/loops/build/mixer-busses/orient/2026-05-21T20-31Z-cadence-evidence-pairing.md` records no need for builder rework or duplicate review. | Agent/process lock: project integrator already ran and wrote waiting evidence at `.meta/multipass/loops/project/act/2026-05-21T20-21Z-mixer-busses-integration-waiting.md`; it verified the candidate and stopped because Scene Perform is not contained in `main`. | P0 after Scene Perform. Mixer Busses should stay waiting until root hygiene is resolved and Scene Perform is integrated first. A follow-up Mixer Busses integration run becomes useful only against the then-current `main`. |
| Step Sequencer | 1. Intended thing not built from current main | PM artifacts are ready-for-build; feature-readiness reports `ready-for-build-queue`. Worktree `.worktrees/roadmap-3-step-sequencer` is clean at `3e77689`, behind current `main`, with 4 merge-tree conflict hints. | No active build lock; capacity is full. | P1 once a build slot opens. Promotion should wait for active loop closure and should account for rebase/conflict cost. |
| Clip History | 1. Intended thing not built from current main | PM artifacts are reconciled and ready-for-build; `clip-history-dual-grid-v4.html` plus `build-resume-handoff.md` are future build authority. The old `auto/roadmap-1-clip-history` branch is reference/salvage only, dirty with 1 untracked path, far behind `main`, and conflict-prone. | No active build lock; capacity is full. | P2 behind Step Sequencer unless priority is deliberately changed. Future build should harvest the stale branch deliberately, not merge it wholesale. |
| Holistic UX / current main | 3. Understandable and efficient | Holistic status says the product direction is coherent and active slices are integration-bound. Older holistic UX still reports visual grammar drift and current-main Scenes as browse/edit-library shaped; Scene Perform addresses that mismatch but is not merged. Runtime scan found no recent app crash, only unattributed CoreAudio HAL warmup errors with `gitCommit=unknown gitBranch=unknown`. | Observation only; no lock. | Keep holistic concerns as product-shape context. No broad lens review or product question is useful while accepted integrations are blocked by repository hygiene. |
| Prototype-review backlog | Product-owner prototype approval | `docs/roadmap/next-actions.md` still lists many `human-review-prototypes` items. Feature-readiness treats these as not-ready, not build candidates. | Human-attention backlog, not an active build lock. | Do not surface the raw backlog from this cadence. Agent-side integration and hygiene are more useful. |
| P0 Track Performance Overlay | Product-owner checkpoint acceptance | Historical checkpoint `d36c78b` remains show-ready with prior UX/IA, visual, architecture, focused test, and full test evidence. Rebase evidence still shows conflict risk because the branch is far behind `main`. | Human lock scoped only to this checkpoint. | Product-owner attention remains valid but separate. It should not block current integration ordering or future build promotion. |
| Runtime/process hygiene | 5. Maintainability | Process health reports product progress recovered after earlier `usage_rate_limit` failures. Fresh inventory/build-capacity show two active build loops, zero available build slots, ready candidates `step-sequencer` and `clip-history`, no build inbox, and only the root-hygiene process-fixer pending. Root `main` still has broad coordination/migration dirt; `pairing-state.sh` and several visibility helpers are absent; inventory/build-capacity emit Ruby gem extension warnings. | Agent/process-side. | This is the active project bottleneck. Treat it as repository/process repair pressure and deterministic-visibility debt, not product uncertainty. |

## Pattern Read

| Pattern | Meaning |
|---|---|
| The active build loops have left product-gate work and entered integration hygiene. | Scene Perform and Mixer Busses both have accepted evidence pairings; more builder/reviewer cadence is likely churn unless integration changes output. |
| Root `main` dirt is now the delivery blocker. | Scene Perform integration proved it blocks a clean product merge even when the candidate is mechanically ready. |
| Merge order remains meaningful and evidenced. | Scene Perform is first after root hygiene. Mixer Busses already stopped once with waiting evidence because that ordering gate is unmet. |
| Build capacity remains full. | Build-capacity reports active loops `build/mixer-busses` and `build/scene-perform`, zero available slots, and unpromoted ready candidates `step-sequencer` and `clip-history`. |
| Future candidates have higher rebase cost than active integrations. | Step Sequencer and Clip History are valid future candidates but older than the active accepted candidates and carry conflict hints. |
| Runtime noise is not a merge hold by itself. | The latest runtime scan found no app crash and no attributable active-feature runtime failure; CoreAudio HAL errors need reproduction only if user-facing audio setup fails. |
| Product-owner attention should stay scoped. | Current blockers are agent/process work: root hygiene, integration order, lifecycle noise, missing helpers, and evidence packaging. The standing human locks are the separate P0 Track Performance Overlay checkpoint and prototype backlog. |

## Decider Urgency

| Need | Urgency | Reason |
|---|---|---|
| Interpret root `main` dirt as the immediate blocker to Scene Perform merge | High | Integration evidence shows Scene Perform is mechanically ready at `1b69d29` but cannot be merged cleanly while unrelated root dirt is unresolved. |
| Preserve Scene Perform before Mixer Busses | High | The decision log, Mixer Busses request, and 20:21Z waiting evidence all confirm this ordering. |
| Let Mixer Busses wait until Scene Perform lands | High | Its integrator already verified the candidate and stopped correctly because Scene Perform is not contained in `main`. |
| Avoid duplicate active build-loop work | Medium | Fresh build orientations for both active loops say no builder/review work is indicated; the next useful movement is project-level hygiene/integration. |
| Promote Step Sequencer or Clip History | Low while capacity is full | Both are valid future candidates, but active build loops still occupy both slots and have not closed. |
| Ask product owner a new question | Not useful now | No active blocker is a product-intent decision. |

## Change Notes

- Refreshed orientation for the 2026-05-21T20:35:47Z orienter cadence request.
- Incorporated 20:21Z Mixer Busses integration waiting evidence and 20:25Z / 20:31Z build-loop orientations.
- Kept Scene Perform first at rebased candidate `1b69d29`, blocked only by root `main` hygiene.
- Reframed Mixer Busses from pending integration to accepted-but-waiting after its integrator verified `1eaebf3` and stopped on the Scene Perform ordering gate.
- Kept build capacity closed: two active build loops, zero available slots, ready candidates `step-sequencer` and `clip-history`.
- Kept product-owner attention out of the active path.
