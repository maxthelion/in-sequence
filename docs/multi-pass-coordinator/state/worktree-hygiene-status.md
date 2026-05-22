# Worktree Hygiene Observation

- generated: 2026-05-21T22:55:00Z
- loop-local copy: `.meta/multipass/loops/project/observe/worktree-hygiene-status.md`
- request: `.meta/multipass/inbox/claimed/2026-05-21T22-51-17-042Z-worktree-hygiene-observer-cadence.md`
- scan command: no project-local `worktree-hygiene-status` script was found; this pass used `scripts/multi-pass/evidence-worktrees.sh`, `git worktree list --porcelain`, direct dirty counts, direct `main...HEAD` ahead/behind checks, direct ancestry checks, loop manifests, merge/rebase/work observations, and recent build-loop summaries.
- local main: `cec6d59`

## Stale Loop Candidates

None observed. Active loop manifests remain `project`, `build/mixer-busses`,
and `build/scene-perform`. Neither active build-loop manifest nor durable
build-loop summary says the loop is merged, abandoned, or superseded.

## Safe Cleanup Candidates

Clean registered worktrees whose branch HEAD is already contained in local
`main`.

| Worktree | Branch | Commit | Dirty | Contained in main | Signal |
|---|---|---:|---:|---:|---|
| `.claude/worktrees/slicer-findings-fix` | `codex/slicer-findings-fix` | `f56104a` | 0 | yes | contained branch |
| `.claude/worktrees/slicer-track-mvp` | `codex/slicer-track-mvp` | `c6a373e` | 0 | yes | contained branch |
| `.worktrees/architecture-engine-controller-carve-up-plan` | `auto/architecture-engine-controller-carve-up-plan` | `f919040` | 0 | yes | contained branch |
| `.worktrees/maintenance-addresses-phrase-timeline` | `auto/maintenance-addresses-phrase-timeline` | `19301bd` | 0 | yes | contained branch |
| `.worktrees/maintenance-macro-descriptor-slots` | `auto/maintenance-macro-descriptor-slots` | `0400e65` | 0 | yes | contained branch |

Contained branch-only candidate with no registered worktree:

| Branch | Commit | Behind/Ahead | Contained in main | Signal |
|---|---:|---:|---:|---|
| `codex/macro-lane-grid-ui` | `07c3d1b` | 426/0 | yes | contained branch-only |

## Dirty Or Uncontained Branches Needing Disposition

Dirty worktrees, active build branches, PM-ready branches, checkpoint branches,
probe/evidence branches, or branches not contained in local `main`.

