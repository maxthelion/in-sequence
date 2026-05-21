# Rebase Status Observation

- generated: 2026-05-21T06:19:01Z
- loop-local copy: `.meta/multipass/loops/project/observe/rebase-status.md`
- request: `.meta/multipass/inbox/claimed/2026-05-21T05-56-33-790Z-rebase-observer-cadence.md`
- scan command: project-local `scripts/multi-pass/rebase-status.sh` is not installed; facts came from direct `git worktree`, ahead/behind, ancestry, status, and `git merge-tree main <branch>` checks. No fetch was performed.

## observation

- Current local `main` is `ccd6fdd`. The root worktree is on `main`, contains current `main`, and is dirty only with observer-state files already present before this pass.
- 37 scanned non-root worktrees are behind current local `main`; none of those branches contains current `main`.
- Active build loop: `.worktrees/roadmap-5-mixer-busses-ui-finish` on `auto/roadmap-5-mixer-busses-ui-finish` is 1 behind / 0 ahead, already contained by `main`, and dirty with 5 builder files. Conflict hints: 0.
- PM-ready but not active: `auto/roadmap-2-scene-perform` and `auto/roadmap-3-step-sequencer` are both clean, 61 behind / 8 ahead, do not contain `main`, and have 4 merge-tree conflict hints each.
- PM-ambiguous: `auto/roadmap-1-clip-history` is dirty, 297 behind / 49 ahead, does not contain `main`, and has 5 conflict hints.
- Product-owner checkpoint: `.worktrees/p0-track-performance-overlay` is clean, 99 behind / 10 ahead, does not contain `main`, and has 4 conflict hints.
- Completed-contained roadmap/feature branches are still behind their base histories but are already contained by `main`: `auto/roadmap-4-mixer-main-out`, `auto/roadmap-5-mixer-busses`, `auto/roadmap-5-mixer-busses-phase-2`, `auto/roadmap-6-send-effects`, and `integration/modifier-chain-7520dbd`.
- Stale completed-feature modifier branches remain dirty and uncontained: `auto/goal-9-modifier-chain-placement` is 213 behind / 7 ahead with 4 conflict hints; `auto/roadmap-9-modifier-chain-placement` is 297 behind / 192 ahead with 25 conflict hints.
- Highest non-roadmap conflict hint counts are `codex/master-bus-scenes` (22), `codex/progression-chord-generator` (8), and probe/UX feedback worktrees at 4-6 hints each.

## scanned worktrees behind main

| Worktree | Branch | Dirty | Behind/Ahead | Contains main | Contained by main | Conflict hints | Active mention |
|---|---:|---:|---:|---:|---:|---:|---|
| `.claude/worktrees/live-perform-fill-overlay` | `codex/live-perform-fill-overlay` | 0 | 453/3 | no | no | 2 | unmentioned |
| `.claude/worktrees/live-perform-performance-mechanics-plan` | `codex/live-perform-performance-mechanics-plan` | 0 | 442/1 | no | no | 0 | unmentioned |
| `.claude/worktrees/macro-lane-grid-ui` | `integration/preserve-macro-lane-grid-ui-main-20260515T2014Z` | 2 | 43/0 | no | yes | 0 | unmentioned |
| `.claude/worktrees/master-bus-scenes` | `codex/master-bus-scenes` | 0 | 429/10 | no | no | 22 | unmentioned |
| `.claude/worktrees/master-bus-scenes-plan` | `codex/master-bus-scenes-plan` | 0 | 442/1 | no | no | 1 | unmentioned |
| `.claude/worktrees/progression-chord-generator` | `codex/progression-chord-generator` | 0 | 397/1 | no | no | 8 | unmentioned |
| `.claude/worktrees/slicer-findings-fix` | `codex/slicer-findings-fix` | 0 | 389/0 | no | yes | 0 | unmentioned |
| `.claude/worktrees/slicer-track-mvp` | `codex/slicer-track-mvp` | 0 | 390/0 | no | yes | 0 | unmentioned |
| `.worktrees/architecture-engine-controller-carve-up-plan` | `auto/architecture-engine-controller-carve-up-plan` | 0 | 14/0 | no | yes | 0 | unmentioned |
| `.worktrees/goal-9-modifier-chain-placement` | `auto/goal-9-modifier-chain-placement` | 1 | 213/7 | no | no | 4 | stale completed-feature branch |
| `.worktrees/integration-modifier-chain-7520dbd` | `integration/modifier-chain-7520dbd` | 0 | 26/0 | no | yes | 0 | completed-contained |
| `.worktrees/maintenance-addresses-phrase-timeline` | `auto/maintenance-addresses-phrase-timeline` | 0 | 13/0 | no | yes | 0 | unmentioned |
| `.worktrees/maintenance-macro-descriptor-slots` | `auto/maintenance-macro-descriptor-slots` | 0 | 16/0 | no | yes | 0 | unmentioned |
| `.worktrees/overnight-simplification-2026-04-29` | `auto/overnight-simplification-2026-04-29` | 1 | 347/1 | no | no | 0 | unmentioned |
| `.worktrees/p0-track-performance-overlay` | `auto/p0-track-performance-overlay` | 0 | 99/10 | no | no | 4 | product-owner checkpoint |
| `.worktrees/roadmap-1-clip-history` | `auto/roadmap-1-clip-history` | 1 | 297/49 | no | no | 5 | PM-ambiguous |
| `.worktrees/roadmap-2-scene-perform` | `auto/roadmap-2-scene-perform` | 0 | 61/8 | no | no | 4 | PM-ready, not active |
| `.worktrees/roadmap-3-step-sequencer` | `auto/roadmap-3-step-sequencer` | 0 | 61/8 | no | no | 4 | PM-ready, not active |
| `.worktrees/roadmap-4-mixer-main-out` | `auto/roadmap-4-mixer-main-out` | 0 | 43/0 | no | yes | 0 | completed-contained |
| `.worktrees/roadmap-5-mixer-busses` | `auto/roadmap-5-mixer-busses` | 0 | 41/0 | no | yes | 0 | completed-contained |
| `.worktrees/roadmap-5-mixer-busses-phase-2` | `auto/roadmap-5-mixer-busses-phase-2` | 0 | 23/0 | no | yes | 0 | completed-contained |
| `.worktrees/roadmap-5-mixer-busses-ui-finish` | `auto/roadmap-5-mixer-busses-ui-finish` | 5 | 1/0 | no | yes | 0 | active build loop |
| `.worktrees/roadmap-6-send-effects` | `auto/roadmap-6-send-effects` | 0 | 17/0 | no | yes | 0 | completed-contained |
| `.worktrees/roadmap-9-modifier-chain-placement` | `auto/roadmap-9-modifier-chain-placement` | 1 | 297/192 | no | no | 25 | stale completed-feature branch |
| `.worktrees/runtime-au-plugin-shutdown` | `codex/runtime-au-plugin-shutdown` | 0 | 387/1 | no | no | 1 | unmentioned |
| `.worktrees/runtime-drum-sample-playback` | `codex/runtime-drum-sample-playback` | 0 | 387/2 | no | no | 2 | unmentioned |

Broad probe and UX feedback worktrees are also behind `main` by 203 commits, do not contain `main`, are not active work by current loop artifacts, and have 4-6 conflict hints each. Dirty probe/feedback worktrees are external-control-and-automation, phrase-scene-song-performance, and track-editor-foundation.

This is an observation only; no rebase, merge, cherry-pick, build, review, push, cleanup, or request lifecycle action was scheduled.
