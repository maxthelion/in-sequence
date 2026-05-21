# Worktree Hygiene Observation

- generated: 2026-05-21T06:38:22Z
- loop-local copy: `.meta/multipass/loops/project/observe/worktree-hygiene-status.md`
- request: `.meta/multipass/inbox/claimed/2026-05-21T05-56-33-791Z-worktree-hygiene-observer-cadence.md`
- scan command: no project-local `worktree-hygiene-status` script was found; this pass used `scripts/multi-pass/evidence-worktrees.sh`, `git worktree list --porcelain`, direct dirty counts, direct `main...HEAD` ahead/behind checks, direct ancestry checks, loop manifests, merge/rebase/work observations, and recent builder/decider summaries.
- local main: `cdf6982`

## Stale Loop Candidates

None observed. Active loop manifests are `project` and `build/mixer-busses`.
The active build loop is not marked merged, abandoned, or superseded by its
loop-local manifest or durable build-loop summary.

## Safe Cleanup Candidates

Clean worktrees whose branch HEAD is already contained in local `main`.

| Worktree | Branch | Commit | Dirty | Contained in main | Signal |
|---|---|---:|---:|---:|---|
| `.claude/worktrees/slicer-findings-fix` | `codex/slicer-findings-fix` | `f56104a` | 0 | yes | contained branch |
| `.claude/worktrees/slicer-track-mvp` | `codex/slicer-track-mvp` | `c6a373e` | 0 | yes | contained branch |
| `.worktrees/architecture-engine-controller-carve-up-plan` | `auto/architecture-engine-controller-carve-up-plan` | `f919040` | 0 | yes | contained branch |
| `.worktrees/integration-modifier-chain-7520dbd` | `integration/modifier-chain-7520dbd` | `783eb80` | 0 | yes | contained integration branch |
| `.worktrees/maintenance-addresses-phrase-timeline` | `auto/maintenance-addresses-phrase-timeline` | `19301bd` | 0 | yes | contained branch |
| `.worktrees/maintenance-macro-descriptor-slots` | `auto/maintenance-macro-descriptor-slots` | `0400e65` | 0 | yes | contained branch |
| `.worktrees/roadmap-4-mixer-main-out` | `auto/roadmap-4-mixer-main-out` | `5e0836c` | 0 | yes | merged roadmap branch |
| `.worktrees/roadmap-5-mixer-busses` | `auto/roadmap-5-mixer-busses` | `4ddb544` | 0 | yes | merged roadmap branch |
| `.worktrees/roadmap-5-mixer-busses-phase-2` | `auto/roadmap-5-mixer-busses-phase-2` | `13c01ee` | 0 | yes | merged roadmap branch |
| `.worktrees/roadmap-6-send-effects` | `auto/roadmap-6-send-effects` | `72171d7` | 0 | yes | merged roadmap branch |

## Dirty Or Uncontained Branches Needing Disposition

Dirty worktrees, active build branches, PM-ready branches, checkpoint branches,
probe/evidence branches, or branches not contained in local `main`.

