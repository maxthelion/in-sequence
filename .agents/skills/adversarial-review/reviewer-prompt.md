# Adversarial Reviewer Dispatch Scaffold

The canonical definition of the adversarial reviewer — mindset, hunt checklist, report format, project-specific priorities — lives in the **`adversarial-reviewer`** subagent at `.claude/agents/adversarial-reviewer.md`. This file is just the per-invocation context scaffold that the `/adversarial-review` skill fills in and passes as the user prompt.

## Dispatch scaffold

```
Review the diff described below against the `adversarial-reviewer` agent's hunt checklist. Follow its report format verbatim.

## Context

- Base ref:     [BASE_REF]
- HEAD:         [HEAD_SHA]
- Active plan:  [PLAN_PATH]
- Parent spec:  [SPEC_PATH]

## Diff

```diff
[git diff BASE_REF..HEAD]
```

## Commit log

```
[git log BASE_REF..HEAD --oneline]
```
```

## Why two files

The agent carries everything **evergreen** (checklist, mindset, reporting shape, project rules). This scaffold carries only **per-invocation** values (which refs, which diff). Evergreen content changes rarely; scaffold gets filled in every review. Splitting them prevents the two-source-drift that duplicating the checklist would cause.
