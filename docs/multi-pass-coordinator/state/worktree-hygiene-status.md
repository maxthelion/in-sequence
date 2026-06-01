# Worktree Hygiene Observation

- generated: 2026-05-22T06:59:42Z
- loop-local copy: `.meta/multipass/loops/project/observe/worktree-hygiene-status.md`
- request: `.meta/multipass/inbox/claimed/2026-05-22T06-58-11-268Z-worktree-hygiene-observer-cadence.md`
- scan command: no project-local `worktree-hygiene-status` script was found;
  this pass used `scripts/multi-pass/evidence-worktrees.sh`, `inventory.ts`,
  `build-capacity.ts`, `git worktree list --porcelain`, direct dirty counts,
  direct `main...HEAD` ahead/behind checks, direct ancestry checks, loop
  manifests, merge/rebase/work observations, and recent build-loop summaries.
- local main: `be465d6`

## Stale Loop Candidates

None observed. Active build-loop manifests are `build/step-sequencer` and
`build/clip-history`; neither active build-loop manifest nor durable
build-loop summary says the loop is merged, abandoned, or superseded.

Completed terminal build loops still have registered worktrees:

| Loop | Status | Worktree | Branch | Commit | Signal |
|---|---|---|---|---:|---|
| `build/mixer-busses` | complete | `.worktrees/roadmap-5-mixer-busses-ui-finish` | `auto/roadmap-5-mixer-busses-ui-finish` | `1eaebf3` | landed at `be465d6`; registry and manifest terminal |
| `build/scene-perform` | complete | `.worktrees/roadmap-2-scene-perform` | `auto/roadmap-2-scene-perform` | `d5b4750` | landed at `a61344f`; registry and manifest terminal |

## Safe Cleanup Candidates

Clean registered worktrees whose branch HEAD is already contained in local
`main`, excluding active build-loop worktrees.

| Worktree | Branch | Commit | Dirty | Behind/Ahead | Contained in main | Signal |
|---|---|---:|---:|---:|---:|---|
| `.claude/worktrees/slicer-findings-fix` | `codex/slicer-findings-fix` | `f56104a` | 0 | 411/0 | yes | contained branch |
| `.claude/worktrees/slicer-track-mvp` | `codex/slicer-track-mvp` | `c6a373e` | 0 | 412/0 | yes | contained branch |
| `.worktrees/architecture-engine-controller-carve-up-plan` | `auto/architecture-engine-controller-carve-up-plan` | `f919040` | 0 | 36/0 | yes | contained branch |
| `.worktrees/maintenance-addresses-phrase-timeline` | `auto/maintenance-addresses-phrase-timeline` | `19301bd` | 0 | 35/0 | yes | contained branch |
| `.worktrees/maintenance-macro-descriptor-slots` | `auto/maintenance-macro-descriptor-slots` | `0400e65` | 0 | 38/0 | yes | contained branch |
| `.worktrees/roadmap-5-mixer-busses-ui-finish` | `auto/roadmap-5-mixer-busses-ui-finish` | `1eaebf3` | 0 | 18/0 | yes | terminal landed build loop; contained in `main` |

Contained branch-only candidate with no registered worktree:

| Branch | Commit | Behind/Ahead | Contained in main | Signal |
|---|---:|---:|---:|---|
| `codex/macro-lane-grid-ui` | `07c3d1b` | 438/0 | yes | contained branch-only |

## Dirty Or Uncontained Branches Needing Disposition

Dirty worktrees, active build branches, PM/reference branches, checkpoint
branches, probe/evidence branches, or branches not contained in local `main`.

