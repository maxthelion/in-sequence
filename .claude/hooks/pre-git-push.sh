#!/usr/bin/env bash
# PreToolUse hook for Bash. Reads the tool-use JSON on stdin; if the command
# is a real git push (including compound commands, bash -c recursion, sudo,
# and env-var prefixes), runs the test suite and blocks on failure.
# The detection logic lives in pre-git-push-scanner.py next to this file.
set -euo pipefail

INPUT="$(cat)"
SCANNER_DIR="$(cd "$(dirname "$0")" && pwd)"
DECISION_LINE="$(printf '%s' "$INPUT" | /usr/bin/python3 "$SCANNER_DIR/pre-git-push-scanner.py")"

DECISION="${DECISION_LINE%% *}"
REST="${DECISION_LINE#* }"
# If DECISION_LINE is just "SKIP" (no trailing space), REST equals the whole
# line — normalise so downstream flag checks do not see a stray token.
[ "$DECISION" = "SKIP" ] && REST=""

if [ "$DECISION" != "FIRE" ]; then
  exit 0
fi

# Allow harmless variants through.
case " $REST " in
  *" --dry-run "* | *" --help "* | *" -h "*)
    echo "pre-git-push hook: bypassing test run for \`git push $REST\` (harmless flag)" >&2
    exit 0
    ;;
esac

REPO="${CLAUDE_PROJECT_DIR:-$(git -C "$SCANNER_DIR" rev-parse --show-toplevel)}"
cd "$REPO"

# Dirty-tree check first (cheap, common-case block).
if [ -n "$(git status --porcelain)" ]; then
  echo "pre-git-push hook: working tree is dirty — commit or stash first" >&2
  git status --short >&2
  exit 1
fi

echo "pre-git-push hook: verifying tests before push" >&2
TMPLOG="$(mktemp -t pre-git-push-test-XXXXXX.log)"
trap 'rm -f "$TMPLOG"' EXIT
# Honour an already-set DEVELOPER_DIR (Xcode-beta, CI, alternate install).
# Fall back to the standard Xcode location only if nothing is configured.
: "${DEVELOPER_DIR:=/Applications/Xcode.app/Contents/Developer}"
export DEVELOPER_DIR
if ! xcodebuild -project SequencerAI.xcodeproj -scheme SequencerAI \
    -destination 'platform=macOS' test >"$TMPLOG" 2>&1; then
  echo "pre-git-push hook: xcodebuild test FAILED — push blocked. Last 40 lines of output:" >&2
  tail -40 "$TMPLOG" >&2
  echo "Full log: $TMPLOG (not auto-cleaned)" >&2
  trap - EXIT   # keep the log around for inspection
  exit 1
fi

echo "pre-git-push hook: tests green, tree clean, pushing" >&2
exit 0
