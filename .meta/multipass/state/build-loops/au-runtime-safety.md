# au-runtime-safety

- loop: `build/au-runtime-safety`
- status: active
- branch: `feature/au-runtime-safety`
- worktree: `.worktrees/au-runtime-safety`
- created: 2026-07-04T18:05:45.516Z
- feature: `au-runtime-safety`
- owner bugs:
  - `docs/bugs/20260624-165547-the-preset-picker-for-an-au-instrument-i/`
  - `docs/bugs/20260629-101847-au-preset-no-change-during-playback-and-hung-note/`
  - `docs/bugs/20260629-121929-au-removal-while-playing-crash/`
- setup evidence:
  `.meta/multipass/runtime/loops/project/act/2026-07-04T18-05Z-au-runtime-safety-build-loop-setup.md`
- initial build-loop decision:
  `.meta/multipass/runtime/loops/build/au-runtime-safety/decide/2026-07-04T18-05Z-route-au-runtime-safety-builder.md`
- initial builder request:
  `.meta/multipass/runtime/inbox/pending/2026-07-04T180545516Z-au-runtime-safety-builder.md`

## Compact Build Intent

This loop exists for the urgent AU runtime safety and preset behavior owner-bug
group on current `main`.

The work is runtime/lifecycle safety while transport is running: AU preset
changes that currently appear to do nothing or leave hung notes, preset picker
behavior during playback, and AU removal while playing crashes. It is not the
closed AU discovery/rescan lane, not AU list ordering, and not UI-only
mixer/perform polish.

## Setup State

The build-loop container defines a fresh branch/worktree target:

- branch: `feature/au-runtime-safety`
- worktree: `.worktrees/au-runtime-safety`
- base: current `main`
- setup-observed local `main`: `52129b6bd307a78aaf07ae7f9f4d875196f9e721`

The process-fixer did not create the worktree because the primary checkout had
unrelated dirty files at setup time. The builder should create or reuse the
named worktree from current `main` without carrying over old
`feature/au-discovery-rescan` work.

## Constraints

Honor the Audio Engine Hard Rules: do not introduce engine stop/start topology
churn during playback, bare note paths, render-thread locks/alloc/file I/O, or
document hot-path writes. Use sparse `DevActivity` breadcrumbs only when needed
for runtime diagnosis.

Unattended actors must not run human-present AU or audio-input flows that can
trigger macOS permission dialogs. Provide deterministic substitutes where
possible, and explicitly record any remaining human-present AU runtime evidence
gap.

Resolution evidence is expected in the three owner bug folders when fixed or
explicitly deferred.

## Latest Orientation — 2026-07-04T22:23Z

The current head is clean committed checkpoint
`ead7586f2cffd12f84bd13326dab240dbefa1a89`
(`test(audio): pin AU preset command path`). This is now paired with exact-state
architecture and testing observer evidence. It is a deterministic checkpoint
for the preset browser command path, not whole-feature completion and not full
closure for the AU preset sound-change / hung-note owner bug.

Changed files at this checkpoint:

- `Tests/SequencerAITests/UI/PresetBrowserSheetViewModelTests.swift`
- `docs/bugs/20260629-101847-au-preset-no-change-during-playback-and-hung-note/report.md`

Builder evidence:
`.meta/multipass/runtime/loops/build/au-runtime-safety/act/2026-07-04T2206Z-preset-command-path-builder.md`

Builder-reported checks for `ead7586f`: combined
`AudioInstrumentHostPresetsTests` + `PresetBrowserSheetViewModelTests` summary
observed `46 tests, 0 failures`; `realtime-path-lint.sh` passed;
`runtime-ownership-lint.sh` passed; `git diff --check` passed. `xcodebuild`
again hung only after the green XCTest summary while finalizing logs.

Exact-state observer evidence:

- architecture review:
  `.meta/multipass/runtime/loops/build/au-runtime-safety/observe/2026-07-04T2212Z-preset-command-path-architecture-review.md`
  - verdict: pass
  - risk: `caution`
  - no blocker found; live AU loader remains runtime authority and document
    commit follows the returned state blob.
- testing review:
  `.meta/multipass/runtime/loops/build/au-runtime-safety/observe/2026-07-04T2224Z-preset-command-path-testing-review.md`
  - verdict: `testing-pass-with-known-manual-evidence-gap`
  - observer-ran `PresetBrowserSheetViewModelTests`: summary observed
    `16 tests, 0 failures`, with the same post-summary log-finalization hang.

