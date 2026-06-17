# Worktree Hygiene Observation

- generated: 2026-06-17T06:36Z
- durable copy: `.meta/multipass/state/worktree-hygiene-status.md`
- loop-local copy: `.meta/multipass/runtime/loops/project/observe/worktree-hygiene-status.md`
- cadence evidence:
  `.meta/multipass/runtime/loops/project/observe/2026-06-17T06-36Z-worktree-hygiene-observation.md`
- request:
  `.meta/multipass/runtime/inbox/claimed/2026-06-17T063257805Z-worktree-hygiene-observer-cadence.md`
- scan command: no executable project-local
  `scripts/multi-pass/worktree-hygiene-status.sh` or
  `project/scripts/worktree-hygiene-status.sh` was found. This pass used
  current project-local direct `git` facts plus Foreman Coordinator
  inventory/capacity/recent-run helpers, inbox status, compact state, loop
  registries, and current lifecycle/build-loop summaries.
- local main: `23c2715c3ed7db1f89cde5c7585d18bd4065c50f`
  (`Add perform mode phrase layer capture wireframes`).
- local `main...origin/main` left/right count: `758/0`; no fetch was
  performed.
- root status before this observer write: direct `git status --porcelain`
  counted `318` dirty paths on `main`.
- operation markers: no root merge, rebase, cherry-pick, or revert marker was
  observed by direct `.git` marker checks.
- registered worktrees observed: `31`.
- runtime inventory: active loops `project`, `build/routing-source-mixer-split`,
  and `build/au-discovery-rescan`; locked loops `pm/scenes-in-phrases`,
  `pm/audio-looping`, `build/observability-log-issues`, and
  `build/midi-interfaces`.
- build capacity: `2` ordinary build loops consuming `2/2` slots
  (`routing-source-mixer-split`, `au-discovery-rescan`); `2` locked build loops
  outside ordinary capacity; `0` ordinary slots available; ready and unpromoted
  ready candidates are `none`.
- inbox status: `4` pending, `3` claimed, `686` blocked, and `3772` done.
  `inbox-status.sh` reported no pending requests for active or unknown loops
  and no pending terminal-loop residue.

## Stale Loop Candidates

Active build loops whose loop-local state, integration evidence, or lifecycle
state says the work is already merged, abandoned, or superseded:

| Loop | Status | Worktree | Branch | Commit | Dirty | Contained in main | Signal |
| --- | --- | --- | --- | ---: | ---: | --- | --- |
| none | n/a | n/a | n/a | n/a | n/a | n/a | No active build loop has terminal merged/abandoned/superseded evidence in this scan |

Active/locked build loops not classified as stale cleanup:

| Loop | Status | Worktree | Branch | Commit | Dirty | Contained in main | Signal |
| --- | --- | --- | --- | ---: | ---: | --- | --- |
| `build/routing-source-mixer-split` | active | `.worktrees/routing-source-mixer-split` | `feature/routing-source-mixer-split` | `0f29736` | 0 | no; `1/5` behind/ahead | active routing build; clean output, blocked on capture/window/CoreAudio evidence |
| `build/au-discovery-rescan` | active | `.worktrees/au-discovery-rescan` | `feature/au-discovery-rescan` | `4ce14c7` | 0 | no; `0/2` behind/ahead | active AU build; clean committed checkpoint, project decision holds on local HAL/CoreAudio evidence |
| `build/observability-log-issues` | locked | `.worktrees/roadmap-21-observability-log-issues` | `auto/roadmap-21-observability-log-issues` | `714fdb8` | 7 | no; `204/8` behind/ahead | human scope-correction lock; dirty app/diagnostics partial remains unpaired |
| `build/midi-interfaces` | locked | `.worktrees/roadmap-8-midi-interfaces` | `auto/roadmap-8-midi-interfaces` | `34d5c43` | 0 | no; `291/9` behind/ahead | human hardware-acceptance lock; software output clean but uncontained |

## Safe Cleanup Candidates

Clean registered worktrees whose branch HEAD is already contained in current
local `main`, plus clean contained integration/legacy worktrees:

| Worktree | Branch | Commit | Dirty | Behind/Ahead | Contained in main | Signal |
| --- | --- | ---: | ---: | ---: | --- | --- |
| none | n/a | n/a | n/a | n/a | n/a | No clean registered non-root worktree is currently contained in `main`; contained registered worktrees observed in this scan are dirty |

Contained branch-only candidates with no registered worktree:

