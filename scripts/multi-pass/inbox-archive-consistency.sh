#!/usr/bin/env bash
set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$repo_root"

echo "# Inbox Archive Consistency"
echo
echo "- command_id: inbox-archive-consistency"
echo "- timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "- repo: $(pwd)"
echo "- branch: $(git branch --show-current 2>/dev/null || echo unknown)"
echo "- commit: $(git rev-parse HEAD 2>/dev/null || echo unknown)"
echo

echo "## Canonical Inbox"
echo "- path: .meta/multipass/runtime/inbox"
for state in pending claimed blocked done; do
  count="$(find ".meta/multipass/runtime/inbox/$state" -maxdepth 1 -type f -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
  echo "- $state: $count"
done
