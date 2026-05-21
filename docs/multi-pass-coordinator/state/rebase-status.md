# Rebase Status Observation

- generated: 2026-05-21T19:27:45Z
- loop-local copy: `.meta/multipass/loops/project/observe/rebase-status.md`
- request: `.meta/multipass/inbox/claimed/2026-05-21T19-25-30-616Z-rebase-observer-cadence.md`
- scan command: project-local `scripts/multi-pass/rebase-status.sh` is not installed; facts came from direct `git worktree`, local branch, ahead/behind, ancestry, status, and `git merge-tree main <branch>` checks. No fetch was performed.

## observation

- Current local `main` is `e5a388f`; local `origin/main` resolves to `cb79a20` from the existing local ref. No network fetch was performed.
- The root worktree is on `main`, contains current `main`, and is dirty with 84 paths before this observer rewrite. The dirt is broad pre-existing coordination/migration state, including `.claude`/`project` deletions, Multi-Pass loop/state docs, roadmap dashboard/scan files, visual-scenario scripts, wiki updates, and untracked coordination files.
- 33 registered non-root worktrees were scanned. 32 are behind current local `main`; `auto/roadmap-2-scene-perform` is no longer behind after its integration rebase and now contains current `main`.
- 38 local branches exist including `main`. 36 non-main branches are behind current local `main`; `auto/roadmap-2-scene-perform` is the only non-main branch observed to contain current `main`.
- Active build loop `build/scene-perform`: `.worktrees/roadmap-2-scene-perform` on `auto/roadmap-2-scene-perform` is at `1b69d29`, dirty only with 2 untracked transient evidence directories, 0 behind / 4 ahead, contains `main`, is not contained by `main`, and has 0 merge-tree conflict hints.
- Active build loop `build/mixer-busses`: `.worktrees/roadmap-5-mixer-busses-ui-finish` on `auto/roadmap-5-mixer-busses-ui-finish` is at `1eaebf3`, tracked clean, 9 behind / 5 ahead, does not contain `main`, is not contained by `main`, and has 0 merge-tree conflict hints.
- Ready-for-promotion but not active: `auto/roadmap-3-step-sequencer` is clean, 69 behind / 8 ahead, does not contain `main`, is not contained by `main`, and has 4 merge-tree conflict hints.
- Ready-for-promotion reference branch: `auto/roadmap-1-clip-history` is dirty with 1 untracked path, 305 behind / 49 ahead, does not contain `main`, is not contained by `main`, and has 5 conflict hints. Current feature-readiness evidence says the old branch is reference/salvage evidence only.
- Product-owner checkpoint branch: `.worktrees/p0-track-performance-overlay` is clean at `d36c78b`, 107 behind / 10 ahead, does not contain `main`, is not contained by `main`, and has 4 conflict hints.
- Highest conflict hint counts are `auto/roadmap-9-modifier-chain-placement` (25), `codex/master-bus-scenes` (22), `codex/max-8-destination-au` (11, branch-only), `codex/progression-chord-generator` (8), and probe/UX feedback branches at 4-6 hints.
- Facts changed enough that orientation should refresh: Scene Perform has been rebased from `ab62060` to `1b69d29` and now contains current `main`; Mixer Busses is now at accepted candidate `1eaebf3` with 9 behind / 5 ahead; root `main` remains broadly dirty and current integration evidence identifies that dirt as the merge blocker.

## scanned registered non-root worktrees

