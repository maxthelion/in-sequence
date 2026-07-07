# routing-source-mixer-split

- loop: `build/routing-source-mixer-split`
- status: complete
- branch: `feature/routing-source-mixer-split`
- worktree: `.worktrees/routing-source-mixer-split`
- created: 2026-06-16T13:37:01.450Z
- feature: `routing-source-mixer-split`
- owner bug: `docs/bugs/20260615-tracks-routing-source-and-mixer-split/`
- setup evidence:
  `.meta/multipass/runtime/loops/project/act/2026-06-16T13-37Z-routing-source-mixer-split-build-loop-setup.md`
- blocked integration evidence:
  `.meta/multipass/runtime/loops/project/act/2026-06-16T12-57Z-routing-source-mixer-split-integration-blocked.md`
- initial build-loop decision:
  `.meta/multipass/runtime/loops/build/routing-source-mixer-split/decide/2026-06-16T13-37Z-route-source-vocabulary-repair.md`
- initial builder request:
  `.meta/multipass/runtime/inbox/pending/2026-06-16T133701450Z-routing-source-mixer-split-source-vocabulary-repair.md`

This is the durable build-loop summary. Transient inboxes, runs, and evidence
live under `.meta/multipass/runtime/loops/build/routing-source-mixer-split/`.

## 2026-07-04 Reconciliation Closeout

2026-07-04T17:35Z process-fixer repair:
`.meta/multipass/runtime/loops/project/act/2026-07-04T17-35Z-routing-source-mixer-split-reconciled.md`

The lane is closed as `complete` by supersession on current `main`, not by
feature-branch ancestry. Current `main` is `9062180d`; the configured worktree
`.worktrees/routing-source-mixer-split` remains absent. Branch checks found:

- `feature/routing-source-mixer-split` preserved at `3938b6bc`, not contained
  in `main`;
- `integrate/routing-source-mixer-split` at `54b265e1`, contained in `main`;
- `feature/routing-source-mixer-split` not contained in the integrate branch.

The feature branch still carries residual stale product/evidence changes: the
old side-by-side two-well routing-tab implementation, source-vocabulary tests,
QA rows, visual fixture work, and a branch-local resolution file. Current
`main` resolves the owner bug through the later Track detail shape instead:
the Sound tab owns source selection/editing with `Add Sound Source`, and the
Mixer tab owns output, scene membership, and sends through
`TrackRoutingTabContent(mode: .mixer)`. Reconstructing the old worktree would
target a stale UI shape and should not consume build capacity.

The build-loop manifest now reports terminal `status: complete`. Do not merge,
delete, or recreate the preserved branch/worktree from this summary alone. If a
future decider wants any surviving tests or capture-fixture ideas, it should
route a fresh bounded request against current `main`, not reopen this lane.

## Process Lock (Superseded)

2026-07-04T17:20Z process-fixer repair:
`.meta/multipass/runtime/loops/project/act/2026-07-04T17-20Z-stale-build-capacity-registry-repair.md`

The configured worktree `.worktrees/routing-source-mixer-split` is absent from
`git worktree list`, and there is no pending routing build-loop inbox work.
The local branch `feature/routing-source-mixer-split` is preserved at
`3938b6bc`, but it is not contained in current `main`. A later
`integrate/routing-source-mixer-split` branch is contained in current `main`,
so this loop needs explicit decider reconciliation before any continuation or
closeout claim.

Coordination state now marks the loop `locked` by `process` so it does not
consume ordinary build capacity while the worktree is missing. Do not recreate
the worktree, route builders, mark complete, merge, push, or delete branches
from this summary alone.

## Compact Build Intent

This loop exists only to repair the mandatory adversarial critic blocker on the
already-routed owner-bug follow-up branch. The routing source/mixer split must
stop exposing old destination vocabulary in the Sound Source well through reused
routing editor UI.

The bounded repair should inspect and fix `TrackDestinationEditor`,
`AddDestinationSheet`, selected MIDI source labels, AU source text,
source-empty labels, and tests covering the source well flow. It should update
or validate
`docs/bugs/20260615-tracks-routing-source-and-mixer-split/resolution.md` on the
branch.

