#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git -C "$(dirname "$0")/../.." rev-parse --show-toplevel)"
ROSTER="${PROJECT_TICK_ROSTER:-$ROOT/project/scripts/loops.tsv}"

echo "# Actor Inventory"
echo
echo "Project: \`$ROOT\`"
echo "Roster: \`${ROSTER#$ROOT/}\`"
echo

while IFS=$'\t' read -r id kind inbox cadence command; do
  case "$id" in ''|\#*) continue ;; esac
  echo "## $id"
  echo
  echo "- kind: $kind"
  echo "- inbox: \`$inbox\`"
  echo "- cadence minutes: $cadence"
  echo "- command: \`$command\`"
  echo
done < "$ROSTER"