| Worktree | Branch | Commit | Dirty | Behind/Ahead | Contained in main | Signal |
|---|---|---:|---:|---:|---:|---|
| `.` | `main` | `cdf6982` | 2 | 0/0 | yes | root dirty: `docs/multi-pass-coordinator/state/runtime-problems.md`; this observer's durable status copy |
| `.worktrees/roadmap-5-mixer-busses-ui-finish` | `auto/roadmap-5-mixer-busses-ui-finish` | `6622bc9` | 0 | 2/1 | no | active build loop; builder completed, review gates not observed yet |
| `.claude/worktrees/macro-lane-grid-ui` | `integration/preserve-macro-lane-grid-ui-main-20260515T2014Z` | `5e0836c` | 2 | 44/0 | yes | dirty contained worktree |
| `.worktrees/goal-9-modifier-chain-placement` | `auto/goal-9-modifier-chain-placement` | `f39c4e5` | 1 | 214/7 | no | stale completed-feature branch per rebase/merge observations |
| `.worktrees/overnight-simplification-2026-04-29` | `auto/overnight-simplification-2026-04-29` | `9257dd0` | 1 | 348/1 | no | dirty legacy worktree |
| `.worktrees/p0-track-performance-overlay` | `auto/p0-track-performance-overlay` | `d36c78b` | 0 | 100/10 | no | legacy current-work says checkpoint-ready, awaiting product-owner acceptance |
| `.worktrees/roadmap-1-clip-history` | `auto/roadmap-1-clip-history` | `ced03ab` | 1 | 298/49 | no | PM-ambiguous; dirty temp state |
| `.worktrees/roadmap-2-scene-perform` | `auto/roadmap-2-scene-perform` | `4ebbc44` | 0 | 62/8 | no | PM-ready, not active build loop |
| `.worktrees/roadmap-3-step-sequencer` | `auto/roadmap-3-step-sequencer` | `3e77689` | 0 | 62/8 | no | PM-ready, not active build loop |
| `.worktrees/roadmap-9-modifier-chain-placement` | `auto/roadmap-9-modifier-chain-placement` | `7520dbd` | 1 | 298/192 | no | stale completed-feature branch per rebase/merge observations |
| `.claude/worktrees/live-perform-fill-overlay` | `codex/live-perform-fill-overlay` | `a08bc09` | 0 | 454/3 | no | unmentioned legacy branch |
| `.claude/worktrees/live-perform-performance-mechanics-plan` | `codex/live-perform-performance-mechanics-plan` | `4757fbe` | 0 | 443/1 | no | unmentioned legacy branch |
| `.claude/worktrees/master-bus-scenes` | `codex/master-bus-scenes` | `8b367b2` | 0 | 430/10 | no | unmentioned legacy branch |
| `.claude/worktrees/master-bus-scenes-plan` | `codex/master-bus-scenes-plan` | `03f71df` | 0 | 443/1 | no | unmentioned legacy branch |
| `.claude/worktrees/progression-chord-generator` | `codex/progression-chord-generator` | `059c174` | 0 | 398/1 | no | unmentioned legacy branch |
| `.worktrees/runtime-au-plugin-shutdown` | `codex/runtime-au-plugin-shutdown` | `f5cf677` | 0 | 388/1 | no | unmentioned runtime branch |
| `.worktrees/runtime-drum-sample-playback` | `codex/runtime-drum-sample-playback` | `f5417ca` | 0 | 388/2 | no | unmentioned runtime branch |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-audio-input-looping-autoslice` | `codex/probe-overnight-broad-probe-2026-05-05-audio-input-looping-autoslice` | `238894d` | 0 | 204/2 | no | broad probe evidence branch |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-external-control-and-automation` | `codex/probe-overnight-broad-probe-2026-05-05-external-control-and-automation` | `d5d94d5` | 0 | 204/2 | no | broad probe evidence branch |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-mixer-routing-and-sends` | `codex/probe-overnight-broad-probe-2026-05-05-mixer-routing-and-sends` | `cf3d3c8` | 0 | 204/2 | no | broad probe evidence branch |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-performance-overrides-pattern-manipulation` | `codex/probe-overnight-broad-probe-2026-05-05-performance-overrides-pattern-manipulation` | `4898a06` | 0 | 204/2 | no | broad probe evidence branch |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-phrase-scene-song-performance` | `codex/probe-overnight-broad-probe-2026-05-05-phrase-scene-song-performance` | `6ca658e` | 0 | 204/2 | no | broad probe evidence branch |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-track-editor-foundation` | `codex/probe-overnight-broad-probe-2026-05-05-track-editor-foundation` | `75c29dd` | 0 | 204/2 | no | broad probe evidence branch |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-audio-input-looping-autoslice` | `codex/probe-ux-feedback-pass-2026-05-06-audio-input-looping-autoslice` | `ce439f7` | 0 | 204/4 | no | UX feedback evidence branch |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-external-control-and-automation` | `codex/probe-ux-feedback-pass-2026-05-06-external-control-and-automation` | `d5d94d5` | 5 | 204/2 | no | dirty UX feedback evidence branch |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-mixer-routing-and-sends` | `codex/probe-ux-feedback-pass-2026-05-06-mixer-routing-and-sends` | `a32d912` | 0 | 204/4 | no | UX feedback evidence branch |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-performance-overrides-pattern-manipulation` | `codex/probe-ux-feedback-pass-2026-05-06-performance-overrides-pattern-manipulation` | `bfc7173` | 0 | 204/4 | no | UX feedback evidence branch |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-phrase-scene-song-performance` | `codex/probe-ux-feedback-pass-2026-05-06-phrase-scene-song-performance` | `6ca658e` | 5 | 204/2 | no | dirty UX feedback evidence branch |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-track-editor-foundation` | `codex/probe-ux-feedback-pass-2026-05-06-track-editor-foundation` | `75c29dd` | 5 | 204/2 | no | dirty UX feedback evidence branch |

## Loop Registry Entries Still Marking Completed Work Active

None observed.

| Registry | Status | Worktree | Branch | Signal |
|---|---|---|---|---|
| `.meta/multipass/loops/build/mixer-busses/manifest.yaml` | active | `.worktrees/roadmap-5-mixer-busses-ui-finish` | `auto/roadmap-5-mixer-busses-ui-finish` | builder completed commit `6622bc9`; loop still legitimately active pending review/evidence gates |
| `docs/multi-pass-coordinator/loops/build/mixer-busses.yaml` | active | `.worktrees/roadmap-5-mixer-busses-ui-finish` | `auto/roadmap-5-mixer-busses-ui-finish` | mirrors active build loop |

## Observer Notes

- Hygiene facts changed since the previous pass: local `main` is now
  `cdf6982`; the active Mixer Busses worktree is clean at `6622bc9`, not
  contained in `main`, and builder completion exists; root `main` is dirty
  with `docs/multi-pass-coordinator/state/runtime-problems.md` plus this observer's
  durable status copy.
- Cleanup-capable follow-up should target the decider/integrator path only
  after orienter interprets these facts.
- This is observation only. No worktree, branch, loop record, inbox lifecycle
  state, merge, rebase, or cleanup action was changed.
