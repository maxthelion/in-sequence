# Rebase Status Observation

- generated: 2026-05-23T13:02Z
- loop-local copy: `.meta/multipass/loops/project/observe/rebase-status.md`
- cadence evidence: `.meta/multipass/loops/project/observe/2026-05-23T13-02Z-rebase-status-observation.md`
- request: `.meta/multipass/inbox/claimed/2026-05-23T13-00-19-473Z-rebase-observer-cadence.md`
- scan command: project-local `scripts/multi-pass/rebase-status.sh` is still not installed or executable; facts came from `inventory.ts`, `scripts/multi-pass/evidence-worktrees.sh`, `scripts/multi-pass/inbox-status.sh`, current durable summaries, merge/orientation evidence, direct `git worktree`, branch ahead/behind, ancestry, status, `git diff --check`, and advisory `git merge-tree --write-tree main <branch>` conflict-output checks.
- network: no fetch was performed. Local `origin/main` resolves to `cb79a2064cb0`.

## Observation

- Current local `main` is `be465d6faab8` (`Merge branch 'auto/roadmap-5-mixer-busses-ui-finish'`); local `origin/main` is `cb79a2064cb0`. Local `main` is `439` ahead / `0` behind local `origin/main`.
- Root worktree is on `main`, contains current `main`, and has `19` dirty coordination/process paths. Observed root dirt is durable/loop coordination state plus `scripts/multi-pass/inbox-status.sh`; no root product-code dirt was observed by this pass.
- Inventory reports active loops `project`, `build/step-sequencer`, and `build/clip-history`. Inbox status reports `5` pending, `1` claimed, `33` blocked, and `583` done requests.
- Pending active/unknown-loop inbox items are Clip History Phase 3 builder continuation, Clip History build-decider cadence, project decider cadence, and project orienter cadence. Pending terminal-loop residue remains the old `build/scene-perform` build-orienter cadence. This rebase-observer request is claimed.
- 34 registered non-root worktrees were scanned. 32 are behind current local `main`; `.worktrees/roadmap-1-clip-history-v2` and `.worktrees/roadmap-3-step-sequencer` are current-main-based and ahead of `main`. 2 non-root worktrees contain current `main`; 8 non-root worktrees are contained by `main`; 24 non-root worktrees are clean and 10 are dirty.
- 39 local branches exist including `main`. 36 non-main branches are behind current local `main`; `auto/roadmap-1-clip-history-v2` is `0` behind / `3` ahead; `auto/roadmap-3-step-sequencer` is `0` behind / `4` ahead. 2 non-main branches contain current `main`; 9 non-main branches are already contained by `main`.
- Active build loop `build/step-sequencer`: `.worktrees/roadmap-3-step-sequencer` on `auto/roadmap-3-step-sequencer` is clean at `26d858e` (`Add unified step cell visual evidence harness`), `0` behind / `4` ahead of current `main`, contains `main`, is not contained by `main`, has 0 advisory merge-tree conflict-output lines, and passed both `git diff --check main...HEAD` and worktree `git diff --check`. Current evidence says this is committed Phase 2-A visual-evidence repair output awaiting fresh exact-output review pairing, not accepted feature or merge-ready output.
- Active build loop `build/clip-history`: `.worktrees/roadmap-1-clip-history-v2` on `auto/roadmap-1-clip-history-v2` has committed `HEAD` at `ac809cd` (`Add clip history audition override`), `0` behind / `3` ahead of current `main`, contains `main`, is not contained by `main`, and has 0 advisory merge-tree conflict-output lines for committed `HEAD`. The worktree is dirty with 5 Phase 3 files changed (`780` insertions / `195` deletions by `git diff --stat`) and passed both committed-range and worktree `git diff --check`. Current evidence says accepted Phase 1-C foundation plus uncommitted Phase 3 implementation material; no Phase 3 commit or review evidence was observed.
- Landed build loop `build/mixer-busses`: `.worktrees/roadmap-5-mixer-busses-ui-finish` on `auto/roadmap-5-mixer-busses-ui-finish` is tracked clean at `1eaebf3`, `18` behind / `0` ahead, does not contain `main`, is contained by `main`, and has 0 advisory merge-tree conflict-output lines.
- Landed build loop `build/scene-perform`: `.worktrees/roadmap-2-scene-perform` on `auto/roadmap-2-scene-perform` is at `d5b4750`, dirty only with 2 untracked transient evidence directories, `9` behind / `0` ahead, does not contain `main`, is contained by `main`, and has 0 advisory merge-tree conflict-output lines.
- Old Clip History reference branch: `.worktrees/roadmap-1-clip-history` on `auto/roadmap-1-clip-history` is dirty with 1 untracked transient path, `319` behind / `49` ahead, does not contain `main`, is not contained by `main`, and has advisory merge-tree conflict-output hints.
- Product-owner checkpoint branch: `.worktrees/p0-track-performance-overlay` on `auto/p0-track-performance-overlay` is clean at `d36c78b`, `121` behind / `10` ahead, does not contain `main`, is not contained by `main`, and has advisory merge-tree conflict-output hints.
- Highest advisory merge-tree conflict-output counts in this scan are `auto/roadmap-9-modifier-chain-placement` (55), `codex/master-bus-scenes` (47), `codex/max-8-destination-au` (31, branch-only), `codex/progression-chord-generator` (18), `auto/p0-track-performance-overlay` (16), `codex/tracks-perform-scenes-workspace` (16, branch-only), `backup/roadmap-2-scene-perform-pre-main-integration` (13, branch-only), `codex/probe-ux-feedback-pass-2026-05-06-performance-overrides-pattern-manipulation` (13), and old Clip History reference `auto/roadmap-1-clip-history` (11).
- Facts changed enough from the previous durable rebase observation that orientation should consume this refresh: Step Sequencer advanced from clean `01b2936` / three ahead to clean `26d858e` / four ahead with visual-evidence act output, and Clip History changed from clean Phase 1-C / pending Phase 3 to dirty partial Phase 3 work with blocked original builder evidence and pending continuation.

