#!/usr/bin/env bash
set -euo pipefail

echo "# Evidence: Promoted Work"
echo
echo "- command_id: evidence-promoted-work"
echo "- timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "- repo: $(pwd)"
echo "- branch: $(git branch --show-current 2>/dev/null || echo unknown)"
echo "- commit: $(git rev-parse HEAD 2>/dev/null || echo unknown)"
echo

echo "## Agentic Loop State"
if [ -f docs/roadmap/agentic-loop/state.md ]; then
  sed -n '1,120p' docs/roadmap/agentic-loop/state.md
else
  echo "missing"
fi
echo

echo "## Recent Build Promotions"
if [ -d docs/multi-pass-coordinator/inbox/build-loop/archive ]; then
  find docs/multi-pass-coordinator/inbox/build-loop/archive -maxdepth 1 -type f -name '*.md' -print0 \
    | xargs -0 ls -t 2>/dev/null \
    | sed -n '1,8p' \
    | while read -r file; do
        echo "### $file"
        sed -n '1,80p' "$file"
        echo
      done
else
  echo "none"
fi

echo "## Implementation Worktrees"
for wt in .worktrees/p0-track-performance-overlay .worktrees/*; do
  [ -d "$wt" ] || continue
  echo "### $wt"
  echo "- branch: $(git -C "$wt" branch --show-current 2>/dev/null || echo unknown)"
  echo "- commit: $(git -C "$wt" rev-parse HEAD 2>/dev/null || echo unknown)"
  echo "- dirty_count: $(git -C "$wt" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  git -C "$wt" log --oneline -3 2>/dev/null || true
  echo
done