Remaining gap: human-present third-party AU validation is still intentionally
unrun. Full owner-bug closure still needs named AU/version and preset evidence
showing stopped and playing preset switches audibly change sound, no
transport pause/glitch, no old-patch tail/hung note after switch, and baseline
note-off length without touching presets.

Lowest unmet pyramid layer: evidence for full owner-bug closure. Deterministic
architecture/testing gates are satisfied for the current checkpoint.

Next action kind for the build decider: continuation or merge-candidacy
decision with explicit evidence gap. If full bug closure is required, the next
bounded step is human-present validation/evidence capture rather than more
unattended implementation. If a deterministic safety checkpoint is acceptable,
the branch can move toward integration while preserving the manual AU A/B gap.

## Latest Decision — 2026-07-04T22:28Z

Disposition: `needs_human_validation`.

Decision artifact:
`.meta/multipass/runtime/loops/build/au-runtime-safety/decide/2026-07-04T22-28Z-hold-for-human-au-validation.md`

The checkpoint `ead7586f2cffd12f84bd13326dab240dbefa1a89`
(`test(audio): pin AU preset command path`) is accepted for deterministic
architecture/testing pairing, but it is not a feature-complete merge candidate.
The remaining owner-bug closure for the AU preset sound-change / hung-note
report requires human-present third-party AU validation. No further unattended
builder or review request was queued because the current gap is an evidence and
permission constraint, not stale deterministic work.

Escalated one compact request to the top project decider:
`.meta/multipass/runtime/inbox/pending/2026-07-04T222818364Z-decider.md`

Requested top-level disposition: hold this build loop pending Max/human-present
validation, or explicitly accept integration as a deterministic safety
checkpoint with the manual AU A/B evidence gap preserved.

## Latest Orientation — 2026-07-04T18:46Z

Fresh builder evidence is dirty partial output, not a finished claim. The run
`.meta/multipass/runtime/runs/actors/builder/2026-07-04T180545516Z-au-runtime-safety-builder.failure.md`
was killed by `usage_rate_limit`/`SIGTERM` before writing a final artifact, but
left uncommitted changes in `.worktrees/au-runtime-safety`:

- `Sources/Audio/AudioInstrumentHost.swift`
- `Tests/SequencerAITests/Audio/AudioInstrumentHostPresetsTests.swift`

The dirty diff targets the AU removal while playing crash path by adding CC120
All-Sound-Off, sending panic MIDI before detach, retiring the live AU reference
before main-thread reset/detach, and adding source-inspection tests for teardown
ordering. Builder stderr records `** BUILD SUCCEEDED **` for this dirty output.

Evidence still missing: builder final, committed/stable output, targeted test
run, realtime/runtime lints, architecture review, testing review, deterministic
runtime teardown evidence, owner-bug resolution notes, and human-present AU
audibility/preset validation where required. Lowest unmet layer is
testing/evidence; architecture risk is `caution` until exact-state review.

Next action kind for the build decider: continuation / evidence repair in the
existing dirty worktree, followed by exact-state architecture and testing
observers after a stable builder claim.

## Latest Decision — 2026-07-04T18:51Z

Disposition: `needs_builder_continuation`.

Decision artifact:
`.meta/multipass/runtime/loops/build/au-runtime-safety/decide/2026-07-04T18-51Z-continue-dirty-au-runtime-safety-builder.md`

Builder continuation request:
`.meta/multipass/runtime/inbox/pending/2026-07-04T185207581Z-builder.md`

The next builder should resume the existing dirty worktree, finish or revise the
partial AU runtime-safety fix, run targeted tests and runtime lints, record
deterministic teardown evidence where possible, update owner-bug evidence only
when justified, and explicitly record the remaining human-present AU validation
gap. Do not merge the phase checkpoint; exact-state architecture/testing
observers come after a stable builder claim.

## Latest Builder — 2026-07-04T19:18Z

Builder continuation produced a clean committed phase checkpoint:

- commit: `0f8a9fd8d8a9d6addf1b96b67c45aed3ca69a7a4`
  (`fix(audio): harden AU teardown during removal`)
- final git state: clean in `.worktrees/au-runtime-safety`
- completion artifact:
  `.meta/multipass/runtime/loops/build/au-runtime-safety/act/2026-07-04T19-18Z-au-runtime-safety-builder.md`

