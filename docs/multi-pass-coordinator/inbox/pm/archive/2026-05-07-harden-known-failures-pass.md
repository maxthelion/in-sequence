---
created: 2026-05-07T11:11:50Z
source: multi-pass-coordinator
status: handled
priority: high
target_output: docs/roadmap/agentic-loop/passes/harden-known-failures.md
handled: 2026-05-07T11:19:00Z
---

# Harden Known Failures Pass

## Request

Action: `diagnose-supervisor-blocker`

The selector cleanup is now complete enough that no active
`review-*-through-lenses.md` pass remains in `docs/roadmap/agentic-loop/passes/`.
However, `scripts/multi-pass/show-readiness.sh` rewrote
`docs/roadmap/agentic-loop/state.md` during the 2026-05-07T11:10Z coordinator
tick to:

```yaml
mode: harden
status: active
next_action: create-hardening-pass
```

The pass file already exists as a draft:

- `docs/roadmap/agentic-loop/passes/harden-known-failures.md`

## Required Work

1. Treat this as the current selector result unless a fresher state file says
   otherwise.
2. Convert the draft hardening pass into the next concrete agent-actionable
   output, or write a concise diagnosis explaining why the selector should have
   promoted the P0 performance overlay plan instead.
3. Preserve the valid P0 performance overlay evidence:
   - `docs/roadmap/agentic-loop/synthesis/production-cherry-pick-candidates.md`
   - `docs/roadmap/agentic-loop/passes/write-p0-performance-overlay-build-plan.md`
   - `docs/plans/2026-05-06-track-performance-overlay.md`
   - `docs/roadmap/agentic-loop/reviews/write-p0-performance-overlay-build-plan/`
4. Do not schedule product-owner attention for this. If hardening finds a real
   product decision, reduce it to one concise question with a recommended
   default in the normal attention path.

## Product-Owner Attention

None. This is agent-side process/product hardening before the next broad run or
build promotion.
