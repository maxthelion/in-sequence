# drum-parts-as-group

- loop: `build/drum-parts-as-group`
- status: complete
- branch: `auto/roadmap-12-drum-parts-as-group`
- worktree: `.worktrees/roadmap-12-drum-parts-as-group`
- created: 2026-06-05T03:28:00Z
- landed-output-commit: `472583cf1fed30a085a19ead5fa5d581de12ffc7`
- current-output-state: landed final v1 output `472583c`; project integration
  fast-forwarded local `main` from
  `36e804a6062e8e8a85c9d55dd5529ec168ff0efc` to exact source commit
  `472583cf1fed30a085a19ead5fa5d581de12ffc7`, and
  `main...auto/roadmap-12-drum-parts-as-group` is `0 0`. The public
  build-loop registry and loop-local manifest now mark
  `build/drum-parts-as-group` terminal `complete`, so it no longer consumes an
  ordinary active build slot.
- final-reviewed-output-state: Phase 6 routing modal rework is committed at
  `472583cf1fed30a085a19ead5fa5d581de12ffc7`
  (`Rework drum routing modal visual state`) on
  `auto/roadmap-12-drum-parts-as-group`; the feature worktree is clean.
  Runtime marked the builder request blocked because the actor was SIGTERM'd
  before writing its final artifact, with compact failure mode
  `usage_rate_limit`, but usable builder action evidence exists in the feature
  worktree. The diff from `0fd66bb` changes only
  `Sources/UI/DrumGroup/DrumKitMatrixView.swift` and is reported as
  presentation-local to the routing modal. Builder evidence for `472583c`
  reports `git diff --check` before commit and `HEAD~1..HEAD` passed, focused
  `DrumGroupRoutingEditorDraftTests` passed with 9 tests and 0 failures, and a
  20-state visual scenario package exists under
  `.worktrees/roadmap-12-drum-parts-as-group/.meta/multipass/runtime/loops/build/drum-parts-as-group/act/2026-06-05T18-44Z-phase-6-routing-modal-rework-rendered`.
  The exact-state observer batch for `472583c` now has durable pass artifacts
  for architecture, testing, UX/IA, and visual economy. The batch manifest is
  closed as `status: complete`; no inherited observer gate evidence is accepted
  because the actual integrated state is covered by fresh exact-state gates.
- next-action: none for Drum Parts build-loop implementation, review,
  integration, or PM planning. Product output is landed locally on `main`, not
  pushed, and the remaining risks are ordinary process/audit residue only.
- closeout evidence:
  `.meta/multipass/runtime/loops/project/act/2026-06-05T22-30Z-drum-parts-lifecycle-capacity-closeout.md`
- current observation batch:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/batches/472583cf1fed30a085a19ead5fa5d581de12ffc7/batch.yaml`
- latest Phase 6 routing modal rework recovered batch orientation:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/orient/2026-06-05T20-34Z-phase-6-routing-modal-rework-recovered-batch-orientation.md`
- previous Phase 6 routing modal rework batch orientation:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/orient/2026-06-05T20-22Z-phase-6-routing-modal-rework-batch-orientation.md`
- latest Phase 6 visual-economy recovery decision:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/decide/2026-06-05T20-26Z-phase-6-routing-modal-visual-economy-recovery-decision.md`
- completed Phase 6 visual-economy recovery request:
  `.meta/multipass/runtime/inbox/done/2026-06-05T20-27-08-848Z-visual-economy-review.md`
- latest Phase 6 routing modal rework visual-economy pass:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T20-31Z-phase-6-routing-modal-rework-visual-economy-review.md`
- latest Phase 6 routing modal rework architecture pass:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T20-02Z-phase-6-routing-modal-rework-architecture-review.md`
- latest Phase 6 routing modal rework testing pass:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T20-08Z-phase-6-routing-modal-rework-testing-review.md`
- latest Phase 6 routing modal rework UX/IA pass:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T19-58Z-phase-6-routing-modal-rework-ux-ia-review.md`
- latest Phase 6 routing modal rework visual-economy blocked request:
  `.meta/multipass/runtime/inbox/blocked/2026-06-05T19-53-12-144Z-visual-economy-review-for-Drum-Parts-Phase-6-routing-modal-rework-exact-state-review.md`
- latest Phase 6 routing modal rework visual-economy failure:
  `.meta/multipass/runtime/runs/actors/visual-economy-review/2026-06-05T19-53-12-144Z-visual-economy-review-for-Drum-Parts-Phase-6-routing-modal-rework-exact-state-review.failure.md`
- latest Phase 6 routing modal rework review batch decision:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/decide/2026-06-05T19-53Z-phase-6-routing-modal-rework-review-batch-decision.md`
- latest Phase 6 review batch decision:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/decide/2026-06-05T18-22Z-phase-6-exact-state-review-batch-decision.md`
- latest Phase 6 routing modal rework decision:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/decide/2026-06-05T18-38Z-phase-6-routing-modal-rework-decision.md`
- latest Phase 6 architecture pass:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T18-24Z-phase-6-integration-architecture-review.md`
- latest Phase 6 testing pass:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T18-27Z-phase-6-integration-testing-review.md`
- latest Phase 6 visual-economy correction:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T18-31Z-phase-6-integration-visual-economy-review.md`
- latest Phase 6 UX/IA correction:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T18-36Z-phase-6-integration-ux-ia-review.md`
- latest orientation:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/orient/2026-06-05T20-34Z-phase-6-routing-modal-rework-recovered-batch-orientation.md`
- previous orientation:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/orient/2026-06-05T20-22Z-phase-6-routing-modal-rework-batch-orientation.md`
- latest Phase 6 routing modal rework action:
  `.worktrees/roadmap-12-drum-parts-as-group/.meta/multipass/runtime/loops/build/drum-parts-as-group/act/2026-06-05T18-45Z-phase-6-routing-modal-rework.md`
- latest Phase 6 routing modal rework builder request:
  `.meta/multipass/runtime/inbox/blocked/2026-06-05T18-35-42-673Z-Drum-Parts-Phase-6-routing-modal-rework.md`
- latest Phase 6 routing modal rework builder failure:
  `.meta/multipass/runtime/runs/actors/builder/2026-06-05T18-35-42-673Z-Drum-Parts-Phase-6-routing-modal-rework.failure.md`
- latest Phase 6 routing modal visual evidence:
  `.worktrees/roadmap-12-drum-parts-as-group/.meta/multipass/runtime/loops/build/drum-parts-as-group/act/2026-06-05T18-44Z-phase-6-routing-modal-rework-rendered`
- previous completed Phase 6 builder action:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/act/2026-06-05T18-16Z-phase-6-builder-recovery.md`
- previous failure orientation:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/orient/2026-06-05T18-06Z-phase-6-builder-failure-orientation.md`
- previous accepted exact-state orientation:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/orient/2026-06-05T17-24Z-phase-5-kit-matrix-exact-state-review-orientation.md`
- latest failed Phase 6 builder request:
  `.meta/multipass/runtime/inbox/blocked/2026-06-05T17-28-02-092Z-builder.md`
