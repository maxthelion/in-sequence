# Worktree Hygiene Observation

- generated: 2026-07-06T10:52Z
- durable copy: `.meta/multipass/state/worktree-hygiene-status.md`
- loop-local copy: `.meta/multipass/runtime/loops/project/observe/worktree-hygiene-status.md`
- cadence evidence:
  `.meta/multipass/runtime/loops/project/observe/2026-07-06T10-52Z-worktree-hygiene-observation.md`
- request:
  `.meta/multipass/runtime/inbox/claimed/2026-07-04T171510660Z-worktree-hygiene-observer-cadence.md`
- scan command: no executable project-local
  `scripts/multi-pass/worktree-hygiene-status.sh` or
  `project/scripts/worktree-hygiene-status.sh` was found. This pass used direct
  `git` facts, Foreman Coordinator inventory/build-capacity, inbox status,
  compact lifecycle/merge/readiness state, and loop registry files.
- local main: `1b34d6ecfe62d913be938a7330c9f541cebc8f0e`
  (`Mark July 5 UI feedback batch resolved`).
- local `main...origin/main` status: `ahead 9`; no fetch was performed.
- root status before this observer write: direct `git status --porcelain`
  counted `357` dirty paths on `main`.
- operation markers: no root merge, rebase, cherry-pick, or revert marker was
  observed by direct `.git` marker checks.
- registered worktrees observed: `10`.
- runtime inventory: active loops `project`,
  `pm/july-4-phrase-layers-global-apply`,
  `pm/track-phrase-perform-interaction-prep`, `build/au-runtime-safety`, and
  `build/drum-kit-matrix-sound-prep`; locked loops `pm/scenes-in-phrases`,
  `pm/audio-looping`, `build/observability-log-issues`, and
  `build/midi-interfaces`.
- build capacity: `2` ordinary build loops consuming `2/2` slots
  (`au-runtime-safety`, `drum-kit-matrix-sound-prep`); `2` locked build loops
  outside ordinary capacity; `0` ordinary slots available; ready and
  unpromoted ready candidates are `none`.
- inbox status: `19` pending, `3` claimed, `714` blocked, and `4997` done.
  `inbox-status.sh` reported no pending requests for terminal build loops.

## Stale Loop Candidates

Active build loops whose loop-local state, integration evidence, or lifecycle
state says the work is already merged, abandoned, or superseded:

| Loop | Status | Worktree | Branch | Commit | Dirty | Contained in main | Signal |
| --- | --- | --- | --- | ---: | ---: | --- | --- |
| none | n/a | n/a | n/a | n/a | n/a | n/a | No active build loop has terminal merged/abandoned/superseded evidence in this scan |

Active/locked build loops not classified as stale cleanup:

| Loop | Status | Worktree | Branch | Commit | Dirty | Contained in main | Signal |
| --- | --- | --- | --- | ---: | ---: | --- | --- |
| `build/au-runtime-safety` | active | `.worktrees/au-runtime-safety` | `feature/au-runtime-safety` | `ead7586f` | 259 | no; `11/3` behind/ahead | active AU runtime safety build; dirty worktree, blocked work remains in lifecycle |
| `build/drum-kit-matrix-sound-prep` | active | `.worktrees/drum-kit-matrix-sound-prep` | `feature/drum-kit-matrix-sound-prep` | `9c1744ba` | 0 | yes; `1/0` behind/ahead | active build loop, but branch HEAD is already contained in local `main`; testing review pending |
| `build/observability-log-issues` | locked | `.worktrees/roadmap-21-observability-log-issues` | `auto/roadmap-21-observability-log-issues` | `1934ef63` | missing worktree | no; branch-only `671/9` in merge status | human scope-correction lock; configured worktree is missing |
| `build/midi-interfaces` | locked | `.worktrees/roadmap-8-midi-interfaces` | `auto/roadmap-8-midi-interfaces` | `34d5c43c` | 0 | no; `761/9` behind/ahead | human hardware-acceptance lock; clean registered worktree, uncontained |

## Safe Cleanup Candidates

Clean registered worktrees whose branch HEAD is already contained in current
local `main`, plus clean contained integration/legacy worktrees:

