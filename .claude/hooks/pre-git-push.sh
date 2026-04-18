#!/usr/bin/env bash
# PreToolUse hook for Bash. Reads the tool-use JSON on stdin; if the command
# is a real `git push` (not a substring occurrence, not --dry-run, not --help),
# runs the full test suite and blocks the push on failure. Non-push commands
# pass through unmodified.
set -euo pipefail

INPUT="$(cat)"

# Parse the command via python3. Emits three lines:
# FIRST   — first token (after stripping leading whitespace + comments)
# SECOND  — second token
# REST    — the remainder of the command as a single string
# Compatible with macOS default bash 3.2 (no mapfile).
# Input JSON passed via env var to avoid stdin/heredoc conflict.
PARSED="$(CLAUDE_HOOK_INPUT="$INPUT" /usr/bin/python3 <<'PY'
import json, os, shlex
try:
    d = json.loads(os.environ.get("CLAUDE_HOOK_INPUT", "") or "{}")
except Exception:
    print(""); print(""); print("")
    raise SystemExit(0)
cmd = d.get("tool_input", {}).get("command", "")
# Drop inline comments (anything after an unquoted '#').
stripped = []
in_single = in_double = False
for ch in cmd:
    if ch == "'" and not in_double:
        in_single = not in_single
    elif ch == '"' and not in_single:
        in_double = not in_double
    elif ch == "#" and not (in_single or in_double):
        break
    stripped.append(ch)
cmd = "".join(stripped).strip()
try:
    tokens = shlex.split(cmd)
except Exception:
    tokens = cmd.split()
first = tokens[0] if len(tokens) > 0 else ""
second = tokens[1] if len(tokens) > 1 else ""
rest = " ".join(tokens[2:]) if len(tokens) > 2 else ""
print(first)
print(second)
print(rest)
PY
)"

FIRST="$(printf '%s\n' "$PARSED" | sed -n '1p')"
SECOND="$(printf '%s\n' "$PARSED" | sed -n '2p')"
REST="$(printf '%s\n' "$PARSED" | sed -n '3p')"

# Gate only `git push …`.
if [ "$FIRST" != "git" ] || [ "$SECOND" != "push" ]; then
  exit 0
fi

# Allow harmless variants through.
case " $REST " in
  *" --dry-run "* | *" --help "* | *" -h "*)
    echo "ℹ️  pre-git-push hook: bypassing test run for \`git push $REST\` (harmless flag)" >&2
    exit 0
    ;;
esac

REPO="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$REPO"

# Dirty-tree check first (cheap, common-case block).
if [ -n "$(git status --porcelain)" ]; then
  echo "❌ pre-git-push hook: working tree is dirty — commit or stash first" >&2
  git status --short >&2
  exit 1
fi

echo "🔒 pre-git-push hook: verifying tests before push" >&2
TMPLOG="$(mktemp -t pre-git-push-test-XXXXXX.log)"
trap 'rm -f "$TMPLOG"' EXIT
if ! DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
    xcodebuild -project SequencerAI.xcodeproj -scheme SequencerAI \
    -destination 'platform=macOS' test >"$TMPLOG" 2>&1; then
  echo "❌ pre-git-push hook: xcodebuild test FAILED — push blocked. Last 40 lines of output:" >&2
  tail -40 "$TMPLOG" >&2
  echo "Full log: $TMPLOG (not auto-cleaned)" >&2
  trap - EXIT   # keep the log around for inspection
  exit 1
fi

echo "✅ pre-git-push hook: tests green, tree clean, pushing" >&2
exit 0
