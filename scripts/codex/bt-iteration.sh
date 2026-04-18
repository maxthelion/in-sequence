#!/usr/bin/env bash
set -euo pipefail

REPO="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$REPO"

STATE_DIR="$REPO/.claude/state"
NEXT_ACTION_FILE="$STATE_DIR/next-action.md"

"$REPO/.claude/hooks/setup-next-action.sh" >/dev/null

ACTION_NAME="$(sed -n 's/^## Action: //p' "$NEXT_ACTION_FILE" | head -1)"

if [ -z "$ACTION_NAME" ]; then
  echo "Unable to determine the next action from $NEXT_ACTION_FILE" >&2
  exit 1
fi

cat <<EOF
Codex behaviour-tree iteration
repo: $REPO
action: $ACTION_NAME
next-action-file: $NEXT_ACTION_FILE

Iteration contract:
- Execute exactly one behaviour-tree action in this worktree.
- Treat .claude/state/ as the durable BT memory.
- Read only the files named by next-action.md, plus the minimal code or docs needed to carry out that action safely.
- If you are blocked or need a human decision, write a markdown note to .claude/state/inbox/ and stop.
- When the action is complete, rerun .claude/hooks/setup-next-action.sh before exiting so the next wake-up sees fresh state.

Current next-action.md:
EOF

cat "$NEXT_ACTION_FILE"
