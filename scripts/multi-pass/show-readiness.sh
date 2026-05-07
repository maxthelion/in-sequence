#!/usr/bin/env bash
set -euo pipefail

echo "# Show Readiness"
echo
echo "## Agentic Loop State"
if [ -f docs/roadmap/agentic-loop/state.md ]; then
  sed -n '1,120p' docs/roadmap/agentic-loop/state.md
else
  echo "missing"
fi
echo
echo "## Ready For User Signals"
find .worktrees -path '*/.claude/state/ready-for-user.md' -print 2>/dev/null | sort || true
echo
echo "## Product Owner Attention"
for file in docs/multi-pass-coordinator/product-owner-attention.md docs/roadmap/user-attention.md; do
  echo "### $file"
  if [ -f "$file" ]; then
    sed -n '1,120p' "$file"
  else
    echo "missing"
  fi
  echo
done
