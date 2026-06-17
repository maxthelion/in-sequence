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

find \
  .meta/multipass/runtime/runs/actors/architecture-review \
  .meta/multipass/runtime/runs/actors/testing-review \
  .meta/multipass/runtime/runs/actors/ux-ia-review \
  .meta/multipass/runtime/runs/actors/visual-economy-review \
  .meta/multipass/runtime/loops \
  -type f \( -name '*.final.md' -o -name '*review*.md' -o -name '*evidence*.md' \) 2>/dev/null \
  | sort \
  | while read -r file; do
      echo "## $file"
      echo "- mtime: $(date -u -r "$file" +"%Y-%m-%dT%H:%M:%SZ")"
      echo "- last_git_commit: $(git log -1 --format=%H -- "$file" 2>/dev/null || echo untracked)"
      sed -n '1,24p' "$file"
      echo
    done
