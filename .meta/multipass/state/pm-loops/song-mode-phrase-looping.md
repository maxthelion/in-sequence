# Song Mode And Phrase Looping PM Loop

- updated: 2026-06-05T01:14Z
- loop: `pm/song-mode-phrase-looping`
- status: active PM cadence over consumed artifacts; accepted v1 PM artifact
  contract complete, already promoted, built, reviewed, integrated, and
  consumed; no PM artifact gap or product-owner lock
- feature: `song-mode-phrase-looping`
- backlog item: 11
- registry manifest:
  `.meta/multipass/config/loops/pm/song-mode-phrase-looping.yaml`
- runtime root: `.meta/multipass/runtime/loops/pm/song-mode-phrase-looping/`
- authoritative product docs: `docs/roadmap/song-mode-phrase-looping/`
- latest observation:
  `.meta/multipass/runtime/loops/pm/song-mode-phrase-looping/observe/2026-06-05T01-14Z-pm-readiness-observation.md`
- latest orientation:
  `.meta/multipass/runtime/loops/pm/song-mode-phrase-looping/orient/2026-06-04T22-00Z-pm-orientation.md`
- latest decision:
  `.meta/multipass/runtime/loops/pm/song-mode-phrase-looping/decide/2026-06-04T22-04Z-pm-decision.md`
- latest action evidence:
  `.meta/multipass/runtime/loops/pm/song-mode-phrase-looping/act/2026-06-04T15-56Z-pm-implementation-handoff.md`
- consumed by build loop: `build/song-mode-phrase-looping`
- build-loop summary:
  `.meta/multipass/state/build-loops/song-mode-phrase-looping.md`
- build promotion decision:
  `.meta/multipass/runtime/loops/project/decide/2026-06-04T16-05Z-song-mode-phrase-looping-promotion.md`
- landed integration evidence:
  `.meta/multipass/runtime/loops/project/act/2026-06-04T20-21Z-song-mode-phrase-looping-integration-landed.md`
- current coordination caveat:
  `stash@{0}` authority repair is active project process risk; visible Song
  Mode PM files are currently untracked.

## Current Interpretation

This lane clarified free-play Song Mode phrase navigation for live
performance: transport current phrase display, queued next phrase,
end-of-cycle switching, immediate switching, and Tracks UI basis-phrase
tracking. That remains aligned with the README intent around turning loops
into arrangement material while preserving performability and keeping edits
coordinated with the phrase the performer is hearing or preparing.

The PM artifact contract is complete through accepted implementation handoff.
It was consumed by project promotion into `build/song-mode-phrase-looping`,
then built, reviewed, integrated, and closed.

Direct evidence now shows current local `HEAD` at Track Fill integration
commit `36e804a`, with accepted Song Mode candidate
`eaa8eea42b5b2257cd12b087bf40d39a9dff6e6e` contained by `HEAD`. The durable
build-loop summary records `build/song-mode-phrase-looping` as terminal
`complete`, with landed merge commit
`5a603cd6626684cb585cc86a482aa31cd2936a30`.

Current feature-readiness state at 2026-06-04T23:44Z classifies Song Mode as
`stale/already-handled`, not as an unpromoted ready candidate. Current project
orientation at 2026-06-05T00:56Z adds a broader caution: `stash@{0}` fragments
coordination authority and makes build capacity look false-empty. The 01:07Z
project decision routed a process repair for that stash. For this lane,
readable PM artifacts are visible and sufficient, but `git status --short`
reports the Song Mode PM manifest, PM summary, and accepted roadmap artifacts
as untracked, so tracked coordination authority is not fully settled until the
stash repair resolves or parks those paths.

The roadmap README metadata still says `status: inventory`,
`stage: write-architecture`, and `updated: 2026-04-30`. Treat that as metadata
drift relative to accepted PM artifacts and landed build evidence. It is not a
readiness blocker.

## Existing PM Source Artifacts

- `README.md`: backlog item metadata; stale relative to accepted PM artifacts
  and landed build-loop evidence.
- `notes.md`: raw user intent for current phrase display, queued next phrase,
  dropdown selection, immediate switch, and Tracks basis updates.