The commit hardens `AudioInstrumentHost.disconnectCurrentInstrument` for the AU
removal-while-playing crash path: CC123 All-Notes-Off plus CC120 All-Sound-Off
are sent before detach, the live AU reference is retired under `auMutationLock`
before main-thread graph teardown, output is disconnected before reset, and the
AU is reset before detach. Source-order coverage was added for the intended
teardown ordering.

Builder-reported checks: app build passed, `realtime-path-lint.sh` passed, and
`runtime-ownership-lint.sh` passed. Targeted
`AudioInstrumentHostPresetsTests` execution was blocked before AU test execution
by an unrelated test-target compile error in
`Tests/SequencerAITests/UI/TrackSourceSourceDisplayStateTests.swift` referencing
missing `TrackSourceRoutingDisplayState`.

Owner-bug status in the branch: the AU-removal crash bug is marked resolved;
the preset no-change / transport-pause bug remains partial/open; the earlier
preset-picker resolution remains unchanged except that this pass records no new
preset behavior claim.

## Latest Orientation — 2026-07-04T19:06Z

The current output is a stable phase checkpoint, not a whole-feature completion.
There are still no loop-local architecture or testing observer artifacts for
exact commit `0f8a9fd8`. The source-order tests are present but not shown
running because the broader test target does not currently compile due unrelated
UI test drift.

Lowest unmet pyramid layer: testing/review evidence. Architecture risk remains
`caution` because this is high-risk AU lifecycle teardown, though the available
shape aligns with the audio hard rules: no engine stop/start topology churn, no
render-thread file/lock work added, and panic MIDI uses the AU MIDI block on a
control path.

Next action kind for the build decider: review / evidence repair. Route
exact-state architecture and testing observers for `0f8a9fd8`; testing should
record the unrelated compile blocker distinctly from product rework. If those
observers pass or accept the deterministic substitute, the remaining gap is
human-present third-party AU validation for real removal stability/audibility
and preset STOPPED-vs-PLAYING behavior.

## Latest Decision — 2026-07-04T19:11Z

Disposition: `needs_review`.

Decision artifact:
`.meta/multipass/runtime/loops/build/au-runtime-safety/decide/2026-07-04T19-11Z-observe-au-runtime-safety-checkpoint.md`

Started an exact-commit observation batch for the required loop gates:

- batch:
  `.meta/multipass/runtime/loops/build/au-runtime-safety/observe/batches/0f8a9fd8d8a9d6addf1b96b67c45aed3ca69a7a4/batch.yaml`
- architecture-review request:
  `.meta/multipass/runtime/inbox/pending/2026-07-04T191152132Z-architecture-review-for-au-runtime-safety-AU-removal-teardown-checkpoint.md`
- testing-review request:
  `.meta/multipass/runtime/inbox/pending/2026-07-04T191152212Z-testing-review-for-au-runtime-safety-AU-removal-teardown-checkpoint.md`

This is not a merge-candidate escalation. The next build-loop step is to wait
for the observer batch, then orient on the paired architecture/testing evidence.

## Latest Orientation — 2026-07-04T19:26Z

The observer batch for exact commit `0f8a9fd8d8a9d6addf1b96b67c45aed3ca69a7a4`
has completed with bounded passes, although the batch metadata file still says
`status: open`.

Current claim: `0f8a9fd8 fix(audio): harden AU teardown during removal` is a
clean committed phase checkpoint for the AU removal-while-playing crash path,
not whole-feature completion for all AU runtime-safety bugs. It changes AU
disconnect to send CC123 All-Notes-Off plus CC120 All-Sound-Off before detach,
retire the live AU reference under `auMutationLock` before main-thread graph
teardown, disconnect output before reset, and reset before detach.

Paired exact-state evidence:

- builder completion:
  `.meta/multipass/runtime/loops/build/au-runtime-safety/act/2026-07-04T19-18Z-au-runtime-safety-builder.md`
- architecture final:
  `.meta/multipass/runtime/runs/actors/architecture-review/2026-07-04T191152132Z-architecture-review-for-au-runtime-safety-AU-removal-teardown-checkpoint.final.md`
- testing final:
  `.meta/multipass/runtime/runs/actors/testing-review/2026-07-04T191152212Z-testing-review-for-au-runtime-safety-AU-removal-teardown-checkpoint.final.md`
