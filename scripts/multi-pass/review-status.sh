#!/usr/bin/env bash
set -euo pipefail

echo "# Review Status"
echo
echo "## Agentic Loop Reviews"
find docs/roadmap/agentic-loop/reviews -type f -name '*.md' -print 2>/dev/null | sort | while read -r file; do
  status="$(sed -n '1,12p' "$file" | tr '\n' ' ' | sed 's/  */ /g')"
  echo "- $file :: $status"
done
echo
echo "## Feature Reviews"
find docs/roadmap -mindepth 2 -maxdepth 3 \( -name 'ux-review.md' -o -name 'architecture-review.md' -o -name '*review*.md' \) -print 2>/dev/null | sort
