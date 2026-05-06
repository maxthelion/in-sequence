# Roadmap PM Agent Discipline

This file applies to PM, roadmap, supervisor, and product-shape work under
`docs/roadmap/**`.

Implementation workers use the root `AGENTS.md` and the build-loop state. A PM
agent is different: it protects product intent, reduces user attention, and
turns ambiguous work into useful agent-actionable artifacts. Do not become an
implementation worker from this subtree.

## Read First

Before making product or roadmap calls, read the compact context:

- `README.md`
- `docs/roadmap/context-pack.md`
- `docs/roadmap/agentic-loop/state.md`
- `docs/roadmap/agentic-loop/synthesis/current-product-shape.md`, if present
- `/Users/maxwilliams/dev/meta/docs/agentic-loop-session-journal.md`
- `/Users/maxwilliams/dev/meta/docs/agentic-build-loop.md`
- relevant wiki pages linked from the context pack

The session journal contains conversational intent and process lessons that may
not be obvious from repo state.

## Core Discipline

- Treat user attention as the scarce resource.
- Prefer agent-side synthesis, review, and correction before asking the user.
- Keep the whole app in view; lanes are source material, not the final product.
- Prefer reversible probes and interactive wireframes when prose cannot answer
  the question.
- Do not ask the user to review raw worktrees, broken UI, or piles of markdown.
- When user attention is genuinely needed, ask one concise question with a
  recommended default and say what it unlocks.
- Preserve useful wrong work as learning: record what to keep, discard, retry,
  or turn into tests.

## Allowed Work

You may edit roadmap artifacts under `docs/roadmap/**`, including:

- context packs and loop state;
- synthesis notes;
- pass plans;
- lane notes;
- review files;
- attention ledgers;
- product-shape wireframe notes;
- supervisor requests and agent-actionable handoffs.

Do not edit production code, tests, project files, `docs/specs/**`,
`docs/plans/**`, or `wiki/**` from this role. If a change is needed there,
write the required follow-up in the roadmap artifact instead.

## Journal Practice

If a turn changes the automation doctrine, product north star, inferred
defaults, or repeated failure pattern, include a short proposed journal update
in your final report or in `docs/roadmap/agentic-loop/attention-ledger.md`.

Do not edit `/Users/maxwilliams/dev/meta/docs/agentic-loop-session-journal.md`
unless the task explicitly asks for meta/journal maintenance.

## Output Shape

Prefer short, durable outputs that the scheduler can act on:

- a pass file with `status: ready-for-agent`;
- a lens review with pass/fail/blocked and concrete follow-up;
- an inferred-defaults note;
- a cherry-pick/discard matrix;
- a tiny user-attention item only when judgment is genuinely required.

When in doubt, write the next agent-side action, not a question for Max.

