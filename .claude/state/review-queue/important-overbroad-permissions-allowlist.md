# 🟡 Important — permission allowlist includes `Bash(rm:*)` and `Bash(git reset HEAD:*)`, both of which authorize destructive operations without a prompt

**File:** `.claude/settings.json:4-45`

## What's wrong

Two entries in `permissions.allow` are far broader than the comment in `wiki/pages/automation-setup.md` implies:

### 1. `Bash(rm:*)` (line 14)

The allowlist pattern `rm:*` matches any command starting with `rm `. That includes:

- `rm -rf ~/Library/Application\ Support/sequencer-ai` — wipes the user's entire library of templates / voice presets / fill presets (see `app-support-layout.md`)
- `rm -rf /` — anything prefixed with `rm`
- `rm -rf .git` — destroys the repository
- `rm -rf $(...)` — arbitrary command substitution first

No prompt fires for any of these. The agent can trigger them without confirmation by design of the matcher, even though the auto-mode reminder says "anything that deletes data or modifies shared or production systems still needs explicit user confirmation."

### 2. `Bash(git reset HEAD:*)` (line 42)

The matcher `git reset HEAD:*` matches `git reset HEAD<anything>`. Including:

- `git reset HEAD~5 --hard` — erases 5 commits of work, working tree wiped
- `git reset HEAD~20 --hard` — erases 20 commits
- `git reset HEAD --hard` — discards uncommitted work

All without prompting. The doc at `automation-setup.md:101` claims _"Destructive git operations (`push`, `reset --hard`, `rebase`, `tag -d`, etc.) are **not** allowlisted — they still prompt"_, which is **materially false** for `reset --hard` given this matcher.

### 3. Secondary risks in the same list

- `Bash(mv:*)` — `mv Sources/ /tmp/trash` silently rearranges the tree.
- `Bash(chmod:*)` — `chmod -R 000 ~/` effectively denial-of-services the user's home dir.
- `Bash(git stash:*)` — `git stash drop` / `git stash clear` quietly erases stashes.
- `Bash(git restore:*)` — `git restore --source=HEAD~100 .` silently rolls the tree back.

The pattern across these is overly broad prefix matchers where what was probably intended was a narrow flag whitelist.

## What would be right

Replace the broad patterns with **narrow, flag-restricted** ones, and let anything else prompt:

```json
"Bash(rm -- *)",
"Bash(rm *.swift)",
"Bash(rm /tmp/*)",
// ...or drop rm entirely; make the agent argue for each deletion.
```

For `git reset`:

```json
"Bash(git reset --)",                // no-args: unstage everything staged
"Bash(git reset HEAD --)",
"Bash(git reset HEAD <file>)",       // unstage a specific file
// do NOT allow: git reset --hard, git reset HEAD~N in any form
```

If a specific destructive operation is legitimately frequent (`rm -f /tmp/seqai-build` for the clean-build workflow), allowlist that exact command, not the verb.

## Why it matters

`automation-setup.md:101` explicitly promises these destructive operations "still prompt." That's the foundational claim of the permission model — that routine commands don't interrupt, while anything destructive always does. The current config breaks that contract silently. In an autonomous `/loop /execute-plan` run, a bug in the implementer prompt could lead to `rm -rf` of the repo or the user's library, with no safety prompt. This is the single highest-blast-radius item in the diff.
