# Important: settings.json deny list has trivial bypasses

**File:** `.claude/settings.json`, lines 56–60 (`deny` block)
**Severity:** Important

## What's wrong

Allowlist has `Bash(git branch:*)` / `Bash(git tag:*)`. Denies only:

```json
"deny": [
  "Bash(git branch -D:*)",
  "Bash(git branch -d:*)",
  "Bash(git tag -d:*)"
]
```

All of these bypass silently:

- `git branch --delete feature/xyz` — long form of `-d`.
- `git branch --delete --force feature/xyz` — long form of `-D`.
- `git branch -Df feature/xyz` — combined flags; `-Df` is not the `-D` prefix the matcher expects.
- `git branch -dr feature/xyz` — combined; `-dr` isn't `-d`.
- `git tag --delete v0.0.1-scaffold` — long form.
- `git update-ref -d refs/heads/feature` — plumbing; deletes a branch.
- `git push origin :feature` — remote-branch deletion (not in this deny list, but authored by the same person who added the list and shares its intent).
- `git worktree remove --force …` — removes worktree + branch.

## What would be right

Two choices:

1. **Deny by broader pattern** — replace the three literal patterns with:

   ```json
   "deny": [
     "Bash(git branch -D*)",
     "Bash(git branch -d*)",
     "Bash(git branch --delete*)",
     "Bash(git tag -d*)",
     "Bash(git tag --delete*)",
     "Bash(git update-ref -d*)",
     "Bash(git push * :*)"
   ]
   ```

   Note the trailing `*` (no colon) to catch combined flags like `-Df`.

2. **Narrow the allowlist** — remove `Bash(git branch:*)` / `Bash(git tag:*)` and allow only specific safe subcommands (`git branch --list`, `git tag --list`, `git branch --show-current`, etc.).

Option 2 is the "right" fix per the spirit of the original critique (explicit allowlist); option 1 is the smaller follow-up.

## Acceptance

- `git branch --delete xyz` → prompts.
- `git branch -Df xyz` → prompts.
- `git tag --delete v1` → prompts.
- `git update-ref -d refs/heads/xyz` → prompts.
- `git branch --list` and `git branch --show-current` still don't prompt.
