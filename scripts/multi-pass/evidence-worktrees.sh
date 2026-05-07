#!/usr/bin/env bash
set -euo pipefail

echo "# Evidence: Worktrees"
echo
echo "- command_id: evidence-worktrees"
echo "- timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "- repo: $(pwd)"
echo "- branch: $(git branch --show-current 2>/dev/null || echo unknown)"
echo "- commit: $(git rev-parse HEAD 2>/dev/null || echo unknown)"
echo

git worktree list --porcelain | awk '
  /^worktree / { if (path) print ""; path=$2; print "## " path }
  /^HEAD / { print "- commit: " $2 }
  /^branch / { sub(/^refs\/heads\//, "", $2); print "- branch: " $2 }
  /^detached$/ { print "- branch: detached" }
'

echo
echo "## Worktree Dirty Summaries"
git worktree list --porcelain | awk '/^worktree / {print $2}' | while read -r wt; do
  [ -d "$wt/.git" ] || [ -f "$wt/.git" ] || continue
  echo "### $wt"
  echo "- branch: $(git -C "$wt" branch --show-current 2>/dev/null || echo unknown)"
  echo "- commit: $(git -C "$wt" rev-parse HEAD 2>/dev/null || echo unknown)"
  echo "- dirty_count: $(git -C "$wt" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
  git -C "$wt" status --short 2>/dev/null | sed -n '1,40p' || true
  echo
done