| Worktree | Branch | Commit | Dirty | Behind/Ahead | Contained in main | Signal |
|---|---|---:|---:|---:|---:|---|
| `.` | `main` | `be465d6` | 17 | 0/0 | yes | root dirty with coordination-state edits and untracked active-loop summaries before this observer write |
| `.worktrees/roadmap-1-clip-history-v2` | `auto/roadmap-1-clip-history-v2` | `be465d6` | 0 | 0/0 | yes | active build loop; fresh v2 worktree from current `main`, not cleanup while active |
| `.worktrees/roadmap-3-step-sequencer` | `auto/roadmap-3-step-sequencer` | `3e77689` | 0 | 83/8 | no | active build loop; stale branch awaiting Phase 0 base/salvage builder |
| `.worktrees/roadmap-2-scene-perform` | `auto/roadmap-2-scene-perform` | `d5b4750` | 2 | 9/0 | yes | terminal landed build loop, but dirty with transient untracked evidence dirs |
| `.claude/worktrees/macro-lane-grid-ui` | `integration/preserve-macro-lane-grid-ui-main-20260515T2014Z` | `5e0836c` | 2 | 65/0 | yes | dirty contained integration worktree |
| `.worktrees/goal-9-modifier-chain-placement` | `auto/goal-9-modifier-chain-placement` | `f39c4e5` | 1 | 235/7 | no | stale completed-feature branch per readiness/rebase observations |
| `.worktrees/overnight-simplification-2026-04-29` | `auto/overnight-simplification-2026-04-29` | `9257dd0` | 1 | 369/1 | no | dirty legacy worktree |
| `.worktrees/p0-track-performance-overlay` | `auto/p0-track-performance-overlay` | `d36c78b` | 0 | 121/10 | no | historical checkpoint-ready; awaiting existing product-owner acceptance |
| `.worktrees/roadmap-1-clip-history` | `auto/roadmap-1-clip-history` | `ced03ab` | 1 | 319/49 | no | old Clip History reference/salvage branch, not merge authority |
| `.worktrees/roadmap-9-modifier-chain-placement` | `auto/roadmap-9-modifier-chain-placement` | `7520dbd` | 1 | 319/192 | no | stale completed-feature branch per readiness/rebase observations |
| `.claude/worktrees/live-perform-fill-overlay` | `codex/live-perform-fill-overlay` | `a08bc09` | 0 | 475/3 | no | unmentioned legacy branch |
| `.claude/worktrees/live-perform-performance-mechanics-plan` | `codex/live-perform-performance-mechanics-plan` | `4757fbe` | 0 | 464/1 | no | unmentioned legacy branch |
| `.claude/worktrees/master-bus-scenes` | `codex/master-bus-scenes` | `8b367b2` | 0 | 451/10 | no | unmentioned legacy branch |
| `.claude/worktrees/master-bus-scenes-plan` | `codex/master-bus-scenes-plan` | `03f71df` | 0 | 464/1 | no | unmentioned legacy branch |
| `.claude/worktrees/progression-chord-generator` | `codex/progression-chord-generator` | `059c174` | 0 | 419/1 | no | unmentioned legacy branch |
| `.worktrees/runtime-au-plugin-shutdown` | `codex/runtime-au-plugin-shutdown` | `f5cf677` | 0 | 409/1 | no | unmentioned runtime branch |
| `.worktrees/runtime-drum-sample-playback` | `codex/runtime-drum-sample-playback` | `f5417ca` | 0 | 409/2 | no | unmentioned runtime branch |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-audio-input-looping-autoslice` | `codex/probe-overnight-broad-probe-2026-05-05-audio-input-looping-autoslice` | `238894d` | 0 | 225/2 | no | broad probe evidence branch |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-external-control-and-automation` | `codex/probe-overnight-broad-probe-2026-05-05-external-control-and-automation` | `d5d94d5` | 0 | 225/2 | no | broad probe evidence branch |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-mixer-routing-and-sends` | `codex/probe-overnight-broad-probe-2026-05-05-mixer-routing-and-sends` | `cf3d3c8` | 0 | 225/2 | no | broad probe evidence branch |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-performance-overrides-pattern-manipulation` | `codex/probe-overnight-broad-probe-2026-05-05-performance-overrides-pattern-manipulation` | `4898a06` | 0 | 225/2 | no | broad probe evidence branch |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-phrase-scene-song-performance` | `codex/probe-overnight-broad-probe-2026-05-05-phrase-scene-song-performance` | `6ca658e` | 0 | 225/2 | no | broad probe evidence branch |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-track-editor-foundation` | `codex/probe-overnight-broad-probe-2026-05-05-track-editor-foundation` | `75c29dd` | 0 | 225/2 | no | broad probe evidence branch |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-audio-input-looping-autoslice` | `codex/probe-ux-feedback-pass-2026-05-06-audio-input-looping-autoslice` | `ce439f7` | 0 | 225/4 | no | UX feedback evidence branch |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-external-control-and-automation` | `codex/probe-ux-feedback-pass-2026-05-06-external-control-and-automation` | `d5d94d5` | 5 | 225/2 | no | dirty UX feedback evidence branch |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-mixer-routing-and-sends` | `codex/probe-ux-feedback-pass-2026-05-06-mixer-routing-and-sends` | `a32d912` | 0 | 225/4 | no | UX feedback evidence branch |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-performance-overrides-pattern-manipulation` | `codex/probe-ux-feedback-pass-2026-05-06-performance-overrides-pattern-manipulation` | `bfc7173` | 0 | 225/4 | no | UX feedback evidence branch |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-phrase-scene-song-performance` | `codex/probe-ux-feedback-pass-2026-05-06-phrase-scene-song-performance` | `6ca658e` | 5 | 225/2 | no | dirty UX feedback evidence branch |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-track-editor-foundation` | `codex/probe-ux-feedback-pass-2026-05-06-track-editor-foundation` | `75c29dd` | 5 | 225/2 | no | dirty UX feedback evidence branch |

