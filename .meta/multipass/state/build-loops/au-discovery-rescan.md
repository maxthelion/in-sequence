# au-discovery-rescan

- loop: `build/au-discovery-rescan`
- status: active
- branch: `feature/au-discovery-rescan`
- worktree: `.worktrees/au-discovery-rescan`
- created: 2026-06-16T19:52:14.407Z
- feature: `au-discovery-rescan`
- owner bugs:
  - `docs/bugs/20260616-104317-plugins-are-missing-from-the-list-of-eff/`
  - `docs/bugs/20260616-au-plugin-list-needs-rescan-without-relaunch/`
- setup evidence:
  `.meta/multipass/runtime/loops/project/act/2026-06-16T19-52Z-au-discovery-rescan-build-loop-setup.md`
- initial build-loop decision:
  `.meta/multipass/runtime/loops/build/au-discovery-rescan/decide/2026-06-16T19-52Z-route-initial-au-discovery-rescan.md`
- initial builder request (blocked/failed):
  `.meta/multipass/runtime/inbox/blocked/2026-06-16T195214407Z-au-discovery-rescan-initial-build.md`

This is the durable build-loop summary. Transient inboxes, runs, and evidence
live under `.meta/multipass/runtime/loops/build/au-discovery-rescan/`.

## Compact Build Intent

This loop exists only to resolve the AU plug-in discovery/rescan bug group:
effect and instrument picker lists appear incomplete or stale after launch, and
newly installed Audio Units require app relaunch before they appear.

The builder should investigate and fix AU effect/instrument enumeration
completeness after restart, including any cap, truncation, or alphabetical-list
issue. It should add a bounded non-blocking runtime rescan action that
invalidates and rewarms `AudioInstrumentChoiceCache` and
`AudioEffectChoiceCache` without UI freeze, and expose clear scanning/rescan
state in the relevant pickers or menus.

Acceptance evidence must explicitly cover restart-time list completeness and
runtime rescan behavior for both effects and instruments.

Do not use this loop for mixer/channel-strip polish, Track Perform pattern-cell
behavior, routing-source-mixer-split, observability-log-issues, midi-interfaces,
merge, push, worktree deletion, or unrelated root cleanup.

## Setup State

- branch: `feature/au-discovery-rescan`
- worktree: `.worktrees/au-discovery-rescan`
- setup-observed branch head:
  `23c2715c3ed7db1f89cde5c7585d18bd4065c50f`
- setup-observed local `main`:
  `23c2715c3ed7db1f89cde5c7585d18bd4065c50f`
- setup-observed worktree state: clean

No product code, merge, rebase, push, worktree deletion, request lifecycle move,
or root cleanup was performed by the container setup.

## Current Decision

2026-06-17T10:31Z decision:

`.meta/multipass/runtime/loops/build/au-discovery-rescan/decide/2026-06-17T10-31Z-route-eb0f0e6c-evidence-repair.md`

Current AU discovery/rescan state:
`clean_committed_fixture_output_needs_evidence_repair`.

The decider scheduled one focused builder evidence-repair pass for exact output
`eb0f0e6cd0802b2ad54337f3aee1154c033de4a3` (`eb0f0e6c Add AU rescan visual
scenario fixtures`):

`.meta/multipass/runtime/inbox/pending/2026-06-17T101031293Z-builder.md`

The fresh testing, UX/IA, and visual-economy reviews accept the fixture UI
grammar but return `needs-correction` because the PNG build badge still shows
`4ce14c75`, no bounded non-fixture runtime artifact proves real installed
`aumu`/`aufx` choices after explicit rescan without relaunch, the focused XCTest
passed its assertion but timed out at the `xcodebuild` process level, and
exact-state architecture evidence for the fixture commit is missing or needs
scoped inheritance. This is evidence/provenance repair, not broad product/UI
rework. No merge candidacy, product-owner attention, push, rebase, or worktree
cleanup is indicated.

2026-06-17T10:12Z orientation:

`.meta/multipass/runtime/loops/build/au-discovery-rescan/orient/2026-06-17T10-12Z-build-orienter-progress.md`

Current AU discovery/rescan state:
`clean_committed_fixture_output_needs_evidence_repair`.

The worktree is clean at `eb0f0e6cd0802b2ad54337f3aee1154c033de4a3`
(`eb0f0e6c Add AU rescan visual scenario fixtures`). The previously dirty AU
picker/menu visual fixture continuation is now committed, with 10 screenshot and
status artifacts under
`.meta/multipass/runtime/loops/build/au-discovery-rescan/act/manual-au-rescan-states-20260617T0910Z/`
covering instrument/effect ready, scanning-disabled, ready-count, previous-list,
and long-list states.

Fresh testing, UX/IA, and visual-economy reviews for `eb0f0e6c` all return
`needs-correction`. They accept the fixture UI grammar as coherent but do not
accept the branch as gate-ready because the PNG build badge still shows
`feature/au-discovery-rescan 4ce14c75`, no non-fixture runtime artifact proves
real installed `aumu`/`aufx` choices appear after explicit rescan without
relaunch, and the focused publication XCTest reached a passing assertion but the
`xcodebuild` invocation timed out with `** BUILD INTERRUPTED **`. A fresh
architecture review artifact for `eb0f0e6c` is also not normalized in `observe/`
yet.

