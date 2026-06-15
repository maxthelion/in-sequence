#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git -C "$(dirname "$0")/../.." rev-parse --show-toplevel)"
RUNTIME="${FOREMAN_COORDINATOR:-/Users/maxwilliams/dev/foreman-coordinator}"

exec bun "$RUNTIME/src/cli/tick.ts" --project "$ROOT" "$@"
