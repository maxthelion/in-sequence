# Rebase Status Observation

- generated: 2026-06-17T02:34Z
- loop-local copy: `.meta/multipass/runtime/loops/project/observe/rebase-status.md`
- cadence evidence:
  `.meta/multipass/runtime/loops/project/observe/2026-06-17T02-34Z-rebase-status-observation.md`
- request:
  `.meta/multipass/runtime/inbox/claimed/2026-06-17T023130250Z-rebase-observer-cadence.md`
- scope: observation only; no inbox messages, request lifecycle moves, rebase,
  merge, cherry-pick, build, review, push, cleanup, worktree deletion,
  product-code edits, process repair, lock clearing, or product-owner question
  performed by this observer.
- scan command: no executable project-local `scripts/multi-pass/rebase-status.sh`
  or `project/scripts/rebase-status.sh` is present. A Foreman Coordinator
  template exists, but was not installed as a project-local script. Facts came
  from Foreman Coordinator inventory/capacity/recent-run helpers, inbox status,
  compact durable summaries, direct `git worktree`, branch ahead/behind,
  ancestry, direct worktree status, `git diff --check`, and advisory
  `git merge-tree --write-tree main <branch>` checks.
- network: no fetch was performed. Local `origin/main` was used as-is.

## Observation

- Current local `main` is
  `23c2715c3ed7db1f89cde5c7585d18bd4065c50f`
  (`Add perform mode phrase layer capture wireframes`).
- Local `main` is `0` behind / `758` ahead of local `origin/main`
  (`cb79a2064cb03d9b80af7eeb36345fcbdf0d7941`) by
  `git rev-list --left-right --count origin/main...main`.
- Root worktree is on `main`, contains current `main`, is contained by current
  `main`, and had `318` dirty/local-only paths before this artifact was
  written, including `105` untracked paths.
- Root `git diff --check` and `git diff --cached --check` passed.
- Root rebase, merge, cherry-pick, and revert markers were absent.
- Runtime inventory reports active loops `project`,
  `build/routing-source-mixer-split`, and `build/au-discovery-rescan`; locked
  loops `pm/scenes-in-phrases`, `pm/audio-looping`,
  `build/observability-log-issues`, and `build/midi-interfaces`.
- Build capacity reports `2` ordinary build loops consuming both slots
  (`build/routing-source-mixer-split`, `build/au-discovery-rescan`), `2` locked
  build loops outside ordinary capacity, `0` ordinary slots open, and no ready
  or unpromoted ready candidates.
- Direct inbox status reports `4` pending, `2` claimed, `685` blocked, and
  `3725` done requests. No pending request targets a terminal build loop.
- Recent-run status during this scan showed this rebase observer and AU build
  orienter running. The AU evidence-repair builder completed immediately before
  this scan and reported the AU worktree remains clean at `4ce14c75`.
- Coordinator CLIs still emit Ruby `executable-hooks` / `gem-wrappers` warning
  noise before useful output.

## Freshness Summary

- Registered worktrees scanned: `31`. Behind current `main`: `29`. Contain
  current `main`: `2` including root `main` and
  `.worktrees/au-discovery-rescan`. Contained by current `main`: `3`.
  Clean/dirty: `20` / `11`. Behind and uncontained by current `main`: `27`.
- Local branches scanned: `63` including `main`. Non-main branches scanned:
  `62`. Non-main branches behind current `main`: `61`. Non-main branches that
  contain current `main`: `1` (`feature/au-discovery-rescan`). Non-main
  branches contained by current `main`: `31`. Behind and uncontained non-main
  branches: `30`.
- Facts changed enough from the prior durable rebase observation to warrant
  orientation consumption. The material branch-freshness change is
  `feature/au-discovery-rescan` advancing from `80be3f56`, `0` behind / `1`
  ahead, to `4ce14c75`, `0` behind / `2` ahead, while remaining clean and
  containing current `main`. Routing, Observability, MIDI, and root `main`
  freshness facts are otherwise materially stable from the latest merge-status
  observation.

## Material Branch Facts