Next action kind appears to be evidence repair/continuation: recapture or
explain/fix the exact-build identity mismatch, add one bounded non-fixture
runtime rescan acceptance artifact for instruments and effects, rerun or
adjudicate the focused XCTest timeout, and complete/inherit the architecture
gate with rationale. No merge candidacy, product/UI rework, product-owner
attention, push, rebase, or worktree cleanup is indicated.

2026-06-17T09:10Z decision:

`.meta/multipass/runtime/loops/build/au-discovery-rescan/decide/2026-06-17T09-10Z-observation-batch-already-pending.md`

Current AU discovery/rescan state:
`clean_committed_exact_output_needs_review`.

The latest repository state is fresher than the 09:00 orientation. The
worktree is clean at `eb0f0e6cd0802b2ad54337f3aee1154c033de4a3`
(`eb0f0e6c Add AU rescan visual scenario fixtures`), with the prior dirty
visual fixture work now committed. The 10 AU picker/menu screenshots and status
files under
`.meta/multipass/runtime/loops/build/au-discovery-rescan/act/manual-au-rescan-states-20260617T0910Z/`
therefore correspond to a clean exact output.

No new request was created by the 09:10 decider run because an exact-state
observation batch for `eb0f0e6c` is already open at
`.meta/multipass/runtime/loops/build/au-discovery-rescan/observe/batches/eb0f0e6cd0802b2ad54337f3aee1154c033de4a3/batch.yaml`
with pending architecture, testing, UX/IA, and visual-economy reviewer
requests. The next build-loop action is to let those observers complete and
then have the build orienter synthesize the batch. No merge candidacy,
builder rework, product-owner attention, push, rebase, or worktree cleanup is
scheduled.

2026-06-17T09:00Z orientation:

`.meta/multipass/runtime/loops/build/au-discovery-rescan/orient/2026-06-17T09-00Z-build-orienter-progress.md`

Current AU discovery/rescan state:
`dirty_partial_visual_fixture_progress_needs_continuation_and_exact_review`.

The branch HEAD is still `4ce14c75940766a319592000b23534288d2f0840`
(`4ce14c75 Test AU plugin rescan publication`), but the worktree now has
uncommitted fixture/automation changes in `EngineController`, AU destination
UI, mixer/track visual command hooks, `VisualScenarioCommandRunner`, and
untracked `scripts/visual-scenarios/au-plugin-rescan-states.sh`.

Fresh manual AU rescan-state artifacts produced 10 screenshots and status files
under
`.meta/multipass/runtime/loops/build/au-discovery-rescan/act/manual-au-rescan-states-20260617T0910Z/`
for instrument/effect ready, scanning-disabled, ready-count, previous-list, and
long-list states. The status files show the automation reached the intended
track AU instrument sheet and mixer AU effect sheet fixture states, but this is
dirty-output fixture evidence, not exact-state gate evidence for clean
`4ce14c75`.

Next action kind appears to be builder continuation/evidence repair: finish the
dirty visual fixture work, commit or discard it with rationale, run focused
build/test evidence, and then route exact-state review/recapture. Real runtime
`aufx`/`aumu` rescan-without-relaunch acceptance remains missing. No merge
candidacy or product-owner attention is indicated.

2026-06-17T08:44Z decision:

`.meta/multipass/runtime/loops/build/au-discovery-rescan/decide/2026-06-17T08-44Z-route-runtime-visual-acceptance-continuation.md`

Current AU discovery/rescan state:
`clean_committed_focused_test_cleared_needs_runtime_visual_acceptance`.

The decider scheduled one bounded builder evidence continuation for exact
output `4ce14c75940766a319592000b23534288d2f0840` (`4ce14c75 Test AU plugin
rescan publication`):

`.meta/multipass/runtime/inbox/pending/2026-06-17T084525577Z-AU-discovery-rescan-runtime-visual-acceptance-continuation.md`

The request preserves the clean output unless a tightly scoped evidence
fixture/test change is necessary and committed. It asks the builder to report
exact commit/worktree state, CoreAudio/HAL and app window health, runtime/manual
`aufx` and `aumu` rescan-without-relaunch acceptance or precise local
impossibility, and exact AU picker/menu screenshot paths or visual-scenario
fixture gaps for ready, scanning, disabled/repeated-rescan, ready-count,
previous-list, and long-list states. The now-green focused EngineController
publication XCTest is explicitly not the main work.

No merge escalation, product-owner attention, broad UI/product rework, push,
rebase, worktree deletion, mixer/routing/Track Perform work, or PM promotion is
scheduled.

2026-06-17T02:53Z decision:

`.meta/multipass/runtime/loops/build/au-discovery-rescan/decide/2026-06-17T02-53Z-escalate-hal-machine-state-block.md`

Current AU discovery/rescan state:
`clean_committed_blocked_by_local_hal_proxy_stall`.

