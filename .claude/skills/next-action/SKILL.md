---
name: next-action
description: Read .claude/state/next-action.md and dispatch the action it specifies. Pair with /loop for autonomous overnight execution. The tree evaluation is done by the cheap deterministic setup-next-action.sh script; this skill only executes what the script chose.
---

# Next Action

## The split

Behaviour-tree evaluation and action execution are separated so only the expensive part uses an LLM:

1. **`./hooks/setup-next-action.sh`** — pure bash. Reads repo state + `.claude/state/` files. Evaluates the selector tree. Writes `.claude/state/next-action.md` naming the single action to take next. Instant.

2. **This skill (`/next-action`)** — LLM. Reads `.claude/state/next-action.md`. Dispatches the named action via a subagent. Updates state. Exits.

Under `/loop`, the pattern is:

```
loop iteration:
  → setup-next-action.sh writes state/next-action.md
  → /next-action reads it, dispatches, updates state, exits
next iteration:
  → setup-next-action.sh re-evaluates (state changed), writes state/next-action.md
  → …
```

This matches the shoe-makers pattern (`bun run setup` before every elf invocation) adapted to Claude Code's hook + skill surface.

Inspiration: <https://github.com/maxthelion/shoe-makers>

## How to invoke

- `/next-action` — manual single iteration. Runs setup first (in case state is stale), then dispatches.
- `/loop /next-action` — continuous autonomous execution. The loop wrapper handles scheduling / cache-hot intervals.

## What this skill does

1. Run `.claude/hooks/setup-next-action.sh` to refresh `state/next-action.md` against current state.
2. Read `.claude/state/next-action.md`. The first `## Action: <name>` line names the action.
3. Look up the action in the table below. Dispatch the corresponding subagent with the relevant context from `next-action.md`.
4. When the subagent returns, apply its state updates (commit, delete consumed files, update `last-*-sha` markers, etc.).
5. Exit. The next iteration will re-evaluate.

## Action table

| Action name | Agent / dispatch | State updates after success |
|---|---|---|
| `verify-tests` | `general-purpose` subagent (narrow test-runner brief — no dedicated agent needed for a mechanical command). Runs `xcodebuild test` and captures output. On pass: write HEAD SHA to `state/last-tests-sha`. On fail: write output to `state/last-tests-failure.md`. | last-tests-sha or last-tests-failure.md |
| `fix-tests` | `implementer` agent briefed with `state/last-tests-failure.md`. Scope: make tests green without changing contracts. | Delete last-tests-failure.md; update last-tests-sha. Commit. |
| `fix-critique` | `implementer` agent briefed with the oldest file in `state/review-queue/`. Scope: address the critique exactly, no scope creep. | Delete the critique file. Commit. |
| `continue-partial-work` | `implementer` agent briefed with `state/partial-work.md`. Picks up where the previous agent left off. | Delete partial-work.md on completion. Commit. |
| `adversarial-review` | Invoke the `/adversarial-review` skill against the diff specified in next-action.md — the skill dispatches the `adversarial-reviewer` agent. Collect findings. Write each as a file in `state/review-queue/` (`severity-slug.md`). | Update `state/last-review-sha` to current HEAD. |
| `handle-inbox` | `general-purpose` subagent briefed with the oldest file in `state/inbox/`. Act on the message (redirect, candidate, plan edit, direct task). If the message requires user action, the skill exits and leaves the file in place. | Move the file to `state/inbox/archive/` only if fully resolved. |
| `execute-work-item` | `implementer` agent via `superpowers:subagent-driven-development` briefed with `state/work-item.md`. The three-stage review (`spec-reviewer` → `code-quality-reviewer` → `adversarial-reviewer`) runs after DONE. | Delete work-item.md on DONE. Commit. |
| `prioritise` | `prioritiser` agent. Reads `state/candidates.md` + the code-review checklist. Picks one, writes a detailed `state/work-item.md`. Marks the candidate as chosen. | Write work-item.md. Update candidates.md. No code commit (state file changes may be committed separately). |
| `promote-plan-task-to-work-item` | Mechanical transformation. Read the named plan file, extract the next-unticked task's full section, write it as `state/work-item.md`. No subagent needed (pure state movement). | Write work-item.md. |
| `write-next-plan` | `implementer` agent invoking `superpowers:writing-plans` for the next unfinished sub-spec. | Writes `docs/plans/YYYY-MM-DD-<slug>.md`. Commit. |
| `explore` | `explorer` agent. Runs `octowiki-invariants` (if present), `octoclean` (if installed in sibling dir), scans for TODOs / test-coverage gaps / wiki-code drift. Writes findings ranked into `state/candidates.md`. | Write candidates.md. |

