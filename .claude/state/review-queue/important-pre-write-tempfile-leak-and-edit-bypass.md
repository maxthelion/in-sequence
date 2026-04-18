# 🟡 Important — `pre-write-file-size.sh` leaks tempfiles on error paths, doesn't gate the `Edit` tool, and misses god-files under `Tests/`

**File:** `.claude/hooks/pre-write-file-size.sh:15-49`

## What's wrong

Three separate weaknesses in one hook:

### 1. Tempfile leaks on any early exit between their creation and the explicit `rm -f`

The Python embedded in the heredoc creates two tempfiles and prints their paths. The shell cleans them up manually:

```bash
TARGET="$(cat "$PATH_")"
rm -f "$PATH_"                    # :31 — if this line or `cat` fails under set -e, $CONTENT leaks

case "$TARGET" in
  */Sources/*) ;;
  *) rm -f "$CONTENT"; exit 0 ;;  # :36 — non-Sources path correctly cleans up
esac

LINES=$(wc -l < "$CONTENT" | tr -d ' ')
rm -f "$CONTENT"                  # :40 — only reached if wc didn't fail
```

If `cat "$PATH_"` or `wc -l` fails (e.g. the python process partially wrote the tempfile, a race with `TMPDIR` cleanup), `set -euo pipefail` + `set -o pipefail` terminates with one or both tempfiles still on disk. Over a long agent run, `$TMPDIR` fills with `claude-hook-path-*` and `claude-hook-content-*`.

Also: **the python stage has its own leak window**. It creates tempfiles before `print`; if the process is killed between `os.close(fd2)` and `print(...)`, the shell never sees the paths and can never clean them up.

### 2. The hook matches `Write` only; `Edit` bypasses the cap

`.claude/settings.json` wires the hook only to `PreToolUse` on `Write`. Agents can inflate a file well past 1000 lines by repeated `Edit` calls, each adding a few lines. The hook enforces the checklist rule for fresh writes only — a substantial enforcement gap, because in practice god-files grow by editing, not by single-shot rewrite.

### 3. The Sources match misses `Tests/` god-files

```bash
case "$TARGET" in
  */Sources/*) ;;
  ...
```

Tests can easily exceed 1000 lines (a single integration test suite for the engine will). `code-review-checklist.md` §2 talks about "no god files" across the project, not only under `Sources/`. Test files under `Tests/SequencerAITests/` aren't gated.

### 4. `wc -l` undercounts by one when content has no trailing newline

`wc -l` counts newline characters, not lines. Content like `"line1\nline2"` (999 `\n`'s between 1000 lines of text, no trailing newline) reports 999. The hard-cap of 1000 then allows exactly 1001 "lines" (1000 `\n`'s = 1001 segments). Minor, but the cap is off-by-one.

## What would be right

- **Use a `trap '... rm -f "$PATH_" "$CONTENT"; ...' EXIT`** set immediately after the python stage so cleanup is unconditional.
- **Don't use tempfiles at all.** Have python print `LINE_COUNT\tPATH` in one line (newlines in content are irrelevant once you've counted them in python) — trivially safer:
  ```bash
  read -r LINES TARGET < <(python3 -c '...print(len(content.splitlines()), path, sep="\t")')
  ```
- **Add `Edit` to the matcher** (or a `PostToolUse` pass that re-checks the file size after any write).
- **Widen the path match** to `*/Sources/*|*/Tests/*` (or just gate any `*.swift` under the repo root).
- **Count lines correctly in python** with `len(content.splitlines())` — no `wc -l` off-by-one.

## Why it matters

The "no god files" rule is one of the three load-bearing invariants the checklist defends. A hook that enforces it only on fresh-writes, only under one directory, and occasionally leaves tempfiles behind is a false assurance — the team will think the cap is enforced, and hit a 1400-line `EngineTests.swift` six months later because nothing blocked the Edits that built it.
