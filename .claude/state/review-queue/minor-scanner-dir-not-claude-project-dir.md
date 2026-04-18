# Minor: pre-git-push repo resolution uses SCANNER_DIR not $CLAUDE_PROJECT_DIR

**File:** `.claude/hooks/pre-git-push.sh`, line 30
**Severity:** Minor

## What's wrong

```bash
REPO="$(git -C "$SCANNER_DIR" rev-parse --show-toplevel)"
```

`SCANNER_DIR` is the directory containing the hook script. If the hook is symlinked from a sibling project (e.g. someone shares the hook), `git rev-parse --show-toplevel` from SCANNER_DIR returns the original repo, not the repo the hook is being invoked against.

Claude Code provides `$CLAUDE_PROJECT_DIR` pointing at the current project. Using it first is more correct.

## What would be right

```bash
REPO="${CLAUDE_PROJECT_DIR:-$(git -C "$SCANNER_DIR" rev-parse --show-toplevel)}"
cd "$REPO"
```

Fall back to SCANNER_DIR-based resolution only when the env var isn't set.

## Acceptance

- Hook symlinked across projects still gates the right repo's tests.
- Hook installed directly in the repo keeps working (env-var present or absent).