The latest orienter confirmed the exact output remains clean at
`4ce14c75940766a319592000b23534288d2f0840` (`4ce14c75 Test AU plugin rescan
publication`). Architecture is paired as pass-with-caution, but testing, UX/IA,
and visual-economy gates remain evidence-insufficient. The HAL-bounded builder
pass reproduced the local CoreAudio/HAL proxy-stall family with the cheap
app-hosted smoke probe and stopped without code changes.

No further build-loop builder retry is scheduled because the loop-local builder
cannot repair the machine-state dependency, and another retry would likely
repeat the same stall instead of producing paired evidence. The decider
escalated one compact note to the top project decider to decide whether to pause
this build loop pending machine recovery, route machine-state/process recovery,
or obtain app-hosted evidence on a healthy CoreAudio/HAL session. No merge
escalation, product/UI rework, push, rebase, or worktree cleanup is scheduled.

2026-06-17T02:40Z decision:

`.meta/multipass/runtime/loops/build/au-discovery-rescan/decide/2026-06-17T02-40Z-route-hal-bounded-evidence-repair.md`

Current AU discovery/rescan state:
`clean_committed_needs_evidence_repair`.

The decider scheduled one HAL-bounded builder evidence pass for exact output
`4ce14c75940766a319592000b23534288d2f0840` (`4ce14c75 Test AU plugin rescan
publication`):

`.meta/multipass/runtime/inbox/pending/2026-06-17T023822416Z-AU-discovery-rescan-HAL-bounded-evidence-repair.md`

The request preserves the clean committed output and forbids merge, push,
rebase, worktree deletion, and broad product/UI rework. It asks the builder to
first run a cheap CoreAudio/HAL health probe. If the same proxy-stall state is
still present, the builder should stop quickly with compact blocker evidence
instead of repeating long app-hosted attempts. If HAL is healthy, the builder
should obtain the missing exact-state focused XCTest, runtime `aufx`/`aumu`
rescan-without-relaunch acceptance, and AU picker/menu screenshots for
instrument and effect ready/scanning/disabled/repeated-rescan/ready-count/
previous-list/long-list states.

No merge escalation, product-owner attention, systemic line-stop, or next
feature phase is scheduled.

2026-06-17T01:47Z decision:

`.meta/multipass/runtime/loops/build/au-discovery-rescan/decide/2026-06-17T01-47Z-route-evidence-repair.md`

Current AU discovery/rescan state:
`clean_committed_needs_evidence_repair`.

The decider scheduled one bounded builder evidence-repair pass for exact output
`4ce14c75940766a319592000b23534288d2f0840` (`4ce14c75 Test AU plugin rescan
publication`):

`.meta/multipass/runtime/inbox/pending/2026-06-17T014731661Z-Repair-AU-discovery-rescan-evidence-for-exact-output-4ce14c75.md`

The request preserves the clean committed output and forbids merge, push,
rebase, worktree deletion, or broad product/UI rework. It asks the builder to
repair missing exact-state evidence: focused EngineController publication XCTest
pass or precise HAL/local-impossibility adjudication with deterministic proof
where appropriate; broad app-hosted gate evidence or adjudication; runtime/manual
acceptance that newly available `aufx` effects and `aumu` instruments appear
after explicit `Rescan plug-ins` without relaunch; exact-build AU picker/menu
captures for ready/scanning/disabled/repeated-rescan/ready-count/previous-list/
long-list states; and loop-local normalization of architecture and UX/IA actor
finals into `observe/` artifacts.

No merge escalation, product-owner attention, systemic line-stop, or next
feature phase is scheduled.

2026-06-17T01:27Z decision:

`.meta/multipass/runtime/loops/build/au-discovery-rescan/decide/2026-06-17T01-27Z-start-exact-output-observation-batch.md`

Current AU discovery/rescan state:
`clean_committed_needs_exact_review`.

The decider started one exact-state observation batch for commit
`4ce14c75940766a319592000b23534288d2f0840`:

`.meta/multipass/runtime/loops/build/au-discovery-rescan/observe/batches/4ce14c75940766a319592000b23534288d2f0840/batch.yaml`

Expected observers:

- `architecture-review`
- `testing-review`
- `ux-ia-review`
- `visual-economy-review`

Generated requests:

- `.meta/multipass/runtime/inbox/pending/2026-06-17T012718949Z-architecture-review-for-AU-discovery-rescan-exact-output-4ce14c75.md`
- `.meta/multipass/runtime/inbox/pending/2026-06-17T012719012Z-testing-review-for-AU-discovery-rescan-exact-output-4ce14c75.md`
- `.meta/multipass/runtime/inbox/pending/2026-06-17T012719078Z-ux-review-for-AU-discovery-rescan-exact-output-4ce14c75.md`
- `.meta/multipass/runtime/inbox/pending/2026-06-17T012719141Z-visual-economy-review-for-AU-discovery-rescan-exact-output-4ce14c75.md`

The batch asks observers to interpret the exact `4ce14c75` output, including
whether prior `80be3f56` evidence can be inherited for any gate, whether the
known CoreAudio/HAL launch/test stall is an accepted local-impossibility
adjudication, and whether missing `aufx`/`aumu` runtime rescan acceptance plus
AU picker/menu screenshots require another builder evidence-repair pass.

