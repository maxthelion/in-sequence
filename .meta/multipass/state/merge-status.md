# Merge Status Observation

## 2026-07-06T19:49Z Integration Addendum

- `feature/track-setup-surface-compression` was merged into local `main` as
  `859b3193d637da0fc29c95caa0deb0d6e0f7e420`.
- Candidate verified:
  `.worktrees/track-setup-surface-compression` was clean at
  `9517f95430acc78dd5ff930ca68371fbb7df5df1`.
- Scope verified: candidate changed only
  `Sources/UI/SamplerDestinationWidget.swift` and
  `Sources/UI/TrackSource/Clip/ClipContentPreview.swift`; root dirty state did
  not overlap those paths.
- Post-merge checks passed:
  `git diff --check HEAD^..HEAD` and
  `scripts/diagnostics/ux-canon-lint.sh` (`0` violations).
- Preserved evidence risk:
  `capture-permission-or-focus` exact-state screenshots remain missing by
  explicit project-loop acceptance. No TCC-gated visual automation was run.

## 2026-07-06T14:51Z Observation

- request:
  `.meta/multipass/runtime/inbox/claimed/2026-07-05T095722953Z-merge-observer-cadence.md`
- loop-local copy:
  `.meta/multipass/runtime/loops/project/observe/merge-status.md`
- cadence evidence:
  `.meta/multipass/runtime/loops/project/observe/2026-07-06T14-51Z-merge-status-observation.md`
- scope: observation only. No inbox message, request lifecycle move, merge,
  rebase, cherry-pick, build, review, cleanup, push, worktree deletion,
  product-code edit, lock clearing, visual automation, or product-owner
  question was performed.
- scan command: no project-local `merge-status.sh` was found. This pass used
  direct `git` checks plus Foreman Coordinator `inventory.ts` and
  `build-capacity.ts`.
- network: no fetch was performed. Local `origin/main` was used as-is.

### Compact Facts

- Root worktree is `main` at
  `c8f368d5c3c5e31e666070c15625b466c441b5b6`
  (`docs: document visual capture mutex`).
- Local `main` is `0` behind / `18` ahead of local `origin/main`.
- Root checkout had `298` dirty/local-only paths before this observation write.
  The dirt includes coordination state, build/PM loop config/state files,
  deleted `.meta/multipass/visual-review/codex/july4-ui-feedback-batch/*`
  capture artifacts, new loop manifests/state files, and
  `docs/roadmap/track-phrase-perform-interaction-prep/closeout-readiness.md`.
- Root `git diff --check` reported one whitespace issue already present before
  this observation write:
  `.meta/multipass/state/loop-lifecycle-status.md:54: new blank line at EOF`.
  `git diff --cached --check` passed.
- No root merge, rebase, cherry-pick, or revert marker was observed by direct
  worktree status.
- Registered worktrees seen in `git worktree list --porcelain`: `11`.
- Local branches containing current `main`: `main` and `codex/limited-color-ui`.
- Current active ordinary build loops from `build-capacity.ts`:
  `build/au-runtime-safety` and `build/drum-kit-matrix-sound-prep`.
  Locked build loops outside ordinary capacity remain
  `build/observability-log-issues` and `build/midi-interfaces`.
- Ready candidates and unpromoted ready candidates are both `none`; ordinary
  build capacity is full (`2` active, `0` slots available).
- Coordinator CLIs still emit Ruby `executable-hooks` / `gem-wrappers` warning
  noise before useful output.

### Branch And Worktree Facts

- `feature/au-runtime-safety` is an active ordinary build branch at
  `ead7586f2cffd12f84bd13326dab240dbefa1a89`
  (`test(audio): pin AU preset command path`). It is `20` behind / `3` ahead
  of current local `main`, and neither contains nor is contained by `main`.
  Advisory `git merge-tree --write-tree main feature/au-runtime-safety` exited
  `0` with tree `2838064e198f4c402a6cbac7e4e8b035e087dbbc`.
- Its worktree `.worktrees/au-runtime-safety` had `259` dirty/local paths,
  sampled as deleted `.meta/multipass/visual-review/codex/july4-ui-feedback-batch/*`
  artifacts. Compact build-loop state still describes the deterministic
  checkpoint as held for human-present third-party AU validation or explicit
  acceptance of that manual evidence gap.