| Worktree | Branch | Commit | Dirty | Behind/Ahead | Contained in main | Signal |
|---|---|---:|---:|---:|---:|---|
| `.` | `main` | `cec6d59` | 3 | 0/0 | yes | root dirty with narrow coordination-state edits before this observer write |
| `.worktrees/roadmap-2-scene-perform` | `auto/roadmap-2-scene-perform` | `d5b4750` | 2 | 1/4 | no | active build loop; accepted integration candidate; transient untracked evidence dirs |
| `.worktrees/roadmap-5-mixer-busses-ui-finish` | `auto/roadmap-5-mixer-busses-ui-finish` | `1eaebf3` | 0 | 11/5 | no | active build loop; accepted integration candidate waiting behind Scene Perform |
| `.claude/worktrees/macro-lane-grid-ui` | `integration/preserve-macro-lane-grid-ui-main-20260515T2014Z` | `5e0836c` | 2 | 53/0 | yes | dirty contained integration worktree |
| `.worktrees/goal-9-modifier-chain-placement` | `auto/goal-9-modifier-chain-placement` | `f39c4e5` | 1 | 223/7 | no | stale completed-feature branch per readiness/rebase observations |
| `.worktrees/overnight-simplification-2026-04-29` | `auto/overnight-simplification-2026-04-29` | `9257dd0` | 1 | 357/1 | no | dirty legacy worktree |
| `.worktrees/p0-track-performance-overlay` | `auto/p0-track-performance-overlay` | `d36c78b` | 0 | 109/10 | no | historical checkpoint-ready; awaiting existing product-owner acceptance |
| `.worktrees/roadmap-1-clip-history` | `auto/roadmap-1-clip-history` | `ced03ab` | 1 | 307/49 | no | ready-for-promotion reference/salvage branch, not merge authority |
| `.worktrees/roadmap-3-step-sequencer` | `auto/roadmap-3-step-sequencer` | `3e77689` | 0 | 71/8 | no | ready-for-promotion, not active build loop |
| `.worktrees/roadmap-9-modifier-chain-placement` | `auto/roadmap-9-modifier-chain-placement` | `7520dbd` | 1 | 307/192 | no | stale completed-feature branch per readiness/rebase observations |
| `.claude/worktrees/live-perform-fill-overlay` | `codex/live-perform-fill-overlay` | `a08bc09` | 0 | 463/3 | no | unmentioned legacy branch |
| `.claude/worktrees/live-perform-performance-mechanics-plan` | `codex/live-perform-performance-mechanics-plan` | `4757fbe` | 0 | 452/1 | no | unmentioned legacy branch |
| `.claude/worktrees/master-bus-scenes` | `codex/master-bus-scenes` | `8b367b2` | 0 | 439/10 | no | unmentioned legacy branch |
| `.claude/worktrees/master-bus-scenes-plan` | `codex/master-bus-scenes-plan` | `03f71df` | 0 | 452/1 | no | unmentioned legacy branch |
| `.claude/worktrees/progression-chord-generator` | `codex/progression-chord-generator` | `059c174` | 0 | 407/1 | no | unmentioned legacy branch |
| `.worktrees/runtime-au-plugin-shutdown` | `codex/runtime-au-plugin-shutdown` | `f5cf677` | 0 | 397/1 | no | unmentioned runtime branch |
| `.worktrees/runtime-drum-sample-playback` | `codex/runtime-drum-sample-playback` | `f5417ca` | 0 | 397/2 | no | unmentioned runtime branch |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-audio-input-looping-autoslice` | `codex/probe-overnight-broad-probe-2026-05-05-audio-input-looping-autoslice` | `238894d` | 0 | 213/2 | no | broad probe evidence branch |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-external-control-and-automation` | `codex/probe-overnight-broad-probe-2026-05-05-external-control-and-automation` | `d5d94d5` | 0 | 213/2 | no | broad probe evidence branch |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-mixer-routing-and-sends` | `codex/probe-overnight-broad-probe-2026-05-05-mixer-routing-and-sends` | `cf3d3c8` | 0 | 213/2 | no | broad probe evidence branch |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-performance-overrides-pattern-manipulation` | `codex/probe-overnight-broad-probe-2026-05-05-performance-overrides-pattern-manipulation` | `4898a06` | 0 | 213/2 | no | broad probe evidence branch |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-phrase-scene-song-performance` | `codex/probe-overnight-broad-probe-2026-05-05-phrase-scene-song-performance` | `6ca658e` | 0 | 213/2 | no | broad probe evidence branch |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-track-editor-foundation` | `codex/probe-overnight-broad-probe-2026-05-05-track-editor-foundation` | `75c29dd` | 0 | 213/2 | no | broad probe evidence branch |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-audio-input-looping-autoslice` | `codex/probe-ux-feedback-pass-2026-05-06-audio-input-looping-autoslice` | `ce439f7` | 0 | 213/4 | no | UX feedback evidence branch |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-external-control-and-automation` | `codex/probe-ux-feedback-pass-2026-05-06-external-control-and-automation` | `d5d94d5` | 5 | 213/2 | no | dirty UX feedback evidence branch |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-mixer-routing-and-sends` | `codex/probe-ux-feedback-pass-2026-05-06-mixer-routing-and-sends` | `a32d912` | 0 | 213/4 | no | UX feedback evidence branch |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-performance-overrides-pattern-manipulation` | `codex/probe-ux-feedback-pass-2026-05-06-performance-overrides-pattern-manipulation` | `bfc7173` | 0 | 213/4 | no | UX feedback evidence branch |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-phrase-scene-song-performance` | `codex/probe-ux-feedback-pass-2026-05-06-phrase-scene-song-performance` | `6ca658e` | 5 | 213/2 | no | dirty UX feedback evidence branch |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-track-editor-foundation` | `codex/probe-ux-feedback-pass-2026-05-06-track-editor-foundation` | `75c29dd` | 5 | 213/2 | no | dirty UX feedback evidence branch |

Uncontained branch-only candidates with no registered worktree:

| Branch | Commit | Behind/Ahead | Contained in main | Signal |
|---|---:|---:|---:|---|
| `backup/roadmap-2-scene-perform-pre-main-integration` | `4ebbc44` | 71/8 | no | backup of Scene Perform pre-main integration |
| `codex/max-8-destination-au` | `5f507ea` | 505/10 | no | unmentioned branch-only |
| `codex/tracks-perform-scenes-workspace` | `87061b0` | 71/10 | no | unmentioned branch-only |

## Loop Registry Entries Still Marking Completed Work Active

None observed.

| Registry | Status | Worktree | Branch | Signal |
|---|---|---|---|---|
| `docs/multi-pass-coordinator/loops/build/mixer-busses.yaml` and `.meta/multipass/loops/build/mixer-busses/manifest.yaml` | active | `.worktrees/roadmap-5-mixer-busses-ui-finish` | `auto/roadmap-5-mixer-busses-ui-finish` | current active build; not completed |
| `docs/multi-pass-coordinator/loops/build/scene-perform.yaml` and `.meta/multipass/loops/build/scene-perform/manifest.yaml` | active | `.worktrees/roadmap-2-scene-perform` | `auto/roadmap-2-scene-perform` | current active build; not completed in registry |

## Observer Notes

- Hygiene facts changed since the previous durable pass: local `main` advanced
  from `e5a388f` to `cec6d59`; root dirty count fell from broad coordination
  churn to 3 narrow coordination files before this observer edit; Scene Perform
  advanced to `d5b4750`; Mixer Busses remains accepted at `1eaebf3`.
- Scene Perform is no longer 0 behind current `main` after the root
  coordination-state commit; it now needs a follow-up integrator rebase or
  merge-prep from `d5b4750` onto `cec6d59`.
- Facts changed enough that orientation should refresh before cleanup or
  disposition actions are chosen.
- This is observation only. No worktree, branch, loop record, inbox lifecycle
  state, merge, rebase, or cleanup action was changed.
