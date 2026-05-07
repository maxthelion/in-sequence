#!/usr/bin/env bash
set -euo pipefail

echo "# Evidence: Tests And Builds"
echo
echo "- command_id: evidence-tests"
echo "- timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
echo "- repo: $(pwd)"
echo "- branch: $(git branch --show-current 2>/dev/null || echo unknown)"
echo "- commit: $(git rev-parse HEAD 2>/dev/null || echo unknown)"
echo

echo "## Evidence Log"
if [ -f docs/multi-pass-coordinator/evidence-log.md ]; then
  sed -n '1,180p' docs/multi-pass-coordinator/evidence-log.md
else
  echo "missing"
fi
echo

echo "## Recent Xcode Test Results"
find "$HOME/Library/Developer/Xcode/DerivedData" -path '*/Logs/Test/*.xcresult' -maxdepth 8 -type d 2>/dev/null \
  | xargs ls -td 2>/dev/null \
  | sed -n '1,8p' \
  | while read -r result; do
      echo "- $result"
    done