Uncontained branch-only candidates with no registered worktree:

| Branch | Commit | Behind/Ahead | Contained in main | Signal |
|---|---:|---:|---:|---|
| `backup/roadmap-2-scene-perform-pre-main-integration` | `4ebbc44` | 83/8 | no | backup of Scene Perform pre-main integration |
| `codex/max-8-destination-au` | `5f507ea` | 517/10 | no | unmentioned branch-only |
| `codex/tracks-perform-scenes-workspace` | `87061b0` | 83/10 | no | unmentioned branch-only |

## Loop Registry Entries Still Marking Completed Work Active

None observed.

| Registry | Status | Worktree | Branch | Signal |
|---|---|---|---|---|
| `docs/multi-pass-coordinator/loops/build/mixer-busses.yaml` and `.meta/multipass/loops/build/mixer-busses/manifest.yaml` | complete | `.worktrees/roadmap-5-mixer-busses-ui-finish` | `auto/roadmap-5-mixer-busses-ui-finish` | terminal landed loop |
| `docs/multi-pass-coordinator/loops/build/scene-perform.yaml` and `.meta/multipass/loops/build/scene-perform/manifest.yaml` | complete | `.worktrees/roadmap-2-scene-perform` | `auto/roadmap-2-scene-perform` | terminal landed loop |

## Observer Notes

- Hygiene facts changed since the previous durable pass: local `main` advanced
  from `cec6d59` to `be465d6`; Scene Perform and Mixer Busses are now landed
  and terminal `complete`; Clip History was promoted and gained the fresh
  active worktree `.worktrees/roadmap-1-clip-history-v2`.
- Build capacity now reports max active build loops `2`, active build loops
  `2`, and available slots `0`: `build/step-sequencer` plus
  `build/clip-history`.
- The old `.worktrees/roadmap-1-clip-history` remains dirty and uncontained as
  reference/salvage evidence only; the new v2 Clip History worktree is clean at
  current `main` but active and therefore not a cleanup candidate.
- A stale pending inbox item still targets terminal `build/scene-perform`:
  `.meta/multipass/inbox/pending/2026-05-22T03-32-22-790Z-build-orienter-cadence.md`.
- Facts changed enough that orientation should refresh before cleanup or
  disposition actions are chosen.
- This is observation only. No worktree, branch, loop record, inbox lifecycle
  state, merge, rebase, or cleanup action was changed.
