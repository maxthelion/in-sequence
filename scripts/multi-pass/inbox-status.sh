#!/usr/bin/env bash
set -euo pipefail

echo "# Inbox Status"
echo
for dir in \
  docs/multi-pass-coordinator/inbox/coordinator \
  docs/multi-pass-coordinator/inbox/pm \
  docs/multi-pass-coordinator/inbox/build-loop \
  docs/multi-pass-coordinator/inbox/visual-review \
  docs/multi-pass-coordinator/inbox/ux-ia \
  docs/multi-pass-coordinator/inbox/architecture \
  docs/multi-pass-coordinator/inbox/testing
do
  echo "## $dir"
  if [ -d "$dir" ]; then
    find "$dir" -maxdepth 1 -type f ! -name '.gitkeep' ! -name 'README.md' -print | sort
  else
    echo "missing"
  fi
  echo
done