- orientation:
  `.meta/multipass/runtime/loops/build/au-runtime-safety/orient/2026-07-04T19-26Z-progress.md`

Architecture observer verdict: pass for the bounded teardown checkpoint; no
line-stop recommended. It ran `architecture-scan.ts`,
`scripts/diagnostics/realtime-path-lint.sh`, and
`scripts/diagnostics/runtime-ownership-lint.sh`, with both lints passing.

Testing observer verdict: pass for the bounded unattended teardown checkpoint,
accepting deterministic source/diff ordering evidence. The new
`AudioInstrumentHostPresetsTests` coverage has still not executed because the
macOS test target is blocked by unrelated UI compile drift in
`TrackSourceSourceDisplayStateTests.swift` referencing missing
`TrackSourceRoutingDisplayState`.

Remaining gaps: executed targeted AU tests, human-present third-party AU
removal-while-playing audibility/stability validation, and the separate
preset sound-change / transport-pause behavior bug. The AU-removal crash bug is
marked resolved in branch evidence; the preset behavior bug remains partial/open.

Lowest unmet pyramid layer: testing/evidence for full feature confidence.
Architecture risk severity: `caution`, not `line-stop-recommended`.

Next action kind for the build decider: evidence repair / continuation. Repair
or isolate the unrelated test-target compile drift so the targeted AU tests can
execute, then decide whether to continue into preset behavior or hold the
teardown checkpoint pending human-present AU validation.

## Latest Decision — 2026-07-04T19:36Z

Disposition: `phase_complete_continue`.

Decision artifact:
`.meta/multipass/runtime/loops/build/au-runtime-safety/decide/2026-07-04T19-36Z-continue-au-runtime-safety-builder.md`

Builder continuation request:
`.meta/multipass/runtime/inbox/pending/2026-07-04T193232124Z-builder.md`

The AU removal-while-playing teardown checkpoint at `0f8a9fd8` is accepted as a
bounded phase with exact-state architecture/testing observer passes; it is not a
merge candidate. The next builder should keep working in
`.worktrees/au-runtime-safety`, repair or isolate the unrelated
`TrackSourceSourceDisplayStateTests.swift` test-target compile blocker enough to
execute `AudioInstrumentHostPresetsTests`, then continue the still-open preset
sound-change / transport-pause bug with deterministic evidence where possible.
Human-present third-party AU audibility/stability validation remains an explicit
evidence gap and must not be attempted by unattended actors.

## Latest Orientation — 2026-07-04T21:13Z

The latest builder continuation produced clean committed checkpoint
`e4e43210fd72e62465cabf3454cbfa2db01aceac`
(`fix(audio): flush AU voices after preset switch`), not a whole-feature
completion. It extends the accepted AU teardown checkpoint by flushing residual
AU voices after preset switch: `AudioInstrumentHost.loadPreset` sends CC123
All-Notes-Off and CC120 All-Sound-Off through the AU `scheduleMIDIEventBlock`
after `au.currentPreset = preset` and before state capture. The builder also
narrowed unrelated UI test compile drift enough for
`AudioInstrumentHostPresetsTests` to run.

Builder-reported exact-output checks for `e4e43210`: `AudioInstrumentHostPresetsTests`
30 passed, `realtime-path-lint.sh` passed, `runtime-ownership-lint.sh` passed,
and `git diff --check` passed. Worktree state was clean.

Missing paired evidence: exact-state architecture review and exact-state
testing review for `e4e43210`. Prior observer passes remain bounded to
`0f8a9fd8` and should not be treated as full inheritance for this preset-flush
change without explicit justification. Human-present third-party AU
STOPPED-vs-PLAYING audibility/stability validation is still an intentional
unattended evidence gap.

## Latest Decision — 2026-07-04T21:17Z

Disposition: `needs_review`.

Decision artifact:
`.meta/multipass/runtime/loops/build/au-runtime-safety/decide/2026-07-04T21-17Z-observe-preset-flush-checkpoint.md`

Started an exact-commit observation batch for the required loop gates:

- batch:
  `.meta/multipass/runtime/loops/build/au-runtime-safety/observe/batches/e4e43210fd72e62465cabf3454cbfa2db01aceac/batch.yaml`
- architecture-review request:
  `.meta/multipass/runtime/inbox/pending/2026-07-04T211741578Z-architecture-review-for-AU-runtime-safety-preset-flush-checkpoint.md`
