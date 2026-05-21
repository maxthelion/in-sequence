# Decision Log

Compact current-shape decision notes. Legacy coordinator logs are historical
context only.

## 2026-05-21T20:40Z

Used fresh orientation, feature-readiness observations, holistic/work status,
live pending inbox state, integration evidence, root `git status`, and the v2
build-capacity CLI as context. Kept capacity closed: active build loops remain
`build/mixer-busses` and `build/scene-perform`, available build slots are `0`,
and unpromoted ready candidates remain `step-sequencer` and `clip-history`.
Did not promote either candidate. Did not write a duplicate actor request
because the correct next project-level action remains pending: root
hygiene/process repair at
`.meta/multipass/inbox/pending/2026-05-21T19-11-16-835Z-process-fixer.md`.
That request is still the blocker to a follow-up Scene Perform integration for
rebased candidate `1b69d29e58edcc327f4f4996d10a90e13e480741`; Mixer Busses
remains accepted at `1eaebf3d6226f39a2438143b192493f54739352d` and waiting
behind Scene Perform. Recorded the no-duplicate decision at
`.meta/multipass/loops/project/decide/2026-05-21T20-40Z-decider-cadence.md`.
No product-owner attention is needed.

## 2026-05-21T20:05Z

Used fresh orientation, feature-readiness observations, live pending inbox
state, and the v2 build-capacity CLI as context. Kept capacity closed: active
build loops remain `build/mixer-busses` and `build/scene-perform`, available
build slots are `0`, and unpromoted ready candidates remain `step-sequencer`
and `clip-history`. Did not promote either candidate. Did not write a
duplicate actor request because the correct next project-level action is
already pending: root hygiene/process repair at
`.meta/multipass/inbox/pending/2026-05-21T19-11-16-835Z-process-fixer.md`.
That request unblocks a follow-up Scene Perform integration for rebased
candidate `1b69d29e58edcc327f4f4996d10a90e13e480741`; Mixer Busses remains
accepted at `1eaebf3d6226f39a2438143b192493f54739352d` and queued behind Scene
Perform. Recorded the no-duplicate decision at
`.meta/multipass/loops/project/decide/2026-05-21T20-05Z-decider-cadence.md`.
No product-owner attention is needed.

## 2026-05-21T19:11Z

Used fresh orientation and the v2 build-capacity CLI as context. Kept capacity
closed: active build loops remain `build/mixer-busses` and
`build/scene-perform`, available build slots are `0`, and unpromoted ready
candidates remain `step-sequencer` and `clip-history`. Did not promote either
candidate. Interpreted Scene Perform as the immediate project blocker:
integrator evidence shows rebased candidate
`1b69d29e58edcc327f4f4996d10a90e13e480741` is mechanically merge-ready, but
root `main` has broad pre-existing coordination/migration dirt. Routed a sparse
act-phase `process-fixer` request at
`.meta/multipass/inbox/pending/2026-05-21T19-11-16-835Z-process-fixer.md` to
classify and resolve root hygiene enough to unblock a follow-up Scene Perform
integration run. Mixer Busses remains queued behind Scene Perform. No
product-owner attention is needed.

## 2026-05-21T18:11Z

Accepted `build/mixer-busses` as a project integration candidate at
`1eaebf3d6226f39a2438143b192493f54739352d` on
`auto/roadmap-5-mixer-busses-ui-finish`, using
`.meta/multipass/loops/build/mixer-busses/decide/2026-05-21T18-05Z-merge-candidate-1eaebf3.md`
and the 17:45Z build orientation as authority. Routed a sparse project
`integrator` request at
`.meta/multipass/inbox/pending/2026-05-21T18-11-22-766Z-integrator.md`, queued
behind the existing Scene Perform integrator request
`.meta/multipass/inbox/pending/2026-05-21T16-05-36-139Z-integrator.md`.
Merge ordering is explicit: Scene Perform remains first; if Mixer Busses is
picked up before Scene Perform is integrated, the integrator should stop with
waiting/blocked evidence rather than merge ahead. Accepted evidence hygiene
caveats as non-blocking and preserved broad root `main` dirt as an integrator
constraint. No product-owner attention is needed.

## 2026-05-21T18:00Z

