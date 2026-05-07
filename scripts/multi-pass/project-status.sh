#!/usr/bin/env bash
set -euo pipefail

echo "# Project Status"
echo
echo "## Git"
git status --short || true
echo
echo "## Branch"
git branch --show-current || true
echo
echo "## Recent Commits"
git log --oneline -12 || true
echo
echo "## Worktrees"
git worktree list || true
echo
echo "## Roadmap Worktrees"
find .worktrees -maxdepth 2 -type d -name '.claude' -print 2>/dev/null | sed 's#/\\.claude$##' | sort || true
