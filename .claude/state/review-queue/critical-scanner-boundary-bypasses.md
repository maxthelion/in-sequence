# Critical: pre-git-push scanner has six real-push bypasses

**File:** `.claude/hooks/pre-git-push-scanner.py`, lines 81–127 (`space_operators` + `find_push`)
**Severity:** Critical

## What's wrong

Confirmed bypasses (scanner returns SKIP):

- `` `git push` `` (backtick command substitution)
- `bash <<EOF\ngit push\nEOF` (heredoc)
- `eval "git push"`
- `echo hi\ngit push` (newline statement separator)
- `command git push`
- `exec git push`

Root causes:
1. `space_operators` splits only on `;|&(){}` — `` ` `` and `\n` are NOT boundaries.
2. `eval`, `command`, `exec` aren't in the recursion-wrapper set (`{bash, sh, zsh}`) nor the prefix-skip set (alongside `sudo`).
3. `bash <<EOF` uses a heredoc; `space_operators` never sees the push because the heredoc body isn't within `bash`'s argument tokens.

## What would be right

1. In `space_operators`: treat `\n` and `` ` `` as boundaries (space-separate them at top level).
2. In `find_push`'s boundary loop: add `eval`, `command`, `exec` as prefix-skip tokens (consume them and keep `at_boundary = True`).
3. Heredoc handling is harder — likely fall back to a substring probe with boundary check for `(^|[\s;&|({`])git\s+push(\s|$|[;&|)}`])` when shlex fails or when the command contains `<<`. Accept some false positives here; the threat model is "don't let a real push slip silently."
4. Add every one of the 6 forms as a FIRE case in `test-pre-git-push-scanner.sh`.

## Acceptance

- `echo "git push" | bash` → FIRE
- `` `git push` `` → FIRE
- `eval "git push origin main"` → FIRE
- `command git push` → FIRE
- `exec git push` → FIRE
- `printf '%s\n' "echo hi" "git push" | bash` → FIRE
- Test harness extended with these cases, still 100% green.
