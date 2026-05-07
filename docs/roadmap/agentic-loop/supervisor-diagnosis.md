---
status: complete
created: 2026-05-07T10:24:47Z
source_request: docs/roadmap/supervisor-requests/2026-05-07-supervisor-diagnose.md
---

# Supervisor Diagnosis

## Diagnosis

The selector that schedules missing lens reviews treated every completed pass
under `docs/roadmap/agentic-loop/passes/` as reviewable. It did not exclude
passes with `mode: review-through-lenses`, and the pass generator then created
another `review-...-through-lenses` pass for the review pass itself.

That allowed `review-write-p0-performance-overlay-build-plan-through-lenses.md`
to become the source for
`review-review-write-p0-performance-overlay-build-plan-through-lenses-through-lenses.md`.
Each later pass repeated the same pattern. The generated review files confirm
the recursion because their `reviewed_output` fields point to review files under
`docs/roadmap/agentic-loop/reviews/` instead of to the implementation or
planning artifact being validated.

## Evidence To Keep

Treat these as valid product/build-planning evidence:

- `docs/roadmap/agentic-loop/synthesis/production-cherry-pick-candidates.md`
- `docs/roadmap/agentic-loop/passes/write-p0-performance-overlay-build-plan.md`
- `docs/plans/2026-05-06-track-performance-overlay.md`
- `docs/roadmap/agentic-loop/reviews/write-p0-performance-overlay-build-plan/ux-ia.md`
- `docs/roadmap/agentic-loop/reviews/write-p0-performance-overlay-build-plan/architecture.md`
- `docs/roadmap/agentic-loop/reviews/write-p0-performance-overlay-build-plan/testing.md`

The earlier candidate and wireframe review directories remain valid historical
evidence for their own source passes. The recursive review artifacts may be
kept only as process-anomaly evidence.

## Evidence To Ignore Or Archive

Ignore for build-readiness gating, and preferably archive outside the active
review scan, all generated review-of-review passes and review directories whose
source is already a `review-through-lenses` pass:

- `docs/roadmap/agentic-loop/passes/review-write-p0-performance-overlay-build-plan-through-lenses.md`
- `docs/roadmap/agentic-loop/passes/review-review-*write-p0-performance-overlay-build-plan*through-lenses*.md`
- `docs/roadmap/agentic-loop/reviews/review-write-p0-performance-overlay-build-plan-through-lenses/`
- `docs/roadmap/agentic-loop/reviews/review-review-*write-p0-performance-overlay-build-plan*through-lenses*/`

Those files reviewed review files, not the P0 production build plan. They
should not be allowed to satisfy, block, or reschedule normal promotion.

## Rule Change

Change the missing-lens selector and review-pass generator so lens review can
target implementation, planning, synthesis, decision, and wireframe outputs,
but cannot target:

- any file under `docs/roadmap/agentic-loop/reviews/`;
- any pass with `mode: review-through-lenses`;
- any pass id or `reviews_pass` value that starts with `review-` and ends in
  `-through-lenses`;
- any pass whose expected outputs are only review files.

The selector should mark review-through-lenses passes as terminal review
actions. After they complete, their `scheduled_follow_up` or the reviewed
artifact should become the next selectable work item; the review pass itself
must not re-enter the review queue.

## P0 Performance Overlay Promotion

The P0 performance overlay build plan can be promoted after the selector fix
and active review scan ignore/archive the recursive artifacts.

It does not need another product-shape review. The non-recursive UX/IA,
architecture, and testing reviews for
`docs/plans/2026-05-06-track-performance-overlay.md` already passed and caught
the material repeat Keep ambiguity. If the selector implementation changes the
review contract, run one fresh non-recursive sanity review of the build plan
only; do not review the review files.

## Product-Owner Attention

No product-owner decision is needed. This is a process/supervision blocker, not
a product conflict.