| Worktree | Branch | HEAD | Dirty | Behind/Ahead | Contains main | Contained by main | Advisory conflict hints | Current signal |
| --- | --- | ---: | ---: | ---: | --- | --- | --- | --- |
| `.` | `main` | `23c2715c` | 318 | `0/0` | yes | yes | n/a | root `main` is broad dirty and local-only |
| `.worktrees/au-discovery-rescan` | `feature/au-discovery-rescan` | `4ce14c75` | 0 | `0/2` | yes | no | merge-tree clean | active build loop; clean AU evidence-repair output, still evidence-insufficient |
| `.worktrees/routing-source-mixer-split` | `feature/routing-source-mixer-split` | `0f297367` | 0 | `1/5` | no | no | merge-tree clean | active build loop; clean but one main commit behind and capture-evidence blocked |
| `.worktrees/roadmap-21-observability-log-issues` | `auto/roadmap-21-observability-log-issues` | `714fdb8b` | 7 | `204/8` | no | no | conflicts in project/app delegate/test/project script paths | locked build loop; dirty unpaired partial remains |
| `.worktrees/roadmap-8-midi-interfaces` | `auto/roadmap-8-midi-interfaces` | `34d5c43c` | 0 | `291/9` | no | no | conflicts in project, engine, UI, tests, visual script | locked build loop; software output clean, hardware acceptance missing |
| `.worktrees/roadmap-2-scene-perform` | `auto/roadmap-2-scene-perform` | `d5b47500` | 2 | `328/0` | no | yes | merge-tree clean | complete branch contained in current `main` with untracked state residue |
| `.claude/worktrees/macro-lane-grid-ui` | `integration/preserve-macro-lane-grid-ui-main-20260515T2014Z` | `5e0836c5` | 2 | `384/0` | no | yes | not rescanned this cadence | dirty contained legacy integration worktree |
| `.worktrees/roadmap-1-clip-history` | `auto/roadmap-1-clip-history` | `ced03ab7` | 1 | `638/49` | no | no | broad modify/delete, add/add, project, engine, UI, and test conflicts | old Clip History reference/salvage branch |
| `.worktrees/roadmap-9-modifier-chain-placement` | `auto/roadmap-9-modifier-chain-placement` | `7520dbd4` | 1 | `638/192` | no | no | broad conflicts across legacy Claude files, project, audio, engine, UI, docs, scripts | stale modifier-chain branch |
| `.worktrees/goal-9-modifier-chain-placement` | `auto/goal-9-modifier-chain-placement` | `f39c4e59` | 1 | `554/7` | no | no | conflicts in `.peekaboo-loop`, project, track-source files | dirty stale modifier-chain branch |
| `.worktrees/p0-track-performance-overlay` | `auto/p0-track-performance-overlay` | `d36c78b4` | 0 | `440/10` | no | no | conflicts in project, session mutation, engine/playback, UI, and tests | historical product-owner checkpoint |

## Active / Locked Worktree Details

- `feature/au-discovery-rescan` direct status is clean at
  `4ce14c75940766a319592000b23534288d2f0840`
  (`Test AU plugin rescan publication`). `main...branch` is `0 2`; the branch
  contains current `main`, is not contained by current `main`, direct worktree
  `git diff --check` and `git diff --cached --check` passed, and advisory
  merge-tree exited cleanly with no conflict files. The latest builder final
  confirms no product-code, merge, push, rebase, or cleanup action occurred and
  the worktree remained clean after evidence repair.
- AU compact state says the loop is clean but evidence-insufficient: focused
  EngineController app-hosted XCTest timed out after entering the selected test
  with repeated HAL proxy failures, `xcodebuild build` passed, and runtime/manual
  rescan acceptance plus exact picker/menu screenshots remain missing.
- `feature/routing-source-mixer-split` direct status is clean at
  `0f29736752eeffad6e68726645c8a386e7f0ae19`
  (`Harden routing source capture waits`). `main...branch` is `1 5`; the branch
  does not contain current `main`, is not contained by current `main`, direct
  worktree `git diff --check` and `git diff --cached --check` passed, and
  advisory merge-tree exited cleanly with no conflict files.
- Routing compact state says product-code risk is low but exact sample/slicer
  `Sound Source` visual evidence is still missing because the capture/window/
  CoreAudio environment is blocked. The branch is not review, critic, or
  integration-ready in compact state.
- `auto/roadmap-21-observability-log-issues` direct status is dirty at
  `714fdb8be29385d76737db53fc6dcd48826d5df5`
  (`Add diagnostic issue candidate review writer`). `main...branch` is
  `204 8`; the branch does not contain current `main`, is not contained by
  current `main`, and direct worktree `git diff --check` and
  `git diff --cached --check` passed.
- Advisory merge-tree for Observability reports content conflicts in
  `SequencerAI.xcodeproj/project.pbxproj`,
  `Sources/App/SequencerAIAppDelegate.swift`,
  `Tests/SequencerAITests/App/SequencerAIAppDelegateTests.swift`,
  `project.yml`, and `scripts/open-latest-build.sh`.
- Observability compact state says exact-state review evidence covers committed
  checkpoint `714fdb8` only; the current dirty pipeline/lifecycle partial has no
  builder final, commit, focused tests, source guard, or exact-state review
  evidence. The build loop remains human-locked for scope correction.
- `auto/roadmap-8-midi-interfaces` direct status is clean at
  `34d5c43c6de6191e7322283975ce19d6877d5ac9`
  (`Keep control surface preferences reachable`). `main...branch` is `291 9`;
  the branch does not contain current `main`, is not contained by current
  `main`, and direct worktree `git diff --check` and
  `git diff --cached --check` passed.
