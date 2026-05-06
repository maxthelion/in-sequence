---
id: prepare-production-cherry-pick-candidates
mode: prepare-candidates
status: complete
created: 2026-05-06T20:14:00+01:00
completed: 2026-05-06T20:18:00+01:00
objective: Separate production-safe model/test candidates from probe-local UI state
max_parallel: 1
requires_context_pack: true
source_decisions: docs/roadmap/agentic-loop/decisions/inferred-defaults.md
---

# Prepare Production Cherry-Pick Candidates

## Completion

Complete. Candidate synthesis exists at
`docs/roadmap/agentic-loop/synthesis/production-cherry-pick-candidates.md`.

The pass did not merge or cherry-pick any branch. It separates pure model/test
seeds from architecture-plan candidates and explicitly rejects probe-local UI
state, temporary fixtures, whole-branch cherry-picks, and broad project-file
churn.

## Objective

Turn the accepted inferred defaults into an agent-actionable candidate list for
the next build round. The output should identify model/test artifacts that may
be worth porting into production and explicitly reject probe-local UI state,
temporary fixtures, or broad project-file churn.

Do not merge or cherry-pick branches in this pass. This is scheduling and
handoff work only.

## Required Inputs

- `README.md`
- `docs/roadmap/context-pack.md`
- `docs/roadmap/agentic-loop/decisions/inferred-defaults.md`
- `docs/roadmap/agentic-loop/synthesis/current-product-shape.md`
- `docs/roadmap/probe-results/holistic-wireframe-from-synthesis-2026-05-06.md`
- `docs/roadmap/probe-results/overnight-broad-probe-2026-05-05-morning-harvest.md`
- `docs/roadmap/probe-results/visual-baseline-2026-05-06/ux-baseline.md`
- relevant lane notes and probe summaries for candidate artifacts

## Expected Outputs

- A candidate list under `docs/roadmap/agentic-loop/synthesis/` that separates:
  - production-safe model/test candidates;
  - requires-plan candidates that need architecture mapping first;
  - reject/do-not-cherry-pick probe UI state.
- `docs/roadmap/agentic-loop/state.md`
- `docs/roadmap/agentic-loop/attention-ledger.md`, if the next action changes
- this pass file, marked complete only after the candidate list exists

## Candidate Scope

Evaluate candidates around:

- transient performance override model and tests;
- audio buffer/reference vocabulary and tests;
- return-send or mixer reducer semantics;
- source-slot capture/history identity and generator recipe preservation;
- observability model/tests only if they are clearly developer tooling and not
  musician-facing control UI.

## Stop Conditions

- Candidate evidence requires inspecting unavailable probe worktrees or logs and
  cannot be inferred from committed summaries.
- A candidate would require user product judgment before it can be classified.
