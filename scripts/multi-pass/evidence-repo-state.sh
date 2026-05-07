#!/usr/bin/env bash
set -euo pipefail

echo "# Evidence: Repo State"
echo
echo "- command_id: evidence-repo-state"
echo "- timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "- repo: $(pwd)"
echo "- branch: $(git branch --show-current 2>/dev/null || echo unknown)"
echo "- commit: $(git rev-parse HEAD 2>/dev/null || echo unknown)"
echo "- dirty_count: $(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
echo
echo "## Dirty Summary"
git status --short || true
echo
echo "## Recent Commits"
git log --oneline -8 || true
