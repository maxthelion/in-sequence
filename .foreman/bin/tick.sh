#!/usr/bin/env bash
set -euo pipefail

# Foreman tick via headless CLI (API-billed `claude -p`). Only one of the
# trigger mechanisms — see README. If you are on a subscription, prefer the
# /loop or scheduled-session triggers described there; this script exists so
# the mechanism survives without any particular harness.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FOREMAN_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${FOREMAN_DIR}/.." && pwd)"

FOREMAN_MODEL="${FOREMAN_MODEL:-fable}"
FOREMAN_AUTONOMY="${FOREMAN_AUTONOMY:-full}"

precheck_output="$("$SCRIPT_DIR/precheck.sh" "${1:-}")" || {
  status=$?
  echo "foreman: $precheck_output"
  exit $((status == 2 ? 0 : 0))
}

cd "$REPO_ROOT"
FOREMAN_AUTONOMY="$FOREMAN_AUTONOMY" claude -p \
  --model "$FOREMAN_MODEL" \
  --dangerously-skip-permissions \
  "$(cat "$FOREMAN_DIR/PROMPT.md")

This is a scheduled foreman tick at $(date '+%Y-%m-%d %H:%M').
Pre-check result:
$precheck_output

Begin with the read-first list."