- Advisory merge-tree for MIDI reports content conflicts in
  `SequencerAI.xcodeproj/project.pbxproj`,
  `Sources/Engine/EngineController.swift`, `Sources/UI/ContentView.swift`,
  `Sources/UI/PhraseWorkspaceView.swift`, `Sources/UI/PreferencesView.swift`,
  `Sources/UI/TracksMatrixView.swift`, `Sources/UI/WorkspaceDetailView.swift`,
  `Tests/SequencerAITests/Engine/EngineControllerTests.swift`,
  `Tests/SequencerAITests/LiveWorkspaceViewTests.swift`, and
  `scripts/visual-scenarios/app-surfaces.sh`.
- MIDI compact state reports software/source checks, Preferences MIDI
  screenshot evidence, and exact-output reviews for `34d5c43`, but Phase 6
  physical Launchpad Mini MK3 hardware acceptance remains missing.

## Behind / Contained Branches

Behind current `main` but already contained by it include:
`auto/architecture-engine-controller-carve-up-plan`,
`auto/maintenance-addresses-phrase-timeline`,
`auto/maintenance-macro-descriptor-slots`,
`auto/roadmap-1-clip-history-v2`,
`auto/roadmap-10-phrase-features`,
`auto/roadmap-11-song-mode-phrase-looping`,
`auto/roadmap-12-drum-parts-as-group`,
`auto/roadmap-13-autoslice-algorithm`,
`auto/roadmap-15-note-repeat`,
`auto/roadmap-16-step-order`,
`auto/roadmap-18-track-fill-toggle`,
`auto/roadmap-2-scene-perform`,
`auto/roadmap-24-track-perform-multiselect-latch`,
`auto/roadmap-3-step-sequencer`,
`auto/roadmap-5-mixer-busses-ui-finish`,
`auto/roadmap-7-input-audio`,
`auto/roadmap-performance-layer-matrix`,
the observed `fix/*` audio/input/mixer/UI branches,
`codex/macro-lane-grid-ui`,
`codex/slicer-findings-fix`,
`codex/slicer-track-mvp`, and
`integration/track-fill-toggle-clean-20260604T2204Z`.

## Behind / Uncontained Worktrees

Behind current `main` and not contained by it include:
`.worktrees/routing-source-mixer-split`,
`.worktrees/roadmap-21-observability-log-issues`,
`.worktrees/roadmap-8-midi-interfaces`,
older `.claude/worktrees/*` planning/probe worktrees for live perform, master
bus scenes, and progression, stale modifier-chain worktrees,
`.worktrees/overnight-simplification-2026-04-29`,
`.worktrees/p0-track-performance-overlay`,
the May 5 broad-probe worktrees, the May 6 UX-feedback worktrees,
`.worktrees/roadmap-1-clip-history`,
`.worktrees/runtime-au-plugin-shutdown`, and
`.worktrees/runtime-drum-sample-playback`.

`feature/au-discovery-rescan` is not in this behind/uncontained set: the
worktree is clean, `0` behind / `2` ahead, contains current `main`, and
advisory merge-tree is clean.

## Branch-Only Behind Main

Uncontained local branches that are behind `main` and have no registered
worktree in the current `git worktree list` output:

| Branch | Behind/Ahead | Contains main | Contained by main | Active mention |
| --- | ---: | --- | --- | --- |
| `backup/roadmap-2-scene-perform-pre-main-integration` | `402/8` | no | no | backup of Scene Perform pre-main integration |
| `codex/max-8-destination-au` | `836/10` | no | no | unmentioned in current compact state |
| `codex/tracks-perform-scenes-workspace` | `402/10` | no | no | unmentioned in current compact state |

## Checks Run

- Read the claimed request, actor prompt/actions, project read-first context
  included in the invocation, coordinator config, prior durable rebase status,
  merge status, project orientation, current-work, feature-readiness, holistic
  status, decision log, and active routing/AU/Observability/MIDI build-loop
  summaries.
- Checked availability of `scripts/multi-pass/rebase-status.sh` and
  `project/scripts/rebase-status.sh`; neither is present/executable. Read the
  Foreman Coordinator rebase-status template as reference only.
- Ran Foreman Coordinator `inventory.ts`, `build-capacity.ts`, and
  `recent-runs.ts --limit 20`.
- Ran `scripts/multi-pass/inbox-status.sh`.
- Read the latest AU evidence-repair builder final because recent-run status
  showed it completed immediately before this cadence and it clarified branch
  freshness.
- Checked root `git status`, root `HEAD`, local `origin/main`, root direct
  diff-check status, root operation markers, worktree and branch ahead/behind,
  ancestry, branch containment, branch-only refs, direct Routing/AU/
  Observability/MIDI worktree status and diff checks, and advisory merge-tree
  conflict hints for active/locked plus stale material branches.
- No product build, test suite, visual capture, rebase, merge, cherry-pick,
  push, cleanup, inbox routing, request lifecycle move, product-code edit,
  worktree deletion, process repair, review scheduling, lock clearing, or
  product-owner request was performed by this observer.

This is an observation only; no rebase, merge, cherry-pick, build, review,
push, cleanup, inbox message, request lifecycle action, process repair,
worktree deletion, lock clearing, or product-owner work was scheduled.
