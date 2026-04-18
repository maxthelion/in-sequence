#!/usr/bin/env bash
# PreToolUse hook for Write + Edit. Reads the tool-use JSON on stdin; if the
# target path is under Sources/ or Tests/ and the resulting file would exceed
# the hard cap, blocks the operation. Soft cap just warns.
#
# For Write: uses the proposed `content` directly.
# For Edit:  reads the current file, applies the old_string→new_string
#            replacement (honouring `replace_all`), and counts lines of the
#            simulated result. If the file is unreadable (e.g. target does
#            not exist yet) the hook fails open.
#
# See wiki/pages/code-review-checklist.md §2 "No god files":
#   ~200 lines OK, ~500 lines smell, ~1000 lines split.
#
# Fail-open policy: malformed JSON, missing fields, non-targeted paths all
# exit 0 so this hook never blocks unrelated writes. Only a line count over
# HARD_CAP on a Sources/ or Tests/ target blocks.
set -euo pipefail

SOFT_CAP=500
HARD_CAP=1000

INPUT="$(cat)"

# Input JSON passed via env var to avoid stdin/heredoc conflict (same pattern
# as pre-git-push.sh). Python computes the answer and prints one line:
#   SKIP                — fail-open: don't block
#   <lines>\t<path>     — lines to compare against caps, path for message
RESULT="$(CLAUDE_HOOK_INPUT="$INPUT" /usr/bin/python3 <<'PY'
import json, os, sys

try:
    d = json.loads(os.environ.get("CLAUDE_HOOK_INPUT", "") or "{}")
except Exception:
    # Malformed JSON: fail open — do not block unrelated writes.
    print("SKIP")
    raise SystemExit(0)

ti = d.get("tool_input", {})
tool_name = d.get("tool_name", "")
path = ti.get("file_path", "")

# Only gate writes/edits under Sources/ or Tests/.
if not path or ("/Sources/" not in path and "/Tests/" not in path):
    print("SKIP")
    raise SystemExit(0)

# Figure out the resulting content.
# Write: `content` is the full new body.
# Edit:  `old_string` / `new_string` — simulate the replacement against the
#        current file contents if readable; else fall back to the current
#        file's line count (which catches already-too-large files).
if tool_name == "Edit" or "old_string" in ti or "new_string" in ti:
    old = ti.get("old_string", "")
    new = ti.get("new_string", "")
    try:
        with open(path, "r", encoding="utf-8") as fh:
            body = fh.read()
    except Exception:
        # File not readable (e.g. new file via Edit — unusual). Skip.
        print("SKIP")
        raise SystemExit(0)
    # Best-effort simulation: replace first occurrence (Edit semantics).
    # If replace_all is true, replace all. If old isn't found, just use body.
    if old and old in body:
        if ti.get("replace_all"):
            body = body.replace(old, new)
        else:
            body = body.replace(old, new, 1)
    lines = len(body.splitlines())
else:
    content = ti.get("content", "")
    lines = len(content.splitlines())

print(f"{lines}\t{path}")
PY
)"

case "$RESULT" in
  SKIP|"") exit 0 ;;
esac

LINES="${RESULT%%$'\t'*}"
TARGET="${RESULT#*$'\t'}"

# Defensive: if LINES isn't a number, fail open.
case "$LINES" in
  ''|*[!0-9]*) exit 0 ;;
esac

if [ "$LINES" -gt "$HARD_CAP" ]; then
  echo "❌ pre-write-file-size hook: $TARGET would be $LINES lines (> hard cap $HARD_CAP). Split before committing. See wiki/pages/code-review-checklist.md §2." >&2
  exit 1
fi

if [ "$LINES" -gt "$SOFT_CAP" ]; then
  echo "⚠️  pre-write-file-size hook: $TARGET would be $LINES lines (> soft cap $SOFT_CAP). Consider splitting. See wiki/pages/code-review-checklist.md §2." >&2
fi

exit 0
