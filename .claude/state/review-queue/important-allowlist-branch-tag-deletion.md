# Important: allowlist permits `git branch -D` / `git tag -d` without prompt

**File:** `.claude/settings.json`
**Severity:** Important

## What's wrong

The tightening pass kept these patterns:

```
"Bash(git branch:*)",
"Bash(git tag:*)",
```

Claude Code's permission matcher treats `:*` as "any subcommand args".
Consequences:

- `git branch -D feature/xyz` → branch deletion without prompt (destructive,
  can lose unmerged work).
- `git tag -d v0.0.1-scaffold` → tag deletion without prompt (you'd also
  need to `push --delete` to propagate, so less immediate, but a durable
  reference point gone locally).

The spirit of the tightening (no destructive without prompt) meant `push`,
`reset --hard`, `rebase`, `tag -d` should prompt. Two of those three are
covered (push not allowlisted, reset is narrowed to `HEAD`); `branch -D`
and `tag -d` still bypass.

## What would be right

Narrow to the read variants, same pattern as `git stash` was split:

```
"Bash(git branch)",           // bare → list
"Bash(git branch -l:*)",      // explicit list
"Bash(git branch --list:*)",
"Bash(git branch -v:*)",
"Bash(git branch --show-current)",
"Bash(git branch --contains:*)",
"Bash(git branch --merged:*)",
"Bash(git branch --no-merged:*)",
"Bash(git tag)",              // bare → list
"Bash(git tag -l:*)",
"Bash(git tag --list:*)",
"Bash(git tag --contains:*)",
```

Creation (`git tag vX.Y.Z`) and deletion (`git branch -D`, `git tag -d`)
then prompt. Creation is arguably okay to allow, but deletion shouldn't be
silent.

Alternative cheaper fix: leave `Bash(git branch:*)` / `Bash(git tag:*)` but
add an explicit deny list. Claude Code settings support `deny` alongside
`allow`:

```json
"deny": [
  "Bash(git branch -D:*)",
  "Bash(git branch -d:*)",
  "Bash(git tag -d:*)"
]
```

Deny takes precedence. Smaller diff, same effect.

## Acceptance

- `git branch -D xyz` prompts before running.
- `git tag -d v0.0.1-scaffold` prompts before running.
- `git branch` (list) and `git tag` (list) still don't prompt.