| Branch | Commit | Behind/Ahead | Contained in main | Signal |
| --- | ---: | ---: | --- | --- |
| `auto/architecture-engine-controller-carve-up-plan` | `f919040` | `355/0` | yes | contained branch-only |
| `auto/maintenance-addresses-phrase-timeline` | `19301bd` | `354/0` | yes | contained branch-only |
| `auto/maintenance-macro-descriptor-slots` | `0400e65` | `357/0` | yes | contained branch-only |
| `auto/roadmap-1-clip-history-v2` | `4eca9ca` | `300/0` | yes | complete build branch contained |
| `auto/roadmap-10-phrase-features` | `4ae5889` | `228/0` | yes | complete build branch contained |
| `auto/roadmap-11-song-mode-phrase-looping` | `eaa8eea` | `253/0` | yes | complete build branch contained |
| `auto/roadmap-12-drum-parts-as-group` | `472583c` | `236/0` | yes | complete build branch contained |
| `auto/roadmap-13-autoslice-algorithm` | `f93b54c` | `217/0` | yes | complete build branch contained |
| `auto/roadmap-15-note-repeat` | `32a8eae` | `218/0` | yes | complete build branch contained |
| `auto/roadmap-16-step-order` | `83f322b` | `206/0` | yes | complete build branch contained |
| `auto/roadmap-18-track-fill-toggle` | `103f6db` | `256/0` | yes | complete build branch contained |
| `auto/roadmap-24-track-perform-multiselect-latch` | `d0f4fe8` | `259/0` | yes | complete build branch contained |
| `auto/roadmap-3-step-sequencer` | `af176f0` | `292/0` | yes | complete build branch contained |
| `auto/roadmap-5-mixer-busses-ui-finish` | `1eaebf3` | `337/0` | yes | complete build branch contained |
| `auto/roadmap-7-input-audio` | `b00bac9` | `265/0` | yes | complete build branch contained |
| `auto/roadmap-performance-layer-matrix` | `e085403` | `197/0` | yes | lifecycle complete; branch-only now contained |
| `codex/macro-lane-grid-ui` | `07c3d1b` | `757/0` | yes | contained branch-only |
| `codex/slicer-findings-fix` | `f56104a` | `730/0` | yes | contained branch-only |
| `codex/slicer-track-mvp` | `c6a373e` | `731/0` | yes | contained branch-only |
| `fix/*` | various | `183-194/0` | yes | nine contained branch-only fix refs observed |
| `integration/track-fill-toggle-clean-20260604T2204Z` | `36e804a` | `247/0` | yes | contained integration branch-only |

## Dirty Or Uncontained Branches Needing Disposition

Dirty worktrees, active/locked build branches, probe/evidence branches, or
branches not contained in local `main`:

| Worktree | Branch | Commit | Dirty | Behind/Ahead | Contained in main | Signal |
| --- | --- | ---: | ---: | ---: | --- | --- |
| `.` | `main` | `23c2715` | 318 | `0/0` | yes | broad root dirt; no operation marker |
| `.worktrees/routing-source-mixer-split` | `feature/routing-source-mixer-split` | `0f29736` | 0 | `1/5` | no | active routing build; clean exact output but not contained |
| `.worktrees/au-discovery-rescan` | `feature/au-discovery-rescan` | `4ce14c7` | 0 | `0/2` | no | active AU build; clean exact output but not contained |
| `.worktrees/roadmap-21-observability-log-issues` | `auto/roadmap-21-observability-log-issues` | `714fdb8` | 7 | `204/8` | no | locked Observability build; dirty partial is not exact-state reviewed |
| `.worktrees/roadmap-8-midi-interfaces` | `auto/roadmap-8-midi-interfaces` | `34d5c43` | 0 | `291/9` | no | locked MIDI build; hardware acceptance missing |
| `.worktrees/roadmap-2-scene-perform` | `auto/roadmap-2-scene-perform` | `d5b4750` | 2 | `328/0` | yes | complete build branch contained but registered worktree has artifact/evidence residue |
| `.claude/worktrees/macro-lane-grid-ui` | `integration/preserve-macro-lane-grid-ui-main-20260515T2014Z` | `5e0836c` | 2 | `384/0` | yes | dirty contained legacy integration worktree |
| `.worktrees/goal-9-modifier-chain-placement` | `auto/goal-9-modifier-chain-placement` | `f39c4e5` | 1 | `554/7` | no | dirty stale modifier-chain branch |
| `.worktrees/overnight-simplification-2026-04-29` | `auto/overnight-simplification-2026-04-29` | `9257dd0` | 1 | `688/1` | no | dirty legacy worktree |
| `.worktrees/roadmap-1-clip-history` | `auto/roadmap-1-clip-history` | `ced03ab` | 1 | `638/49` | no | old Clip History reference/salvage branch |
| `.worktrees/roadmap-9-modifier-chain-placement` | `auto/roadmap-9-modifier-chain-placement` | `7520dbd` | 1 | `638/192` | no | dirty stale modifier-chain branch |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-external-control-and-automation` | `codex/probe-ux-feedback-pass-2026-05-06-external-control-and-automation` | `d5d94d5` | 5 | `544/2` | no | dirty UX feedback evidence worktree |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-phrase-scene-song-performance` | `codex/probe-ux-feedback-pass-2026-05-06-phrase-scene-song-performance` | `6ca658e` | 5 | `544/2` | no | dirty UX feedback evidence worktree |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-track-editor-foundation` | `codex/probe-ux-feedback-pass-2026-05-06-track-editor-foundation` | `75c29dd` | 5 | `544/2` | no | dirty UX feedback evidence worktree |
| `.claude/worktrees/live-perform-fill-overlay` | `codex/live-perform-fill-overlay` | `a08bc09` | 0 | `794/3` | no | clean uncontained legacy branch |
| `.claude/worktrees/live-perform-performance-mechanics-plan` | `codex/live-perform-performance-mechanics-plan` | `4757fbe` | 0 | `783/1` | no | clean uncontained legacy branch |
| `.claude/worktrees/master-bus-scenes` | `codex/master-bus-scenes` | `8b367b2` | 0 | `770/10` | no | clean uncontained legacy branch |
| `.claude/worktrees/master-bus-scenes-plan` | `codex/master-bus-scenes-plan` | `03f71df` | 0 | `783/1` | no | clean uncontained legacy branch |
| `.claude/worktrees/progression-chord-generator` | `codex/progression-chord-generator` | `059c174` | 0 | `738/1` | no | clean uncontained legacy branch |
| `.worktrees/p0-track-performance-overlay` | `auto/p0-track-performance-overlay` | `d36c78b` | 0 | `440/10` | no | historical product-owner checkpoint branch |
| `.worktrees/probe-overnight-broad-probe-2026-05-05-*` | `codex/probe-overnight-broad-probe-2026-05-05-*` | various | 0 | `544/2` | no | six broad probe evidence worktrees |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-audio-input-looping-autoslice` | `codex/probe-ux-feedback-pass-2026-05-06-audio-input-looping-autoslice` | `ce439f7` | 0 | `544/4` | no | clean UX feedback evidence worktree |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-mixer-routing-and-sends` | `codex/probe-ux-feedback-pass-2026-05-06-mixer-routing-and-sends` | `a32d912` | 0 | `544/4` | no | clean UX feedback evidence worktree |
| `.worktrees/probe-ux-feedback-pass-2026-05-06-performance-overrides-pattern-manipulation` | `codex/probe-ux-feedback-pass-2026-05-06-performance-overrides-pattern-manipulation` | `bfc7173` | 0 | `544/4` | no | clean UX feedback evidence worktree |
| `.worktrees/runtime-au-plugin-shutdown` | `codex/runtime-au-plugin-shutdown` | `f5cf677` | 0 | `728/1` | no | clean uncontained runtime branch |
| `.worktrees/runtime-drum-sample-playback` | `codex/runtime-drum-sample-playback` | `f5417ca` | 0 | `728/2` | no | clean uncontained runtime branch |

Uncontained branch-only candidates with no registered worktree:

| Branch | Commit | Behind/Ahead | Contained in main | Signal |
| --- | ---: | ---: | --- | --- |
| `backup/roadmap-2-scene-perform-pre-main-integration` | `4ebbc44` | `402/8` | no | Scene Perform backup branch |
| `codex/max-8-destination-au` | `5f507ea` | `836/10` | no | uncontained branch-only |
| `codex/tracks-perform-scenes-workspace` | `87061b0` | `402/10` | no | uncontained branch-only |

## Loop Registry Entries Still Marking Completed Work Active

| Registry | Status | Worktree | Branch | Signal |
| --- | --- | --- | --- | --- |
| `.meta/multipass/config/loops/pm/autoslice-algorithm.yaml` | active | `.` | `main` | lifecycle/readiness says matching `build/autoslice-algorithm` is complete and branch is contained in `main` |
| `.meta/multipass/config/loops/pm/note-repeat.yaml` | active | `.` | `main` | lifecycle/readiness says matching `build/note-repeat` is complete and branch is contained in `main` |
| `.meta/multipass/config/loops/pm/step-order.yaml` | active | `.` | `main` | lifecycle/readiness says matching `build/step-order` is complete and branch is contained in `main` |

Registry hygiene signals that may need orientation before cleanup/disposition:

| Registry | Status | Worktree | Branch | Signal |
| --- | --- | --- | --- | --- |
| `.meta/multipass/config/loops/pm/observability-log-issues.yaml` | active | `.` | `main` | PM handoff consumed by locked `build/observability-log-issues`; not a cleanup target by itself |
| `.meta/multipass/config/loops/build/routing-source-mixer-split.yaml` | active | `.worktrees/routing-source-mixer-split` | `feature/routing-source-mixer-split` | active clean uncontained build output; capture evidence blocked |
| `.meta/multipass/config/loops/build/au-discovery-rescan.yaml` | active | `.worktrees/au-discovery-rescan` | `feature/au-discovery-rescan` | active clean uncontained build output; local HAL/CoreAudio evidence hold |
| `.meta/multipass/config/loops/build/observability-log-issues.yaml` | locked | `.worktrees/roadmap-21-observability-log-issues` | `auto/roadmap-21-observability-log-issues` | locked scope-correction build; dirty, diverged, uncontained |
| `.meta/multipass/config/loops/build/midi-interfaces.yaml` | locked | `.worktrees/roadmap-8-midi-interfaces` | `auto/roadmap-8-midi-interfaces` | locked hardware-acceptance build; clean, diverged, uncontained |
| `.meta/multipass/config/loops/build/scene-perform.yaml` | complete | `.worktrees/roadmap-2-scene-perform` | `auto/roadmap-2-scene-perform` | complete contained build branch still has dirty registered worktree |
| `.meta/multipass/config/loops/pm/song-mode-phrase-looping.yaml` | complete | n/a | n/a | lifecycle reports terminal-loop open-message residue: 2 pending |
| `.meta/multipass/config/loops/pm/track-fill-toggle.yaml` | complete | n/a | n/a | lifecycle reports terminal-loop open-message residue: 2 pending |

## Observer Notes

- Hygiene facts changed enough that orientation should consume this refresh
  before cleanup or disposition actions are chosen: `build/au-discovery-rescan`
  is now clean at `4ce14c7` rather than the older `80be3f5` output recorded in
  the prior hygiene snapshot, lifecycle status was refreshed at
  `2026-06-17T06:08:40.996Z`, and runtime inbox counts changed.
- No clean registered non-root worktree is currently both present and contained
  in `main`; many completed build refs are branch-only contained candidates.
- Root `main` remains broad dirty/local-only. Whole-app, merge, cleanup, and
  integration claims need exact checkout and dirty-state evidence.
- Direct `git diff --check` passed for root, Routing Source/Mixer, AU
  Discovery/Rescan, Observability, and MIDI worktrees.
- Coordinator CLIs still emit Ruby `executable-hooks` / `gem-wrappers`
  extension warnings before useful output.
- This is observation only. No worktree, branch, loop record, inbox lifecycle
  state, merge, rebase, cleanup, product-code edit, PM/build scheduling,
  process-fixer action, review scheduling, or product-owner request was
  changed or scheduled.

## Checks Run

- Read the claimed request, central worktree-hygiene observer prompt/actions,
  project read-first context, current-work, feature-readiness, holistic status,
  decision log, loop-lifecycle status, active/locked build-loop summaries, and
  current loop registries.
- Ran Foreman Coordinator `inventory.ts`, `build-capacity.ts`, and
  `recent-runs.ts --limit 25`.
- Ran `scripts/multi-pass/inbox-status.sh`.
- Checked project-local hygiene script availability; no executable dedicated
  hygiene status script was present.
- Ran direct `git worktree list --porcelain`.
- Ran direct root/worktree `git status --porcelain`, `git rev-parse`,
  `git log -1 --oneline`, `git rev-list --left-right --count main...<branch>`,
  and branch `git merge-base --is-ancestor` containment checks.
- Ran branch-only containment checks for local branches without registered
  worktrees.
- Checked root merge/rebase/cherry-pick/revert marker files.
- Ran direct `git diff --check` for root, Routing Source/Mixer, AU
  Discovery/Rescan, Observability, and MIDI worktrees.
- No product build, test suite, visual capture, promotion, inbox routing,
  request lifecycle move, merge, rebase, cleanup, product-code edit, PM
  artifact action, build action, process-fixer action, review scheduling, or
  product-owner question was performed.
