#!/usr/bin/env bash
# PreToolUse hook for Write. Reads the tool-use JSON on stdin; if the target
# path is under Sources/ and the proposed content would exceed the hard cap,
# blocks the write. Soft cap just warns.
#
# See wiki/pages/code-review-checklist.md §2 "No god files":
#   ~200 lines OK, ~500 lines smell, ~1000 lines split.
set -euo pipefail

SOFT_CAP=500
HARD_CAP=1000

INPUT="$(cat)"

read -r PATH_ CONTENT < <(printf '%s' "$INPUT" | /usr/bin/python3 -c 'import json,sys
d = json.load(sys.stdin)
ti = d.get("tool_input", {})
# The file_path/content layout matches the Write tool. If absent, pass.
p = ti.get("file_path", "")
c = ti.get("content", "")
# Print path + NUL-safe content; but shell read can not handle newlines.
# So: write to two temp files and print their paths.
import tempfile, os
fd1, path_f = tempfile.mkstemp(prefix="claude-hook-path-")
fd2, content_f = tempfile.mkstemp(prefix="claude-hook-content-")
os.write(fd1, p.encode()); os.close(fd1)
os.write(fd2, c.encode()); os.close(fd2)
print(path_f, content_f)')

TARGET="$(cat "$PATH_")"
rm -f "$PATH_"

# Only inspect writes under Sources/.
case "$TARGET" in
  */Sources/*) ;;
  *) rm -f "$CONTENT"; exit 0 ;;
esac

LINES=$(wc -l < "$CONTENT" | tr -d ' ')
rm -f "$CONTENT"

if [ "$LINES" -gt "$HARD_CAP" ]; then
  echo "❌ pre-write-file-size hook: $TARGET would be $LINES lines (> hard cap $HARD_CAP). Split before committing. See wiki/pages/code-review-checklist.md §2." >&2
  exit 1
fi

if [ "$LINES" -gt "$SOFT_CAP" ]; then
  echo "⚠️  pre-write-file-size hook: $TARGET would be $LINES lines (> soft cap $SOFT_CAP). Consider splitting. See wiki/pages/code-review-checklist.md §2." >&2
fi

exit 0