No builder rework, merge escalation, product-owner attention, or
phase-continuation is scheduled until the observer batch completes and the
orienter synthesizes the gate results.

2026-06-17T00:32Z decision:

`.meta/multipass/runtime/loops/build/au-discovery-rescan/decide/2026-06-17T00-32Z-route-dirty-evidence-repair-continuation.md`

Current AU discovery/rescan state:
`dirty_partial_needs_continuation_and_evidence_repair`.

The decider scheduled one focused builder continuation for the second
interrupted evidence-repair pass. The next builder must preserve the existing
dirty worktree unless deliberately rejecting it with rationale, finish/verify
and commit-or-discard the focused `EngineController.rescanAudioPluginChoices()`
publication-test work, and remove or explicitly account for untracked
`default.profraw`. It should then continue the outstanding evidence repair:
broad app-hosted gate or compact CoreAudio/HAL adjudication, direct publication
evidence, manual/runtime `aufx` + `aumu` rescan-without-relaunch acceptance or
local impossibility note, exact-build AU picker/menu captures, and loop-local
normalization of the testing-review final.

No merge, product-owner attention, or broad product/UI rework is scheduled.

2026-06-16T23:11Z decision:

`.meta/multipass/runtime/loops/build/au-discovery-rescan/decide/2026-06-16T23-11Z-route-dirty-evidence-repair-continuation.md`

Current AU discovery/rescan state:
`dirty_partial_needs_continuation_and_evidence_repair`.

The decider scheduled one focused builder continuation for the interrupted
evidence-repair pass. The next builder must preserve the existing dirty
worktree unless deliberately rejecting it with rationale, then finish/verify and
commit-or-discard the focused `EngineController.rescanAudioPluginChoices()`
publication-test work. After that, the builder should continue the outstanding
evidence repair: broad app-hosted gate or compact CoreAudio/HAL adjudication,
direct publication evidence, manual/runtime `aufx` + `aumu`
rescan-without-relaunch acceptance or local impossibility note, exact-build AU
picker/menu captures, and loop-local normalization of the testing-review final.

No merge, product-owner attention, or broad product/UI rework is scheduled.

2026-06-16T22:24Z decision:

`.meta/multipass/runtime/loops/build/au-discovery-rescan/decide/2026-06-16T22-24Z-route-evidence-repair.md`

Current AU discovery/rescan state: `needs_evidence_repair`.

The decider scheduled one builder evidence-repair pass for exact output
`80be3f56596c2d77d42a62f02ea2e49c2cd75b1b`. The builder should not merge or
start broad product rework. It should obtain exact-build AU picker/menu captures,
broad app-hosted test evidence or a compact CoreAudio/HAL machine-state
adjudication, direct `EngineController.rescanAudioPluginChoices()` publication
evidence, manual/runtime `aufx` + `aumu` rescan-without-relaunch acceptance, and
a normalized loop-local testing-review evidence artifact. If this requires a
test-only commit or exposes a real product defect, the builder must record the
new exact output commit and completion evidence for the next orient/decide pass.

Builder request now blocked after failed actor run:
`.meta/multipass/runtime/inbox/blocked/2026-06-16T222146945Z-Repair-AU-discovery-rescan-evidence.md`

2026-06-16T21:26Z decision:

`.meta/multipass/runtime/loops/build/au-discovery-rescan/decide/2026-06-16T21-26Z-start-exact-output-observation-batch.md`

Current AU discovery/rescan state: `needs_review`.

The decider started one exact-state observation batch for commit
`80be3f56596c2d77d42a62f02ea2e49c2cd75b1b`:

`.meta/multipass/runtime/loops/build/au-discovery-rescan/observe/batches/80be3f56596c2d77d42a62f02ea2e49c2cd75b1b/batch.yaml`

Expected observers:

- `architecture-review`
- `testing-review`
- `ux-ia-review`
- `visual-economy-review`

No builder rework, merge escalation, or phase continuation is scheduled until
the observer batch reports whether the exact output passes, needs focused
rework, or needs evidence repair.

2026-06-16T20:10Z decision:

`.meta/multipass/runtime/loops/build/au-discovery-rescan/decide/2026-06-16T20-10Z-route-dirty-partial-rework.md`

Previous AU discovery/rescan state: `committed_needs_review_and_evidence_repair`.

## Current Orientation

2026-06-17T08:37Z orientation:

`.meta/multipass/runtime/loops/build/au-discovery-rescan/orient/2026-06-17T08-37Z-build-orienter-focused-test-unblock.md`

Current AU discovery/rescan state:
`clean_committed_focused_test_cleared_needs_runtime_visual_acceptance`.

The current output remains clean at
`4ce14c75940766a319592000b23534288d2f0840` (`4ce14c75 Test AU plugin rescan
publication`). Manual supervisory evidence cleared the previously missing
focused XCTest:
`SequencerAITests/EngineControllerTests/test_rescanAudioPluginChoicesPublishesScanningThenReadyCountsAndIgnoresRepeat`
passed locally with `1` test and `0` failures. The run still emitted the local
CoreAudio/HAL proxy warning, but it did not block this focused non-UI
publication proof.

