---
name: execute-plan
description: Run one full plan cycle autonomously — implementer subagent, three-stage review (spec + quality + adversarial), fix loop, /simplify, wiki update, tag. Use after a plan has been written and committed under docs/plans/. Pair with `/loop /execute-plan` for continuous plan-queue execution.
---

# Execute Plan

## What it does

Automates a complete plan cycle end-to-end. Replaces the manual dance of "dispatch implementer, wait, dispatch reviewer, decide, dispatch fix, …"

## Preconditions

1. The target plan file exists at `docs/plans/*.md` and has not yet been marked `Status: ✅ Completed`.
2. The parent spec is committed.
3. Working tree is clean (`git status` shows no modifications).
4. A previous plan's completion tag (`v0.0.N-…`) exists as the base ref. First plan uses initial commit as base.

## Steps when invoked

Ordered; each step gates the next.

### 1. Resolve the plan

- If invoked with an argument, use that path.
- Otherwise pick the oldest `docs/plans/*.md` without `Status: ✅ Completed` in its header.
- Abort if none found — write the next plan via `superpowers:writing-plans` first.

### 2. Dispatch the implementer

Dispatch the local `implementer` agent:

```
Agent tool:
  subagent_type: "implementer"
  prompt: <plan task brief — use the structure from
          superpowers:subagent-driven-development/implementer-prompt.md,
          with placeholders filled in for this plan's task>
```

The `.Codex/agents/implementer.md` system prompt enforces sequencer-ai's
scope rules (Sources/ + Tests/ only; no hooks/agents/skills/wiki/specs/plans)
and the Sonnet 4.5+ model requirement. The superpowers template stays in
scope only as the *dispatch brief* shape — see the agent file's "Built on"
section.

**If the agent isn't registered** (see § "Agent registration" in `AGENTS.md`),
fall back to `subagent_type: "general-purpose"` with `model: "sonnet"` and
paste the body of `.Codex/agents/implementer.md` as the system-prompt
preamble of your task prompt.

### 3. Wait for implementer

- `DONE` → proceed to reviews
- `DONE_WITH_CONCERNS` → note concerns, proceed to reviews (they'll surface if real)
- `BLOCKED` → surface to the user, abort cycle
- `NEEDS_CONTEXT` → surface to user, abort cycle (don't guess)

### 4. Dispatch three reviewers in parallel

Fire the following subagents in a single message (parallel, independent):

a. **spec-compliance reviewer** — `subagent_type: "spec-reviewer"`. The agent builds on `superpowers:subagent-driven-development/spec-reviewer-prompt.md` and layers sequencer-ai specifics (plan checkbox convention, parent-spec chain).
b. **code-quality reviewer** — `subagent_type: "code-quality-reviewer"`. Built on `superpowers:code-reviewer`; adds the `wiki/pages/code-review-checklist.md` §1-4 hooks.
c. **adversarial reviewer** — `/adversarial-review` skill against `<previous-tag>..HEAD`. The skill dispatches the local `adversarial-reviewer` agent (opus model) with the scaffold from `.Codex/skills/adversarial-review/reviewer-prompt.md`.

**If any of the local agents isn't registered** (see § "Agent registration" in `AGENTS.md`), fall back to `subagent_type: "general-purpose"` with the appropriate model (`sonnet` for spec/quality reviewers, `opus` for adversarial) and paste the corresponding `.Codex/agents/<role>.md` body as the system-prompt preamble.

### 5. Collect findings, run fix loop

- Combine all three reports.
- If any 🔴 Critical findings → dispatch a fix subagent with the list; re-run reviewers; loop until no Criticals.
- 🟡 Important findings → dispatch fix subagent unless the fix would violate the plan (in which case document as a TODO-with-linked-issue and include in the post-cycle summary).
- 🔵 Minor findings → list in the commit summary; file away for checklist evolution.

### 6. Run `/simplify`

Via the Skill tool. It reviews changed code for reuse / quality / efficiency and commits fixes if it finds any. Re-run tests after (should still be green).

### 7. Update the wiki

Dispatch the `wiki-maintainer` agent:

```
Agent tool:
  subagent_type: "wiki-maintainer"
  prompt:
    - Diff: <previous-tag>..HEAD
    - Plan file: <path>
    - Task: update wiki/pages/* to describe what shipped.
    - Commit under `docs(wiki):` prefix.
```

The agent's scope is `wiki/pages/` only — it cannot touch Sources/, Tests/,
docs/, AGENTS.md, AGENTS.md, or .Codex/. New pages only if the plan
explicitly asked for one (see `wiki/pages/category-taxonomy.md` for the
taxonomy).

Skip anything that's time-stamped (plan details, spec iteration) — those belong in `docs/`, not the wiki. The wiki captures evergreen truths only.

**If the agent isn't registered**, fall back to `subagent_type: "general-purpose"` with `model: "sonnet"` and paste the body of `.Codex/agents/wiki-maintainer.md` as the system-prompt preamble.

### 8. Tick the plan's checkboxes and add the Status line

- Replace `- [ ]` with `- [x]` across the plan file (all steps the implementer actually completed — it's okay to mass-tick if the run succeeded).
- Add the `Status: ✅ Completed 2026-MM-DD. Tag vX.Y.Z-<slug>. …` line after `Parent spec`.
- Commit: `docs(plan): mark N-<slug> completed`.

### 9. Tag and summarize

- `git tag -a v0.0.N-<slug> -m "<plan name> complete: <commit count> commits, tests green, reviews passed"`
- Write a one-paragraph summary message to the user: what was built, what was reviewed, what's tagged, what's next.
- If there are unresolved Important findings, list them with file:line refs.

### 10. If no blockers, continue to next plan

- If the caller is `/loop`, return cleanly and let the outer loop drive the next iteration.
- Otherwise surface completion to the user and stop.

## Failure modes

- **Implementer blocks** — don't move to reviews; surface to user.
- **Review loop can't converge** — if a fix subagent fails to address findings after 3 attempts, stop and surface to user.
- **Tests regress during /simplify** — revert the simplify commit, surface, stop.
- **Wiki-update subagent can't produce clean diff** — skip wiki update, note in summary, continue.

## Out of scope

- Writing new plans — that's `superpowers:writing-plans` or `/next-plan`.
- Executing across the full plan queue — that's `/loop /execute-plan`.
- Merging to `main` from a branch — that's `superpowers:finishing-a-development-branch`.

## Telemetry / status

The `SessionStart` hook prints the current plan and review state. After each cycle, the status should show the new tag and the next plan on deck.
