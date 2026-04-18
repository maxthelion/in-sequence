#!/usr/bin/env bash
# PreToolUse hook for Bash. Reads the tool-use JSON on stdin; if the command
# is a `git push`, runs the full test suite and blocks the push on failure.
# Non-push commands pass through unmodified.
set -euo pipefail

INPUT="$(cat)"
CMD="$(printf '%s' "$INPUT" | /usr/bin/python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("tool_input",{}).get("command",""))')"

# Only gate pushes.
case "$CMD" in
  *"git push"*) ;;
  *) exit 0 ;;
esac

REPO="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$REPO"

echo "🔒 pre-git-push hook: verifying tests before push" >&2
if ! DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
    xcodebuild -project SequencerAI.xcodeproj -scheme SequencerAI \
    -destination 'platform=macOS' test 2>&1 | tail -5 >&2; then
  echo "❌ pre-git-push hook: xcodebuild test FAILED — push blocked" >&2
  exit 1
fi

# Also refuse to push with a dirty working tree.
if [ -n "$(git status --porcelain)" ]; then
  echo "❌ pre-git-push hook: working tree is dirty — commit or stash first" >&2
  exit 1
fi

echo "✅ pre-git-push hook: tests green, tree clean, pushing" >&2
exit 0