- latest failed Phase 6 builder result:
  `.meta/multipass/runtime/runs/actors/builder/2026-06-05T17-28-02-092Z-builder.failure.md`
- latest Phase 6 builder recovery decision:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/decide/2026-06-05T18-12Z-phase-6-builder-recovery-decision.md`
- previous Phase 6 integration builder decision:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/decide/2026-06-05T17-29Z-phase-6-integration-builder-decision.md`
- latest accepted Phase 5 review batch:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/batches/147e98e583fc0872071e8d5b0e3c836b9d2f0625/batch.yaml`
- latest Phase 5 architecture pass:
  `.meta/multipass/runtime/runs/actors/architecture-review/2026-06-05T17-14-35-130Z-architecture-review-for-Drum-Parts-Phase-5-kit-matrix-evidence-repair-exact-state-review.final.md`
- latest Phase 5 testing pass:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T17-18Z-phase-5-kit-matrix-evidence-repair-testing-review.md`
- latest Phase 5 UX/IA pass:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T17-19Z-phase-5-kit-matrix-evidence-repair-ux-ia-review.md`
- latest Phase 5 visual-economy pass:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T17-20Z-phase-5-kit-matrix-visual-economy-review.md`
- previous exact-state review orientation:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/orient/2026-06-05T17-11Z-phase-5-kit-matrix-evidence-repair-recovery-orientation.md`
- latest completed builder action:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/act/2026-06-05T17-10Z-phase-5-kit-matrix-evidence-repair-recovery.md`
- latest completed builder final:
  `.meta/multipass/runtime/runs/actors/builder/2026-06-05T16-58-52-063Z-builder.final.md`
- latest completed builder request:
  `.meta/multipass/runtime/inbox/done/2026-06-05T16-58-52-063Z-builder.md`
- latest rendered Phase 5 kit matrix evidence:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/act/phase-5-kit-matrix-rendered-2026-06-05T17-08Z`
- latest recovery decision:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/decide/2026-06-05T16-58Z-phase-5-dirty-evidence-repair-recovery-decision.md`
- previous failure orientation:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/orient/2026-06-05T16-54Z-phase-5-kit-matrix-evidence-repair-failure-orientation.md`
- previous clean exact-state review orientation:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/orient/2026-06-05T16-07Z-phase-5-kit-matrix-review-orientation.md`
- latest failed builder request:
  `.meta/multipass/runtime/inbox/blocked/2026-06-05T16-11-55-221Z-Drum-Parts-Phase-5-kit-matrix-evidence-repair.md`
- latest failed builder result:
  `.meta/multipass/runtime/runs/actors/builder/2026-06-05T16-11-55-221Z-Drum-Parts-Phase-5-kit-matrix-evidence-repair.failure.md`
- latest failed builder run:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/runs/act/builder/2026-06-05T16-11-55-221Z-Drum-Parts-Phase-5-kit-matrix-evidence-repair.json`
- prior failed repair decision:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/decide/2026-06-05T16-11Z-phase-5-kit-matrix-evidence-repair-decision.md`
- previous source checkpoint builder action:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/act/2026-06-05T15-44Z-phase-5-source-project-finalization-checkpoint.md`
- previous source checkpoint builder final:
  `.meta/multipass/runtime/runs/actors/builder/2026-06-05T15-42-27-301Z-Drum-Phase-5-source-project-finalization-checkpoint.final.md`
- previous source checkpoint builder request:
  `.meta/multipass/runtime/inbox/done/2026-06-05T15-42-27-301Z-Drum-Phase-5-source-project-finalization-checkpoint.md`
- latest Phase 5 review batch decision:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/decide/2026-06-05T15-52Z-phase-5-exact-state-review-batch-decision.md`
- latest project route:
  `.meta/multipass/runtime/loops/project/decide/2026-06-05T15-42Z-drum-phase-5-source-project-finalization-route.md`
- latest process-fixer handoff:
  `.meta/multipass/runtime/loops/project/act/2026-06-05T15-35Z-drum-phase-5-process-fixer-recovery.md`
- previous same-failure orientation:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/orient/2026-06-05T14-06Z-phase-5-third-builder-failure-orientation.md`
- latest prior blocked builder request:
  `.meta/multipass/runtime/inbox/blocked/2026-06-05T13-22-14-375Z-builder.md`
- latest prior builder failure:
  `.meta/multipass/runtime/runs/actors/builder/2026-06-05T13-22-14-375Z-builder.failure.md`
- latest prior failed builder run:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/runs/act/builder/2026-06-05T13-22-14-375Z-builder.json`
- latest accepted Phase 4 builder action:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/act/2026-06-05T11-25Z-phase-4-header-fixture-coverage-repair.md`
- latest accepted Phase 4 builder final:
  `.meta/multipass/runtime/runs/actors/builder/2026-06-05T11-01-32-166Z-Drum-Parts-Phase-4-header-fixture-coverage-repair.final.md`
- latest accepted Phase 4 rendered evidence:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/act/phase-4-header-rendered-coverage-repair/`
- previous blocked builder request:
  `.meta/multipass/runtime/inbox/blocked/2026-06-05T09-21-47-306Z-builder.md`
