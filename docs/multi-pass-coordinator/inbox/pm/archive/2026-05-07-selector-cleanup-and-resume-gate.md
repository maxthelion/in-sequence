---
created: 2026-05-07T10:51:36Z
source: multi-pass-coordinator
status: handled
priority: high
target_output: docs/roadmap/agentic-loop/state.md
handled: 2026-05-07T10:55:53Z
---

# Selector Cleanup And Resume Gate

The supervisor diagnosis now exists at
`docs/roadmap/agentic-loop/supervisor-diagnosis.md`. It says the recursive
review-of-review artifacts are process noise, and the original non-recursive
reviews for `docs/plans/2026-05-06-track-performance-overlay.md` are valid
build-planning evidence.

Please perform the next PM/supervisor cleanup step before any build promotion.

## Required Context

- `README.md`
- `docs/roadmap/AGENTS.md`
- `docs/roadmap/context-pack.md`
- `docs/roadmap/agentic-loop/state.md`
- `docs/roadmap/agentic-loop/supervisor-diagnosis.md`
- `docs/roadmap/agentic-loop/passes/write-p0-performance-overlay-build-plan.md`
- `docs/roadmap/agentic-loop/passes/review-write-p0-performance-overlay-build-plan-through-lenses.md`
- `docs/roadmap/agentic-loop/reviews/write-p0-performance-overlay-build-plan/`
- `docs/plans/2026-05-06-track-performance-overlay.md`

## Requested Work

1. Update `docs/roadmap/agentic-loop/state.md` so it no longer waits for the
   already-complete supervisor diagnosis.
2. Record the active gate clearly: P0 performance overlay build promotion is
   allowed only after the selector/review scan can no longer select
   `review-through-lenses` passes or review files for further lens review.
3. If the cleanup is local to `docs/roadmap/agentic-loop`, neutralize the
   recursive review-of-review artifacts from active review gating by archiving
   them or writing an explicit ignore manifest/note. Preserve them as process
   evidence; do not delete them outright.
4. If the selector fix lives outside this repo or outside PM permissions, write
   the exact external fix/blocker into state and stop. Do not promote build work
   until that fix is confirmed.

## Expected Outcome

The next coordinator tick should be able to tell one of these states:

- `selector-cleanup-blocked`: an external selector/harness change is needed;
- `ready-for-p0-overlay-promotion`: local cleanup is complete and the original
  P0 overlay plan reviews are the active evidence;
- `needs-one-clean-review`: the selector contract changed enough that one fresh
  non-recursive review of the build plan is required.

No product-owner decision is requested. This is a process integrity gate.