| Worktree | Branch | Commit | Dirty | Behind/Ahead | Contained in main | Signal |
| --- | --- | ---: | ---: | ---: | --- | --- |
| `.worktrees/drum-kit-matrix-sound-prep` | `feature/drum-kit-matrix-sound-prep` | `9c1744ba` | 0 | `1/0` | yes | active build worktree clean and contained, but loop still active with testing review pending |

Contained branch-only candidates with no registered worktree:

| Branch | Commit | Behind/Ahead | Contained in main | Signal |
| --- | ---: | ---: | --- | --- |
| `auto/architecture-engine-controller-carve-up-plan` | `f919040d` | `825/0` | yes | contained branch-only |
| `auto/maintenance-addresses-phrase-timeline` | `19301bd0` | `824/0` | yes | contained branch-only |
| `auto/maintenance-macro-descriptor-slots` | `0400e650` | `827/0` | yes | contained branch-only |
| `auto/roadmap-1-clip-history-v2` | `4eca9ca0` | `770/0` | yes | complete build branch contained |
| `auto/roadmap-10-phrase-features` | `4ae58898` | `698/0` | yes | complete build branch contained |
| `auto/roadmap-11-song-mode-phrase-looping` | `eaa8eea4` | `723/0` | yes | complete build branch contained |
| `auto/roadmap-12-drum-parts-as-group` | `472583cf` | `706/0` | yes | complete build branch contained |
| `auto/roadmap-13-autoslice-algorithm` | `f93b54c8` | `687/0` | yes | complete build branch contained |
| `auto/roadmap-15-note-repeat` | `32a8eae0` | `688/0` | yes | complete build branch contained |
| `auto/roadmap-16-step-order` | `83f322b1` | `676/0` | yes | complete build branch contained |
| `auto/roadmap-18-track-fill-toggle` | `103f6dbe` | `726/0` | yes | complete build branch contained |
| `auto/roadmap-2-scene-perform` | `d5b47500` | `798/0` | yes | complete build branch contained |
| `auto/roadmap-24-track-perform-multiselect-latch` | `d0f4fe8b` | `729/0` | yes | complete build branch contained |
| `auto/roadmap-3-step-sequencer` | `af176f0b` | `762/0` | yes | complete build branch contained |
| `auto/roadmap-5-mixer-busses-ui-finish` | `1eaebf3d` | `807/0` | yes | complete build branch contained |
| `auto/roadmap-7-input-audio` | `b00bac98` | `735/0` | yes | complete build branch contained |
| `auto/roadmap-perform-mode-phrase-layer-capture` | `cbae6a26` | `436/0` | yes | complete build branch contained |
| `auto/roadmap-performance-layer-matrix` | `e0854033` | `667/0` | yes | complete build branch contained |
| `auto/roadmap-track-view-ia` | `092a93c1` | `386/0` | yes | contained branch-only |
| `bug-batch-20260623` | `c0d00aa3` | `279/0` | yes | contained branch-only |
| `codex/july-5-ui-feedback-batch` | `1b34d6ec` | `0/0` | yes | identical to local `main` |
| `codex/phrase-layer-modes` | `b58f90b9` | `288/0` | yes | contained branch-only |
| `fix/*` | various | `52-664/0` | yes | thirteen contained branch-only fix refs observed |
| `integrate/routing-source-mixer-split` | `54b265e1` | `202/0` | yes | contained integration branch-only |
| `integration/track-fill-toggle-clean-20260604T2204Z` | `36e804a6` | `717/0` | yes | contained integration branch-only |
| `ux/canon-sweep-2` | `61d254c5` | `57/0` | yes | contained branch-only |

## Dirty Or Uncontained Branches Needing Disposition

Dirty worktrees, active/locked build branches, probe/evidence branches, or
branches not contained in local `main`:

| Worktree | Branch | Commit | Dirty | Behind/Ahead | Contained in main | Signal |
| --- | --- | ---: | ---: | ---: | --- | --- |
| `.` | `main` | `1b34d6ec` | 357 | `0/0` | yes | broad root coordination/evidence/visual-review dirt; no operation marker |
| `.worktrees/au-runtime-safety` | `feature/au-runtime-safety` | `ead7586f` | 259 | `11/3` | no | active AU runtime safety build; dirty and uncontained |
| `.worktrees/drum-kit-matrix-sound-prep` | `feature/drum-kit-matrix-sound-prep` | `9c1744ba` | 0 | `1/0` | yes | active clean build worktree already contained in local `main`; pending testing-review evidence |
| `.worktrees/mixer-strip-followup` | `feature/mixer-strip-followup` | `04a0e071` | 259 | `3/0` | yes | complete loop by registry; registered worktree is dirty though contained |
| `.worktrees/track-phrase-perform-mini-cells` | `feature/track-phrase-perform-mini-cells` | `9c1744ba` | 259 | `1/0` | yes | integration evidence says branch merged/preserved; registered worktree dirty though contained |
| `.worktrees/drum-timing` | `fix/record-arm-crash-v2` | `fd71effc` | 1 | `36/0` | yes | contained registered worktree with untracked residue |
| `.worktrees/track-view-tabs` | `feat/generator-pitch-cleanup` | `50b731e5` | 1 | `51/0` | yes | contained registered worktree with untracked residue |
| `.worktrees/ux-batch` | `fix/slicer-polish` | `849eda89` | 2 | `51/0` | yes | contained registered worktree with dirty Xcode project and untracked residue |
| `.worktrees/ws1-fill-mode` | `fix/audio-idle-cleanup` | `575c67c7` | 1 | `54/0` | yes | contained registered worktree with untracked residue |
| `.worktrees/roadmap-8-midi-interfaces` | `auto/roadmap-8-midi-interfaces` | `34d5c43c` | 0 | `761/9` | no | locked MIDI build; clean but uncontained |

Uncontained branch-only candidates with no registered worktree:

| Branch | Commit | Behind/Ahead | Contained in main | Signal |
| --- | ---: | ---: | --- | --- |
| `audio-routing-cleanup` | `d3b1f890` | n/a | no | uncontained branch-only |
| `auto/goal-9-modifier-chain-placement` | `f39c4e59` | n/a | no | uncontained branch-only |
| `auto/overnight-simplification-2026-04-29` | `9257dd06` | n/a | no | uncontained branch-only |
| `auto/p0-track-performance-overlay` | `d36c78b4` | n/a | no | historical product-owner checkpoint branch |
| `auto/roadmap-1-clip-history` | `ced03ab7` | n/a | no | old Clip History reference/salvage branch |
| `auto/roadmap-21-observability-log-issues` | `1934ef63` | n/a | no | locked Observability branch; configured worktree missing |
| `auto/roadmap-9-modifier-chain-placement` | `7520dbd4` | n/a | no | stale modifier-chain branch |
| `backup/roadmap-2-scene-perform-pre-main-integration` | `4ebbc448` | n/a | no | Scene Perform backup branch |
| `codex/probe-*` | various | n/a | no | historical probe/evidence branches |
| `codex/runtime-*` | various | n/a | no | historical runtime branches |
| `feature/au-discovery-rescan` | `754e210f` | n/a | no | completed/superseded lane preserved branch; configured worktree missing |
| `feature/routing-source-mixer-split` | `3938b6bc` | n/a | no | completed/superseded lane preserved branch; configured worktree missing |
| `feature/*` | various | n/a | no | other uncontained branch-only feature refs observed |
| `work/observability-harvest` | `0a45a1d5` | n/a | no | uncontained branch-only |

## Loop Registry Entries Still Marking Completed Work Active

| Registry | Status | Worktree | Branch | Signal |
| --- | --- | --- | --- | --- |
| `.meta/multipass/config/loops/pm/autoslice-algorithm.yaml` | active | `.` | `main` | lifecycle/readiness says matching `build/autoslice-algorithm` is complete and branch is contained in `main` |
| `.meta/multipass/config/loops/pm/note-repeat.yaml` | active | `.` | `main` | lifecycle/readiness says matching `build/note-repeat` is complete and branch is contained in `main` |
| `.meta/multipass/config/loops/pm/step-order.yaml` | active | `.` | `main` | lifecycle/readiness says matching `build/step-order` is complete and branch is contained in `main` |