Fresh gate state: architecture remains `pass` with risk severity `caution`;
testing is improved but still `evidence-insufficient`; UX/IA remains
`evidence-insufficient`; visual economy remains `evidence-insufficient`.
The focused publication test gap is now cleared. Remaining evidence gaps are
runtime/manual acceptance that newly available `aufx` effects and `aumu`
instruments appear after explicit `Rescan plug-ins` without relaunch, broad
app-hosted gate evidence or explicit acceptance of the HAL limitation, and
exact-build AU picker/menu screenshots for ready, scanning,
disabled/repeated-rescan, ready-count, previous-list, and long-list states.

`scripts/visual-scenarios/qa-surface-coverage.sh` still says there is no runner
command coverage for AU preset/macro sheets needing a live AU destination; the
manual unblock artifact records live AU destination picker states as still
uncovered. Preserve this as `tooling-fixture-gap` / `missing-runtime-state`,
not as product/UI rework and not as visual acceptance.

Lowest unmet pyramid layer: testing/evidence. Architecture risk severity:
`caution`, no line-stop. Next action kind for the decider appears to remain
`evidence repair / continuation`: obtain runtime visual acceptance on a
healthy app-hosted CoreAudio/HAL session or add a bounded visual-scenario
fixture for the uncovered AU picker/menu states, unless the decider explicitly
accepts focused publication evidence plus the existing HAL limitation as
sufficient. No merge candidacy, broad UI/product rework, push, worktree
deletion, or product-owner attention is indicated.

2026-06-17T02:47Z orientation:

`.meta/multipass/runtime/loops/build/au-discovery-rescan/orient/2026-06-17T02-47Z-build-orienter-progress.md`

Current AU discovery/rescan state:
`clean_committed_blocked_by_local_hal_needs_evidence_repair`.

The current output remains clean at
`4ce14c75940766a319592000b23534288d2f0840` (`4ce14c75 Test AU plugin rescan
publication`). The fresh HAL-bounded builder pass preserved that exact output
and changed no product code, UI code, tests, merge state, or worktree cleanup.

The builder ran the requested cheap CoreAudio/HAL probe:
`MainAudioGraphDeviceSwitchTests/test_applyDefaultDevicesToMainAudioGraphSmoke`.
The app-hosted test process launched and the selected smoke test started, then
reproduced the same local HAL proxy failure family:
`HALC_ShellObject::SetPropertyData: call to the proxy failed, Error: 1852797029
(nope)`, followed by `** BUILD INTERRUPTED **`. No `SequencerAI` process was
left running. This confirms the local machine-state blocker and makes another
immediate app-hosted runtime/capture attempt low value.

Fresh gate state is unchanged in substance: architecture is `pass` with risk
severity `caution`; testing remains `evidence-insufficient`; UX/IA remains
`evidence-insufficient`; visual economy remains `evidence-insufficient`.
Inherited evidence is still limited to unchanged architecture/cache context.
Prior testing, UX/IA, and visual-economy gates were not passing evidence and
cannot be inherited as passes.

Remaining gaps: completed focused
`EngineController.rescanAudioPluginChoices()` publication XCTest or equivalent
non-HAL proof where appropriate; broad app-hosted gate evidence or accepted
substitute; runtime acceptance that newly available `aufx` effects and `aumu`
instruments appear after explicit `Rescan plug-ins` without relaunch; and
exact-build AU picker/menu screenshots for ready, scanning,
disabled/repeated-rescan, ready-count, previous-list, and long-list states.
The gap type is `missing-runtime-state` caused by local CoreAudio/HAL machine
state; for visual gates, missing screenshots remain real evidence gaps rather
than product/UI rework.

Lowest unmet pyramid layer: testing/evidence. Architecture risk severity:
`caution`, no line-stop. Next action kind for the decider appears to remain
`evidence repair / continuation`, gated on a healthy CoreAudio/HAL session for
app-hosted checks and screenshots, with bounded deterministic non-HAL proof
useful only for non-visual claims. No product/UI rework, merge candidacy,
systemic escalation, or product-owner attention is indicated.

2026-06-17T02:32Z orientation:

`.meta/multipass/runtime/loops/build/au-discovery-rescan/orient/2026-06-17T02-32Z-build-orienter-progress.md`

Current AU discovery/rescan state:
`clean_committed_needs_evidence_repair`.

The current output remains clean at
`4ce14c75940766a319592000b23534288d2f0840` (`4ce14c75 Test AU plugin rescan
publication`). The fresh builder evidence-repair pass preserved that exact
output and changed no product code. It repaired loop-local evidence plumbing by
normalizing the architecture and UX/IA actor finals into `observe/`, and it
added exact-output check evidence: `git diff --check` passed, non-hosted
`xcodebuild build` passed, and the focused app-hosted
`EngineController.rescanAudioPluginChoices()` publication XCTest compiled,
launched, and started.

