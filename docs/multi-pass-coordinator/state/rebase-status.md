# Rebase Status Observation

- generated: 2026-05-21T23:32:54Z
- loop-local copy: `.meta/multipass/loops/project/observe/rebase-status.md`
- request: `.meta/multipass/inbox/claimed/2026-05-21T23-31-26-235Z-rebase-observer-cadence.md`
- scan command: project-local `scripts/multi-pass/rebase-status.sh` is not installed; facts came from direct `git worktree`, local branch, ahead/behind, ancestry, status, and `git merge-tree main <branch>` checks. No fetch was performed.

## observation

- Current local `main` is `cec6d59`; local `origin/main` resolves to `cb79a20` from the existing local ref. No network fetch was performed.
- The root worktree is on `main`, contains current `main`, and is dirty with 7 coordination-state paths before this observer rewrite: `docs/multi-pass-coordinator/ooda/orientation.md`, build-loop summaries for Mixer Busses and Scene Perform, `decision-log.md`, `holistic-status.md`, `process-health.md`, and `worktree-hygiene-status.md`.
- 33 registered non-root worktrees were scanned. All 33 are behind current local `main`.
- 38 local branches exist including `main`. All 37 non-main branches are behind current local `main`; no non-main branch currently contains current `main`.
- Active build loop `build/scene-perform`: `.worktrees/roadmap-2-scene-perform` on `auto/roadmap-2-scene-perform` is at `d5b4750`, dirty only with 2 untracked transient evidence directories, 1 behind / 4 ahead, does not contain `main`, is not contained by `main`, and has 0 merge-tree conflict hints.
- Active build loop `build/mixer-busses`: `.worktrees/roadmap-5-mixer-busses-ui-finish` on `auto/roadmap-5-mixer-busses-ui-finish` is at `1eaebf3`, tracked clean, 11 behind / 5 ahead, does not contain `main`, is not contained by `main`, and has 0 merge-tree conflict hints.
- Ready-for-promotion but not active: `auto/roadmap-3-step-sequencer` is clean, 71 behind / 8 ahead, does not contain `main`, is not contained by `main`, and has 8 merge-tree conflict hints.
- Ready-for-promotion reference branch: `auto/roadmap-1-clip-history` is dirty with 1 untracked path, 307 behind / 49 ahead, does not contain `main`, is not contained by `main`, and has 6 conflict hints. Current feature-readiness evidence says the old branch is reference/salvage evidence only.
- Product-owner checkpoint branch: `.worktrees/p0-track-performance-overlay` is clean at `d36c78b`, 109 behind / 10 ahead, does not contain `main`, is not contained by `main`, and has 4 conflict hints.
- Highest conflict hint counts are `auto/roadmap-9-modifier-chain-placement` (28), `codex/master-bus-scenes` (22), `codex/max-8-destination-au` (11, branch-only), `codex/progression-chord-generator` (8), `auto/roadmap-3-step-sequencer` (8), `backup/roadmap-2-scene-perform-pre-main-integration` (8, branch-only), and `codex/tracks-perform-scenes-workspace` (8, branch-only).
- Facts changed enough that orientation should refresh: `main` advanced to `cec6d59`; Scene Perform is now `d5b4750` and 1 behind / 4 ahead rather than containing `main`; Mixer Busses is now 11 behind / 5 ahead; root dirt has narrowed to 7 current coordination-state files, while all non-main branches are now behind current local `main`.

## scanned registered non-root worktrees

