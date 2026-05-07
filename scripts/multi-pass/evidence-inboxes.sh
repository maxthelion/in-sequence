#!/usr/bin/env bash
set -euo pipefail

echo "# Evidence: Actor Inboxes"
echo
echo "- command_id: evidence-inboxes"
echo "- timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "- repo: $(pwd)"
echo "- branch: $(git branch --show-current 2>/dev/null || echo unknown)"
echo "- commit: $(git rev-parse HEAD 2>/dev/null || echo unknown)"
echo

find docs/multi-pass-coordinator/inbox -mindepth 1 -maxdepth 1 -type d | sort | while read -r dir; do
  echo "## $dir"
  echo "### Pending"
  find "$dir" -maxdepth 1 -type f -name '*.md' ! -name 'README.md' -print | sort | while read -r file; do
    echo "- $file"
    sed -n '1,20p' "$file" | sed 's/^/  /'
  done
  echo "### Recent Archive"
  if [ -d "$dir/archive" ]; then
    find "$dir/archive" -maxdepth 1 -type f -name '*.md' -print0 \
      | xargs -0 ls -t 2>/dev/null \
      | sed -n '1,5p' \
      | while read -r file; do
          echo "- $file"
          sed -n '1,12p' "$file" | sed 's/^/  /'
        done
  else
    echo "- none"
  fi
  echo
done
