# song-mode-phrase-looping

- loop: `build/song-mode-phrase-looping`
- status: complete
- branch: `auto/roadmap-11-song-mode-phrase-looping`
- worktree: `.worktrees/roadmap-11-song-mode-phrase-looping`
- created: 2026-06-04T16:05:21Z
- current-fully-reviewed-commit: `eaa8eea42b5b2257cd12b087bf40d39a9dff6e6e`
- current-output-commit: `eaa8eea42b5b2257cd12b087bf40d39a9dff6e6e`
- current-output-state: landed final v1 output `eaa8eea`; all accepted build
  gates were paired to that exact commit, project integration landed it on
  local `main` by merge commit `5a603cd`, and the build-loop lifecycle is
  terminal `complete`.

This is the durable build-loop summary. Transient inboxes, runs, and evidence
live under `.meta/multipass/runtime/loops/build/song-mode-phrase-looping/`.

## Current Disposition

Song Mode And Phrase Looping final v1 output
`eaa8eea42b5b2257cd12b087bf40d39a9dff6e6e` landed on local `main` by merge
commit `5a603cd6626684cb585cc86a482aa31cd2936a30`. Project integration
evidence is recorded at
`.meta/multipass/runtime/loops/project/act/2026-06-04T20-21Z-song-mode-phrase-looping-integration-landed.md`.

Direct closeout checks confirm local `main` resolves to merge commit
`5a603cd6626684cb585cc86a482aa31cd2936a30`, accepted candidate
`eaa8eea42b5b2257cd12b087bf40d39a9dff6e6e` is an ancestor of both local
`main` and the merge commit, and branch
`auto/roadmap-11-song-mode-phrase-looping` is contained by local `main`. The
public build-loop registry and loop-local manifest now mark
`build/song-mode-phrase-looping` terminal `complete`, so it no longer consumes
active build-loop capacity.

The accepted v1 boundary remains the free-play phrase-navigation workflow:
transport current phrase display, `Queue` and `Now` phrase actions, queued
phrase visibility and cycle-boundary promotion, immediate switching, stopped
and invalid-state reconciliation, Tracks basis-phrase tracking/edit targeting,
and required accessibility and verification. It does not include scripted Song
Mode arrangement, Audio Looping work, MIDI hardware acceptance, Track Perform
follow-up, persisted queue arrangement data, a dedicated queue-cancel control,
or transient queued-edit buffers.

No product rework, merge, push, worktree deletion, review routing, or
product-owner action is implied by this lifecycle closeout.

## Promotion Context

Project decider promoted Song Mode And Phrase Looping because build capacity is
open and the lane is now builder-ready from the PM artifact contract
perspective. Fresh PM state at
`.meta/multipass/state/pm-loops/song-mode-phrase-looping.md`
reports accepted open questions, prototype approval, architecture, spec, plan,
and implementation handoff. Live build capacity reports one active build loop,
one available build slot, and no unpromoted ready candidates from the older
feature-readiness snapshot.

Authoritative handoff:

- `docs/roadmap/song-mode-phrase-looping/implementation-handoff.md`
- `docs/roadmap/song-mode-phrase-looping/spec.md`
- `docs/roadmap/song-mode-phrase-looping/architecture.md`
- `docs/roadmap/song-mode-phrase-looping/plan.md`
- `docs/roadmap/song-mode-phrase-looping/prototype-approval.md`

Initial build-loop request:

- `.meta/multipass/runtime/inbox/pending/2026-06-04T16-06-33-304Z-Song-Mode-And-Phrase-Looping-promoted-to-build.md`

## Build-Loop Boundary

Implement the accepted free-play phrase-navigation workflow only:

- transport current phrase display;
- phrase dropdown with separate `Queue` and `Now` actions;
- queued phrase visibility after dropdown dismissal;
- queued phrase promotion at the current phrase cycle boundary;
- immediate phrase switching;
- stopped and invalid-state reconciliation;
- Tracks basis-phrase tracking and edit targeting;
- accessibility and verification required by the accepted spec and plan.

The first build-loop decision should verify or create the named worktree/branch
from current local `main`, then schedule the Phase 0 read-only verification
called out in `docs/roadmap/song-mode-phrase-looping/implementation-handoff.md`
before any product-code changes.