| Worktree | Branch | HEAD | Dirty | Behind/Ahead | Contains main | Contained by main | Conflict hints | Active mention |
|---|---|---:|---:|---:|---:|---:|---:|---|
| `.claude/worktrees/live-perform-fill-overlay` | `codex/live-perform-fill-overlay` | `a08bc09` | 0 | 461/3 | no | no | 2 | unmentioned |
| `.claude/worktrees/live-perform-performance-mechanics-plan` | `codex/live-perform-performance-mechanics-plan` | `4757fbe` | 0 | 450/1 | no | no | 0 | unmentioned |
| `.claude/worktrees/macro-lane-grid-ui` | `integration/preserve-macro-lane-grid-ui-main-20260515T2014Z` | `5e0836c` | 2 | 51/0 | no | yes | 0 | contained branch |
| `.claude/worktrees/master-bus-scenes` | `codex/master-bus-scenes` | `8b367b2` | 0 | 437/10 | no | no | 22 | unmentioned |
| `.claude/worktrees/master-bus-scenes-plan` | `codex/master-bus-scenes-plan` | `03f71df` | 0 | 450/1 | no | no | 1 | unmentioned |
| `.claude/worktrees/progression-chord-generator` | `codex/progression-chord-generator` | `059c174` | 0 | 405/1 | no | no | 8 | unmentioned |
| `.claude/worktrees/slicer-findings-fix` | `codex/slicer-findings-fix` | `f56104a` | 0 | 397/0 | no | yes | 0 | contained branch |
| `.claude/worktrees/slicer-track-mvp` | `codex/slicer-track-mvp` | `c6a373e` | 0 | 398/0 | no | yes | 0 | contained branch |
| `.worktrees/architecture-engine-controller-carve-up-plan` | `auto/architecture-engine-controller-carve-up-plan` | `f919040` | 0 | 22/0 | no | yes | 0 | contained/maintenance branch |
| `.worktrees/goal-9-modifier-chain-placement` | `auto/goal-9-modifier-chain-placement` | `f39c4e5` | 1 | 221/7 | no | no | 4 | stale completed-feature branch |
| `.worktrees/maintenance-addresses-phrase-timeline` | `auto/maintenance-addresses-phrase-timeline` | `19301bd` | 0 | 21/0 | no | yes | 0 | contained/maintenance branch |
| `.worktrees/maintenance-macro-descriptor-slots` | `auto/maintenance-macro-descriptor-slots` | `0400e65` | 0 | 24/0 | no | yes | 0 | contained/maintenance branch |
| `.worktrees/overnight-simplification-2026-04-29` | `auto/overnight-simplification-2026-04-29` | `9257dd0` | 1 | 355/1 | no | no | 0 | unmentioned |
| `.worktrees/p0-track-performance-overlay` | `auto/p0-track-performance-overlay` | `d36c78b` | 0 | 107/10 | no | no | 4 | product-owner checkpoint |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-audio-input-looping-autoslice` | `codex/probe-overnight-broad-probe-2026-05-05-audio-input-looping-autoslice` | `238894d` | 0 | 211/2 | no | no | 4 | broad probe evidence |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-external-control-and-automation` | `codex/probe-overnight-broad-probe-2026-05-05-external-control-and-automation` | `d5d94d5` | 0 | 211/2 | no | no | 4 | broad probe evidence |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-mixer-routing-and-sends` | `codex/probe-overnight-broad-probe-2026-05-05-mixer-routing-and-sends` | `cf3d3c8` | 0 | 211/2 | no | no | 5 | broad probe evidence |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-performance-overrides-pattern-manipulation` | `codex/probe-overnight-broad-probe-2026-05-05-performance-overrides-pattern-manipulation` | `4898a06` | 0 | 211/2 | no | no | 4 | broad probe evidence |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-phrase-scene-song-performance` | `codex/probe-overnight-broad-probe-2026-05-05-phrase-scene-song-performance` | `6ca658e` | 0 | 211/2 | no | no | 4 | broad probe evidence |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-track-editor-foundation` | `codex/probe-overnight-broad-probe-2026-05-05-track-editor-foundation` | `75c29dd` | 0 | 211/2 | no | no | 4 | broad probe evidence |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-audio-input-looping-autoslice` | `codex/probe-ux-feedback-pass-2026-05-06-audio-input-looping-autoslice` | `ce439f7` | 0 | 211/4 | no | no | 4 | UX feedback evidence |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-external-control-and-automation` | `codex/probe-ux-feedback-pass-2026-05-06-external-control-and-automation` | `d5d94d5` | 5 | 211/2 | no | no | 4 | UX feedback evidence |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-mixer-routing-and-sends` | `codex/probe-ux-feedback-pass-2026-05-06-mixer-routing-and-sends` | `a32d912` | 0 | 211/4 | no | no | 5 | UX feedback evidence |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-performance-overrides-pattern-manipulation` | `codex/probe-ux-feedback-pass-2026-05-06-performance-overrides-pattern-manipulation` | `bfc7173` | 0 | 211/4 | no | no | 6 | UX feedback evidence |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-phrase-scene-song-performance` | `codex/probe-ux-feedback-pass-2026-05-06-phrase-scene-song-performance` | `6ca658e` | 5 | 211/2 | no | no | 4 | UX feedback evidence |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-track-editor-foundation` | `codex/probe-ux-feedback-pass-2026-05-06-track-editor-foundation` | `75c29dd` | 5 | 211/2 | no | no | 4 | UX feedback evidence |
| `.worktrees/roadmap-1-clip-history` | `auto/roadmap-1-clip-history` | `ced03ab` | 1 | 305/49 | no | no | 5 | ready-for-promotion reference/salvage branch |
| `.worktrees/roadmap-2-scene-perform` | `auto/roadmap-2-scene-perform` | `1b69d29` | 2 | 0/4 | yes | no | 0 | active build loop; accepted integration candidate |
| `.worktrees/roadmap-3-step-sequencer` | `auto/roadmap-3-step-sequencer` | `3e77689` | 0 | 69/8 | no | no | 4 | ready-for-promotion, not active |
| `.worktrees/roadmap-5-mixer-busses-ui-finish` | `auto/roadmap-5-mixer-busses-ui-finish` | `1eaebf3` | 0 | 9/5 | no | no | 0 | active build loop; accepted integration candidate |
| `.worktrees/roadmap-9-modifier-chain-placement` | `auto/roadmap-9-modifier-chain-placement` | `7520dbd` | 1 | 305/192 | no | no | 25 | stale completed-feature branch |
| `.worktrees/runtime-au-plugin-shutdown` | `codex/runtime-au-plugin-shutdown` | `f5cf677` | 0 | 395/1 | no | no | 1 | unmentioned |
| `.worktrees/runtime-drum-sample-playback` | `codex/runtime-drum-sample-playback` | `f5417ca` | 0 | 395/2 | no | no | 2 | unmentioned |

## branch-only behind main

These local branches are behind `main` and have no registered worktree in the current `git worktree list` output.

| Branch | HEAD | Behind/Ahead | Contains main | Contained by main | Conflict hints | Active mention |
|---|---:|---:|---:|---:|---:|---|
| `backup/roadmap-2-scene-perform-pre-main-integration` | `4ebbc44` | 69/8 | no | no | 4 | backup of Scene Perform pre-main integration |
| `codex/macro-lane-grid-ui` | `07c3d1b` | 424/0 | no | yes | 0 | contained branch-only |
| `codex/max-8-destination-au` | `5f507ea` | 503/10 | no | no | 11 | unmentioned branch-only |
| `codex/tracks-perform-scenes-workspace` | `87061b0` | 69/10 | no | no | 5 | unmentioned branch-only |

This is an observation only; no rebase, merge, cherry-pick, build, review, push, cleanup, or request lifecycle action was scheduled.