- previous builder failure:
  `.meta/multipass/runtime/runs/actors/builder/2026-06-05T09-21-47-306Z-builder.failure.md`
- previous rendered evidence:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/act/phase-4-header-rendered/`
- latest build-loop recovery decision before project route:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/decide/2026-06-05T13-31Z-phase-5-narrow-recovery-decision.md`
- latest pending builder request:
  `.meta/multipass/runtime/inbox/pending/2026-06-05T18-35-42-673Z-Drum-Parts-Phase-6-routing-modal-rework.md`
- previous Phase 5 recovery orientation:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/orient/2026-06-05T13-25Z-phase-5-recovery-failure-orientation.md`
- previous Phase 5 recovery blocked builder request:
  `.meta/multipass/runtime/inbox/blocked/2026-06-05T12-38-51-092Z-builder.md`
- previous Phase 5 recovery builder failure:
  `.meta/multipass/runtime/runs/actors/builder/2026-06-05T12-38-51-092Z-builder.failure.md`
- previous Phase 5 recovery failed builder run:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/runs/act/builder/2026-06-05T12-38-51-092Z-builder.json`
- previous Phase 5 recovery decision:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/decide/2026-06-05T12-38Z-phase-5-builder-recovery-decision.md`
- previous Phase 5 blocked builder request:
  `.meta/multipass/runtime/inbox/blocked/2026-06-05T11-54-48-570Z-builder.md`
- previous Phase 5 builder failure:
  `.meta/multipass/runtime/runs/actors/builder/2026-06-05T11-54-48-570Z-builder.failure.md`
- previous Phase 5 decision:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/decide/2026-06-05T11-54Z-phase-5-pushed-kit-matrix-builder-decision.md`
- previous decision:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/decide/2026-06-05T11-41Z-phase-4-header-fixture-coverage-review-batch-decision.md`
- latest observation batch (stale for current `147e98e`; paired to `ae2a6db`,
  manifest still open due bookkeeping lag, all expected observer artifacts
  exist):
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/batches/ae2a6db9480f089111f179a82c5387b047771438/batch.yaml`
- latest Phase 5 architecture pass:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T15-54Z-phase-5-kit-matrix-architecture-review.md`
- latest Phase 5 testing gap:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T15-57Z-phase-5-kit-matrix-testing-review.md`
- latest Phase 5 UX/IA gap:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T15-53Z-phase-5-kit-matrix-ux-ia-review.md`
- latest Phase 5 visual-economy gap:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T15-54Z-phase-5-kit-matrix-visual-economy-review.md`
- latest accepted Phase 4 observation batch:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/batches/0da26fd6789d9cef1efa264c264048eaf3c2e07c/batch.yaml`
- latest accepted Phase 4 architecture pass:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T11-52Z-phase-4-header-fixture-coverage-repair-architecture-review.md`
- latest accepted Phase 4 testing pass:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T11-45Z-phase-4-header-fixture-coverage-testing-review.md`
- latest accepted Phase 4 UX/IA pass:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T11-46Z-phase-4-header-fixture-coverage-repair-ux-ia-review.md`
- latest accepted Phase 4 visual-economy pass:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T11-54Z-phase-4-header-fixture-coverage-repair-visual-economy-review.md`
- previous observation batch (stale for current `0da26fd`):
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/batches/17a66485109143ee3ec49a17193de6e32630c775/batch.yaml`
- latest UX/IA gap (superseded by `0da26fd` UX/IA pass):
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T10-58Z-phase-4-header-fixture-ux-ia-review.md`
- latest prior testing pass (stale for current `0da26fd`):
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T10-54Z-phase-4-header-exact-state-testing-review.md`
- latest prior visual-economy pass (stale for current `0da26fd`):
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T10-54Z-phase-4-header-visual-economy-review.md`
- latest prior architecture pass (stale for current `0da26fd`):
  `.meta/multipass/runtime/runs/actors/architecture-review/2026-06-05T10-50-22-867Z-Drum-Parts-Phase-4-exact-state-review-for-header-visual-fixture.final.md`
- latest accepted Phase 4 completed builder request:
  `.meta/multipass/runtime/inbox/done/2026-06-05T11-01-32-166Z-Drum-Parts-Phase-4-header-fixture-coverage-repair.md`
- previous builder final:
  `.meta/multipass/runtime/runs/actors/builder/2026-06-05T10-10-36-319Z-Drum-Parts-Phase-4-dirty-visual-fixture-finalization.final.md`
- latest resolved blocked builder request:
  `.meta/multipass/runtime/inbox/blocked/2026-06-05T07-36-18-426Z-builder.md`
- previous orientation:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/orient/2026-06-05T11-55Z-phase-4-header-fixture-coverage-review-orientation.md`
- earlier orientation:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/orient/2026-06-05T11-37Z-phase-4-header-fixture-coverage-repair-orientation.md`
- latest accepted checkpoint orientation:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/orient/2026-06-05T11-55Z-phase-4-header-fixture-coverage-review-orientation.md`
- latest accepted Phase 4 successful builder run:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/runs/act/builder/2026-06-05T11-01-32-166Z-Drum-Parts-Phase-4-header-fixture-coverage-repair.json`
- latest resolved failed builder result:
  `.meta/multipass/runtime/runs/actors/builder/2026-06-05T07-36-18-426Z-builder.failure.md`
- previous header builder final:
  `.meta/multipass/runtime/runs/actors/builder/2026-06-05T08-19-22-029Z-Drum-Parts-Phase-4-header-recovery-finalization.final.md`
- prior builder failure orientation superseded by recovery:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/orient/2026-06-05T07-11Z-phase-3-builder-failure-orientation.md`
- prior blocked builder request:
  `.meta/multipass/runtime/inbox/blocked/2026-06-05T06-29-34-257Z-Drum-Parts-Phase-3-routing-editor-domain.md`
- latest previous observation batch:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/batches/0562479c3aad9ccf84f694ddbcbbaffe1ee3adaf/batch.yaml`
- latest previous observation batch needing superseding:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/batches/8b0388cb2ed82c5ce0723889c8ddcab29ee792be/batch.yaml`
- first build-loop decision request:
  `.meta/multipass/runtime/inbox/claimed/2026-06-05T03-29-11-468Z-Drum-Parts-As-A-Group-promoted-to-build.md`