Do not expand v1 into scripted Song Mode arrangement, Audio Looping work, MIDI
hardware acceptance, Track Perform follow-up, persisted queue arrangement data,
a dedicated queue-cancel control, or transient queued-edit buffers.

## Risk Notes

- `docs/roadmap/song-mode-phrase-looping/README.md` metadata still says
  `status: inventory` / `stage: write-architecture`; this promotion uses the
  fresher PM summary and accepted handoff evidence.
- MIDI Interfaces remains active and held on real Launchpad Mini MK3 evidence
  or an explicit accepted limitation; Song Mode does not conflict with that
  scoped acceptance hold.
- Root `main` has broad pre-existing dirt and is local-only; build work should
  happen in the named worktree and preserve unrelated root changes.
- Product-owner attention is not needed for the accepted Song Mode v1 handoff.

## Latest Build Orientation

- updated: 2026-06-04T19:40Z
- latest orientation:
  `.meta/multipass/runtime/loops/build/song-mode-phrase-looping/orient/2026-06-04T19-40Z-build-orientation.md`
- latest committed output:
  `eaa8eea42b5b2257cd12b087bf40d39a9dff6e6e`
  (`eaa8eea Route Tracks edits to engine basis phrase`)
- previous fully reviewed output:
  `27fc1a4efe66bf0d186d880d8497e5d4eb1371da`
  (`27fc1a4 Stabilize transport queued phrase capture`)
- worktree status: clean source state at
  `auto/roadmap-11-song-mode-phrase-looping` on `eaa8eea`; only the ignored
  worktree-local `.meta/multipass/runtime/loops/build/song-mode-phrase-looping/`
  evidence directory is present.
- committed changed files from `27fc1a4..eaa8eea`:
  - `Sources/UI/LiveWorkspaceView.swift`
  - `Sources/UI/TracksMatrixView.swift`
  - `Tests/SequencerAITests/LiveWorkspaceViewTests.swift`

Phase 4 Tracks basis/edit targeting is built and all current gates are now
closed at exact commit `eaa8eea`. No source, test, script, or tracked
documentation change exists after the latest builder scope-evidence pass or
targeted UX/IA rerun.

The original Phase 4 builder evidence remains:
`.worktrees/roadmap-11-song-mode-phrase-looping/.meta/multipass/runtime/loops/build/song-mode-phrase-looping/evidence/2026-06-04T19-10Z-builder-phase-4-tracks-basis.md`.
It reports that a shared `TracksBasisPhraseResolver` drives the Tracks matrix
and live workspace edit surfaces. Basis resolution prefers a valid
`EngineController.basisPhraseID`, then selected phrase, then the existing
first-phrase fallback. Edits made while the queued phrase is the basis write
directly to the queued phrase ID and survive queue replacement plus `Now`.
Different-length basis phrases expose their real `stepCount` and `lengthBars`.

The focused builder evidence:
`.worktrees/roadmap-11-song-mode-phrase-looping/.meta/multipass/runtime/loops/build/song-mode-phrase-looping/evidence/2026-06-04T19-31Z-live-workspace-non-production-statement.md`
documents that `LiveWorkspaceView` is not an MVP production surface at this
checkpoint. The routed production Tracks surface is `TracksWorkspaceView` via
`.tracks`, which hosts `TracksMatrixView`; no `WorkspaceSection` case, top-bar
route, `WorkspaceDetailView` branch, or visual command target opens
`LiveWorkspaceView`. The accepted MVP basis surface remains the compact
`Basis Phrase` pill in the routed Tracks matrix.

Exact-state gate pairing:

- Architecture: pass. Final
  `.meta/multipass/runtime/runs/actors/architecture-review/2026-06-04T19-16-30-754Z-architecture-review-for-Phase-4-Tracks-basis-edit-targeting-at-eaa8eea.final.md`
  reports the slice keeps basis/current/queued state owned by
  `EngineController`, keeps it out of `PlaybackSnapshot` and
  `SequencerSnapshotCompiler`, and routes edits through existing scoped session
  mutation. No `caution`, `line-stop-recommended`, systemic blast radius, or
  top-loop escalation condition was raised.
