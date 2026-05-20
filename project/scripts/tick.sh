#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git -C "$(dirname "$0")/../.." rev-parse --show-toplevel)"
RUNTIME="${MULTIPASS_COORDINATOR:-/Users/maxwilliams/dev/multi-pass-coordinator}"

exec bun "$RUNTIME/src/cli/tick.ts" --project "$ROOT" "$@"