This is the durable build-loop summary. Transient inboxes, runs, and evidence
live under `.meta/multipass/runtime/loops/build/drum-parts-as-group/`.

## Promotion Context

Project decider promoted Drum Parts As A Group because one ordinary build slot
is open, direct PM readiness evidence is current, no duplicate build loop is
known, and the product priority is clear enough to use the slot while
Phrase Features reviews continue in their own active loop.

Fresh PM evidence says the architecture, spec, plan, and implementation
handoff are complete for promotion consideration:

- `docs/roadmap/drum-parts-as-group/architecture.md`
- `docs/roadmap/drum-parts-as-group/spec.md`
- `docs/roadmap/drum-parts-as-group/plan.md`
- `docs/roadmap/drum-parts-as-group/implementation-handoff.md`
- `.meta/multipass/runtime/loops/pm/drum-parts-as-group/observe/2026-06-05T03-25Z-pm-readiness-observation.md`

`build-capacity.ts` still reports no ready candidates because it reads stale
candidate surfaces, but it confirms the factual capacity shape: max active
build loops `2`, active capacity-consuming build loops `1`, locked build loops
`1`, and one available ordinary build slot.

## Intended User Outcome

Make drum-kit parts behave like coordinated group material while preserving
the existing independent drum-part tracks, pattern banks, destinations, and
editor surfaces.

The v1 build should add sibling navigation from part workspaces, a pushed
kit matrix for all member parts and active pattern slots, a post-creation
group routing editor, and persisted trigger mapping modes for per-note,
per-channel, and individual routing.

## Build-Loop Boundary

Use the Drum Parts PM handoff package as the authoritative source:

- `docs/roadmap/drum-parts-as-group/implementation-handoff.md`
- `docs/roadmap/drum-parts-as-group/spec.md`
- `docs/roadmap/drum-parts-as-group/architecture.md`
- `docs/roadmap/drum-parts-as-group/plan.md`
- `docs/roadmap/drum-parts-as-group/ux-review.md`
- `docs/roadmap/drum-parts-as-group/prototypes/01-part-workspace-header.html`
- `docs/roadmap/drum-parts-as-group/prototypes/02-kit-step-matrix.html`
- `docs/roadmap/drum-parts-as-group/prototypes/03-group-routing-editor.html`

Do not broaden v1 into a new drum-specific track type, kit-level pattern
object, inline kit-matrix step editing, generator/layer editing from the
matrix, new per-member mute/solo behavior, or unrelated phrase, scene, mixer,
slicer, or melodic-track grammar changes.

## Current Output State

The first build-loop decision verified and created
`.worktrees/roadmap-12-drum-parts-as-group` on
`auto/roadmap-12-drum-parts-as-group` from current local `main` at
`36e804a6062e8e8a85c9d55dd5529ec168ff0efc`.

Phase 0 read-only seam verification is complete:

- request:
  `.meta/multipass/runtime/inbox/claimed/2026-06-05T03-30-52-200Z-Drum-Parts-Phase-0-read-only-seam-verification.md`
- actor: `architecture-review`
- phase: `observe`
- decision artifact:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/decide/2026-06-05T03-31Z-phase-0-seam-verification-decision.md`
- result artifact:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05-phase-0-read-only-seam-verification.md`
- orientation artifact:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/orient/2026-06-05T03-38Z-phase-0-seam-verification-orientation.md`
- exact commit:
  `36e804a6062e8e8a85c9d55dd5529ec168ff0efc`
- worktree state: clean, no implementation diff

Phase 0 confirmed the current model, persistence, synchronization, drum-group
creation, destination, routing, playback/store, and part-workspace seams named
by the handoff. The PM handoff remains coherent with current code. The first
implementation slice should remain model/persistence/creation-defaults/
normalization only:

- add `DrumTriggerMappingMode` with `.perNote`, `.perChannel`, and
  `.individual`;
- persist `triggerMappingMode` and `channelMapping` on `TrackGroup`;
- decode older documents as `.perNote` with empty `channelMapping`;
- keep `noteMapping` as offsets from `DrumKitNoteMap.baselineNote`;
- normalize both `noteMapping` and `channelMapping` to current `memberIDs`;
- seed shared MIDI note defaults from `DrumGroupPlan.Member.tag` through
  `DrumKitNoteMap`;
- seed channel defaults in `memberIDs` order as stored channels `0...15`;
- preserve sample/internal kit behavior when no shared MIDI destination exists.

Phase 1 model/document implementation and invariant rework exist:

- request:
  `.meta/multipass/runtime/inbox/claimed/2026-06-05T03-41-40-127Z-builder.md`
- rework request:
  `.meta/multipass/runtime/inbox/claimed/2026-06-05T04-25-09-725Z-Drum-Parts-Phase-1-channelMapping-invariant-rework.md`
- actor: `builder`
- phase: `act`
- initial result:
  `.meta/multipass/runtime/runs/actors/builder/2026-06-05T03-41-40-127Z-builder.final.md`
- rework result:
  `.meta/multipass/runtime/runs/actors/builder/2026-06-05T04-25-09-725Z-Drum-Parts-Phase-1-channelMapping-invariant-rework.final.md`
- initial action artifact:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/act/2026-06-05T03-48Z-phase-1-model-document-builder.md`
- rework action artifact:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/act/2026-06-05T04-28Z-phase-1-channelMapping-invariant-rework-builder.md`
- pre-review orientation artifact:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/orient/2026-06-05T03-50Z-phase-1-model-document-orientation.md`
- exact-state review orientation artifact:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/orient/2026-06-05T04-24Z-phase-1-exact-state-review-orientation.md`
- rework orientation artifact:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/orient/2026-06-05T04-31Z-phase-1-channelMapping-rework-orientation.md`
- review-closure orientation artifact:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/orient/2026-06-05T04-41Z-phase-1-channelMapping-review-closure-orientation.md`
- current observation batch:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/batches/ab410421221a7236b2b33caa65fdc92f10ae712a/batch.yaml`
- initial exact commit:
  `176cbb48f1fdc4e106813f5cfdacb35a60a4c74e`