- Testing: `evidence-sufficient`. Artifact
  `.meta/multipass/runtime/loops/build/song-mode-phrase-looping/observe/2026-06-04T19-19Z-testing-review-phase-4-tracks-basis.md`
  reran focused `xcodebuild` tests with 19 tests / 0 failures, inspected the
  diff, confirmed no engine/snapshot delta, and found the key resolver,
  queued-edit, and different-length basis behavior covered. Residual
  non-blocking hardening: no direct assertion for invalid engine basis plus
  invalid selected phrase falling back to first phrase.
- UX/IA: pass, coverage `covered`. Artifact
  `.worktrees/roadmap-11-song-mode-phrase-looping/.meta/multipass/runtime/loops/build/song-mode-phrase-looping/observe/2026-06-04T19-39Z-ux-ia-review-phase-4-tracks-basis-rerun.md`
  accepted the routed Tracks workspace / `TracksMatrixView` production surface.
  With `LiveWorkspaceView` scoped as non-production, no product-impacting
  UX/IA gap remains. Queued-state captures show transport current `Intro Lift`
  with a distinct queued Verse chip and the Tracks `Basis Phrase` pill resolved
  to the queued Verse phrase; `Now` captures show `Chorus Drop` as both current
  and basis with queue cleared.
- Visual economy: pass. Artifact
  `.meta/multipass/runtime/loops/build/song-mode-phrase-looping/observe/batches/eaa8eea42b5b2257cd12b087bf40d39a9dff6e6e/visual-economy-review.md`
  confirms the basis state remains in the existing compact top-right
  `BASIS PHRASE` pill without adding a second selector, queue controls,
  basis/current badges, or always-on explanatory text.

Advisory scoped gate invalidation was run at 2026-06-04T19:13Z against
`27fc1a4..eaa8eea` using the reusable coordinator CLI. It reported changed
files `LiveWorkspaceView.swift`, `TracksMatrixView.swift`, and
`LiveWorkspaceViewTests.swift`, no configured scope hints, no prior passing gate
evidence found by the helper, and full-review default for architecture,
testing, UX/IA, visual, and visual-economy. Manual interpretation still agrees:
Phase 4 touches persistent UI/edit-targeting surfaces and tests, so Phase 3
gate evidence is not inherited.

Evidence packaging caveats remain non-blocking:

- Observation batch
  `.meta/multipass/runtime/loops/build/song-mode-phrase-looping/observe/batches/eaa8eea42b5b2257cd12b087bf40d39a9dff6e6e/batch.yaml`
  still says `status: open`, and the batch directory only contains the copied
  visual-economy review. Runtime run artifacts and done inbox state show all
  four expected observer requests completed for exact `eaa8eea`; the incomplete
  batch directory copy is process/evidence packaging debt, not product
  evidence.
- The targeted UX request named the production Tracks capture directory under
  root `.meta`, but that root path is absent. The same capture set exists under
  the feature worktree `.meta` directory and was inspected by UX/IA.

No current Phase 4 builder or observer failure exists. Older Song Mode
usage-limit failures are process history, not current product blockers. The
latest actor-failure evidence at 2026-06-04T19:20Z is a project work-observer
usage-limit failure and is unrelated to this build-loop output.

Lowest unmet layer: none inside the feature gate stack. The accepted
implementation handoff and plan end at Phase 4 for this build loop, and Phase
4 is now reviewed across architecture, testing, UX/IA, and visual economy at
exact commit `eaa8eea`.

Next action kind for the build decider:
`decider-acceptance-and-merge-readiness`. The decider should record acceptance
or route the appropriate merge-readiness/integration disposition for the fully
reviewed output. Product-owner attention is not needed.

## Latest Build Decision

- updated: 2026-06-04T19:44Z
- decision:
  `.meta/multipass/runtime/loops/build/song-mode-phrase-looping/decide/2026-06-04T19-44Z-feature-complete-merge-candidate-decision.md`
- disposition: `feature_complete_merge_candidate`
- next action created:
  `.meta/multipass/runtime/inbox/claimed/2026-06-04T19-45-18-311Z-Song-Mode-Phrase-Looping-merge-candidate.md`

The build decider accepted the current output as complete for the promoted v1
scope at exact commit `eaa8eea42b5b2257cd12b087bf40d39a9dff6e6e`. All required
gates are paired to that state, and the accepted implementation handoff and
plan end at Phase 4. The next action is top-level project decider routing for
merge-readiness/integration. Product-owner attention is not needed.