Used the v2 build-capacity CLI as context and kept capacity closed: active
build loops remain `build/mixer-busses` and `build/scene-perform`, with zero
available build slots and unpromoted ready candidates `step-sequencer` and
`clip-history`. Did not promote either candidate. Did not write a duplicate
actor request because Scene Perform already has a pending project integrator
request for accepted candidate `ab620600`, and Mixer Busses already has a
pending `build/mixer-busses` build-decider cadence to dispose fresh
`1eaebf3` PASS evidence. Recorded the decision at
`.meta/multipass/loops/project/decide/2026-05-21T18-00Z-decider-cadence.md`.
No product-owner attention is needed.

## 2026-05-21T16:45Z

Used the v2 build-capacity CLI as context and kept capacity closed: active
build loops are still `build/mixer-busses` and `build/scene-perform`, with zero
available build slots. Did not promote `step-sequencer` or `clip-history`.
Fresh inbox/runtime evidence supersedes the stale Mixer Busses orientation: the
Master Out clipping builder continuation completed and left
`.worktrees/roadmap-5-mixer-busses-ui-finish` clean at
`1eaebf3d6226f39a2438143b192493f54739352d`, with `git diff --check`, focused
`MixerMasterOutputTests`, and fresh populated visual evidence. Did not write a
duplicate actor request because `build/mixer-busses` already has a pending
build-decider cadence to route review/disposition from the fresh exact state,
and Scene Perform already has a pending project integrator request for accepted
candidate `ab620600`. No product-owner attention is needed.

## 2026-05-21T16:05Z

Accepted `build/scene-perform` as a merge/integration candidate at
`ab6206004edd4d0b35c917e53ef85f147df47723` on
`auto/roadmap-2-scene-perform`. Routed a sparse project `integrator` request
for merge-prep/integration against `main`, using
`.meta/multipass/loops/build/scene-perform/decide/2026-05-21T15-54Z-merge-candidate-ab62060.md`
as authority. Accepted scoped architecture inheritance from `e5fe9ea` because
the final delta is the one-file SwiftUI presentation/control-direction change
in `Sources/UI/Mixer/ScenesWorkspaceView+Perform.swift`; exact-state testing,
UX/IA, and visual-economy passes are current for `ab62060`. Preserved residual
risks around absent filled macro-label screenshots, missing automated SwiftUI
drag/card hard-switch coverage, and broad pre-existing root `main` dirt as
integrator constraints, not product-owner questions.

## 2026-05-21T15:49Z

Used the v2 build-capacity CLI as context and kept capacity closed: active
build loops are still `build/mixer-busses` and `build/scene-perform`, with zero
available build slots. Did not promote `step-sequencer` or `clip-history`.
Did not write duplicate actor requests because Mixer Busses already has a
focused builder continuation pending for the Send B / fixed Master Out clipping
failure plus a build-decider cadence, and Scene Perform already has a pending
build-decider cadence for merge/readiness disposition after exact-state
UX/IA, visual-economy, and testing passes at `ab620600`. No product-owner
attention is needed.

## 2026-05-21T14:10Z

Used the v2 build-capacity CLI as context and kept capacity closed: active
build loops are still `build/mixer-busses` and `build/scene-perform`, with zero
available build slots. Did not promote `step-sequencer` or `clip-history`.
Fresh Mixer Busses build orientation reports the previous Master Out clipping
builder request is blocked with no final artifact, no new commit, and the
worktree still clean at `f82d525`. Wrote a sparse `build/mixer-busses`
build-decider request to route one focused builder continuation/rework for the
Send B / fixed Master Out clipping failure. Did not duplicate Scene Perform
routing because a fresh `build/scene-perform` build-decider cadence is already
pending for disposition after current UX/IA and visual-economy passes at
`ab620600`. No product-owner attention is needed.

## 2026-05-21T13:29Z

Used the v2 build-capacity CLI as context and kept capacity closed: active
build loops are still `build/mixer-busses` and `build/scene-perform`, with zero
available build slots. Did not promote `step-sequencer` or `clip-history`.
Did not write duplicate actor requests because `build/mixer-busses` already has
a specific pending build-decider request for the Send B / Master Out
visual-economy correction at `f82d525`, and `build/scene-perform` already has a
pending build-decider cadence after fresh orientation identified visual-economy
evidence freshness as the lowest unmet layer for `ab620600`. No product-owner
attention is needed.

## 2026-05-21T12:18Z