| Worktree | Branch | HEAD | Dirty | Behind/Ahead | Contains main | Contained by main | Conflict hints | Active mention |
|---|---|---:|---:|---:|---:|---:|---:|---|
| `.claude/worktrees/live-perform-fill-overlay` | `codex/live-perform-fill-overlay` | `a08bc09` | 0 | 463/3 | no | no | 2 | unmentioned |
| `.claude/worktrees/live-perform-performance-mechanics-plan` | `codex/live-perform-performance-mechanics-plan` | `4757fbe` | 0 | 452/1 | no | no | 0 | unmentioned |
| `.claude/worktrees/macro-lane-grid-ui` | `integration/preserve-macro-lane-grid-ui-main-20260515T2014Z` | `5e0836c` | 2 | 53/0 | no | yes | 0 | contained branch |
| `.claude/worktrees/master-bus-scenes` | `codex/master-bus-scenes` | `8b367b2` | 0 | 439/10 | no | no | 22 | unmentioned |
| `.claude/worktrees/master-bus-scenes-plan` | `codex/master-bus-scenes-plan` | `03f71df` | 0 | 452/1 | no | no | 1 | unmentioned |
| `.claude/worktrees/progression-chord-generator` | `codex/progression-chord-generator` | `059c174` | 0 | 407/1 | no | no | 8 | unmentioned |
| `.claude/worktrees/slicer-findings-fix` | `codex/slicer-findings-fix` | `f56104a` | 0 | 399/0 | no | yes | 0 | contained branch |
| `.claude/worktrees/slicer-track-mvp` | `codex/slicer-track-mvp` | `c6a373e` | 0 | 400/0 | no | yes | 0 | contained branch |
| `.worktrees/architecture-engine-controller-carve-up-plan` | `auto/architecture-engine-controller-carve-up-plan` | `f919040` | 0 | 24/0 | no | yes | 0 | contained/maintenance branch |
| `.worktrees/goal-9-modifier-chain-placement` | `auto/goal-9-modifier-chain-placement` | `f39c4e5` | 1 | 223/7 | no | no | 4 | stale completed-feature branch |
| `.worktrees/maintenance-addresses-phrase-timeline` | `auto/maintenance-addresses-phrase-timeline` | `19301bd` | 0 | 23/0 | no | yes | 0 | contained/maintenance branch |
| `.worktrees/maintenance-macro-descriptor-slots` | `auto/maintenance-macro-descriptor-slots` | `0400e65` | 0 | 26/0 | no | yes | 0 | contained/maintenance branch |
| `.worktrees/overnight-simplification-2026-04-29` | `auto/overnight-simplification-2026-04-29` | `9257dd0` | 1 | 357/1 | no | no | 0 | unmentioned |
| `.worktrees/p0-track-performance-overlay` | `auto/p0-track-performance-overlay` | `d36c78b` | 0 | 109/10 | no | no | 4 | product-owner checkpoint |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-audio-input-looping-autoslice` | `codex/probe-overnight-broad-probe-2026-05-05-audio-input-looping-autoslice` | `238894d` | 0 | 213/2 | no | no | 4 | broad probe evidence |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-external-control-and-automation` | `codex/probe-overnight-broad-probe-2026-05-05-external-control-and-automation` | `d5d94d5` | 0 | 213/2 | no | no | 4 | broad probe evidence |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-mixer-routing-and-sends` | `codex/probe-overnight-broad-probe-2026-05-05-mixer-routing-and-sends` | `cf3d3c8` | 0 | 213/2 | no | no | 5 | broad probe evidence |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-performance-overrides-pattern-manipulation` | `codex/probe-overnight-broad-probe-2026-05-05-performance-overrides-pattern-manipulation` | `4898a06` | 0 | 213/2 | no | no | 4 | broad probe evidence |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-phrase-scene-song-performance` | `codex/probe-overnight-broad-probe-2026-05-05-phrase-scene-song-performance` | `6ca658e` | 0 | 213/2 | no | no | 4 | broad probe evidence |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-track-editor-foundation` | `codex/probe-overnight-broad-probe-2026-05-05-track-editor-foundation` | `75c29dd` | 0 | 213/2 | no | no | 4 | broad probe evidence |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-audio-input-looping-autoslice` | `codex/probe-ux-feedback-pass-2026-05-06-audio-input-looping-autoslice` | `ce439f7` | 0 | 213/4 | no | no | 4 | UX feedback evidence |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-external-control-and-automation` | `codex/probe-ux-feedback-pass-2026-05-06-external-control-and-automation` | `d5d94d5` | 5 | 213/2 | no | no | 4 | UX feedback evidence |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-mixer-routing-and-sends` | `codex/probe-ux-feedback-pass-2026-05-06-mixer-routing-and-sends` | `a32d912` | 0 | 213/4 | no | no | 5 | UX feedback evidence |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-performance-overrides-pattern-manipulation` | `codex/probe-ux-feedback-pass-2026-05-06-performance-overrides-pattern-manipulation` | `bfc7173` | 0 | 213/4 | no | no | 6 | UX feedback evidence |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-phrase-scene-song-performance` | `codex/probe-ux-feedback-pass-2026-05-06-phrase-scene-song-performance` | `6ca658e` | 5 | 213/2 | no | no | 4 | UX feedback evidence |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-track-editor-foundation` | `codex/probe-ux-feedback-pass-2026-05-06-track-editor-foundation` | `75c29dd` | 5 | 213/2 | no | no | 4 | UX feedback evidence |
| `.worktrees/roadmap-1-clip-history` | `auto/roadmap-1-clip-history` | `ced03ab` | 1 | 307/49 | no | no | 6 | ready-for-promotion reference/salvage branch |
| `.worktrees/roadmap-2-scene-perform` | `auto/roadmap-2-scene-perform` | `d5b4750` | 2 | 1/4 | no | no | 0 | active build loop; accepted integration candidate |
| `.worktrees/roadmap-3-step-sequencer` | `auto/roadmap-3-step-sequencer` | `3e77689` | 0 | 71/8 | no | no | 8 | ready-for-promotion, not active |
| `.worktrees/roadmap-5-mixer-busses-ui-finish` | `auto/roadmap-5-mixer-busses-ui-finish` | `1eaebf3` | 0 | 11/5 | no | no | 0 | active build loop; accepted integration candidate |
| `.worktrees/roadmap-9-modifier-chain-placement` | `auto/roadmap-9-modifier-chain-placement` | `7520dbd` | 1 | 307/192 | no | no | 28 | stale completed-feature branch |
| `.worktrees/runtime-au-plugin-shutdown` | `codex/runtime-au-plugin-shutdown` | `f5cf677` | 0 | 397/1 | no | no | 1 | unmentioned |
| `.worktrees/runtime-drum-sample-playback` | `codex/runtime-drum-sample-playback` | `f5417ca` | 0 | 397/2 | no | no | 2 | unmentioned |

## branch-only behind main

These local branches are behind `main` and have no registered worktree in the current `git worktree list` output.

| Branch | HEAD | Behind/Ahead | Contains main | Contained by main | Conflict hints | Active mention |
|---|---:|---:|---:|---:|---:|---|
| `backup/roadmap-2-scene-perform-pre-main-integration` | `4ebbc44` | 71/8 | no | no | 8 | backup of Scene Perform pre-main integration |
| `codex/macro-lane-grid-ui` | `07c3d1b` | 426/0 | no | yes | 0 | contained branch-only |
| `codex/max-8-destination-au` | `5f507ea` | 505/10 | no | no | 11 | unmentioned branch-only |
| `codex/tracks-perform-scenes-workspace` | `87061b0` | 71/10 | no | no | 8 | unmentioned branch-only |

This is an observation only; no rebase, merge, cherry-pick, build, review, push, cleanup, or request lifecycle action was scheduled.