The focused XCTest did not complete: it timed out after 240s in the same
CoreAudio/HAL proxy failure family already accepted by reviewers as local
machine-state impossibility for this actor cycle. That adjudication explains
why another immediate local app-hosted rerun or capture retry is not useful; it
does not convert missing XCTest, runtime acceptance, or screenshots into gate
passes.

Fresh gate state: architecture is `pass` with risk severity `caution`; testing
is still `evidence-insufficient`; UX/IA is still `evidence-insufficient`;
visual economy is still `evidence-insufficient`. Prior inheritance is limited
to unchanged architecture/cache context, because prior testing/UX/visual gates
were not passing evidence.

Remaining gaps: broad app-hosted gate evidence or a stronger deterministic
substitute where appropriate; completed focused publication proof; runtime
acceptance that newly available `aufx` effects and `aumu` instruments appear
after explicit `Rescan plug-ins` without relaunch; and exact-build AU
picker/menu screenshots for ready, scanning, disabled/repeated-rescan,
ready-count, previous-list, and long-list states. The `4ce14c75` observation
batch file still says `status: open` despite expected results now existing as
direct or normalized artifacts; this is compact status hygiene, not a product
blocker.

Lowest unmet pyramid layer: testing/evidence. Architecture risk severity:
`caution`, no line-stop. Next action kind for the decider appears to remain
`evidence repair / continuation`, preferably on a healthy CoreAudio/HAL session
or via bounded deterministic non-HAL proof only for non-visual claims. No
product/UI rework, merge candidacy, systemic escalation, or product-owner
attention is indicated.

2026-06-17T01:41Z orientation:

`.meta/multipass/runtime/loops/build/au-discovery-rescan/orient/2026-06-17T01-41Z-build-orienter-progress.md`

Current AU discovery/rescan state:
`clean_committed_needs_evidence_repair`.

The current output remains clean at
`4ce14c75940766a319592000b23534288d2f0840` (`4ce14c75 Test AU plugin rescan
publication`). This is a focused evidence-repair continuation on top of
`80be3f56`, touching only `Sources/Engine/EngineController.swift` and
`Tests/SequencerAITests/Engine/EngineControllerTests.swift`. It adds the
injectable `audioPluginChoiceRescanner`, publishes ready counts from
`EngineController.rescanAudioPluginChoices()`, and adds a focused app-hosted
publication test.

Fresh exact-output observer synthesis: architecture is `pass` with risk
severity `caution`; testing is `evidence-insufficient`; UX/IA is
`evidence-insufficient`; visual economy is `evidence-insufficient`. The
CoreAudio/HAL stall is accepted by reviewers as a local-impossibility
adjudication for this actor cycle, so another immediate local rerun is not the
right evidence move. It does not turn the missing focused XCTest pass, broad
gate, runtime `aufx`/`aumu` rescan-without-relaunch acceptance, or AU
picker/menu screenshots into passing evidence.

Paired current evidence includes the builder continuation, loop-local testing
and visual-economy reviews, the exact-build capture/HAL sample bundle, and actor
finals for architecture and UX/IA. Process/evidence gap: the architecture and
UX/IA requests are done but wrote only actor finals, not loop-local `observe/`
artifacts, so they still need normalization if the loop wants all gate evidence
under `observe/`.

Lowest unmet pyramid layer: testing/evidence. Architecture risk severity:
`caution`, no line-stop. Next action kind for the decider appears to be
`evidence repair / continuation`: repair evidence on a healthy CoreAudio/HAL
session or via deterministic non-HAL proof where appropriate, then recapture and
review exact AU picker/menu states. No product/UI rework, merge candidacy,
systemic escalation, or product-owner attention is indicated by current
evidence.

2026-06-17T01:21Z orientation:

`.meta/multipass/runtime/loops/build/au-discovery-rescan/orient/2026-06-17T01-21Z-build-orienter-progress.md`

Current AU discovery-rescan state:
`clean_committed_needs_exact_review_and_evidence_repair`.

The branch now has a clean committed evidence-repair output at
`4ce14c75940766a319592000b23534288d2f0840` (`4ce14c75 Test AU plugin
rescan publication`). This supersedes the previous dirty-partial state. The
new commit is a focused continuation on top of the whole-feature claim at
`80be3f56`, touching only:

- `Sources/Engine/EngineController.swift`
- `Tests/SequencerAITests/Engine/EngineControllerTests.swift`

The builder removed accidental untracked `default.profraw`; the worktree is
clean. The committed continuation adds `AudioPluginChoiceScanResult`, injects
`audioPluginChoiceRescanner`, publishes rescan ready counts through
`EngineController.rescanAudioPluginChoices()`, and adds an async app-hosted
EngineController publication test for scanning state, repeated-rescan no-op,
ready counts, and display text.

Paired evidence for `4ce14c75`: `git diff --check` passed; `xcodebuild build`
passed; the focused EngineController app-hosted XCTest built and started but
did not complete because it stalled in the known CoreAudio/HAL proxy failure
family; exact-build launch/capture also stalled before a usable app window,
with a sample showing `MainAudioGraph.init -> AVAudioEngine mainMixerNode ->
HALC_ShellObject::HasProperty -> mach_msg2_trap`.

