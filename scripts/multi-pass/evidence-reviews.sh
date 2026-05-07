#!/usr/bin/env bash
set -euo pipefail

echo "# Evidence: Reviews"
echo
echo "- command_id: evidence-reviews"
echo "- timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "- repo: $(pwd)"
echo "- branch: $(git branch --show-current 2>/dev/null || echo unknown)"
echo "- commit: $(git rev-parse HEAD 2>/dev/null || echo unknown)"
echo

find docs/roadmap/agentic-loop/reviews docs/multi-pass-coordinator/inbox -type f -name '*.md' 2>/dev/null \
  | sort \
  | while read -r file; do
      echo "## $file"
      echo "- mtime: $(date -u -r "$file" +"%Y-%m-%dT%H:%M:%SZ")"
      echo "- last_git_commit: $(git log -1 --format=%H -- "$file" 2>/dev/null || echo untracked)"
      sed -n '1,24p' "$file"
      echo
    done
