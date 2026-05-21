# Worktree Hygiene Observation

- generated: 2026-05-21T14:45:06Z
- loop-local copy: `.meta/multipass/loops/project/observe/worktree-hygiene-status.md`
- request: `.meta/multipass/inbox/claimed/2026-05-21T14-44-14-520Z-worktree-hygiene-observer-cadence.md`
- scan command: no project-local `worktree-hygiene-status` script was found; this pass used `scripts/multi-pass/evidence-worktrees.sh`, `git worktree list --porcelain`, direct dirty counts, direct `main...HEAD` ahead/behind checks, direct ancestry checks, loop manifests, merge/rebase/work observations, and recent build-loop summaries.
- local main: `e5a388f`

## Stale Loop Candidates

None observed. Active loop manifests are `project`, `build/mixer-busses`, and
`build/scene-perform`. Neither active build-loop manifest nor durable
build-loop summary says the loop is merged, abandoned, or superseded.

## Safe Cleanup Candidates

Clean worktrees whose branch HEAD is already contained in local `main`.

| Worktree | Branch | Commit | Dirty | Contained in main | Signal |
|---|---|---:|---:|---:|---|
| `.claude/worktrees/slicer-findings-fix` | `codex/slicer-findings-fix` | `f56104a` | 0 | yes | contained branch |
| `.claude/worktrees/slicer-track-mvp` | `codex/slicer-track-mvp` | `c6a373e` | 0 | yes | contained branch |
| `.worktrees/architecture-engine-controller-carve-up-plan` | `auto/architecture-engine-controller-carve-up-plan` | `f919040` | 0 | yes | contained branch |
| `.worktrees/maintenance-addresses-phrase-timeline` | `auto/maintenance-addresses-phrase-timeline` | `19301bd` | 0 | yes | contained branch |
| `.worktrees/maintenance-macro-descriptor-slots` | `auto/maintenance-macro-descriptor-slots` | `0400e65` | 0 | yes | contained branch |

## Dirty Or Uncontained Branches Needing Disposition

Dirty worktrees, active build branches, PM-ready branches, checkpoint branches,
probe/evidence branches, or branches not contained in local `main`.