Used the v2 build-capacity CLI as context and kept capacity closed: active
build loops are still `build/mixer-busses` and `build/scene-perform`, with zero
available build slots. Did not promote `step-sequencer` or `clip-history`.
Fresh project orientation says the useful project action is active-loop
disposition: Mixer Busses needs exact-state handling for clean commit
`f82d525`, and Scene Perform needs fresh gates for horizontal-crossfader commit
`ab620600`. Did not write duplicate actor requests because pending
build-decider cadence tickets already exist for both active build loops.

## 2026-05-21T09:29Z

Used the v2 build-capacity CLI as context and kept capacity closed: active
build loops are still `build/mixer-busses` and `build/scene-perform`, with zero
available build slots. Did not promote `step-sequencer` or `clip-history`.
Scheduled the `build/scene-perform` build decider to route exact-state reviews
against clean builder continuation commit
`e5fe9eaea038e268369fd2b812e177b374a26f8d`, noting that the builder could not
capture a meaningful UI screenshot and reviewers must produce evidence or a
bounded blocker. Did not route Mixer Busses from the top loop because its latest
visual-correction run still lacks a final artifact despite visible commit and
evidence files.

## 2026-05-21T06:58Z

Accepted refreshed orientation that supersedes the older dirty Mixer Busses UI
merge snapshot: builder continuation completed clean commit `6622bc9` in
`.worktrees/roadmap-5-mixer-busses-ui-finish` with focused mixer/session tests
passing. Sent the build-loop decider an exact-state gate request for visual
economy, UX/IA, architecture, and testing review; did not reopen the stale
partial-work read. Scene Perform and Step Sequencer remain P1 PM-ready
follow-ons after Mixer Busses gates.

## 2026-05-21T07:44Z

Promoted `scene-perform` into `build/scene-perform` using the available v2
build-capacity slot. Mixer Busses remains active with routine builder and
visual-evidence follow-ups already pending inside `build/mixer-busses`; no
top-level micromanagement needed. Chose Scene Perform over Step Sequencer for
this slot because it is the lower-numbered P1 PM-ready item and advances the
scenes/live-performance workflow. Recorded the known clean-but-behind branch
and merge-tree conflict risk in the build-decider request.

## 2026-05-21T08:22Z

Accepted fresh work and feature-readiness observations over the older
orientation where they differ: both build slots are now occupied by
`build/mixer-busses` and `build/scene-perform`, each with current builder
requests already pending. The v2 capacity CLI reports zero available build
slots and `step-sequencer` as the only unpromoted ready candidate, so no new
promotion or top-level follow-up was scheduled. `step-sequencer` remains the
next clear ready candidate once a build slot opens; `clip-history` remains
PM-ambiguous.

## 2026-05-21T09:55Z

Reconciled Clip History PM artifacts after discovering the split state: `main`
contains the rejected save-latest modal, while `auto/roadmap-1-clip-history`
contains useful but stale repair work. Updated the roadmap artifacts so
`clip-history-dual-grid-v4.html` is build authority, added
`docs/roadmap/clip-history/build-resume-handoff.md`, and moved Clip History into
ready-for-promotion evidence. Do not merge the old branch as-is; when capacity
opens, create a fresh v2 build loop on current `main` and harvest the branch
deliberately.

## 2026-05-21T08:48Z

Accepted refreshed orientation that `build/scene-perform` is blocked on a
builder continuation after `usage_rate_limit`, not ready for review. Sent a
continuation request to `builder` for `build/scene-perform` to verify/resolve
the merge state, preserve the approved three-column Scene Perform intent, run
focused checks, capture feasible UI evidence, and report exact commit/check
state before any gates are routed. Mixer Busses remains blocked on its existing
visual-correction continuation, capacity remains full, and no product-owner
attention is needed.

## 2026-05-21T08:53Z

Handled the Clip History reconciliation ticket as a future-promotion decision,
not an immediate build request. `docs/roadmap/clip-history/prototypes/clip-history-dual-grid-v4.html`
and `docs/roadmap/clip-history/build-resume-handoff.md` are the future build
authority; the save-latest modal on `main` remains rejected as the finished
feature, and `auto/roadmap-1-clip-history` is salvage/reference only. Capacity
is still full with `build/mixer-busses` and `build/scene-perform`, so no
promotion was scheduled. Reconsider Clip History, alongside Step Sequencer, when
a build slot opens or a deliberate priority swap is made.
