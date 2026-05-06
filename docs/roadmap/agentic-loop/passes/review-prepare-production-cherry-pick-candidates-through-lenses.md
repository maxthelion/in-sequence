---
id: review-prepare-production-cherry-pick-candidates-through-lenses
mode: review-through-lenses
status: ready-for-agent
created: 2026-05-06T20:18:00+01:00
objective: Review prepare-production-cherry-pick-candidates through UX/IA, architecture, and testing lenses
max_parallel: 1
requires_context_pack: true
reviews_pass: prepare-production-cherry-pick-candidates
---

# Review Prepare Production Cherry Pick Candidates Through Lenses

## Objective

Review `/Users/maxwilliams/dev/in-sequence/docs/roadmap/agentic-loop/passes/prepare-production-cherry-pick-candidates.md` and its outputs through the missing lenses:
- ux-ia
- architecture
- testing

This is agent-side review. Do not ask the user to inspect raw output. Decide
what can be corrected by agents, what should become a follow-up pass, and what
small product judgment is genuinely needed, if any.

## Required Inputs

- `docs/roadmap/context-pack.md`
- `docs/roadmap/agentic-loop/state.md`
- `/Users/maxwilliams/dev/in-sequence/docs/roadmap/agentic-loop/passes/prepare-production-cherry-pick-candidates.md`
- outputs and evidence linked from the reviewed pass
- relevant wiki pages linked from the context pack

## Expected Outputs

- `docs/roadmap/agentic-loop/reviews/prepare-production-cherry-pick-candidates/ux-ia.md`
- `docs/roadmap/agentic-loop/reviews/prepare-production-cherry-pick-candidates/architecture.md`
- `docs/roadmap/agentic-loop/reviews/prepare-production-cherry-pick-candidates/testing.md`
- an attention-ledger entry saying what was caught, fixed, or scheduled;
- updated loop state pointing at the next agent-side correction pass when
  review finds issues.

## Stop Conditions

- visual evidence is missing or invalid and cannot be recreated;
- the output is too broken to review without first scheduling a correction pass.