- `feature/drum-kit-matrix-sound-prep` is an active ordinary build branch at
  `9c1744ba2247b9613909194710d9f1ba02da7ed7`
  (`Use icon controls for track mini cell actions`). It is `10` behind / `0`
  ahead of current local `main`, does not contain current `main`, and is
  contained by current `main`. Its worktree
  `.worktrees/drum-kit-matrix-sound-prep` is clean.
- Advisory
  `git merge-tree --write-tree main feature/drum-kit-matrix-sound-prep`
  exited `0` with tree `d3ebbdbb90c36bc422661f4c699f55d9cbeb6393`.
  Compact build-loop state describes this as a current-main/read-only seam
  check with architecture/test/canon evidence and remaining visual/review
  evidence gaps, not a new implementation merge candidate.

- `feature/track-phrase-perform-mini-cells` is a preserved landed branch at
  `9c1744ba2247b9613909194710d9f1ba02da7ed7`. It is `10` behind / `0` ahead
  of current local `main`, does not contain current `main`, and is contained by
  current `main`. Its worktree had `259` dirty/local paths, sampled as the same
  deleted July 4 visual-review batch artifacts. Advisory merge-tree exited `0`
  with tree `d3ebbdbb90c36bc422661f4c699f55d9cbeb6393`.

- `feature/mixer-strip-followup` is a preserved landed branch at
  `04a0e0716b7cbc301c9cc91cf3c6972a6e163023`
  (`Mark mixer strip polish bugs resolved`). It is `12` behind / `0` ahead of
  current local `main`, does not contain current `main`, and is contained by
  current `main`. Its worktree had `259` dirty/local paths, sampled as the same
  deleted July 4 visual-review batch artifacts. Advisory merge-tree exited `0`
  with tree `d3ebbdbb90c36bc422661f4c699f55d9cbeb6393`.

- `codex/limited-color-ui` is a registered worktree branch at current `main`
  (`c8f368d5`). It is `0` behind / `0` ahead, contains current `main`, and is
  contained by current `main`. Its worktree had `85` dirty/local product-code
  paths, sampled under `Sources/StepGrid` and `Sources/UI/DrumGroup`.
  Advisory merge-tree exited `0` with tree
  `d3ebbdbb90c36bc422661f4c699f55d9cbeb6393`.

- `auto/roadmap-8-midi-interfaces` is the locked MIDI Interfaces branch at
  `34d5c43c6de6191e7322283975ce19d6877d5ac9`
  (`Keep control surface preferences reachable`). It is `770` behind / `9`
  ahead of current local `main`, and neither contains nor is contained by
  `main`. Its worktree `.worktrees/roadmap-8-midi-interfaces` is clean.
  Advisory merge-tree exited `1` with conflict hints in the Xcode project,
  `EngineController`, workspace/UI files, tests, and visual scenario scripts.

- `auto/roadmap-21-observability-log-issues` is the locked Observability branch
  at `1934ef630b78ad505896855ce253e91256058c8a`
  (`WIP: preserve uncommitted Diagnostics work (parked branch)`). It is `683`
  behind / `9` ahead of current local `main`, and neither contains nor is
  contained by `main`. Its configured worktree is still missing. Advisory
  merge-tree exited `1` with conflict hints in the Xcode project, app delegate,
  diagnostics files/tests, `Info.plist`, `project.yml`, and
  `scripts/open-latest-build.sh`.

- `feature/au-discovery-rescan` is a terminal/superseded preserved branch at
  `754e210fe1bd98cc4daf25a5101a47ee41373c9a`
  (`Support runtime AU rescan visual command`). It is `479` behind / `4` ahead
  of current local `main`, and neither contains nor is contained by `main`.
  The configured worktree is missing. Advisory merge-tree exited `1` with
  conflict hints in AU choice/cache/engine files, mixer/scene UI files,
  `VisualScenarioCommandRunner.swift`, and `EngineControllerTests.swift`.

- `feature/routing-source-mixer-split` is a terminal/superseded preserved
  branch at `3938b6bccd0ef29e0190e64c1494697c5aa46eba`
  (`Fix slicer routing visual fixture`). It is `480` behind / `6` ahead of
  current local `main`, and neither contains nor is contained by `main`. The
  configured worktree is missing. Advisory merge-tree exited `1` with conflict
  hints in the Xcode project, routing/source/destination UI, visual scenario
  command/capture files, the routing bug resolution, and
  `qa-surface-coverage.sh`.

