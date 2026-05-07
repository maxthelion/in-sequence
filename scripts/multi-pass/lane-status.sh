#!/usr/bin/env bash
set -euo pipefail

echo "# Lane Status"
echo
if [ -d docs/roadmap/lanes ]; then
  for file in docs/roadmap/lanes/*.md; do
    [ -f "$file" ] || continue
    echo "## $file"
    sed -n '1,80p' "$file"
    echo
  done
else
  echo "No docs/roadmap/lanes directory"
fi