| Worktree | Branch | Commit | Dirty | Behind/Ahead | Contained in main | Signal |
|---|---|---:|---:|---:|---:|---|
| `.` | `main` | `e5a388f` | 83 | 0/0 | yes | root dirty with broad pre-existing coordination/migration changes; this observer updates hygiene status copies |
| `.worktrees/roadmap-5-mixer-busses-ui-finish` | `auto/roadmap-5-mixer-busses-ui-finish` | `f82d525` | 0 | 9/4 | no | active build loop; visual-economy correction still pending |
| `.worktrees/roadmap-2-scene-perform` | `auto/roadmap-2-scene-perform` | `ab62060` | 2 | 3/4 | no | active build loop; untracked transient evidence directories remain |
| `.claude/worktrees/macro-lane-grid-ui` | `integration/preserve-macro-lane-grid-ui-main-20260515T2014Z` | `5e0836c` | 2 | 51/0 | yes | dirty contained worktree |
| `.worktrees/goal-9-modifier-chain-placement` | `auto/goal-9-modifier-chain-placement` | `f39c4e5` | 1 | 221/7 | no | stale completed-feature branch per readiness/rebase observations |
| `.worktrees/overnight-simplification-2026-04-29` | `auto/overnight-simplification-2026-04-29` | `9257dd0` | 1 | 355/1 | no | dirty legacy worktree |
| `.worktrees/p0-track-performance-overlay` | `auto/p0-track-performance-overlay` | `d36c78b` | 0 | 107/10 | no | historical checkpoint-ready; awaiting product-owner acceptance |
| `.worktrees/roadmap-1-clip-history` | `auto/roadmap-1-clip-history` | `ced03ab` | 1 | 305/49 | no | ready-for-promotion reference/salvage branch, not merge authority |
| `.worktrees/roadmap-3-step-sequencer` | `auto/roadmap-3-step-sequencer` | `3e77689` | 0 | 69/8 | no | ready-for-promotion, not active build loop |
| `.worktrees/roadmap-9-modifier-chain-placement` | `auto/roadmap-9-modifier-chain-placement` | `7520dbd` | 1 | 305/192 | no | stale completed-feature branch per readiness/rebase observations |
| `.claude/worktrees/live-perform-fill-overlay` | `codex/live-perform-fill-overlay` | `a08bc09` | 0 | 461/3 | no | unmentioned legacy branch |
| `.claude/worktrees/live-perform-performance-mechanics-plan` | `codex/live-perform-performance-mechanics-plan` | `4757fbe` | 0 | 450/1 | no | unmentioned legacy branch |
| `.claude/worktrees/master-bus-scenes` | `codex/master-bus-scenes` | `8b367b2` | 0 | 437/10 | no | unmentioned legacy branch |
| `.claude/worktrees/master-bus-scenes-plan` | `codex/master-bus-scenes-plan` | `03f71df` | 0 | 450/1 | no | unmentioned legacy branch |
| `.claude/worktrees/progression-chord-generator` | `codex/progression-chord-generator` | `059c174` | 0 | 405/1 | no | unmentioned legacy branch |
| `.worktrees/runtime-au-plugin-shutdown` | `codex/runtime-au-plugin-shutdown` | `f5cf677` | 0 | 395/1 | no | unmentioned runtime branch |
| `.worktrees/runtime-drum-sample-playback` | `codex/runtime-drum-sample-playback` | `f5417ca` | 0 | 395/2 | no | unmentioned runtime branch |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-audio-input-looping-autoslice` | `codex/probe-overnight-broad-probe-2026-05-05-audio-input-looping-autoslice` | `238894d` | 0 | 211/2 | no | broad probe evidence branch |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-external-control-and-automation` | `codex/probe-overnight-broad-probe-2026-05-05-external-control-and-automation` | `d5d94d5` | 0 | 211/2 | no | broad probe evidence branch |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-mixer-routing-and-sends` | `codex/probe-overnight-broad-probe-2026-05-05-mixer-routing-and-sends` | `cf3d3c8` | 0 | 211/2 | no | broad probe evidence branch |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-performance-overrides-pattern-manipulation` | `codex/probe-overnight-broad-probe-2026-05-05-performance-overrides-pattern-manipulation` | `4898a06` | 0 | 211/2 | no | broad probe evidence branch |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-phrase-scene-song-performance` | `codex/probe-overnight-broad-probe-2026-05-05-phrase-scene-song-performance` | `6ca658e` | 0 | 211/2 | no | broad probe evidence branch |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-track-editor-foundation` | `codex/probe-overnight-broad-probe-2026-05-05-track-editor-foundation` | `75c29dd` | 0 | 211/2 | no | broad probe evidence branch |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-audio-input-looping-autoslice` | `codex/probe-ux-feedback-pass-2026-05-06-audio-input-looping-autoslice` | `ce439f7` | 0 | 211/4 | no | UX feedback evidence branch |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-external-control-and-automation` | `codex/probe-ux-feedback-pass-2026-05-06-external-control-and-automation` | `d5d94d5` | 5 | 211/2 | no | dirty UX feedback evidence branch |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-mixer-routing-and-sends` | `codex/probe-ux-feedback-pass-2026-05-06-mixer-routing-and-sends` | `a32d912` | 0 | 211/4 | no | UX feedback evidence branch |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-performance-overrides-pattern-manipulation` | `codex/probe-ux-feedback-pass-2026-05-06-performance-overrides-pattern-manipulation` | `bfc7173` | 0 | 211/4 | no | UX feedback evidence branch |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-phrase-scene-song-performance` | `codex/probe-ux-feedback-pass-2026-05-06-phrase-scene-song-performance` | `6ca658e` | 5 | 211/2 | no | dirty UX feedback evidence branch |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-track-editor-foundation` | `codex/probe-ux-feedback-pass-2026-05-06-track-editor-foundation` | `75c29dd` | 5 | 211/2 | no | dirty UX feedback evidence branch |

## Loop Registry Entries Still Marking Completed Work Active

None observed.

| Registry | Status | Worktree | Branch | Signal |
|---|---|---|---|---|
| `docs/multi-pass-coordinator/loops/build/mixer-busses.yaml` and `.meta/multipass/loops/build/mixer-busses/manifest.yaml` | active | `.worktrees/roadmap-5-mixer-busses-ui-finish` | `auto/roadmap-5-mixer-busses-ui-finish` | current active build; not completed |
| `docs/multi-pass-coordinator/loops/build/scene-perform.yaml` and `.meta/multipass/loops/build/scene-perform/manifest.yaml` | active | `.worktrees/roadmap-2-scene-perform` | `auto/roadmap-2-scene-perform` | current active build; not completed in registry |

## Observer Notes

- Hygiene facts changed since the previous durable pass: active build loops are
  now `build/mixer-busses` and `build/scene-perform`; local `main` is
  `e5a388f`; root dirty count is 83 before this observer edit; Mixer Busses is
  clean at `f82d525`; Scene Perform is at `ab62060` with two untracked evidence
  directories.
- Several previously listed contained roadmap worktrees are no longer present
  in `git worktree list`; the current safe-cleanup list only includes currently
  registered worktrees.
- Facts changed enough that orientation should refresh before cleanup or
  disposition actions are chosen.
- This is observation only. No worktree, branch, loop record, inbox lifecycle
  state, merge, rebase, or cleanup action was changed.