Registry hygiene signals that may need orientation before cleanup/disposition:

| Registry | Status | Worktree | Branch | Signal |
| --- | --- | --- | --- | --- |
| `.meta/multipass/config/loops/build/au-runtime-safety.yaml` | active | `.worktrees/au-runtime-safety` | `feature/au-runtime-safety` | active dirty uncontained build worktree |
| `.meta/multipass/config/loops/build/drum-kit-matrix-sound-prep.yaml` | active | `.worktrees/drum-kit-matrix-sound-prep` | `feature/drum-kit-matrix-sound-prep` | active loop branch is already contained in `main`; testing review pending |
| `.meta/multipass/config/loops/build/mixer-strip-followup.yaml` | complete | `.worktrees/mixer-strip-followup` | `feature/mixer-strip-followup` | complete contained build branch still has dirty registered worktree |
| `.meta/multipass/config/loops/build/observability-log-issues.yaml` | locked | `.worktrees/roadmap-21-observability-log-issues` | `auto/roadmap-21-observability-log-issues` | locked scope-correction build; configured worktree missing, branch uncontained |
| `.meta/multipass/config/loops/build/midi-interfaces.yaml` | locked | `.worktrees/roadmap-8-midi-interfaces` | `auto/roadmap-8-midi-interfaces` | locked hardware-acceptance build; clean, diverged, uncontained |
| `.meta/multipass/config/loops/pm/song-mode-phrase-looping.yaml` | complete | n/a | n/a | lifecycle reports terminal-loop open-message residue: 2 pending |
| `.meta/multipass/config/loops/pm/track-fill-toggle.yaml` | complete | n/a | n/a | lifecycle reports terminal-loop open-message residue: 2 pending |

## Observer Notes

- Hygiene facts changed enough that orientation should consume this refresh
  before cleanup or disposition actions are chosen: the registered worktree set
  is now `10` rather than the prior `31`, active ordinary build loops are now
  `au-runtime-safety` and `drum-kit-matrix-sound-prep`, and
  `feature/track-phrase-perform-mini-cells` is integrated into local `main` but
  still has a registered dirty worktree.
- `build/drum-kit-matrix-sound-prep` is an active loop whose branch HEAD is
  contained in `main`; this is a fact, not a cleanup recommendation, because
  the loop still has pending testing-review evidence.
- Several contained registered worktrees are dirty only by count in this scan;
  disposition should inspect exact paths before cleanup.
- Root `main` remains broad dirty/local-only. Whole-app, merge, cleanup, and
  integration claims need exact checkout and dirty-state evidence.
- Coordinator CLIs still emit Ruby `executable-hooks` / `gem-wrappers`
  extension warnings before useful output.
- This is observation only. No worktree, branch, loop record, inbox lifecycle
  state, merge, rebase, cleanup, product-code edit, PM/build scheduling,
  process-fixer action, review scheduling, or product-owner request was changed
  or scheduled.

## Checks Run

- Read the claimed request, central worktree-hygiene observer prompt/actions,
  project read-first context, prior hygiene status, compact lifecycle, merge,
  and readiness state, and loop registries.
- Ran Foreman Coordinator `inventory.ts` and `build-capacity.ts`.
- Ran `scripts/multi-pass/inbox-status.sh`.
- Checked project-local hygiene script availability; no executable dedicated
  hygiene status script was present.
- Ran direct `git worktree list --porcelain`.
- Ran direct root/worktree `git status --porcelain`, `git rev-parse`,
  `git rev-list --left-right --count main...<branch>`, and branch
  `git merge-base --is-ancestor` containment checks.
- Ran branch-only containment checks for local branches without registered
  worktrees.
- Checked root merge/rebase/cherry-pick/revert marker files.
- Ran `git diff --check` for the hygiene status artifacts before editing.
- No product build, test suite, visual capture, promotion, inbox routing,
  request lifecycle move, merge, rebase, cleanup, product-code edit, PM
  artifact action, build action, process-fixer action, review scheduling, or
  product-owner question was performed.