### Other Registered Worktrees

- `.worktrees/drum-timing` on `fix/record-arm-crash-v2` is clean except
  untracked `.meta/work-specs/`.
- `.worktrees/track-view-tabs` on `feat/generator-pitch-cleanup` is clean
  except untracked `.meta/work-specs/`.
- `.worktrees/ux-batch` on `fix/slicer-polish` is dirty in
  `SequencerAI.xcodeproj/project.pbxproj` and has untracked
  `.meta/work-specs/`.
- `.worktrees/ws1-fill-mode` on `fix/audio-idle-cleanup` is clean except
  untracked `.meta/work-specs/`.
- No current compact build-loop state names these four worktrees as active
  merge candidates.

### Dependency And Containment Hints

- `feature/au-runtime-safety` is the only active ordinary build branch with
  unique unmerged commits. Advisory merge-tree is conflict-clean, but the
  branch is behind current `main`, its worktree has broad visual-review
  deletion dirt, and compact state holds it for human-present AU validation.
- `feature/drum-kit-matrix-sound-prep` is active in the registry but its branch
  is already contained by current `main`; compact state describes it as a
  read-only seam-check/evidence lane with a queued testing-review refresh.
- `feature/track-phrase-perform-mini-cells` and `feature/mixer-strip-followup`
  remain preserved landed branches contained by `main`; their worktrees now
  show the same visual-review deletion dirt seen in AU runtime safety.
- `codex/limited-color-ui` points at current `main` but has local product-code
  dirt; it is not listed as an active build-loop candidate by inventory.
- Completed/superseded `feature/au-discovery-rescan` and
  `feature/routing-source-mixer-split` remain preserved, diverged, and
  conflict-hinted; current compact state says their product intent is already
  represented on `main` by other commits.
- Locked Observability and MIDI branches remain far behind, conflict-hinted,
  and blocked by human/scope constraints rather than current merge mechanics.
- No active or locked downstream build-loop branch was observed as depending on
  another current build-loop branch as its base.

### Loop And Runtime Mentions

- Foreman inventory currently lists active build loops
  `build/au-runtime-safety` and `build/drum-kit-matrix-sound-prep`; locked
  build loops `build/observability-log-issues` and `build/midi-interfaces`;
  active PM loops `pm/july-4-phrase-layers-global-apply` and
  `pm/track-phrase-perform-interaction-prep`; and locked PM loops
  `pm/scenes-in-phrases` and `pm/audio-looping`.
- Build capacity reports `2` active ordinary build loops, `2` locked build
  loops outside capacity, `0` available build slots, and no ready candidates.
- Current feature-readiness state says `drum-kit-matrix-sound-prep` is consumed
  by its active build loop, `track-phrase-perform-interaction-prep` is already
  promoted/built/fast-forwarded into local `main` at `9c1744ba`, and
  `july-4-phrase-layers-global-apply` is not a build-loop promotion candidate.
- Holistic status at 2026-07-06T14:26Z records local `main` as broad-dirty,
  ordinary build capacity full, drum-kit matrix sound prep awaiting testing
  review/visual evidence, AU runtime safety held for human-present validation,
  and a fresh clip-header UI bug as future bounded UI-economy work.

### Freshness

Merge facts changed materially from the 2026-07-05 body below:

- Local `main` advanced from `9c1744ba` to `c8f368d5` and is now `18` commits
  ahead of local `origin/main`.
- Active ordinary build capacity changed from `mixer-strip-followup` /
  `au-runtime-safety` to `au-runtime-safety` /
  `drum-kit-matrix-sound-prep`.
- `feature/mixer-strip-followup` is no longer an active capacity-consuming
  build loop and is now `12` behind / `0` ahead, contained by current `main`.
- `feature/drum-kit-matrix-sound-prep` is active but also contained by current
  `main`; its worktree is clean and its lane is evidence/review continuation.
- Registered worktrees increased from `8` to `11`, including
  `.worktrees/limited-color-ui` with local product-code dirt.
- Root and several preserved worktrees now show broad visual-review deletion
  dirt.

These facts changed enough that project orientation should refresh before any
merge-order, closeout, capacity, or worktree-hygiene decision.

## 2026-07-05T15:57Z Integrator Addendum

- source:
  `.meta/multipass/runtime/loops/project/act/2026-07-05T15-57Z-track-phrase-perform-mini-cells-integration-confirmed.md`