- `user-stories.md`: stories for transport current-phrase display, queueing,
  end-of-cycle switching, immediate switching, and Tracks basis tracking.
- `existing-state.md`: production-state report for missing engine/model/UI
  wiring and duplicated phrase-index derivation before implementation.
- `artifacts.md`: screenshot-derived note that the Tracks UI already has a
  `Basis Phrase` panel.
- `ux-review.md`: recommends the two prototypes as complementary design bases.
- `prototype-approval.md`: accepts both prototypes as the complementary design
  basis.
- `open-questions.md`: packages UX, product, and architecture decision points;
  later accepted spec/plan/handoff answer the v1 decisions.
- `architecture.md`: accepted architecture for engine-owned live
  current/queued/basis state, tick-boundary promotion, no MVP snapshot queue
  field, and explicit MVP defaults.
- `spec.md`: accepted spec with transport, queue, immediate switch, Tracks
  basis, accessibility, edge-state, acceptance, and testing requirements.
- `plan.md`: accepted implementation plan through engine, reconciliation,
  transport UI, Tracks basis/edit targeting, tests, accessibility, and
  regression checks.
- `implementation-handoff.md`: accepted builder-facing contract for the
  approved workflow and out-of-scope boundaries.
- `prototypes/01-transport-phrase-indicator.html` and
  `prototypes/02-tracks-basis-phrase-tracking.html`: accepted design bases.
- `fixtures/transport-phrase-navigation.seqai`: fixture retained with the PM
  docs.

## Lowest Unmet PM Artifact Layer

No PM artifact/readiness layer is currently unmet for the accepted v1 workflow.

Handled PM layers:

- `docs/roadmap/song-mode-phrase-looping/prototype-approval.md`
- `docs/roadmap/song-mode-phrase-looping/open-questions.md`
- `docs/roadmap/song-mode-phrase-looping/architecture.md`
- `docs/roadmap/song-mode-phrase-looping/spec.md`
- `docs/roadmap/song-mode-phrase-looping/plan.md`
- `docs/roadmap/song-mode-phrase-looping/implementation-handoff.md`

The remaining visible issues are evidence/coordination hygiene, not PM
readiness gates: stale roadmap README metadata, untracked visible PM files, and
the broader `stash@{0}` authority repair.

## Next Useful PM Action Kind

No PM artifact action is useful for this lane now. The useful PM posture is
quiet observation: act only if fresh landed-output evidence exposes a new
product tradeoff outside the accepted handoff.

If the coordinator wants to reduce process noise, the useful action kind is a
project/process lifecycle or authority cleanup of consumed PM cadence and
untracked/stashed coordination state, not a Song Mode PM artifact-author
request. This summary does not schedule that work.

## Product-Owner Attention

No product-owner attention is needed for the current PM lane state. The
accepted architecture, spec, plan, and handoff already record defensible MVP
answers for queue cancellation, queued-basis edit semantics, stopped-state
queue behavior, dropdown dismissal, long-name truncation, existing basis-pill
usage, accessibility/keyboard behavior, different-length basis phrase
handling, and no MVP `PlaybackSnapshot` queue/current/basis field.

Product-owner attention would only be useful if fresh landed-output evidence
exposes a new product tradeoff outside the accepted handoff.

## Build Promotion

Build promotion was appropriate from the PM artifact contract perspective and
has already been consumed. Project decision evidence at
`.meta/multipass/runtime/loops/project/decide/2026-06-04T16-05Z-song-mode-phrase-looping-promotion.md`
created `build/song-mode-phrase-looping`.

Further PM-side promotion is not appropriate now. The accepted v1 candidate
`eaa8eea42b5b2257cd12b087bf40d39a9dff6e6e` is contained by current `HEAD`, the
landed merge commit is
`5a603cd6626684cb585cc86a482aa31cd2936a30`, and
`build/song-mode-phrase-looping` is terminal `complete`.

## Current Build / Integration Context

The durable build-loop summary is
`.meta/multipass/state/build-loops/song-mode-phrase-looping.md`.
It reports:

- accepted Phase 1 engine checkpoint:
  `d0733151d2a3f8d7b80b566c95423cc96df8c01a`
  (`d073315 Add engine phrase navigation state`);
- accepted Phase 2 reconciliation/stopped-state checkpoint:
  `4db394167fb003c1ee4f1f7979dfaea1540d42d0`
  (`4db3941 Harden phrase navigation reconciliation`);
- accepted Phase 3 transport queued-state checkpoint:
  `27fc1a4efe66bf0d186d880d8497e5d4eb1371da`
  (`27fc1a4 Stabilize transport queued phrase capture`);
- accepted Phase 4 Tracks basis/edit targeting and final reviewed output:
  `eaa8eea42b5b2257cd12b087bf40d39a9dff6e6e`
  (`eaa8eea Route Tracks edits to engine basis phrase`);
- exact-state Phase 4 architecture pass, testing evidence-sufficient, UX/IA
  pass, and visual-economy pass evidence at `eaa8eea`;
- project integration landed on local `main` at merge commit
  `5a603cd6626684cb585cc86a482aa31cd2936a30`;
- build-loop lifecycle terminal `complete`.

This is useful freshness context only. The PM lane has no integration
authority and no further PM artifact work is implied.

## Evidence Freshness

- Latest PM readiness observation:
  `.meta/multipass/runtime/loops/pm/song-mode-phrase-looping/observe/2026-06-05T01-14Z-pm-readiness-observation.md`.
- Latest PM orientation:
  `.meta/multipass/runtime/loops/pm/song-mode-phrase-looping/orient/2026-06-04T22-00Z-pm-orientation.md`.
- Latest PM decision:
  `.meta/multipass/runtime/loops/pm/song-mode-phrase-looping/decide/2026-06-04T22-04Z-pm-decision.md`.
- Latest PM action evidence:
  `.meta/multipass/runtime/loops/pm/song-mode-phrase-looping/act/2026-06-04T15-56Z-pm-implementation-handoff.md`.
- Build promotion decision:
  `.meta/multipass/runtime/loops/project/decide/2026-06-04T16-05Z-song-mode-phrase-looping-promotion.md`.
- Landed integration evidence:
  `.meta/multipass/runtime/loops/project/act/2026-06-04T20-21Z-song-mode-phrase-looping-integration-landed.md`.
- Current feature-readiness state:
  `.meta/multipass/state/feature-readiness.md`, updated
  2026-06-04T23:44Z and classifying this lane as `stale/already-handled`.
- Current project orientation:
  `.meta/multipass/state/ooda/orientation.md`, updated
  2026-06-05T00:56Z and warning that `stash@{0}` fragments coordination
  authority.
- Current project decision log:
  `.meta/multipass/state/decision-log.md`, with 2026-06-05T01:07Z
  stash authority repair routing.
- Durable build-loop summary:
  `.meta/multipass/state/build-loops/song-mode-phrase-looping.md`.

Freshness note: PM artifact readiness, build-loop disposition, and direct git
containment agree that Song Mode is already handled. The remaining risk is
coordination evidence authority because the broader preservation stash repair
is still active and the visible PM paths are untracked.

Coordinator checks still emit the known Ruby `executable-hooks` /
`gem-wrappers` warning noise before useful output.

## Checks Run

- Read the claimed request, actor prompt/actions, README product intent, PM
  loop manifest, lane README, accepted PM roadmap artifacts, latest PM
  readiness observation, prior durable PM summary, latest PM orientation and
  decision, current inventory, current project orientation, current
  feature-readiness state, current decision log, stash authority repair route,
  integration evidence, and durable build-loop summary.
- Ran coordinator inventory:
  `bun /Users/maxwilliams/dev/multi-pass-coordinator/src/cli/inventory.ts --project /Users/maxwilliams/dev/in-sequence`.
- Checked direct git evidence:
  `git status --short`, `git stash list --max-count=3`, `git log -1 --oneline`,
  and `git merge-base --is-ancestor eaa8eea42b5b2257cd12b087bf40d39a9dff6e6e HEAD`.
- No product build or test suite was run; this request was PM readiness
  observation only.