Do not use this loop for AU discovery/rescan, mixer strip follow-up, Track
Perform pattern cells, Observability, MIDI, PM reserve recovery, root cleanup,
merge, push, worktree deletion, or unrelated cleanup.

## Setup State

The build-loop container uses the existing branch and worktree:

- branch: `feature/routing-source-mixer-split`
- worktree: `.worktrees/routing-source-mixer-split`
- setup-observed branch head:
  `afbd875f49210443c767fbd2aa4b055dbc749702`
- setup-observed local `main`:
  `abc9adf63c1274ed3b2c1f5cda8c8de3cbf62d00`
- setup-observed `main...HEAD`: `2 1`
- setup-observed worktree state: clean

No product code, merge, rebase, push, worktree deletion, request lifecycle move,
or root cleanup was performed by the container setup.

## Current Orientation

2026-06-17T09:34Z orientation:

`.meta/multipass/runtime/loops/build/routing-source-mixer-split/orient/2026-06-17T09-34Z-sample-slicer-review-synthesis.md`

The branch remains clean at `3938b6bc` (`Fix slicer routing visual fixture`).
The latest commit is still fixture-only in
`Sources/UI/VisualScenarioCommandRunner.swift`; `git diff --check HEAD`
passed.

Observation batch `3938b6bc` is partially passed but not critic-ready:

- architecture: pass via actor final; prior product-code architecture evidence
  is inheritable because `3938b6bc` is fixture-only and keeps slicer setup on
  the existing typed session/destination path;
- testing: pass; the testing review accepted the focused 21/0 run and
  fixture-only diff for this batch;
- UX/IA: pass; screenshots show the intended Tracks routing tab split with
  `Sound Source` and adjacent `Mixer & FX` wells for sample and slicer source
  states;
- visual-economy: `evidence-insufficient`, gap type `stale-or-wrong-commit`.
  The screenshots show the right surfaces, but their visible build badge says
  `feature/routing-source-mixer-split 0f297367` while the requested exact output
  is `3938b6bc`.

Missing evidence is narrow: rebuild/relaunch from `3938b6bc`, confirm the
visible in-app build badge reflects `3938b6bc`, recapture only `22d` sample
source and `22e` slicer source, then route visual-economy review over those
exact-state screenshots. This is an evidence freshness gap, not a product UX
correction.

Lowest unmet pyramid layer: exact-state visual evidence / visual-economy gate.

Architecture risk severity: low. Evidence risk severity: caution because the
surface looks correct but exact-commit visual evidence failed.

Next action kind: evidence repair (`stale-or-wrong-commit` recapture), not
rework, integration, or product escalation. After visual-economy passes, rerun
the mandatory adversarial critic before any integration decision.

Product-owner attention is not needed.

Prior orientation:

2026-06-17T08:47Z orientation:

`.meta/multipass/runtime/loops/build/routing-source-mixer-split/orient/2026-06-17T08-47Z-manual-capture-unblock-synthesis.md`

The branch is clean at `3938b6bc` (`Fix slicer routing visual fixture`).
`git diff --stat` is empty and `git diff --check` passed. The latest commit is
fixture-only in `Sources/UI/VisualScenarioCommandRunner.swift`: slicer routing
visual commands now attach a slicer destination to the currently selected track
instead of creating/selecting a slice track.

Latest unblock outcome:

- artifact:
  `.meta/multipass/runtime/loops/build/routing-source-mixer-split/act/2026-06-17T08-27Z-manual-capture-unblock.md`
- status: `manual_capture_unblocked`
- valid sample-source screenshot:
  `.meta/multipass/runtime/loops/build/routing-source-mixer-split/act/manual-unblock-20260617T082320Z-22d-after-fixture-fix/22d-track-routing-tab-sample-source.png`
- valid slicer-source screenshot:
  `.meta/multipass/runtime/loops/build/routing-source-mixer-split/act/manual-unblock-20260617T082108Z-22e-after-fixture-fix/22e-track-routing-tab-slicer-source.png`
- focused tests passed:
  `TrackRoutingWellsPresentationTests`, `WorkspaceModeTests`,
  `QuantiseHarnessProtocolTests`, and `PerformOverviewHarnessProtocolTests`,
  21 tests, 0 failures