> **Wiki updates** are not in this table — they happen at plan completion via `execute-plan` step 7, which dispatches the `wiki-maintainer` agent. The BT doesn't route to wiki as a top-level action.

## Context-narrowing principle

From the shoe-makers pattern: each phase should hand off a **well-scoped brief** to the next, not a "go figure it out" prompt.

- **Explore** (broad context) — reads everything; writes `candidates.md`
- **Prioritise** (medium context) — reads candidates + the relevant code/wiki; writes a detailed `work-item.md`
- **Execute** (narrow context) — reads only `work-item.md`; does exactly what it says

If execute is ever reading broadly to figure out what to do, prioritise didn't write a good enough brief. If prioritise is improvising, explore didn't surface strong candidates. The handoffs are the system's QA.

## Model selection for dispatched subagents

Model is declared per-agent in `.claude/agents/*.md` frontmatter. Quick reference:

- `implementer` → **sonnet** (required; never Haiku or older Sonnet for code-writing)
- `adversarial-reviewer` → **opus** (last line of defence before ship)
- `spec-reviewer`, `code-quality-reviewer`, `wiki-maintainer`, `prioritiser` → **sonnet**
- `explorer` → **haiku** (cheap bulk scan)

Full table and rationale in `AGENTS.md` § "Per-action subagent configuration". Feedback memory `feedback_implementation_model.md` has the underlying rule.

## Safety rails

- **One action per invocation.** The skill does not chain actions. The next iteration will pick the next.
- **No human interaction in the loop.** If a subagent returns BLOCKED or NEEDS_CONTEXT, write the report as a file in `state/inbox/` and exit. The next iteration's setup will see the inbox message and route to `handle-inbox`, which will also exit (since handling a user request usually needs the user). Autonomous run stops cleanly.
- **Auto-revert on regression.** If a commit causes tests to fail on the next `verify-tests` action, the next iteration's `fix-tests` action should try to fix; if after one iteration it can't, revert the offending commit and write the situation to inbox. (Implementation deferred — first automation of this when we see the pattern in practice.)
- **Daily branch discipline.** If running autonomously, the caller (the `/loop` driver or a cron trigger) should operate on an auto branch (`auto/YYYY-MM-DD`). Nothing reaches main without human review. This skill doesn't create branches; it assumes the caller has set the working branch.

## Not yet implemented

The action table lists the actions the tree can emit. The implementer side is built incrementally:

- **Built:** `/adversarial-review` (plus the hooks and `execute-plan` as a fallback).
- **Next (when we hit it in practice):** `verify-tests`, `fix-tests`, `execute-work-item`, `fix-critique`, `handle-inbox`.
- **Later:** `prioritise`, `promote-plan-task-to-work-item`, `write-next-plan`, `explore`.

Until a given action is implemented, the skill dispatches a general-purpose subagent with the action's brief text as prompt and falls back to reporting what it would do. This is acceptable bootstrapping — the tree is correct from day one; the leaves are filled in as needed.

## Related

- `.claude/hooks/setup-next-action.sh` — the evaluator (bash; pure function of state)
- `/adversarial-review` — invoked by the `adversarial-review` action
- `/execute-plan` — still useful as a manual batch driver when you want to force one plan through
- [[automation-setup]] — the wiki overview
- Shoe-makers repo: <https://github.com/maxthelion/shoe-makers>
- Blog: <https://blog.maxthelion.me/blog/behaviour-trees/>