- `feature/track-phrase-perform-mini-cells` remains integrated into local
  `main` at `9c1744ba`.
- This integrator performed no new merge because local `main` already contained
  the exact candidate after the 13:32Z fast-forward merge.
- Candidate worktree `.worktrees/track-phrase-perform-mini-cells` was clean and
  preserved.
- Post-integration checks now passed on local `main`: UX canon lint 0
  violations, `SequencerDocumentSessionQuantisedToggleTests` 16/0, and
  `TrackPerformSelectionStateTests` 22/0.
- Remaining evidence risk: `missing-visual-evidence`. The prior
  `disk-exhausted-post-merge-check` risk for this candidate is superseded by
  the passing warmed serial focused tests in this addendum, though the root
  checkout still has unrelated coordination/doc/bug-intake dirt.

## 2026-07-05T13:32Z Integrator Addendum

- source:
  `.meta/multipass/runtime/loops/project/act/2026-07-05T13-32Z-track-phrase-perform-mini-cells-integration-merged.md`
- `feature/track-phrase-perform-mini-cells` was fast-forward merged into local
  `main`.
- Local `main` moved from `04a0e0716b7cbc301c9cc91cf3c6972a6e163023` to
  `9c1744ba2247b9613909194710d9f1ba02da7ed7`.
- Candidate worktree `.worktrees/track-phrase-perform-mini-cells` was clean
  before integration and remains preserved. Branch deletion/worktree deletion
  were not performed.
- Post-merge UX canon lint passed with 0 violations.
- Post-merge focused Xcode tests were attempted but blocked before execution by
  machine disk exhaustion (`73Mi` free, `100%` capacity) after one CodeSign
  internal error and one isolated DerivedData retry with `No space left on
  device (28)`.
- Remaining evidence risk: `disk-exhausted-post-merge-check` and
  `missing-visual-evidence`. Pre-merge exact-commit review evidence had passing
  focused tests and architecture/testing review on `9c1744ba`.

- generated: 2026-07-05T05:50Z
- loop-local copy: `.meta/multipass/runtime/loops/project/observe/merge-status.md`
- cadence evidence:
  `.meta/multipass/runtime/loops/project/observe/2026-07-05T05-50Z-merge-status-observation.md`
- request:
  `.meta/multipass/runtime/inbox/claimed/2026-07-04T171510638Z-merge-observer-cadence.md`
- scope: observation only. No inbox messages, request lifecycle moves, merge,
  rebase, cherry-pick, build, review, cleanup, push, worktree deletion,
  product-code edits, lock clearing, or product-owner question performed.
- scan command: no project-local `merge-status.sh` was found. This scan used
  direct `git` checks plus Foreman Coordinator inventory/build-capacity/
  lifecycle helpers and `scripts/multi-pass/inbox-status.sh`.
- network: no fetch was performed. Local `origin/main` was used as-is.

## Compact Facts

- Root worktree is `main` at
  `04a0e0716b7cbc301c9cc91cf3c6972a6e163023`
  (`Mark mixer strip polish bugs resolved`).
- Local `main` is `0` behind / `6` ahead of local `origin/main`.
- Root checkout had `25` dirty/local-only paths before this observation write,
  including coordination state, build/PM loop config/state files, the routing
  bug `resolution.md`, and `docs/roadmap/autoslice-algorithm/README.md`.
- Root `git diff --check` reported one whitespace issue already present before
  this observation write:
  `.meta/multipass/state/loop-lifecycle-status.md:49: new blank line at EOF`.
  `git diff --cached --check` passed.
- No root merge, rebase, cherry-pick, or revert marker was observed by direct
  worktree status.
- Registered worktrees seen in `git worktree list --porcelain`: `8`.
- Local branches containing current `main`: `main` and
  `feature/mixer-strip-followup`.
- Local branches merged into current `main`: many historical/landed branches;
  current lifecycle marks only `build/mixer-strip-followup` as an active build
  branch contained in `main`.
- Live build capacity reports both ordinary slots consumed by
  `build/mixer-strip-followup` and `build/au-runtime-safety`. Locked build
  loops outside ordinary capacity remain `build/observability-log-issues` and
  `build/midi-interfaces`. Ready candidates and unpromoted ready candidates are
  both `none`.
- Coordinator CLIs still emit Ruby `executable-hooks` / `gem-wrappers` warning
  noise before useful output.

