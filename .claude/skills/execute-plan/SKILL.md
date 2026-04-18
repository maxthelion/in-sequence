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

Use `superpowers:subagent-driven-development`'s implementer-prompt template.
Pass the plan file path, the environment note, and the parent spec.

### 3. Wait for implementer

- `DONE` → proceed to reviews
- `DONE_WITH_CONCERNS` → note concerns, proceed to reviews (they'll surface if real)
- `BLOCKED` → surface to the user, abort cycle
- `NEEDS_CONTEXT` → surface to user, abort cycle (don't guess)

### 4. Dispatch three reviewers in parallel

Fire the following subagents in a single message (parallel, independent):

a. **spec-compliance reviewer** — per `superpowers:subagent-driven-development/spec-reviewer-prompt.md`
b. **code-quality reviewer** — `superpowers:code-reviewer` with WHAT_WAS_IMPLEMENTED derived from the plan
c. **adversarial reviewer** — `/adversarial-review` against `<previous-tag>..HEAD`

### 5. Collect findings, run fix loop

- Combine all three reports.
- If any 🔴 Critical findings → dispatch a fix subagent with the list; re-run reviewers; loop until no Criticals.
- 🟡 Important findings → dispatch fix subagent unless the fix would violate the plan (in which case document as a TODO-with-linked-issue and include in the post-cycle summary).
- 🔵 Minor findings → list in the commit summary; file away for checklist evolution.

### 6. Run `/simplify`

Via the Skill tool. It reviews changed code for reuse / quality / efficiency and commits fixes if it finds any. Re-run tests after (should still be green).

### 7. Update the wiki

Dispatch a wiki-update subagent with:
- The committed diff (`<previous-tag>..HEAD`)
- The current set of wiki pages
- Instructions: update existing pages to match new reality, add new pages for net-new stable truths (see category-taxonomy.md), commit under `docs(wiki):` prefix.

Skip anything that's time-stamped (plan details, spec iteration) — those belong in `docs/`, not the wiki. The wiki captures evergreen truths only.

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