- testing-review request:
  `.meta/multipass/runtime/inbox/pending/2026-07-04T211741658Z-testing-review-for-AU-runtime-safety-preset-flush-checkpoint.md`

This is not a merge-candidate escalation. The next build-loop step is to wait
for the observer batch, then orient on exact-state architecture/testing
evidence for `e4e43210`.

The newest builder continuation did not produce a stable claim. Run
`.meta/multipass/runtime/runs/actors/builder/2026-07-04T193232124Z-builder.failure.md`
was killed by `usage_rate_limit` / `SIGTERM` before writing a final artifact and
left dirty partial output in `.worktrees/au-runtime-safety`:

- `Sources/Audio/AudioInstrumentHost.swift`
- `Tests/SequencerAITests/Audio/AudioInstrumentHostPresetsTests.swift`
- `Tests/SequencerAITests/UI/TrackSourceSourceDisplayStateTests.swift`
- `docs/bugs/20260629-101847-au-preset-no-change-during-playback-and-hung-note/report.md`

The dirty preset work sends CC120 All-Sound-Off immediately after the existing
CC123 All-Notes-Off in `AudioInstrumentHost.loadPreset`, ordered after
`au.currentPreset = preset` and before AU state capture. It adds source-order
coverage for that sequence, removes stale `TrackSourceSectionPills` test
arguments that referenced the missing `TrackSourceRoutingDisplayState`, and
updates the preset owner-bug report as deterministic partial evidence while
leaving real-AU STOPPED-vs-PLAYING validation open.

Evidence paired to exact output remains split: commit `0f8a9fd8` has bounded
architecture/testing observer passes for AU removal teardown, but the dirty
preset/compile-blocker continuation has only failure-artifact and diff evidence.
There is no builder final, commit, targeted `AudioInstrumentHostPresetsTests`
execution, runtime lint result, or exact-state review for the dirty output.

Lowest unmet pyramid layer: testing/evidence. Architecture risk severity:
`caution` because the shape still appears aligned with audio hard rules but
touches high-risk AU lifecycle/preset behavior and is unreviewed dirty work.

Next action kind for the build decider: continuation / evidence repair. Resume
the dirty worktree, stabilize the output, run the targeted AU preset tests and
runtime lints, then route exact-state architecture/testing observers. Preserve
the human-present third-party AU validation gap; do not attempt it unattended.

## Latest Decision — 2026-07-04T20:42Z

Disposition: `needs_builder_continuation`.

Decision artifact:
`.meta/multipass/runtime/loops/build/au-runtime-safety/decide/2026-07-04T20-42Z-continue-dirty-preset-runtime-builder.md`

Builder continuation request:
`.meta/multipass/runtime/inbox/pending/2026-07-04T204250483Z-builder.md`

The current worktree is dirty partial output from an interrupted builder run,
so it is not ready for an observer batch or merge escalation. The next builder
should resume `.worktrees/au-runtime-safety`, stabilize or revise the preset
runtime changes, run targeted `AudioInstrumentHostPresetsTests`, run
`realtime-path-lint.sh` and `runtime-ownership-lint.sh`, and write a final with
exact commit/state and evidence. Human-present third-party AU STOPPED-vs-PLAYING
validation remains recorded as an explicit evidence gap and must not be
attempted unattended.

## Latest Orientation — 2026-07-04T21:13Z

The latest builder continuation produced a clean committed phase checkpoint:

- commit: `e4e43210fd72e62465cabf3454cbfa2db01aceac`
  (`fix(audio): flush AU voices after preset switch`)
- final git state: clean in `.worktrees/au-runtime-safety`
- builder final:
  `.meta/multipass/runtime/runs/actors/builder/2026-07-04T204250483Z-builder.final.md`
- orientation:
  `.meta/multipass/runtime/loops/build/au-runtime-safety/orient/2026-07-04T21-13Z-progress.md`

The commit extends the prior AU teardown work into the preset-switch path:
`AudioInstrumentHost.loadPreset` sends CC123 All-Notes-Off followed by CC120
All-Sound-Off through the AU's own `scheduleMIDIEventBlock` immediately after
`au.currentPreset = preset` and before AU state capture. It adds deterministic
source-order coverage for that sequence, repairs the unrelated stale
`TrackSourceSourceDisplayStateTests.swift` arguments that blocked AU test-target
compilation, and updates the preset owner-bug report as deterministic partial
evidence while leaving real-AU validation open.

