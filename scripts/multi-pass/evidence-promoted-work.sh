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

echo "## Loop Lifecycle"
if [ -f .meta/multipass/state/loop-lifecycle-status.md ]; then
  sed -n '1,180p' .meta/multipass/state/loop-lifecycle-status.md
else
  echo "missing"
fi
echo

echo "## Build Loop Registry"
find .meta/multipass/config/loops/build -maxdepth 1 -type f -name '*.yaml' -print 2>/dev/null \
  | sort \
  | while read -r file; do
      echo "### $file"
      sed -n '1,44p' "$file"
      echo
    done

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
