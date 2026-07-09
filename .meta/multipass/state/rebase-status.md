# Rebase Status Observation

- generated: 2026-07-06T10:42Z
- loop-local copy: `.meta/multipass/runtime/loops/project/observe/rebase-status.md`
- cadence evidence:
  `.meta/multipass/runtime/loops/project/observe/2026-07-06T10-42Z-rebase-status-observation.md`
- request:
  `.meta/multipass/runtime/inbox/claimed/2026-07-04T171510650Z-rebase-observer-cadence.md`
- scope: observation only; no inbox messages, request lifecycle moves, rebase,
  merge, cherry-pick, build, review, push, cleanup, worktree deletion, product
  edits, process repair, or product-owner question performed.
- scan command: no executable project-local `scripts/multi-pass/rebase-status.sh`
  or `project/scripts/rebase-status.sh` is present.
- network: no fetch was performed. Local `origin/main` was used as-is.

## Observation

- Local `main` is `9c1744ba2247b9613909194710d9f1ba02da7ed7`
  (`Route pattern mini-cells through quantise policy`).
- Local `main` is `0` behind / `8` ahead of local `origin/main`.
- The root checkout is not on branch `main`; it is on
  `codex/july-5-ui-feedback-batch` at the same commit as local `main`.
- Root worktree dirty count before this artifact was written was `360` paths.
  The dirty set includes coordination state, many deleted local visual-review
  capture files under `.meta/multipass/visual-review/codex/july4-ui-feedback-batch/`,
  product/UI files, roadmap docs, bug reports, and visual-scenario scripts.
- Root `git diff --check` reported one whitespace issue:
  `.meta/multipass/state/loop-lifecycle-status.md:49: new blank line at EOF`.
  `git diff --cached --check` produced no output. No rebase, merge,
  cherry-pick, or revert marker was observed in `.git`.
- Foreman inventory reports active loops: project; PM loops
  `pm/july-4-phrase-layers-global-apply` and
  `pm/track-phrase-perform-interaction-prep`; build loops
  `build/au-runtime-safety` and `build/drum-kit-matrix-sound-prep`; locked PM
  loops `pm/scenes-in-phrases` and `pm/audio-looping`; locked build loops
  `build/observability-log-issues` and `build/midi-interfaces`.
- Coordinator CLI output still contains Ruby `executable-hooks` /
  `gem-wrappers` warning noise before useful output.

## Freshness Summary

- Registered worktrees scanned: `10`. Behind current `main`: `7`. Dirty:
  `8`. Worktrees containing current `main`: root
  `codex/july-5-ui-feedback-batch`, `.worktrees/drum-kit-matrix-sound-prep`,
  and `.worktrees/track-phrase-perform-mini-cells`.
- Local branches scanned: `100` including `main`. Non-main branches scanned:
  `99`. Non-main branches behind current `main`: `96`. Non-main branches that
  contain current `main`: `3`. Non-main branches not contained by current
  `main`: `36`.
- Facts changed enough from the previous durable rebase observation to warrant
  orientation consumption. Material changes: local `main` advanced from
  `23c2715c` to `9c1744ba`; the root checkout moved from `main` to
  `codex/july-5-ui-feedback-batch`; active build work now includes
  `feature/au-runtime-safety` and `feature/drum-kit-matrix-sound-prep`; the
  prior Routing/AU discovery worktrees are no longer registered, though their
  branches remain behind and uncontained.

## Material Worktree Facts

| Worktree | Branch | HEAD | Dirty | Behind/Ahead vs main | Contains main | Contained by main | Advisory conflict hints | Current signal |
| --- | --- | ---: | ---: | ---: | --- | --- | --- | --- |
| `.` | `codex/july-5-ui-feedback-batch` | `9c1744ba` | 360 | `0/0` | yes | yes | n/a | root checkout equals `main` commit but is broad dirty |
| `.worktrees/au-runtime-safety` | `feature/au-runtime-safety` | `ead7586f` | 259 | `10/3` | no | no | merge-tree output only showed a tree id in this scan | active build loop; deterministic checkpoint held for human AU validation, but worktree now dirty |
| `.worktrees/drum-kit-matrix-sound-prep` | `feature/drum-kit-matrix-sound-prep` | `9c1744ba` | 0 | `0/0` | yes | yes | n/a | active build loop; clean current-main seam-check checkpoint |
| `.worktrees/roadmap-8-midi-interfaces` | `auto/roadmap-8-midi-interfaces` | `34d5c43c` | 0 | `760/9` | no | no | conflicts in project, EngineController, Content/Phrase/Preferences/Tracks/Workspace UI, tests, visual script | locked build loop; hardware acceptance remains missing |
| `.worktrees/track-phrase-perform-mini-cells` | `feature/track-phrase-perform-mini-cells` | `9c1744ba` | 259 | `0/0` | yes | yes | n/a | complete/landed loop residue; preserved dirty worktree |
| `.worktrees/mixer-strip-followup` | `feature/mixer-strip-followup` | `04a0e071` | 259 | `2/0` | no | yes | n/a | complete/landed loop residue; branch contained by `main` but worktree dirty |
| `.worktrees/drum-timing` | `fix/record-arm-crash-v2` | `fd71effc` | 1 | `35/0` | no | yes | n/a | contained branch with dirty residue |
| `.worktrees/track-view-tabs` | `feat/generator-pitch-cleanup` | `50b731e5` | 1 | `50/0` | no | yes | n/a | contained branch with dirty residue |
| `.worktrees/ux-batch` | `fix/slicer-polish` | `849eda89` | 2 | `50/0` | no | yes | n/a | contained branch with dirty residue |
| `.worktrees/ws1-fill-mode` | `fix/audio-idle-cleanup` | `575c67c7` | 1 | `53/0` | no | yes | n/a | contained branch with dirty residue |

