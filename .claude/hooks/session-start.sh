#!/usr/bin/env bash
# SessionStart hook. Emits a status banner the session can use for orientation.
set -euo pipefail

REPO="$(git -C "$(dirname "$0")" rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$REPO"

# Current plan: newest file in docs/plans/ that isn't marked completed at the
# very top, or the latest plan file if all complete.
CURRENT_PLAN="(no plans yet)"
if [ -d docs/plans ]; then
  for f in $(ls -1 docs/plans/*.md 2>/dev/null | sort); do
    if ! grep -q "Status:.*Completed" "$f" 2>/dev/null; then
      CURRENT_PLAN="$(basename "$f")"
      break
    fi
  done
  if [ "$CURRENT_PLAN" = "(no plans yet)" ]; then
    last="$(ls -1 docs/plans/*.md 2>/dev/null | sort | tail -1 || true)"
    [ -n "$last" ] && CURRENT_PLAN="$(basename "$last") [all complete]"
  fi
fi

# Last tag + commits since.
LAST_TAG="$(git describe --tags --abbrev=0 2>/dev/null || echo 'no tags')"
if [ "$LAST_TAG" != "no tags" ]; then
  AHEAD="$(git rev-list --count "$LAST_TAG"..HEAD 2>/dev/null || echo '?')"
else
  AHEAD="$(git rev-list --count HEAD 2>/dev/null || echo '?')"
fi

# Dirty tree?
DIRTY=""
[ -n "$(git status --porcelain 2>/dev/null)" ] && DIRTY=" (dirty)"

# Behaviour-tree state summary.
STATE="$REPO/.claude/state"
INBOX=$(find "$STATE/inbox" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
CRITIQUES=$(find "$STATE/review-queue" -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')
PARTIAL="no"; [ -f "$STATE/partial-work.md" ] && PARTIAL="yes"
WORK_ITEM="no"; [ -f "$STATE/work-item.md" ] && WORK_ITEM="yes"
CANDIDATES="no"; [ -f "$STATE/candidates.md" ] && CANDIDATES="yes"
NEXT_ACTION="(none)"
[ -f "$STATE/next-action.md" ] && NEXT_ACTION="$(grep -m1 '^## Action:' "$STATE/next-action.md" 2>/dev/null | sed 's/^## Action: //' || echo 'unknown')"

cat <<EOF
┌─ sequencer-ai status
│ plan:     $CURRENT_PLAN
│ last tag: $LAST_TAG   +$AHEAD commits$DIRTY
│ BT state: next-action=$NEXT_ACTION · inbox=$INBOX · critiques=$CRITIQUES · partial=$PARTIAL · work-item=$WORK_ITEM · candidates=$CANDIDATES
│ drive:    /next-action (auto) · /execute-plan (explicit) · /adversarial-review (manual)
│ refresh:  run .claude/hooks/setup-next-action.sh to recompute next-action.md
└─
EOF
