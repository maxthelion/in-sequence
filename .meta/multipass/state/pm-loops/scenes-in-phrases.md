# Scenes In Phrases PM Loop

- updated: 2026-06-07T15:11Z
- loop: `pm/scenes-in-phrases`
- status: locked on product-owner prototype approval
- feature: `scenes-in-phrases`
- backlog item: 22
- registry manifest:
  `.meta/multipass/config/loops/pm/scenes-in-phrases.yaml`
- runtime root: `.meta/multipass/runtime/loops/pm/scenes-in-phrases/`
- authoritative product docs: `docs/roadmap/scenes-in-phrases/`
- selected prototype direction:
  `docs/roadmap/scenes-in-phrases/prototypes/03-selected-phrase-scene-rail.html`
- comparison artifact:
  `docs/roadmap/scenes-in-phrases/prototypes/04-inline-scene-strip-matrix.html`
- PM critique:
  `docs/roadmap/scenes-in-phrases/ux-review.md`
- latest observation:
  `.meta/multipass/runtime/loops/pm/scenes-in-phrases/observe/2026-06-07T14-31Z-pm-readiness-observation.md`
- latest orientation:
  `.meta/multipass/runtime/loops/pm/scenes-in-phrases/orient/2026-06-07T15-07Z-pm-orientation.md`
- latest decision:
  `.meta/multipass/runtime/loops/pm/scenes-in-phrases/decide/2026-06-07T15-11Z-scenes-in-phrases-prototype-lock.md`
- latest PM action evidence: none yet for this PM loop

## Current Interpretation

This lane exists to rebuild ready-buffer depth through PM artifact work, not
to promote a build loop. It is now loop-local locked on the narrow
product-owner prototype approval gate for the selected Scenes In Phrases
direction.

Current roadmap artifacts show a replacement prototype pass for adding scene
authoring into the existing track-oriented Phrase Matrix shape. The accepted
PM critique selects `prototypes/03-selected-phrase-scene-rail.html` as the
direction and keeps `prototypes/04-inline-scene-strip-matrix.html` as
comparison evidence.

The accepted critique is sufficient evidence that prototype 03 is the
PM-selected candidate. It is not sufficient evidence that the product-owner
approval gate is cleared: the lane README, PM feature table, latest PM
readiness observation, feature-readiness state, and UX review wording all still
point to human prototype review before architecture work, and no separate
owner approval artifact was observed.

The 2026-06-07T15:11Z PM decision locked the loop manifest on that prototype
approval question. No `pm-artifact-author` request is useful until the answer
exists, because architecture/spec/plan/handoff authoring would otherwise
pretend the human approval gate is cleared.

The smallest product-owner question is whether prototype 03, the
selected-phrase scene rail, is approved as the architecture/spec direction, or
whether the owner wants changes toward the heavier row-visible scene-summary
emphasis shown by prototype 04. Recommended default: approve prototype 03 and
keep prototype 04 only as comparison evidence for final row-summary language.

## Existing PM Artifacts

- `README.md`: stage `review-prototypes`; says the selected prototype needs
  human approval before architecture work.
- `notes.md`: raw product notes for Tracks/Scenes phrase modes and phrase-owned
  Scene A, crossfader, and Scene B values.
- `user-stories.md`: stories for phrase-owned Scene A/B assignment, static
  blend, per-bar blend changes, Tracks/Scenes mode switching, and row-level
  scene-intent readability.
- `existing-state.md`: Phrase Matrix, phrase model, master-bus scene model,
  runtime, UI, architecture, and testing gap context.
- `artifacts.md`: artifact inventory and design implication from the current
  Phrase Matrix screenshot.
- `feedback/20260503-153024-prototypes-feedback.md`: handled feedback that
  rejected standalone scene-page prototypes and required extending the current
  track-oriented Phrase Matrix.
- `ux-review.md`: accepted PM critique selecting prototype 03 and retaining
  prototype 04 as a comparison artifact.
- `prototypes/README.md`: active replacement-pass summary and review focus.
- `prototypes/03-selected-phrase-scene-rail.html`: selected direction.
- `prototypes/04-inline-scene-strip-matrix.html`: comparison artifact.
- `ux-reviews/ux-review-2026-05-03-needs-rework.md`: archived prior failed
  review.

## Missing Or Stale Readiness Gates

- Missing explicit product-owner prototype approval for
  `docs/roadmap/scenes-in-phrases/prototypes/03-selected-phrase-scene-rail.html`.
- Missing accepted `architecture.md`, `spec.md`, `plan.md`, and
  `implementation-handoff.md`.
- PM-loop decision artifact now exists and locks the loop manifest on the
  prototype approval question.
- The PM feature table is stale for several consumed lanes, but it remains
  consistent with current Scenes In Phrases roadmap evidence.

## Product-Owner Attention

Needed before architecture work starts if this lane is to progress. The
bounded decision is whether prototype 03, the selected-phrase scene rail, is
approved as the architecture/spec direction or whether the owner wants changes,
especially toward the heavier row-visible summary emphasis shown by prototype
04.

No broader product question is needed from this observation. The compact row
summary language, scene-library binding, and phrase-entry recall timing gaps
are already identified as architecture/spec follow-up after prototype approval.

The loop manifest now reports `status: locked` with this question. Unlock when
a product-owner approval or requested-change answer is recorded in the
Scenes In Phrases PM artifacts.

## Promotion Readiness

Not ready for build-loop promotion. There is no accepted architecture, spec,
plan, or implementation handoff.

Not ready for architecture authoring until a separate owner approval artifact
or direct product-owner answer clears the prototype gate.

The owner lock is narrow and should not block unrelated project work.

## Evidence Freshness

- PM decision:
  `.meta/multipass/runtime/loops/pm/scenes-in-phrases/decide/2026-06-07T15-11Z-scenes-in-phrases-prototype-lock.md`.
- Project orientation:
  `.meta/multipass/state/ooda/orientation.md`, updated 2026-06-07T14:20Z.
- Feature readiness:
  `.meta/multipass/state/feature-readiness.md`, updated 2026-06-07T13:45Z.
- PM feature table:
  `.meta/multipass/state/pm-loop-feature-table.md`, updated
  2026-06-05T01:56Z and stale for several consumed lanes, but still consistent
  with Scenes In Phrases needing prototype approval.
- Setup evidence:
  `.meta/multipass/runtime/loops/project/act/2026-06-07T14-28Z-scenes-in-phrases-pm-loop-setup.md`.
- First loop-local observation:
  `.meta/multipass/runtime/loops/pm/scenes-in-phrases/observe/2026-06-07T14-31Z-pm-readiness-observation.md`.
- First loop-local orientation:
  `.meta/multipass/runtime/loops/pm/scenes-in-phrases/orient/2026-06-07T15-07Z-pm-orientation.md`.

## Checks Run

- Read the claimed request, project spirit, README.md, PM loop manifest, lane
  README, latest project orientation, feature-readiness, decision log,
  existing Scenes In Phrases PM summary, PM feature table, lane notes, user
  stories, existing-state, artifact inventory, handled prototype feedback,
  prototypes README, UX review, and direct lane/runtime file lists.
- Ran coordinator inventory:
  `bun /Users/maxwilliams/dev/multi-pass-coordinator/src/cli/inventory.ts --project /Users/maxwilliams/dev/in-sequence`.
- No product build, test suite, visual capture, promotion, inbox lifecycle
  move, merge, rebase, push, cleanup, product-code edit, build-loop manifest
  edit, PM artifact authoring, product rework, or inbox request was
  performed. The PM loop manifest was changed from `active` to `locked` with
  the narrow product-owner prototype approval question.
