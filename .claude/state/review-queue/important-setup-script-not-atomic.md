# 🟡 Important — `setup-next-action.sh` writes `next-action.md` non-atomically; concurrent invocations race and can leave a truncated file

**File:** `.claude/hooks/setup-next-action.sh:23-39` (the `emit` function)

## What's wrong

```bash
emit() {
  {
    echo "# Next Action"
    …
  } > "$OUT"                   # direct redirection, not atomic rename
}
```

`> "$OUT"` truncates `next-action.md` immediately, then the block writes incrementally. If two invocations interleave — e.g. one from `SessionStart` and one from an explicit `/next-action` — the second's `>` truncates the first's in-progress output; a reader between the two sees a partial file.

Scenarios:

- SessionStart hook runs as the user launches a session; a `/next-action` skill invocation simultaneously runs `setup-next-action.sh` to refresh state.
- `/loop /next-action` re-evaluates at the start of every iteration; if the previous action subagent also fires the script from inside (e.g. to recheck state after a commit), timing can overlap.
- Multiple Claude Code sessions in different tabs (not currently prevented) each running SessionStart.

Additionally, the docstring explicitly advertises concurrency: _"It's run either by a SessionStart hook, the /setup slash command, or a /loop wrapper before every iteration."_ — three invocation points, no mutual exclusion.

## What would be right

Use atomic rename, which is the standard Unix idiom:

```bash
emit() {
  local tmp="$OUT.tmp.$$"
  {
    echo "# Next Action"
    …
  } > "$tmp"
  mv "$tmp" "$OUT"
}
```

`mv` within the same filesystem is atomic on POSIX. A reader of `$OUT` either sees the pre-emit version or the post-emit version, never a partial.

Alternatively, use `flock` to guarantee mutual exclusion between invocations:

```bash
exec 200>"$STATE/.setup.lock"
flock -n 200 || exit 0   # or wait, depending on desired semantics
```

## Why it matters

The `/next-action` skill reads `next-action.md` and dispatches the named action. If the file is mid-rewrite, the skill can grep a partial `## Action:` line and either dispatch nothing (silent stop) or dispatch the wrong action. Hard to reproduce deterministically, which is the worst kind of bug to own — it'll appear during long autonomous runs and be misattributed to the agent.