Paired exact-output checks reported by the builder:

- `AudioInstrumentHostPresetsTests`: 30 passed, 0 failed; `xcodebuild` hung only
  while saving/finalizing logs after the pass and the stale process was killed.
- `scripts/diagnostics/realtime-path-lint.sh`: passed.
- `scripts/diagnostics/runtime-ownership-lint.sh`: passed.
- `git diff --check`: passed.

Prior exact-state observer passes remain valid only for the AU removal-teardown
checkpoint at `0f8a9fd8`; there are no exact-state architecture or testing
observer artifacts yet for `e4e43210`.

Remaining gaps: exact-state architecture/testing reviews for `e4e43210`,
deterministic runtime proof of audible preset switching without transport
disruption, and the intentionally human-present third-party AU
STOPPED-vs-PLAYING audibility/stability validation.

Lowest unmet pyramid layer: review/evidence. Architecture risk severity:
`caution`, not `line-stop-recommended`, because the shape uses sample-stamped AU
MIDI on a control path and does not add engine stop/start topology churn,
document hot-path writes, or render-thread file/lock work, but it still touches
high-risk AU preset/lifecycle behavior.

Next action kind for the build decider: review / evidence repair. Route
exact-state architecture and testing observers for `e4e43210`; preserve the
human-present AU validation gap rather than trying it unattended.

## Latest Orientation — 2026-07-04T21:34Z

The exact-state observer batch for committed checkpoint
`e4e43210fd72e62465cabf3454cbfa2db01aceac`
(`fix(audio): flush AU voices after preset switch`) now has both required gate
artifacts, and both pass. Worktree `.worktrees/au-runtime-safety` is clean on
`feature/au-runtime-safety`.

Paired evidence for `e4e43210`:

- builder final:
  `.meta/multipass/runtime/runs/actors/builder/2026-07-04T204250483Z-builder.final.md`
- orientation:
  `.meta/multipass/runtime/loops/build/au-runtime-safety/orient/2026-07-04T21-34Z-progress.md`
- architecture review pass:
  `.meta/multipass/runtime/loops/build/au-runtime-safety/observe/architecture-review/2026-07-04T212211Z-preset-flush-e4e43210.md`
- testing review pass:
  `.meta/multipass/runtime/loops/build/au-runtime-safety/observe/testing-review/2026-07-04T2130Z-preset-flush-e4e43210.md`

Architecture review found the preset-flush checkpoint keeps live AU
preset/control mutation inside `AudioInstrumentHost`, reuses the existing
`scheduleAllSoundOff(using:)` helper, adds no document hot path or duplicate
runtime owner, and does not introduce engine stop/start topology churn or
render-thread file/lock work. Testing review reran
`AudioInstrumentHostPresetsTests` and observed 30 tests, 0 failures; the
post-summary `xcodebuild` log-finalization hang was terminated after the green
summary. Lints paired to the commit passed:
`realtime-path-lint.sh`, `runtime-ownership-lint.sh`, and
`git diff --check HEAD~1..HEAD`.

Remaining gaps: human-present third-party AU STOPPED-vs-PLAYING
audibility/stability validation remains intentionally unrun in unattended mode,
and the owner preset bug remains `PARTIAL / OPEN` because this checkpoint
proves deterministic flush ordering only. The exact-commit batch metadata still
says `status: open` despite both observer artifacts existing and passing, which
is a process metadata gap rather than a product blocker.

Lowest unmet pyramid layer: human-present runtime evidence for full owner-bug
closure. Architecture risk severity: `caution`, not
`line-stop-recommended`.

Next action kind for the build decider: continuation or merge-candidacy
decision, depending on policy for accepting deterministic evidence before
attended AU validation. More exact-state architecture/testing review of
`e4e43210` is not the next useful action.

## Latest Decision — 2026-07-04T21:37Z

Disposition: `phase_complete_continue`.

Decision artifact:
`.meta/multipass/runtime/loops/build/au-runtime-safety/decide/2026-07-04T21-37Z-continue-preset-runtime-builder.md`

Builder continuation request:
`.meta/multipass/runtime/inbox/pending/2026-07-04T213753687Z-builder.md`

The preset-flush checkpoint at `e4e43210` is accepted as a bounded phase with
fresh exact-state architecture/testing passes. It is not a merge candidate:
the preset owner bug remains `PARTIAL / OPEN`, and the human-present third-party
AU STOPPED-vs-PLAYING audibility/stability gap remains intentionally unrun.

