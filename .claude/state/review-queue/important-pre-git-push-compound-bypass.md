# Important: pre-git-push hook misses compound commands

**File:** `.claude/hooks/pre-git-push.sh`
**Severity:** Important

## What's wrong

The rewritten hook parses the first two shell tokens via `shlex.split` and
gates only when `FIRST == "git"` and `SECOND == "push"`. This fixes the
previous round's false-positive (`echo "git push"` used to gate), but
introduces false negatives for any compound or wrapped invocation.

Confirmed bypasses (all exit 0 — hook does not fire):

```
echo done && git push origin main
echo safe; git push origin main
(git push origin main)
bash -c "git push origin main"
sudo git push origin main
GIT_DIR=/tmp/foo git push origin main
```

(I ran these against the hook on this machine to verify.)

The previous behaviour (`case "$CMD" in *"git push"*) ;;`) caught all of the
above at the cost of false positives. The threat model for this hook is
"don't let red tests get pushed" — missing a real push is a harder failure
than gating a harmless `echo "git push"` invocation.

## What would be right

Split the check into two passes:

1. **Cheap substring test** to determine "is `git push` plausibly in this
   command?" — if not, exit 0.
2. **Token walk** through the shlex output. For each statement boundary
   (`&&`, `||`, `;`, `|`, subshell parens), check if the next token sequence
   starts with `git` followed by `push` (skipping env-var assignments like
   `FOO=bar`, skipping `sudo`). If any statement is a real `git push`, gate.

Or simpler: parse via `shlex` into a flat token list, then look for any
`git` immediately followed by `push` where the preceding token is one of
`{"", "&&", "||", ";", "|", "(", "sudo"}` or matches `^[A-Z_]+=`.

The `--dry-run` / `--help` allow-through still applies in the found-push
statement's `REST`.

## Acceptance

- `echo done && git push origin main` → hook fires, gates on dirty tree /
  test failure.
- `bash -c "git push"` → hook fires.
- `echo "git push in a string"` → hook does NOT fire (still correct).
- `git push --dry-run` → hook allows through as harmless.
