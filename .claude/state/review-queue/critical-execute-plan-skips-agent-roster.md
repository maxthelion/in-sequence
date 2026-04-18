# Critical: `/execute-plan` skill doesn't use the new agent roster

**File:** `.claude/skills/execute-plan/SKILL.md`, steps 2, 4a, 4b, 7
**Severity:** Critical

## What's wrong

The new agent roster (`.claude/agents/*.md`) exists but `/execute-plan` — the primary plan-execution skill — still dispatches to the old generic targets:

- **Step 2 (implement)** says "Use `superpowers:subagent-driven-development`'s implementer-prompt template." Bypasses `.claude/agents/implementer.md` entirely; sequencer-ai's scope rules (Sources/Tests only, no hooks/agents/skills, sonnet model requirement) are not enforced.
- **Step 4a (spec review)** calls out `superpowers:subagent-driven-development/spec-reviewer-prompt.md` — generic template, not the local `spec-reviewer` agent that adds plan-checkbox/parent-spec-chain specifics.
- **Step 4b (code quality)** dispatches `superpowers:code-reviewer` — a different agent, not the local `code-quality-reviewer` that cites `code-review-checklist.md` sections.
- **Step 7 (wiki update)** says "Dispatch a wiki-update subagent" — generic phrasing, no reference to `wiki-maintainer.md` with its EDIT-only-wiki/pages/ scope.

The agent roster is a dead letter for the most-invoked skill.

## Why this is critical

- The whole point of declaring per-agent model overrides (opus for adversarial, haiku for explorer, sonnet for implementer) is lost if the most-common caller bypasses them.
- Implementer scope rules are toothless — execute-plan will happily dispatch an implementer that edits `wiki/` / `AGENTS.md` / hooks.
- Wiki maintenance doesn't get the path-scope guard.

## What would be right

Update `.claude/skills/execute-plan/SKILL.md`:

- Step 2: `Agent tool, subagent_type: "implementer", prompt: <plan-task brief>`. If the implementer sub-agent isn't registered yet (discoverability question — see note below), fall back to `general-purpose` + `model: "sonnet"` and paste the system prompt from `.claude/agents/implementer.md` inline.
- Step 4a: `subagent_type: "spec-reviewer"`.
- Step 4b: `subagent_type: "code-quality-reviewer"`.
- Step 7: `subagent_type: "wiki-maintainer"`.

## Note on discoverability

The Agent tool's `subagent_type` enum is populated at session start. Agent files created mid-session aren't visible until the next session. Document this in `AGENTS.md` § Per-action subagent configuration so callers don't silently fall back to generic dispatch without noticing.

## Acceptance

- `/execute-plan` calls name the specific agents in each step.
- A dry-run grep for `subagent_type` in `skills/execute-plan/SKILL.md` shows every role agent used.
- `AGENTS.md` notes the session-start registration caveat.