## Scanned Registered Non-Root Worktrees

| Worktree | Branch | HEAD | Dirty | Behind/Ahead | Contains main | Contained by main | Conflict output | Active mention |
|---|---|---:|---:|---:|---:|---:|---:|---|
| `.claude/worktrees/live-perform-fill-overlay` | `codex/live-perform-fill-overlay` | `a08bc09` | 0 | 475/3 | no | no | 5 | unmentioned |
| `.claude/worktrees/live-perform-performance-mechanics-plan` | `codex/live-perform-performance-mechanics-plan` | `4757fbe` | 0 | 464/1 | no | no | 0 | unmentioned |
| `.claude/worktrees/macro-lane-grid-ui` | `integration/preserve-macro-lane-grid-ui-main-20260515T2014Z` | `5e0836c` | 2 | 65/0 | no | yes | 0 | contained/maintenance branch |
| `.claude/worktrees/master-bus-scenes` | `codex/master-bus-scenes` | `8b367b2` | 0 | 451/10 | no | no | 47 | unmentioned |
| `.claude/worktrees/master-bus-scenes-plan` | `codex/master-bus-scenes-plan` | `03f71df` | 0 | 464/1 | no | no | 2 | unmentioned |
| `.claude/worktrees/progression-chord-generator` | `codex/progression-chord-generator` | `059c174` | 0 | 419/1 | no | no | 18 | unmentioned |
| `.claude/worktrees/slicer-findings-fix` | `codex/slicer-findings-fix` | `f56104a` | 0 | 411/0 | no | yes | 0 | contained branch |
| `.claude/worktrees/slicer-track-mvp` | `codex/slicer-track-mvp` | `c6a373e` | 0 | 412/0 | no | yes | 0 | contained branch |
| `.worktrees/architecture-engine-controller-carve-up-plan` | `auto/architecture-engine-controller-carve-up-plan` | `f919040` | 0 | 36/0 | no | yes | 0 | contained/maintenance branch |
| `.worktrees/goal-9-modifier-chain-placement` | `auto/goal-9-modifier-chain-placement` | `f39c4e5` | 1 | 235/7 | no | no | 8 | stale completed-feature branch |
| `.worktrees/maintenance-addresses-phrase-timeline` | `auto/maintenance-addresses-phrase-timeline` | `19301bd` | 0 | 35/0 | no | yes | 0 | contained/maintenance branch |
| `.worktrees/maintenance-macro-descriptor-slots` | `auto/maintenance-macro-descriptor-slots` | `0400e65` | 0 | 38/0 | no | yes | 0 | contained/maintenance branch |
| `.worktrees/overnight-simplification-2026-04-29` | `auto/overnight-simplification-2026-04-29` | `9257dd0` | 1 | 369/1 | no | no | 0 | unmentioned |
| `.worktrees/p0-track-performance-overlay` | `auto/p0-track-performance-overlay` | `d36c78b` | 0 | 121/10 | no | no | 16 | product-owner checkpoint |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-audio-input-looping-autoslice` | `codex/probe-overnight-broad-probe-2026-05-05-audio-input-looping-autoslice` | `238894d` | 0 | 225/2 | no | no | 8 | broad probe evidence |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-external-control-and-automation` | `codex/probe-overnight-broad-probe-2026-05-05-external-control-and-automation` | `d5d94d5` | 0 | 225/2 | no | no | 8 | broad probe evidence |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-mixer-routing-and-sends` | `codex/probe-overnight-broad-probe-2026-05-05-mixer-routing-and-sends` | `cf3d3c8` | 0 | 225/2 | no | no | 10 | broad probe evidence |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-performance-overrides-pattern-manipulation` | `codex/probe-overnight-broad-probe-2026-05-05-performance-overrides-pattern-manipulation` | `4898a06` | 0 | 225/2 | no | no | 9 | broad probe evidence |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-phrase-scene-song-performance` | `codex/probe-overnight-broad-probe-2026-05-05-phrase-scene-song-performance` | `6ca658e` | 0 | 225/2 | no | no | 8 | broad probe evidence |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-track-editor-foundation` | `codex/probe-overnight-broad-probe-2026-05-05-track-editor-foundation` | `75c29dd` | 0 | 225/2 | no | no | 8 | broad probe evidence |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-audio-input-looping-autoslice` | `codex/probe-ux-feedback-pass-2026-05-06-audio-input-looping-autoslice` | `ce439f7` | 0 | 225/4 | no | no | 8 | UX feedback evidence |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-external-control-and-automation` | `codex/probe-ux-feedback-pass-2026-05-06-external-control-and-automation` | `d5d94d5` | 5 | 225/2 | no | no | 8 | UX feedback evidence |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-mixer-routing-and-sends` | `codex/probe-ux-feedback-pass-2026-05-06-mixer-routing-and-sends` | `a32d912` | 0 | 225/4 | no | no | 10 | UX feedback evidence |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-performance-overrides-pattern-manipulation` | `codex/probe-ux-feedback-pass-2026-05-06-performance-overrides-pattern-manipulation` | `bfc7173` | 0 | 225/4 | no | no | 13 | UX feedback evidence |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-phrase-scene-song-performance` | `codex/probe-ux-feedback-pass-2026-05-06-phrase-scene-song-performance` | `6ca658e` | 5 | 225/2 | no | no | 8 | UX feedback evidence |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-track-editor-foundation` | `codex/probe-ux-feedback-pass-2026-05-06-track-editor-foundation` | `75c29dd` | 5 | 225/2 | no | no | 8 | UX feedback evidence |
| `.worktrees/roadmap-1-clip-history` | `auto/roadmap-1-clip-history` | `ced03ab` | 1 | 319/49 | no | no | 11 | old Clip History reference/salvage branch |
| `.worktrees/roadmap-1-clip-history-v2` | `auto/roadmap-1-clip-history-v2` | `ac809cd` | 5 | 0/3 | yes | no | 0 | active build loop; dirty Phase 3 continuation |
| `.worktrees/roadmap-2-scene-perform` | `auto/roadmap-2-scene-perform` | `d5b4750` | 2 | 9/0 | no | yes | 0 | landed/contained; build loop complete |
| `.worktrees/roadmap-3-step-sequencer` | `auto/roadmap-3-step-sequencer` | `26d858e` | 0 | 0/4 | yes | no | 0 | active build loop; exact review pairing pending |
| `.worktrees/roadmap-5-mixer-busses-ui-finish` | `auto/roadmap-5-mixer-busses-ui-finish` | `1eaebf3` | 0 | 18/0 | no | yes | 0 | landed/contained; build loop complete |
| `.worktrees/roadmap-9-modifier-chain-placement` | `auto/roadmap-9-modifier-chain-placement` | `7520dbd` | 1 | 319/192 | no | no | 55 | stale completed-feature branch |
| `.worktrees/runtime-au-plugin-shutdown` | `codex/runtime-au-plugin-shutdown` | `f5cf677` | 0 | 409/1 | no | no | 4 | unmentioned |
| `.worktrees/runtime-drum-sample-playback` | `codex/runtime-drum-sample-playback` | `f5417ca` | 0 | 409/2 | no | no | 4 | unmentioned |

## Branch-Only Behind Main

These local branches are behind `main` and have no registered worktree in the current `git worktree list` output.

| Branch | HEAD | Behind/Ahead | Contains main | Contained by main | Conflict output | Active mention |
|---|---:|---:|---:|---:|---:|---|
| `backup/roadmap-2-scene-perform-pre-main-integration` | `4ebbc44` | 83/8 | no | no | 13 | backup of Scene Perform pre-main integration |
| `codex/macro-lane-grid-ui` | `07c3d1b` | 438/0 | no | yes | 0 | contained branch-only |
| `codex/max-8-destination-au` | `5f507ea` | 517/10 | no | no | 31 | unmentioned branch-only |
| `codex/tracks-perform-scenes-workspace` | `87061b0` | 83/10 | no | no | 16 | unmentioned branch-only |

This is an observation only; no rebase, merge, cherry-pick, build, review, push, cleanup, inbox message, or request lifecycle action was scheduled.
