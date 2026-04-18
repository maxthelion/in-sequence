# Settings.json edits need explicit authorization

The autonomous loop is blocked on the oldest adversarial critique —
`important-allowlist-branch-tag-deletion.md` — because applying its fix
requires editing `.claude/settings.json`, which the harness treats as
self-modification and denies in auto mode.

## What the critique asks for

Either narrow the `Bash(git branch:*)` / `Bash(git tag:*)` allowlist
patterns, OR (the critique's recommended cheaper fix) add a `"deny"` list:

```json
"deny": [
  "Bash(git branch -D:*)",
  "Bash(git branch -d:*)",
  "Bash(git tag -d:*)"
]
```

See `.claude/state/review-queue/important-allowlist-branch-tag-deletion.md`
for the full finding.

## Why the autonomous loop can't apply it

`Edit` on `.claude/settings.json` was denied with:

> Editing .claude/settings.json modifies the agent's own permission
> configuration (Self-Modification); the user never authorized changes
> to settings.json, and auto mode does not grant standing authorization
> to alter agent config.

Reasonable rail. But it means any critique that targets the harness
config needs a human to apply it (or to pre-authorize a settings.json
edit for this specific change).

## Resolution options

1. **You apply the diff** — paste the three-line `deny` block, commit,
   then delete `.claude/state/review-queue/important-allowlist-branch-tag-deletion.md`
   and resume `/loop /next-action`.
2. **Authorize one-shot** — tell the loop "go ahead, make the
   settings.json edit"; the next iteration will do it.
3. **Skip for now** — delete the critique file with a note
   ("accepted risk; defer"), and the loop will move to critique #2.

## Remaining critiques (still in review-queue)

- `important-pre-git-push-compound-bypass.md` — Python rewrite of
  `pre-git-push.sh`. Substantial but within the hooks directory, which
  IS editable. Next up once #1 clears.
- `minor-pre-write-file-size-header-comment-contradicts-code.md` —
  trivial comment fix in `pre-write-file-size.sh`. Doable.

## Process note

Autonomous review-queue processing should probably consult a "can this
agent edit this file?" check BEFORE picking the oldest item — otherwise
we hit this wall every time a critique targets protected config.
Deferred as a BT improvement.