Architecture pass remains only for `80be3f56` with severity `caution`; because
`4ce14c75` changes `EngineController` publication behavior, architecture and
testing should not be treated as exact-state passed by inheritance. UX/IA and
visual-economy remain evidence-insufficient: prior capture/focus gaps persist,
and the new exact-build capture attempt produced desktop/no-window evidence,
not AU picker/menu screenshots.

Missing evidence remains: exact-state architecture/testing interpretation for
`4ce14c75`; focused publication test completion or reviewer-accepted HAL
adjudication; broad app-hosted gate or accepted HAL adjudication;
manual/runtime `aufx` + `aumu` rescan-without-relaunch acceptance or accepted
local-impossibility note; and exact-build AU picker/menu captures after
capture/focus/HAL repair.

Lowest unmet pyramid layer: testing/evidence. Architecture risk severity:
`caution`, no line-stop. Next action kind for the decider appears to be
`review / evidence repair`: use `4ce14c75` as the new exact output for
observer interpretation while preserving the machine/capture gaps. No
product/UI rework, merge candidacy, escalation, or product-owner attention is
indicated by current evidence.

2026-06-17T00:27Z orientation:

`.meta/multipass/runtime/loops/build/au-discovery-rescan/orient/2026-06-17T00-27Z-build-orienter-progress.md`

Current AU discovery/rescan state:
`dirty_partial_needs_continuation_and_evidence_repair`.

The last complete builder output remains the whole-feature claim at
`80be3f56596c2d77d42a62f02ea2e49c2cd75b1b`
(`80be3f56 Fix AU plugin discovery rescan`). A second evidence-repair
continuation run
`2026-06-16T231211881Z-Continue-AU-discovery-rescan-evidence-repair` failed
with `usage_rate_limit` / `SIGTERM` before writing a final artifact and left
the worktree dirty:

- `Sources/Engine/EngineController.swift`
- `Tests/SequencerAITests/Engine/EngineControllerTests.swift`
- untracked `default.profraw`

The dirty diff is still focused on missing
`EngineController.rescanAudioPluginChoices()` publication evidence. It adds an
injectable `audioPluginChoiceRescanner`, `AudioPluginChoiceScanResult`, an async
EngineController publication test, and test fakes for `SamplePlaybackSink` and
`MasterBusHosting`. Current tracked diff size is 2 files, 148 insertions, 7
deletions; orienter `git diff --check` passed. The failure artifact indicates a
selected EngineController evidence test again stalled on the HAL proxy path
before completion. There is no compile result, passing focused test result,
commit, or builder completion artifact for this dirty state.

Paired evidence for committed `80be3f56` remains as before: build and focused
cache tests exist; architecture passed with severity `caution`; testing, UX/IA,
and visual-economy remain `evidence-insufficient`. The current dirty partial
has only failure evidence plus local status/diff inspection, so it is not
reviewed or merge-ready.

Missing evidence remains: finish/verify/commit-or-discard the dirty
EngineController publication-test change; handle `default.profraw`; broad
app-hosted gate or compact HAL/CoreAudio adjudication; manual/runtime `aufx` +
`aumu` rescan-without-relaunch acceptance or precise local impossibility note;
exact-build AU picker/menu screenshots after capture/focus repair; and
loop-local normalization of the testing-review actor final.

Lowest unmet pyramid layer: testing/evidence. Architecture risk severity:
`caution` for committed output; dirty partial is unreviewed but appears local to
testability and publication evidence. Next action kind for the decider appears
to be `continuation / evidence repair`: recover the dirty continuation in
place, then continue evidence repair. No product/UI rework or product-owner
attention is indicated by current evidence.

2026-06-16T23:06Z orientation:

`.meta/multipass/runtime/loops/build/au-discovery-rescan/orient/2026-06-16T23-06Z-build-orienter-progress.md`

Current AU discovery/rescan state: `dirty_partial_needs_continuation_and_evidence_repair`.

The last complete builder output is still the whole-feature claim at
`80be3f56596c2d77d42a62f02ea2e49c2cd75b1b`
(`80be3f56 Fix AU plugin discovery rescan`), but the worktree is no longer
clean. The 22:24 evidence-repair builder run failed with `usage_rate_limit` /
`SIGTERM` before final evidence and left uncommitted partial edits:

- `Sources/Engine/EngineController.swift`
- `Tests/SequencerAITests/Engine/EngineControllerTests.swift`

The dirty diff is focused on the missing
`EngineController.rescanAudioPluginChoices()` publication evidence: it injects
an `audioPluginChoiceRescanner`, adds `AudioPluginChoiceScanResult`, and adds
an async test for scanning state, repeated-rescan no-op behavior, and ready
counts. Diff size is 2 files, 104 insertions, 7 deletions; orienter
`git diff --check` passed. There is no compile/test result, commit, or builder
completion artifact for this dirty state.