The next builder should continue from `e4e43210` in
`.worktrees/au-runtime-safety`, add the smallest unattended-safe deterministic
evidence or harness for the remaining preset no-change / hung-note behavior, or
write a compact branch validation artifact if the next honest evidence requires
a human-present third-party AU. Do not run real AU UI automation, audio-input
flows, visual scenarios, `osascript`, or other TCC-gated flows unattended. Do
not merge the checkpoint.

## Latest Builder — 2026-07-04T22:06Z

Builder continuation produced a clean committed checkpoint:

- commit: `ead7586f2cffd12f84bd13326dab240dbefa1a89`
  (`test(audio): pin AU preset command path`)
- final git state: clean in `.worktrees/au-runtime-safety`
- completion artifact:
  `.meta/multipass/runtime/loops/build/au-runtime-safety/act/2026-07-04T2206Z-preset-command-path-builder.md`

The checkpoint adds deterministic unattended coverage around the preset browser
command seam: successful preset selection must call the live preset loader
before committing the returned state blob and moving the current-preset readout;
failed live preset load must not commit document state or move the readout from
the last confirmed preset. The owner preset bug report now includes the
remaining human-present validation checklist and remains `PARTIAL / OPEN`.

Builder-reported checks: `AudioInstrumentHostPresetsTests` plus
`PresetBrowserSheetViewModelTests` observed `46 tests, 0 failures`;
`xcodebuild` hung after the green summary while finalizing logs and was
terminated. `realtime-path-lint.sh`, `runtime-ownership-lint.sh`, and
`git diff --check HEAD~1..HEAD` passed.

## Latest Orientation — 2026-07-04T22:03Z

The current output is committed checkpoint `ead7586f`, not a whole-feature
completion. It has builder-run targeted tests and lint evidence, but there are
no exact-state architecture or testing observer artifacts for this commit yet;
the prior observer passes are bounded to `e4e43210`.

Paired current-output evidence:

- builder final:
  `.meta/multipass/runtime/runs/actors/builder/2026-07-04T213753687Z-builder.final.md`
- act evidence:
  `.meta/multipass/runtime/loops/build/au-runtime-safety/act/2026-07-04T2206Z-preset-command-path-builder.md`
- orientation:
  `.meta/multipass/runtime/loops/build/au-runtime-safety/orient/2026-07-04T22-03Z-progress.md`

Remaining gaps: exact-state architecture review for `ead7586f`, exact-state
testing review for `ead7586f`, the recurring `xcodebuild` post-summary
log-finalization hang as a tooling caveat, and the human-present third-party AU
STOPPED-vs-PLAYING audibility/stability validation required for full owner-bug
closure. The owner preset bug remains `PARTIAL / OPEN`.

Lowest unmet pyramid layer: review/evidence. Architecture risk severity:
`caution`, not `line-stop-recommended`.

Next action kind for the build decider: review / evidence repair. Route
exact-state architecture and testing observers for `ead7586f`; if those pass,
the remaining decision is whether to hold for attended AU validation or accept
the branch only as a bounded deterministic checkpoint with that evidence gap
preserved.

## Latest Decision — 2026-07-04T22:08Z

Disposition: `needs_review`.

Decision artifact:
`.meta/multipass/runtime/loops/build/au-runtime-safety/decide/2026-07-04T22-08Z-observe-preset-command-path-checkpoint.md`

Started an exact-commit observation batch for the required loop gates on
`ead7586f2cffd12f84bd13326dab240dbefa1a89`:

- batch:
  `.meta/multipass/runtime/loops/build/au-runtime-safety/observe/batches/ead7586f2cffd12f84bd13326dab240dbefa1a89/batch.yaml`
- architecture-review request:
  `.meta/multipass/runtime/inbox/pending/2026-07-04T220801478Z-architecture-review-for-au-runtime-safety-preset-command-path-checkpoint.md`
- testing-review request:
  `.meta/multipass/runtime/inbox/pending/2026-07-04T220801557Z-testing-review-for-au-runtime-safety-preset-command-path-checkpoint.md`

This checkpoint is not a merge candidate. The next build-loop step is to wait
for the observer batch, then orient on paired architecture/testing evidence.
Human-present third-party AU STOPPED-vs-PLAYING validation remains explicitly
unrun in unattended mode.