## Branch And Worktree Facts

- `feature/mixer-strip-followup` is the active Mixer Strip Follow-Up branch at
  `04a0e0716b7cbc301c9cc91cf3c6972a6e163023`
  (`Mark mixer strip polish bugs resolved`). It is identical to local `main`
  (`0` behind / `0` ahead), contains current `main`, and is contained by
  current `main`. Its worktree `.worktrees/mixer-strip-followup` is clean.
  Worktree `git diff --check` and `git diff --cached --check` passed.
- Advisory `git merge-tree --write-tree main feature/mixer-strip-followup`
  exited `0` and produced tree `434b31eb2cb8073d41b39f7bd5c1e36f161b39d9`
  with no conflict output.
- Loop lifecycle flags `build/mixer-strip-followup` as active with
  lifecycle signal `active-build-branch-contained-in-main` and `3` blocked
  requests. Integration evidence at
  `.meta/multipass/runtime/loops/project/act/2026-07-05T05-42Z-mixer-strip-followup-integration-merged.md`
  says the branch was fast-forward merged to local `main`; post-merge UX canon
  lint and focused mixer tests passed; visual screenshots remain blocked by
  `capture-permission-or-focus`.

- `feature/au-runtime-safety` is the active AU Runtime Safety branch at
  `ead7586f2cffd12f84bd13326dab240dbefa1a89`
  (`test(audio): pin AU preset command path`). It is `8` behind / `3` ahead of
  current local `main`, and neither contains nor is contained by `main`. Its
  worktree `.worktrees/au-runtime-safety` is clean. Worktree
  `git diff --check` and `git diff --cached --check` passed.
- Advisory `git merge-tree --write-tree main feature/au-runtime-safety` exited
  `0` and produced tree `9419586312c2707c2c6b5f9e3f58f4f06b3f2628` with no
  conflict output.
- AU runtime compact state reports deterministic architecture/testing evidence
  for the preset command-path checkpoint, but the lane is held for
  human-present third-party AU validation or an explicit acceptance of that
  manual evidence gap.

- `feature/au-discovery-rescan` is a completed/superseded lane preserved branch
  at `754e210fe1bd98cc4daf25a5101a47ee41373c9a`
  (`Support runtime AU rescan visual command`). It is `467` behind / `4` ahead
  of current local `main`, and neither contains nor is contained by `main`.
  The configured worktree is missing.
- Advisory `git merge-tree --write-tree main feature/au-discovery-rescan`
  exited `1` with content conflict hints in AU choice/cache/engine files,
  mixer/scene UI files, `VisualScenarioCommandRunner.swift`, and
  `EngineControllerTests.swift`.
- Compact state says current `main` already contains the AU discovery/rescan
  product work by supersession; the preserved branch is historical
  implementation/evidence material, not a live continuation target.

- `feature/routing-source-mixer-split` is a completed/superseded lane preserved
  branch at `3938b6bccd0ef29e0190e64c1494697c5aa46eba`
  (`Fix slicer routing visual fixture`). It is `468` behind / `6` ahead of
  current local `main`, and neither contains nor is contained by `main`. The
  configured worktree is missing.
- Advisory `git merge-tree --write-tree main feature/routing-source-mixer-split`
  exited `1` with content conflict hints in the Xcode project,
  routing/source/destination UI, visual scenario command/capture files, and
  related scripts.
- Compact state says current `main` satisfies the routing-source/mixer owner
  bug intent by supersession; the preserved feature branch remains stale.
  `integrate/routing-source-mixer-split` is contained by current `main`
  (`199` behind / `0` ahead).

- `auto/roadmap-8-midi-interfaces` is the locked MIDI Interfaces branch at
  `34d5c43c6de6191e7322283975ce19d6877d5ac9`
  (`Keep control surface preferences reachable`). It is `758` behind / `9`
  ahead of current local `main`, and neither contains nor is contained by
  `main`. Its worktree `.worktrees/roadmap-8-midi-interfaces` is clean.
  Worktree `git diff --check` and `git diff --cached --check` passed.
- Advisory `git merge-tree --write-tree main auto/roadmap-8-midi-interfaces`
  exited `1` with conflict hints in the Xcode project, `EngineController`,
  main workspace/UI files, tests, and visual scenario scripts. Compact state
  keeps the lane human-locked on Launchpad Mini MK3 hardware acceptance.