Current branch sequence after the source/mixer split:

- `babe91e0` fixed source-well editor vocabulary.
- `20bd6fcc` fixed nested sampler/slicer source-widget vocabulary and added
  focused presentation coverage.
- `69227d3e` added routing-source visual fixture commands/QA rows.
- `0f297367` committed fixture wait/status hardening only.
- `3938b6bc` fixed the slicer routing visual fixture only.

Paired evidence for exact output `3938b6bc`:

- current clean worktree status and current head;
- `git diff --check` passed and no current worktree diff;
- `3938b6bc` changes only `Sources/UI/VisualScenarioCommandRunner.swift`;
- manual unblock artifact with the 21/0 focused test result;
- visual inspection confirms both `22d` and `22e` screenshots are nonblank,
  readable, and on the Tracks routing tab with the `Sound Source` and
  `Mixer & FX` wells visible.

Inherited evidence remains scoped:

- `20bd6fcc` still provides the nested sampler/slicer source-vocabulary
  product rework and focused `TrackRoutingWellsPresentationTests` result, 9/0.
- Earlier architecture/testing evidence remains useful for the unchanged
  source-vocabulary implementation path.
- The 17:33Z UX/IA and visual-economy passes remain valid only for already
  rendered no-source, internal-sampler, and add-source sheet states.

Missing: UX/IA and visual-economy review over the valid current `22d`/`22e`
screenshots, then the mandatory adversarial critic rerun if those pass.

Lowest unmet pyramid layer: UX/IA and visual-economy review over current exact
evidence. Evidence correctness has been repaired; integration is still
premature.

Architecture risk severity: low to caution. Product implementation risk is low
because the latest exact output is fixture-only and focused tests pass, but the
branch still needs the standard review and critic sequence before integration.

Next action kind: observation batch. Route reviewers to inspect the valid
`22d`/`22e` screenshots and exact output state. If observations pass, route the
mandatory adversarial critic rerun. Do not route integration directly from this
state.

Product-owner attention is not needed.

## Current Decision

2026-06-17T09:40Z decision:

`.meta/multipass/runtime/loops/build/routing-source-mixer-split/decide/2026-06-17T09-40Z-route-exact-state-sample-slicer-recapture.md`

Disposition: `needs_review`.

Routed a focused builder evidence-repair request:

`.meta/multipass/runtime/inbox/pending/2026-06-17T094026691Z-builder.md`

The only current blocker is exact-state visual-economy pairing for the sample
and slicer source screenshots. The branch is clean at `3938b6bc`, and
architecture/testing/UX evidence has passed or been accepted for the
fixture-only current output, but visual-economy rejected the available
screenshots because their visible build badge says `0f297367` instead of
`3938b6bc`.

Builder should rebuild/relaunch from `3938b6bc`, confirm the visible badge
shows `3938b6bc`, recapture only `22d` sample source and `22e` slicer source,
and write loop-local act evidence with screenshot paths and badge confirmation.
After that, route only the visual-economy rerun against repaired exact-state
captures. If visual-economy passes, route the mandatory adversarial critic
before any integration decision.

Prior decision:

2026-06-17T08:56Z decision:

`.meta/multipass/runtime/loops/build/routing-source-mixer-split/decide/2026-06-17T08-56Z-start-sample-slicer-observation-batch.md`

Disposition: `needs_review`.

Started observation batch for exact output `3938b6bc`:

`.meta/multipass/runtime/loops/build/routing-source-mixer-split/observe/batches/3938b6bc/batch.yaml`

The batch created pending review requests for architecture, testing, UX/IA, and
visual-economy. The core missing evidence is UX/IA and visual-economy review of
the valid `22d`/`22e` sample/slicer source screenshots; architecture/testing
inheritance is plausible because the latest commit is fixture-only and focused
tests passed 21/0, but reviewers must record pass/inheritance or contrary
findings explicitly.

Do not route integration yet. If the batch passes, the next build-loop action is
the mandatory adversarial critic rerun. If any gate fails, route focused
builder rework.
