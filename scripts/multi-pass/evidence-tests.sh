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

echo "## Recent Testing Review Evidence"
find .meta/multipass/runtime/runs/actors/testing-review .meta/multipass/runtime/loops -type f \
  \( -name '*.final.md' -o -name '*testing*.md' \) 2>/dev/null \
  | xargs ls -t 2>/dev/null \
  | sed -n '1,12p' \
  | while read -r file; do
      echo "### $file"
      sed -n '1,48p' "$file"
      echo
    done
echo

echo "## Recent Xcode Test Results"
find "$HOME/Library/Developer/Xcode/DerivedData" -path '*/Logs/Test/*.xcresult' -maxdepth 8 -type d 2>/dev/null \
  | xargs ls -td 2>/dev/null \
  | sed -n '1,8p' \
  | while read -r result; do
      echo "- $result"
    done
