#!/usr/bin/env bash
set -euo pipefail

echo "# Show Readiness"
echo
echo "## Current Project Orientation"
if [ -f .meta/multipass/state/ooda/orientation.md ]; then
  sed -n '1,160p' .meta/multipass/state/ooda/orientation.md
else
  echo "missing"
fi
echo
echo "## Current State"
for file in .meta/multipass/state/feature-readiness.md .meta/multipass/state/loop-lifecycle-status.md .meta/multipass/state/flow-status.md; do
  echo "### $file"
  if [ -f "$file" ]; then
    sed -n '1,120p' "$file"
  else
    echo "missing"
  fi
  echo
done