- `auto/roadmap-21-observability-log-issues` is the locked Observability branch
  at `1934ef630b78ad505896855ce253e91256058c8a`
  (`WIP: preserve uncommitted Diagnostics work (parked branch)`). It is `671`
  behind / `9` ahead of current local `main`, and neither contains nor is
  contained by `main`. The configured worktree is missing.
- Advisory
  `git merge-tree --write-tree main auto/roadmap-21-observability-log-issues`
  exited `1` with conflict hints in the Xcode project, app delegate,
  diagnostics files/tests, `Info.plist`, `project.yml`, and
  `scripts/open-latest-build.sh`. Compact state keeps the lane human-locked
  for scope correction.

## Other Registered Worktrees

- `.worktrees/drum-timing` on `fix/record-arm-crash-v2` is `33` behind / `0`
  ahead of current `main`, clean except untracked `.meta/work-specs/`.
  Advisory merge-tree exited `0`.
- `.worktrees/track-view-tabs` on `feat/generator-pitch-cleanup` is `48`
  behind / `0` ahead of current `main`, clean except untracked
  `.meta/work-specs/`. Advisory merge-tree exited `0`.
- `.worktrees/ux-batch` on `fix/slicer-polish` is `48` behind / `0` ahead of
  current `main`, dirty in `SequencerAI.xcodeproj/project.pbxproj`, and has
  untracked `.meta/work-specs/`. Advisory merge-tree exited `0`.
- `.worktrees/ws1-fill-mode` on `fix/audio-idle-cleanup` is `51` behind / `0`
  ahead of current `main`, clean except untracked `.meta/work-specs/`.
  Advisory merge-tree exited `0`.
- No current compact build-loop state names these four worktrees as active
  merge candidates.

## Dependency And Containment Hints

- `feature/mixer-strip-followup` is already identical to current `main`; its
  active-loop lifecycle state is stale relative to integration.
- `feature/au-runtime-safety` is the only active ordinary build branch with
  unique unmerged commits. It is conflict-clean by advisory merge-tree but is
  behind current `main` and has an explicit human-present AU validation gap.
- Completed/superseded `feature/au-discovery-rescan` and
  `feature/routing-source-mixer-split` remain preserved, diverged, and
  conflict-hinted; current compact state says their product intent is already
  represented on `main` by other commits.
- Locked Observability and MIDI branches are far behind, conflict-hinted, and
  blocked by human/scope constraints rather than current merge mechanics.
- No active or locked downstream build-loop branch was observed as depending on
  another current build-loop branch as its base.

## Loop And Runtime Mentions

- Foreman inventory currently lists active build loops
  `build/mixer-strip-followup` and `build/au-runtime-safety`; locked build
  loops `build/observability-log-issues` and `build/midi-interfaces`; active
  PM loop `pm/july-4-phrase-layers-global-apply`; and locked PM loops
  `pm/scenes-in-phrases` and `pm/audio-looping`.
- Build capacity reports `2` active ordinary build loops, `2` locked build
  loops outside capacity, `0` available build slots, and no ready candidates.
- Loop lifecycle generated at 2026-07-05T05:46Z flags
  `build/mixer-strip-followup` as `active-build-branch-contained-in-main`,
  `build/au-runtime-safety` as active/diverged with blocked work,
  Observability and MIDI as locked/diverged, and the routing/AU-discovery lanes
  as terminal complete/diverged.
- `scripts/multi-pass/inbox-status.sh` reported `16` pending, `1` claimed,
  `712` blocked, and `4675` done requests. No pending requests target a
  terminal build loop.
- Runtime-problems compact state is stale from 2026-06-17 and was not refreshed
  by this merge observer.

## Freshness

Merge facts changed materially from the older June body that remained in this
file:

- Local `main` advanced from `23c2715c` to `04a0e071` and is now `6` commits
  ahead of local `origin/main`, not `758`.
- `build/mixer-strip-followup` exists, was merged to local `main`, and is still
  lifecycle-active despite branch containment.
- `build/au-runtime-safety` is the live unmerged ordinary build branch.
- `build/routing-source-mixer-split` and `build/au-discovery-rescan` are
  terminal complete by current-main supersession, with preserved old branches
  now conflict-hinted against current `main`.
- Registered worktrees have shrunk to `8`; older worktree facts in the prior
  merge-status body were stale.

These facts changed enough that project orientation should refresh before any
merge-order, closeout, or capacity decision.