- current exact commit:
  `ab410421221a7236b2b33caa65fdc92f10ae712a`
- Phase 1 review worktree state: clean at review time

The Phase 1 commits add the persisted drum trigger mapping contract, shared
MIDI note/channel defaults, mapping normalization, membership-mutation cleanup
for `channelMapping`, and focused model/document tests. The exact commit
`ab410421221a7236b2b33caa65fdc92f10ae712a` remains the last accepted committed
checkpoint in `.worktrees/roadmap-12-drum-parts-as-group` on
`auto/roadmap-12-drum-parts-as-group`.

Changed files across Phase 1 are:

- `Sources/Document/TrackGroup.swift`
- `Sources/Document/Project+DrumGroups.swift`
- `Sources/Document/Project+Codable.swift`
- `Sources/Document/Project+Destinations.swift`
- `Tests/SequencerAITests/Document/TrackGroupTests.swift`
- `Tests/SequencerAITests/Document/ProjectAddDrumGroupTests.swift`
- `Tests/SequencerAITests/Document/ProjectNormalizationTests.swift`

Builder-reported checks at `ab410421221a7236b2b33caa65fdc92f10ae712a`
passed:

- `git diff --check` passed.
- Focused document tests passed, 25 tests.
- Drum-kit shim/sample behavior tests passed, 11 tests.

The first exact-state observer batch at `176cbb48f1fdc4e106813f5cfdacb35a60a4c74e`
showed the output was not ready for later routing/editor/playback slices. The
architecture and testing reviewers both identified that existing group
membership mutations pruned stale `noteMapping` entries but did not prune stale
`channelMapping` entries:

- `Project.addToGroup(trackID:groupID:)` removes a moved track from the
  previous group's `memberIDs` and `noteMapping`, but leaves
  `channelMapping[trackID]` behind.
- `Project.removeFromGroup(trackID:)` removes the track from `memberIDs` and
  `noteMapping`, but leaves `channelMapping[trackID]` behind.

The `ab41042` rework mirrors the existing `noteMapping.removeValue` cleanup for
`channelMapping` in those two helpers and adds focused document tests proving
removal and moving between groups keep `memberIDs`, `noteMapping`, and
`channelMapping` aligned. The corrected exact state has now passed the four
expected gate dispositions for this non-UI Phase 1 checkpoint.

Phase 2 mutations/playback stabilization is now committed and exact-state
reviewed:

- request:
  `.meta/multipass/runtime/inbox/claimed/2026-06-05T05-10-48-226Z-Drum-Parts-Phase-2-stabilization-checkpoint.md`
- actor: `builder`
- phase: `act`
- final:
  `.meta/multipass/runtime/runs/actors/builder/2026-06-05T05-10-48-226Z-Drum-Parts-Phase-2-stabilization-checkpoint.final.md`
- action artifact:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/act/2026-06-05T05-37Z-phase-2-stabilization-builder.md`
- run metadata:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/runs/act/builder/2026-06-05T05-10-48-226Z-Drum-Parts-Phase-2-stabilization-checkpoint.json`
- current orientation artifact:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/orient/2026-06-05T06-24Z-phase-2-exact-state-review-orientation.md`
- pre-review orientation artifact:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/orient/2026-06-05T06-14Z-phase-2-stabilization-orientation.md`
- observation batch:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/batches/7d66707c8577be133a04db9be4010b387a5e5753/batch.yaml`
- architecture review:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T06-18Z-phase-2-stabilization-architecture-review.md`
- testing review:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T06-20Z-phase-2-stabilization-testing-review.md`
- UX/IA review:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T06-20Z-phase-2-stabilization-ux-ia-review.md`
- visual-economy review:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T06-20Z-phase-2-stabilization-visual-economy.md`
- current `HEAD`:
  `7d66707c8577be133a04db9be4010b387a5e5753`
- current worktree state: clean

The Phase 2 commit touches 12 files with 929 insertions and 31 deletions:

- `Sources/App/SequencerDocumentSession+Mutations.swift`
- `Sources/Document/Project+Destinations.swift`
- `Sources/Document/Project+TrackMacros.swift`
- `Sources/Engine/EngineControllerRoutingHelpers.swift`
- `Sources/Engine/LiveSequencerStore+Accessors.swift`
- `Sources/Engine/LiveSequencerStore.swift`
- `Sources/Engine/SequencerSnapshotCompiler.swift`
- `Tests/SequencerAITests/App/SessionBatchHelperTests.swift`
- `Tests/SequencerAITests/Document/TrackDestinationEditingTests.swift`
- `Tests/SequencerAITests/Engine/EngineControllerTests.swift`
- `Tests/SequencerAITests/Engine/SequencerSnapshotCompilerSemanticsTests.swift`
- `Tests/SequencerAITests/Engine/StoreAccessorHelpersTests.swift`

Builder evidence says the checkpoint adds project and session mutations for
group shared destinations, inherited-vs-own member destinations, mapping mode,
note offsets, channel mapping, and routing draft application; shared
document/store playback resolution for `.perNote`, `.perChannel`, and
`.individual`; and focused tests for destination editing, session batching,
engine effective destination, snapshot compiler semantics, and store accessors.

Builder checks at `7d66707c8577be133a04db9be4010b387a5e5753` passed:

- `git diff --check`.
- Focused xcodebuild for `TrackDestinationEditingTests`,
  `SessionBatchHelperTests`, `StoreAccessorHelpersTests`,
  `EngineControllerTests`, and `SequencerSnapshotCompilerSemanticsTests`.
- 102 tests executed, 1 existing skip, 0 failures. Xcode printed a
  result-bundle save warning after test completion, but the test invocation
  exited `0`.

Compact actor-failure evidence records two earlier Phase 2 builder failures as
`usage_rate_limit`; those are superseded for output-state purposes by the
successful stabilization builder final and committed checkpoint. A later
build-orienter retry also failed with `usage_rate_limit`; the
`2026-06-05T06-14Z` orientation recovered the pre-review interpretation, and
the `2026-06-05T06-24Z` orientation synthesizes the completed review batch.

Phase 3 routing editor domain recovery is now committed and exact-state
reviewed for the domain-only checkpoint:

- request:
  `.meta/multipass/runtime/inbox/done/2026-06-05T07-15-09-981Z-Drum-Parts-Phase-3-routing-editor-domain-recovery.md`
- actor: `builder`
- phase: `act`
- final:
  `.meta/multipass/runtime/runs/actors/builder/2026-06-05T07-15-09-981Z-Drum-Parts-Phase-3-routing-editor-domain-recovery.final.md`
- action artifact:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/act/2026-06-05T07-20Z-phase-3-routing-editor-domain-recovery-builder.md`
- current orientation artifact:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/orient/2026-06-05T07-35Z-phase-3-exact-state-review-orientation.md`
- pre-review orientation artifact:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/orient/2026-06-05T07-22Z-phase-3-routing-editor-domain-orientation.md`
- run metadata:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/runs/act/builder/2026-06-05T07-15-09-981Z-Drum-Parts-Phase-3-routing-editor-domain-recovery.json`
- base commit:
  `7d66707c8577be133a04db9be4010b387a5e5753`
- current `HEAD`:
  `0562479c3aad9ccf84f694ddbcbbaffe1ee3adaf`
- current worktree state: clean
- observation batch:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/batches/0562479c3aad9ccf84f694ddbcbbaffe1ee3adaf/batch.yaml`
- architecture review final:
  `.meta/multipass/runtime/runs/actors/architecture-review/2026-06-05T07-26-31-072Z-architecture-review-for-Drum-Parts-Phase-3-routing-editor-domain-checkpoint.final.md`