## Active / Locked Branch Details

- `feature/au-runtime-safety` is behind current `main` by `10` commits and
  ahead by `3`. Compact state says latest accepted deterministic checkpoint is
  `ead7586f` and the loop is held for human-present AU validation. Direct
  worktree status now shows `259` dirty paths, so branch freshness and worktree
  cleanliness differ from the compact state.
- `feature/drum-kit-matrix-sound-prep` is clean at current `main`
  `9c1744ba`. Compact state says it is an active read-only seam-check /
  evidence-repair checkpoint with visual evidence still missing because visual
  automation was not explicitly allowed.
- `auto/roadmap-8-midi-interfaces` is clean but far behind current `main`
  (`760/9`). Compact state says it remains locked on missing Launchpad hardware
  acceptance. Advisory merge-tree reports conflicts in
  `SequencerAI.xcodeproj/project.pbxproj`, `Sources/Engine/EngineController.swift`,
  `Sources/UI/ContentView.swift`, `Sources/UI/PhraseWorkspaceView.swift`,
  `Sources/UI/PreferencesView.swift`, `Sources/UI/TracksMatrixView.swift`,
  `Sources/UI/WorkspaceDetailView.swift`,
  `Tests/SequencerAITests/Engine/EngineControllerTests.swift`,
  `Tests/SequencerAITests/LiveWorkspaceViewTests.swift`, and
  `scripts/visual-scenarios/app-surfaces.sh`.
- `auto/roadmap-21-observability-log-issues` has no registered worktree in the
  current `git worktree list` output, but the branch remains behind/uncontained
  (`673/9`). Advisory merge-tree reports conflicts in project, app delegate,
  diagnostics, Info.plist, app delegate tests, diagnostics tests,
  `project.yml`, and `scripts/open-latest-build.sh`.
- `feature/routing-source-mixer-split` has no registered worktree in the
  current `git worktree list` output, but the branch remains
  behind/uncontained (`470/6`). Advisory merge-tree reports conflicts in the
  project file, sampler/destination editor files, routing tab content,
  `VisualScenarioCommandRunner`, and `qa-surface-coverage.sh`.
- `feature/au-discovery-rescan` has no registered worktree in the current
  `git worktree list` output, but the branch remains behind/uncontained
  (`469/4`). Advisory merge-tree reports conflicts in audio effect choice,
  EngineController, mixer/source UI, destination editor, visual command runner,
  and EngineController tests.

## Branch-Only Behind Main

Behind/uncontained local branches with no registered worktree and material
freshness risk include:

`audio-routing-cleanup` (`203/6`), `auto/goal-9-modifier-chain-placement`
(`1023/7`), `auto/overnight-simplification-2026-04-29` (`1157/1`),
`auto/p0-track-performance-overlay` (`909/10`),
`auto/roadmap-1-clip-history` (`1107/49`),
`auto/roadmap-9-modifier-chain-placement` (`1107/192`),
`backup/roadmap-2-scene-perform-pre-main-integration` (`871/8`),
`codex/live-perform-fill-overlay` (`1263/3`),
`codex/live-perform-performance-mechanics-plan` (`1252/1`),
`codex/master-bus-scenes` (`1239/10`),
`codex/master-bus-scenes-plan` (`1252/1`),
`codex/max-8-destination-au` (`1305/10`),
the May 5/May 6 probe branches, `codex/progression-chord-generator`
(`1207/1`), `codex/runtime-au-plugin-shutdown` (`1197/1`),
`codex/runtime-drum-sample-playback` (`1197/2`),
`codex/tracks-perform-scenes-workspace` (`871/10`),
`observer-sweep-remediation` (`288/2`), `wip/ws-batch-snapshot` (`86/1`),
and `work/observability-harvest` (`194/1`).

Behind current `main` but already contained by it include many stale/landed
feature, fix, and integration branches, including `feature/mixer-strip-followup`,
`fix/record-arm-crash-v2`, `fix/slicer-polish`, `fix/audio-idle-cleanup`,
`feat/generator-pitch-cleanup`, `probe/drum-timing`, and older roadmap/fix
branches. These do not require rebase to preserve committed code, but several
registered worktrees for contained branches are dirty.

## Checks Run

- Read the claimed request, project read-first context included in the
  invocation, coordinator config, prior durable rebase status, Foreman
  inventory, and compact build-loop summaries for AU runtime safety, drum kit
  matrix sound prep, track phrase perform mini cells, mixer strip follow-up,
  and MIDI interfaces.
- Checked `scripts/multi-pass/rebase-status.sh` and
  `project/scripts/rebase-status.sh`; neither is present/executable.
- Ran `git worktree list --porcelain`, root `git status --short --branch`,
  branch/worktree ahead-behind and ancestry checks, root diff checks, operation
  marker checks, and advisory `git merge-tree --name-only main <branch>` for
  material uncontained branches.
- No product build, test suite, visual capture, rebase, merge, cherry-pick,
  branch deletion, worktree deletion, cleanup, push, or inbox write was run.
