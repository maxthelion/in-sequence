#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git -C "$(dirname "$0")/../../.." rev-parse --show-toplevel)"
cd "$ROOT"

MODE="write"
for arg in "$@"; do
  case "$arg" in
    --dry-run) MODE="dry-run" ;;
    --write) MODE="write" ;;
  esac
done

if [ "$MODE" = "dry-run" ]; then
  echo "# PM Behaviour Tree"
  echo
  echo "- status: dry-run"
  echo "- command: scripts/codex/bt-iteration.sh"
  exit 0
fi

exec "$ROOT/scripts/codex/bt-iteration.sh"