- testing review:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T07-30Z-phase-3-routing-editor-domain-testing-review.md`
- UX/IA review:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T07-33Z-phase-3-routing-editor-domain-ux-ia-review.md`
- visual-economy review:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T07-29Z-phase-3-routing-editor-domain-visual-economy.md`

The Phase 3 commit touches 5 files with 627 insertions:

- `SequencerAI.xcodeproj/project.pbxproj`
- `Sources/Musical/DAWNoteName.swift`
- `Sources/UI/DrumGroup/DrumGroupRoutingEditorDraft.swift`
- `Tests/SequencerAITests/Musical/DAWNoteNameTests.swift`
- `Tests/SequencerAITests/UI/DrumGroupRoutingEditorDraftTests.swift`

Builder evidence says the checkpoint adds DAW note-name display/parsing and a
routing editor draft/view-model domain type for shared destination, mapping
mode, ordered member rows, inherit/own state, note/channel draft inputs, Cancel
reset, atomic Apply through `Project.DrumGroupRoutingDraft`, validation
issues, and non-blocking duplicate-channel warnings. The builder also repaired
Xcode project membership so the new source and test files are compiled.

Builder checks at `0562479c3aad9ccf84f694ddbcbbaffe1ee3adaf` passed:

- `git diff --check`.
- Focused xcodebuild for `DAWNoteNameTests`: 7 tests, 0 failures.
- Focused xcodebuild for `DrumGroupRoutingEditorDraftTests`: 9 tests, 0
  failures.
- `rg` against generated Xcode Swift file lists confirmed the four new
  source/test files are present after focused test runs.

Phase 3 exact-state review passes for this intentionally domain-only checkpoint.
It does not implement the visible routing editor surface, part workspace
header, pushed kit matrix, visual wiring, screenshots, merge, or final
integration.

Phase 4 part workspace header and sibling navigation is now committed, with a
follow-up visual fixture finalization checkpoint that makes the rendered header
evidence reviewable:

- header implementation request:
  `.meta/multipass/runtime/inbox/done/2026-06-05T08-19-22-029Z-Drum-Parts-Phase-4-header-recovery-finalization.md`
- header implementation builder final:
  `.meta/multipass/runtime/runs/actors/builder/2026-06-05T08-19-22-029Z-Drum-Parts-Phase-4-header-recovery-finalization.final.md`
- header implementation action artifact:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/act/2026-06-05T08-58Z-phase-4-header-recovery-builder.md`
- visual fixture finalization request:
  `.meta/multipass/runtime/inbox/done/2026-06-05T10-10-36-319Z-Drum-Parts-Phase-4-dirty-visual-fixture-finalization.md`
- visual fixture finalization builder final:
  `.meta/multipass/runtime/runs/actors/builder/2026-06-05T10-10-36-319Z-Drum-Parts-Phase-4-dirty-visual-fixture-finalization.final.md`
- visual fixture finalization action artifact:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/act/2026-06-05T10-46Z-phase-4-dirty-visual-fixture-finalization.md`
- header run metadata:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/runs/act/builder/2026-06-05T08-19-22-029Z-Drum-Parts-Phase-4-header-recovery-finalization.json`
- visual fixture run metadata:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/runs/act/builder/2026-06-05T10-10-36-319Z-Drum-Parts-Phase-4-dirty-visual-fixture-finalization.json`
- orientation artifact:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/orient/2026-06-05T10-45Z-phase-4-visual-fixture-finalization-orientation.md`
- current `HEAD`:
  `17a66485109143ee3ec49a17193de6e32630c775`
- current worktree state: clean

Compact failure evidence records `usage_rate_limit`; run metadata records
`status: failed` with `SIGTERM`; the expected final artifact
`.meta/multipass/runtime/runs/actors/builder/2026-06-05T07-36-18-426Z-builder.final.md`
does not exist. That failure is now superseded by the recovery commit and
builder action artifact, but remains useful compact process evidence.

Another builder attempt to repair rendered evidence failed at
`.meta/multipass/runtime/runs/actors/builder/2026-06-05T09-21-47-306Z-builder.failure.md`
with `usage_rate_limit` / `SIGTERM`, leaving useful screenshots/status files
but a dirty worktree. That dirty state is now superseded by commit `17a6648`.

The Phase 4 header implementation commit `8b0388c` changed two files from the
Phase 3 checkpoint:

- `Sources/UI/Track/TrackWorkspaceView.swift`
- `Tests/SequencerAITests/UI/UIReadsStoreDirectlyTests.swift`