Paired evidence for the committed `80be3f56` output remains as below: focused
cache tests and build evidence exist; architecture passed with severity
`caution`; testing, UX/IA, and visual-economy remain
`evidence-insufficient`. The fresh dirty partial has only compact failure
evidence and local diff inspection, so it is not reviewed or merge-ready.

Missing evidence remains: finish/verify/commit-or-discard the dirty
EngineController publication-test change; broad app-hosted gate or compact
HAL/CoreAudio adjudication; manual/runtime `aufx` + `aumu`
rescan-without-relaunch acceptance or precise local impossibility note;
exact-build AU picker/menu screenshots after capture/focus repair; and
loop-local normalization of the testing-review actor final.

Lowest unmet pyramid layer: testing/evidence. Architecture risk severity:
`caution`, local to this loop. Next action kind for the decider appears to be
`continuation / evidence repair`: recover the interrupted builder pass in
place, then continue evidence repair. No product/UI rework or product-owner
attention is indicated by current evidence.

2026-06-16T22:16Z orientation:

`.meta/multipass/runtime/loops/build/au-discovery-rescan/orient/2026-06-16T22-16Z-build-orienter-progress.md`

Current AU discovery/rescan state: `needs_evidence_repair`.

The builder output is still a whole-feature claim on
`feature/au-discovery-rescan`:

- commit: `80be3f56596c2d77d42a62f02ea2e49c2cd75b1b`
  (`80be3f56 Fix AU plugin discovery rescan`)
- worktree: clean
- changed files: 9 files, 459 insertions, 120 deletions, limited to AU choice
  caches, `EngineController`, AU picker/menu surfaces, and focused cache tests.

Current implementation claim:

- `AudioInstrumentChoiceCache` and `AudioEffectChoiceCache` use
  condition-backed cache states with explicit rescan APIs and previous-choice
  snapshots during scanning.
- `EngineController` exposes `AudioPluginChoiceScanState` and a background
  `rescanAudioPluginChoices()` path that publishes ready counts to main.
- AU picker/menu surfaces expose "Rescan plug-ins" controls and scan-state text.
- Effect-picker `.prefix(16)` truncation was removed from the touched insert
  surfaces.
- Focused cache tests cover instrument/effect rescan replacement,
  previous-list availability, repeated active rescan no-ops, and large effect
  lists without the prior cap.

Paired exact-output evidence:

- Builder: `git diff --check` passed, macOS app build passed, focused
  `AudioInstrumentChoicesCacheTests` printed 10 tests / 0 failures under both
  `xcodebuild test` and `test-without-building`.
- Builder broad gate: app-hosted XCTest started and the focused AU cache tests
  passed inside it, then the run stalled in `AudioInstrumentHostPresetsTests`
  with repeated HAL proxy errors and was killed as machine-state blocked.
- Architecture observer: `pass`, severity `caution`, with no architecture
  correction required before other gates. Residual local risks are stale cache
  comments, duplicated SwiftUI scan-header helpers, and an edge case where a
  first-ever rescan could still block through `defaultChoices`.
- Testing observer: `evidence-insufficient`. The focused tests are meaningful,
  but broad app-hosted gate evidence,
  `EngineController.rescanAudioPluginChoices()` publication evidence, and
  manual/runtime newly installed `aufx`/`aumu` acceptance remain missing. The
  testing actor completed but wrote only an actor final, not a normal loop-local
  `observe/*.md` artifact.
- UX/IA observer: `evidence-insufficient` due to
  `capture-permission-or-focus`; console was at `loginwindow`, the visible
  SequencerAI window was a stale `feature/routing-source-mixer-split` build,
  and exact AU-rescan processes had no usable windows.
- Visual-economy observer: `evidence-insufficient` due to
  `capture-permission-or-focus`; Peekaboo/window control did not capture target
  AU picker/menu surfaces, and fallback screenshot captured only desktop
  wallpaper.

Missing evidence:

- broad gate completion or explicit accepted adjudication of the CoreAudio/HAL
  machine-state blocker;
- direct `EngineController.rescanAudioPluginChoices()` scan-state/ready-count
  publication evidence;
- manual/runtime acceptance for newly installed `aufx` effects and `aumu`
  instruments appearing after explicit rescan without relaunch;
- exact-build screenshots of the AU instrument picker and AU effect
  picker/menu surfaces showing ready/scanning states, ready counts, disabled
  repeated rescan state where feasible, previous choices visible, and long AU
  lists;
- loop-local testing observer markdown copied or rewritten from the actor final.

Lowest unmet pyramid layer: testing/evidence. Architecture risk severity:
`caution`, local to this loop. Next action kind for the decider appears to be
`evidence repair`: repair exact-build capture/focus evidence, obtain or
adjudicate the broad gate and EngineController/manual AU acceptance evidence,
and normalize the missing loop-local testing artifact. No product/UI rework is
justified by current built evidence, and this is not merge-ready yet.

The initial builder request is blocked/failed:

`.meta/multipass/runtime/inbox/blocked/2026-06-16T195214407Z-au-discovery-rescan-initial-build.md`

The continuation builder request completed:

`.meta/multipass/runtime/runs/actors/builder/2026-06-16T201014140Z-builder.final.md`

Product-owner attention is not needed.
