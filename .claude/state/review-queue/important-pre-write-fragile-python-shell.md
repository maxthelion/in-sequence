# 🟡 Important — `pre-write-file-size.sh` has brittle python-in-bash plumbing and fails-closed on malformed JSON (but fails-open on missing fields)

**File:** `.claude/hooks/pre-write-file-size.sh:13-28`

## What's wrong

The python block prints `path_f content_f` on stdout, and the shell does `read -r PATH_ CONTENT < <(...)`. Mix of problems:

1. **Fails closed on malformed JSON.** If the Write tool ever sends non-JSON stdin (say, due to a future Claude Code tool-input format change, or a test harness feeding the hook raw text), `python3 -c 'json.load(...)'` raises and exits non-zero, `set -e` kills the script, hook exits 1, **Write is blocked**. Verified: `echo 'not json' | ./pre-write-file-size.sh` → traceback + exit 1.

2. **Fails open on missing fields.** If `tool_input` is present but lacks `file_path` or `content`, python writes empty tempfiles, shell reads empty paths, `case "$TARGET" in */Sources/*) ;;` doesn't match, tempfile is removed, exit 0 — the write proceeds. Verified: `echo '{"tool_input":{}}' | ./pre-write-file-size.sh` → exit 0. Inconsistency: one malformation blocks, the other allows.

3. **`read -r PATH_ CONTENT`** splits the stdin on `$IFS`. Because python names tempfiles `claude-hook-path-XXXX` / `claude-hook-content-XXXX` with no spaces, this is safe *today*. It's not safe if `TMPDIR` ever includes spaces (possible on macOS with users whose home directory has a space), because python's `tempfile.mkstemp` returns a path under `$TMPDIR`. Tested theory: a dev account with display name containing a space produced `/Users/...` (macOS mangles it), but a custom `TMPDIR=/tmp/with space/` absolutely breaks it.

4. **The variable name `PATH_`** is deliberately obscured to avoid shadowing `$PATH`, but the trailing-underscore convention is still fragile: a future author doing `PATH="$PATH_"` (dropping the underscore) will wipe their `$PATH` silently. Use a properly-named variable (`PATH_FILE` / `file_path_tmp`).

5. **Hard-coded `/usr/bin/python3`**. Works on current macOS but won't work inside a sandbox that has only a homebrew python. Using `python3` (let `PATH` find it) would be more portable — unless the concern was preventing a malicious `python3` in PATH, in which case the hook should say so.

## What would be right

Replace the whole tempfile dance with a single python-to-stdout pipe that computes the answer:

```bash
set -euo pipefail
SOFT_CAP=500
HARD_CAP=1000

RESULT="$(python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    # Malformed input: fail open — do not block unrelated writes.
    print("SKIP"); sys.exit(0)
ti = d.get("tool_input", {})
p, c = ti.get("file_path", ""), ti.get("content", "")
if "/Sources/" not in p and "/Tests/" not in p:
    print("SKIP"); sys.exit(0)
lines = len(c.splitlines())
print(f"{lines}\t{p}")
' <<< "$INPUT")"

case "$RESULT" in
  SKIP) exit 0 ;;
esac
LINES="${RESULT%%$'\t'*}"
TARGET="${RESULT#*$'\t'}"
# ... (soft / hard cap logic unchanged)
```

No tempfiles, consistent fail-open on both malformed-JSON and missing-field cases, line count computed in python (no `wc -l` off-by-one), path can contain spaces/tabs without breaking (use `\t` as delimiter, spaces OK).

## Why it matters

A hook that malforms its input handling has a non-trivial chance of either blocking legitimate writes (user frustration; push toward disabling the hook) or letting bad writes through silently (invariant violation). The current implementation does both, inconsistently. Also the code is harder to read than a 10-line equivalent — "does this hook block empty input?" should not require tracing tempfile lifecycles.