The diff is 430 insertions and 17 deletions. It adds a kit-aware
part-workspace header model/view, bounded previous/next IDs derived from
`TrackGroup.memberIDs`, stale sibling filtering, retained originating part
state for a later `Open Kit View` matrix path, color parsing, non-kit fallback,
rename preservation through the existing editor, and focused model/read-path
tests for bounds, ordering, stale/missing groups, one-member groups, non-kit
fallback, long names, and origin retention.

Builder checks at `8b0388cb2ed82c5ce0723889c8ddcab29ee792be` passed:

- `git diff --check`.
- Focused xcodebuild for `DrumPartWorkspaceHeaderModelTests` and
  `UIReadsStoreDirectlyTests/test_trackWorkspaceView_readPath_doesNotCallExportToProject`:
  10 tests, 0 failures.

The visual fixture finalization commit `17a6648` changes three files from
`8b0388c`:

- `Sources/UI/Track/TrackWorkspaceView.swift`
- `Sources/UI/VisualScenarioCommandRunner.swift`
- `scripts/visual-scenarios/drum-part-workspace-header.sh`

It adds deterministic visual-command/status plumbing plus a project-local
capture script. Rendered evidence now exists under
`.meta/multipass/runtime/loops/build/drum-parts-as-group/act/phase-4-header-rendered/`
for middle selected part, first-part previous disabled, last-part next
disabled, rename editing, Open Kit View retained-origin, and non-kit fallback.
The focused xcodebuild log in that directory reports 10 selected tests, 0
failures, against the same fixture-enabled tree before commit.

## Gate Pairing

For the current Phase 4 commit
`17a66485109143ee3ec49a17193de6e32630c775`, no gates are paired yet.

The prior `8b0388c` Phase 4 batch has architecture pass, testing pass, UX/IA
`evidence-insufficient`, and visual-economy `evidence-insufficient`; it cannot
be inherited for `17a6648` because the new commit changes production SwiftUI
and visual scenario command plumbing. The prior UX/IA gap was
`capture-permission-or-focus` because the actor captured lock-screen content;
the prior visual-economy gap was `tooling-fixture-gap` because no deterministic
fixture could create/select the drum group member workspace. The new commit
addresses those evidence gaps, but reviewer acceptance still needs to be
paired to the new exact state.

The coordinator scoped-gate invalidation helper was run with source commit
`8b0388cb2ed82c5ce0723889c8ddcab29ee792be` and current commit `17a6648`. It
found no configured project scope hints and reported `full-review-default` for
architecture, testing, UX/IA, visual, and visual economy; build/compile remains
`exact-state-required`. This advisory report supports full exact-state review
and no inherited gates.

For the current Phase 3 commit, builder and observer evidence are exact-state
paired to `0562479c3aad9ccf84f694ddbcbbaffe1ee3adaf`. No Phase 2 gates are
inherited because Phase 3 touches Xcode project membership, musical mapping
code, UI-domain support code, and tests.

For Phase 3 at `0562479c3aad9ccf84f694ddbcbbaffe1ee3adaf`:

- Architecture: pass. Evidence:
  `.meta/multipass/runtime/runs/actors/architecture-review/2026-06-05T07-26-31-072Z-architecture-review-for-Drum-Parts-Phase-3-routing-editor-domain-checkpoint.final.md`
- Testing: pass. Evidence:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T07-30Z-phase-3-routing-editor-domain-testing-review.md`
- UX/IA: pass, not-applicable for rendered UX because this exact commit adds
  UI-domain state but no production SwiftUI view, sheet body, part workspace
  header, kit matrix, inspector, app root, or rendered routing editor surface.
  Evidence:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T07-33Z-phase-3-routing-editor-domain-ux-ia-review.md`
- Visual economy: pass, not-applicable/domain-only because no rendered target
  surface or state exists to capture. Evidence:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T07-29Z-phase-3-routing-editor-domain-visual-economy.md`

The Phase 3 batch manifest
`.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/batches/0562479c3aad9ccf84f694ddbcbbaffe1ee3adaf/batch.yaml`
still says `status: open`, and the architecture reviewer did not mirror a
loop-local observe artifact, but the architecture run metadata completed with
exit `0` and the final artifact records the pass verdict. Treat that as
runtime/evidence hygiene, not a missing product gate.

For the current Phase 2 commit, builder and observer evidence are exact-state
paired to `7d66707c8577be133a04db9be4010b387a5e5753`. The prior Phase 1 gate
passes remain valid for the accepted
`ab410421221a7236b2b33caa65fdc92f10ae712a` checkpoint only; no Phase 1 gate is
inherited for Phase 2 because the commit touches architecture/runtime behavior,
document/session mutations, engine/store/snapshot resolution, and tests.

The scoped gate invalidation helper was run with source commit
`ab410421221a7236b2b33caa65fdc92f10ae712a` and current commit `7d66707`. It
found no configured project scope hints and reported `full-review-default` for
architecture, testing, UX/IA, visual, and visual economy; build/compile remains
`exact-state-required`. This advisory report supports full exact-state review
and no inherited gates. The actual Phase 2 gate status comes from the four
observer artifacts listed below.

For Phase 2 at `7d66707c8577be133a04db9be4010b387a5e5753`:

- Architecture: pass. Evidence:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T06-18Z-phase-2-stabilization-architecture-review.md`
- Testing: evidence-sufficient. Evidence:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T06-20Z-phase-2-stabilization-testing-review.md`
- UX/IA: pass, not-applicable for this exact non-UI checkpoint. Evidence:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T06-20Z-phase-2-stabilization-ux-ia-review.md`
- Visual economy: pass, non-visual stabilization slice. Evidence:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T06-20Z-phase-2-stabilization-visual-economy.md`

The batch manifest
`.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/batches/7d66707c8577be133a04db9be4010b387a5e5753/batch.yaml`
still says `status: open`, but all four expected observer artifacts exist.
Treat that as stale runtime bookkeeping, not missing review evidence.

- Architecture: Phase 0 read-only seam verification passed at exact commit
  `36e804a6062e8e8a85c9d55dd5529ec168ff0efc`.
  Evidence:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05-phase-0-read-only-seam-verification.md`
