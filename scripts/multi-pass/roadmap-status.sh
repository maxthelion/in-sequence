#!/usr/bin/env bash
set -euo pipefail

echo "# Roadmap Status"
echo
if [ -f docs/roadmap/next-actions.md ]; then
  sed -n '1,180p' docs/roadmap/next-actions.md
else
  echo "docs/roadmap/next-actions.md missing"
fi
echo
echo "## Feature README Files"
find docs/roadmap -mindepth 2 -maxdepth 2 -name README.md -print | sort
