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

for state in pending claimed blocked done; do
  dir=".meta/multipass/runtime/inbox/$state"
  echo "## $dir"
  count="$(find "$dir" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
  echo "- count: $count"
  find "$dir" -maxdepth 1 -type f -name '*.md' -print0 2>/dev/null \
    | xargs -0 ls -t 2>/dev/null \
    | sed -n '1,8p' \
    | while read -r file; do
        echo "- $file"
        sed -n '1,18p' "$file" | sed 's/^/  /'
      done
  echo
done