- Architecture for Phase 1 initial output: exact-state paired and
  `needs-correction` at
  `176cbb48f1fdc4e106813f5cfdacb35a60a4c74e`.
  Evidence:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T03-54Z-phase-1-model-document-architecture-review.md`
- Testing for Phase 1 initial output: exact-state paired and
  `needs-correction` at
  `176cbb48f1fdc4e106813f5cfdacb35a60a4c74e`.
  Evidence:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T03-56Z-phase-1-testing-review.md`
- UX/IA for Phase 1 initial output: exact-state paired and passed as
  not-applicable for this non-UI document/model slice.
  Evidence:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T03-55Z-phase-1-ux-ia-review.md`
- Visual economy for Phase 1 initial output: missing final observer artifact.
  The routed
  visual-economy observer timed out before writing a final artifact, with
  `timeout_without_final_artifact` / `SIGTERM` recorded in compact actor
  failure evidence. This is a process/evidence gap, not product visual rework
  evidence. Evidence:
  `.meta/multipass/state/actor-failures.md`;
  `.meta/multipass/runtime/runs/actors/visual-economy-review/2026-06-05T03-53-07-422Z-Drum-Parts-Phase-1-exact-state-review.failure.md`

For the accepted Phase 1 `ab41042` rework, all four expected observer gates
are exact-state paired:

- Architecture: pass at
  `ab410421221a7236b2b33caa65fdc92f10ae712a`.
  Evidence:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T04-38Z-phase-1-channelMapping-rework-architecture-review.md`
- Testing: pass at `ab410421221a7236b2b33caa65fdc92f10ae712a`.
  Evidence:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T04-38Z-phase-1-channelMapping-rework-testing-review.md`
- UX/IA: pass, not-applicable, at
  `ab410421221a7236b2b33caa65fdc92f10ae712a` because the exact rework changed
  only document/test files and no visible workflow surface.
  Evidence:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T04-37Z-phase-1-channelMapping-rework-ux-ia-review.md`
- Visual economy: pass, not-applicable, at
  `ab410421221a7236b2b33caa65fdc92f10ae712a` because the exact rework changed
  only document/test files and no persistent visual surface.
  Evidence:
  `.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/2026-06-05T04-37Z-phase-1-channelMapping-rework-visual-economy-review.md`

The batch manifest
`.meta/multipass/runtime/loops/build/drum-parts-as-group/observe/batches/ab410421221a7236b2b33caa65fdc92f10ae712a/batch.yaml`
still says `status: open`, but all four expected observer run metadata files
show `status: complete` and exit `0`. Treat that as a runtime bookkeeping
discrepancy, not missing gate evidence.

## Architecture Risk

No line-stop issue was found.

The prior local Phase 1 architecture/testing issue is cleared for
`ab410421221a7236b2b33caa65fdc92f10ae712a`. The exact-state reviewers confirm
that `Project.addToGroup(trackID:groupID:)` and
`Project.removeFromGroup(trackID:)` now prune `channelMapping` wherever they
prune `noteMapping`, with focused regression tests for removing a member and
moving a member between shared-MIDI drum groups.

The prior local Phase 2 caution was that playback/routing work could update
only `EngineController.effectiveDestination(for:in:)` and miss
`SequencerSnapshotCompiler.compileResolvedDestinations`, creating divergent
document-based and compiled playback behavior. That caution has been reviewed
and cleared for the Phase 2 commit. The
architecture reviewer confirmed that document-model engine setup and snapshot
compilation delegate inherited drum-group playback through the same
document-side resolver, and that mapping-only edits use live-store mutation plus
snapshot publishing rather than a full document engine apply.

There is no top-loop systemic architecture escalation from the latest accepted
checkpoint, the failed Phase 3 builder attempt, or the recovered Phase 3
checkpoint. The prior Phase 3 issue was local to this build loop: a builder
runtime failure left a dirty partial routing-editor domain implementation
without a committed checkpoint. Recovery produced a clean committed checkpoint,
and exact-state review has now accepted it for the domain-only scope.

The Phase 4 builder failures were also local to this build loop:
usage-rate-limit failures left dirty partial header/fixture work before final
artifacts or reviewable pairing. Those states have now been recovered into
commit `17a66485109143ee3ec49a17193de6e32630c775`. No product architecture
line stop is established, but the new exact state still needs architecture
review before it can become an accepted checkpoint. Review should check whether
`TrackWorkspaceView.swift` remains an acceptable local owner for header model
formation and retained matrix-origin navigation state, whether the
`VisualScenarioCommandRunner` fixture/status hooks stay bounded as evidence
tooling, and whether the seam composes cleanly with the upcoming pushed kit
matrix.

The Phase 3 architecture reviewer passed the draft/view-model ownership,
validation boundary, `Project.DrumGroupRoutingDraft` coupling,
document/runtime boundary, and Xcode project membership. The remaining
architecture risk is future UI wiring: the visible routing editor should
consume this draft model without duplicating validation or splitting
document/session/runtime ownership.

The remaining architecture watch item is local maintainability pressure in
broad owner files such as `SequencerDocumentSession+Mutations.swift`,
`EngineController.swift`, and `LiveSequencerStore+Accessors.swift`; no line stop
was recommended.

## Next Action Kind

The next useful build-loop action is a build-decider decision for an
exact-state observer batch at
`17a66485109143ee3ec49a17193de6e32630c775`, not another builder recovery pass
and not merge readiness.

For the current output, the lowest unmet layer is exact-state observer review.
For the overall feature, user-facing workflow implementation remains
incomplete: accepted header rendering review, pushed kit matrix, routing editor
UI integration, final integration, and complete visual workflow evidence are
still incomplete. The Phase 2 non-UI UX/visual passes, Phase 3 domain-only
UX/visual dispositions, and Phase 4 `8b0388c` observer outcomes must not be
inherited by the current or future rendered surfaces.

Product-owner attention is not needed.

## Product-Owner Attention

Product-owner attention is not needed for this promotion. Existing unrelated
locks remain scoped to MIDI hardware availability and the Audio Looping v1
scope choice.
