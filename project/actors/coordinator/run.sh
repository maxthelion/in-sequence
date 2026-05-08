#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git -C "$(dirname "$0")/../../.." rev-parse --show-toplevel)"
cd "$ROOT"

source "$ROOT/project/lib/inbox.sh"
source "$ROOT/project/lib/codex.sh"

MODE="write"
TIMEOUT_SECONDS="${PROJECT_COORDINATOR_TIMEOUT_SECONDS:-1500}"
for arg in "$@"; do
  case "$arg" in
    --dry-run) MODE="dry-run" ;;
    --write) MODE="write" ;;
    *)
      echo "Unknown argument: $arg" >&2
      exit 2
      ;;
  esac
done

RUNTIME="$ROOT/.meta/project/actors/coordinator"
PROMPT_FILE="$RUNTIME/last-prompt.md"
RESULT_FILE="$RUNTIME/last-result.md"
INBOX="$ROOT/docs/multi-pass-coordinator/inbox/coordinator"
mkdir -p "$RUNTIME" "$INBOX"

INBOX_REFS="$(find "$INBOX" -maxdepth 1 -type f -name '*.md' ! -name 'README.md' | sort | sed "s#^$ROOT/##" || true)"

cat > "$PROMPT_FILE" <<EOF
$(cat "$ROOT/project/actors/coordinator/prompt.md")

## Invocation Context

- Project root: \`$ROOT\`
- Coordinator inbox: \`docs/multi-pass-coordinator/inbox/coordinator\`
- Runtime dir: \`${RUNTIME#$ROOT/}\`
- Current time: $(project_tick_now_iso)

## Coordinator Inbox References

${INBOX_REFS:-"(empty)"}

## References To Read

- \`README.md\`
- \`docs/multi-pass-coordinator/settings.yaml\`
- \`docs/multi-pass-coordinator/current-plan.md\`
- \`docs/multi-pass-coordinator/show-readiness.md\`
- \`docs/multi-pass-coordinator/evidence-log.md\`
- \`docs/roadmap/agentic-loop/state.md\`
- recent actor summaries under \`.meta/project/actors/\`

Do one bounded coordinator tick, then stop.
EOF

if [ "$MODE" = "dry-run" ]; then
  cat > "$RUNTIME/last-summary.md" <<EOF
# Coordinator Run

- status: dry-run
- prompt: ${PROMPT_FILE#$ROOT/}
- result: ${RESULT_FILE#$ROOT/}
EOF
  cat "$RUNTIME/last-summary.md"
  exit 0
fi

set +e
project_tick_run_codex "coordinator" "$PROMPT_FILE" "$RESULT_FILE" "$ROOT" "$TIMEOUT_SECONDS" "$RUNTIME"
STATUS=$?
set -e

if [ "$STATUS" -eq 124 ]; then
  project_tick_write_note "$ROOT/project/actors/process-fixer/inbox" "coordinator-timeout" "Coordinator Timeout" "The coordinator exceeded its timeout. Inspect runtime files under \`${RUNTIME#$ROOT/}\` and simplify or repair the project-local loop."
fi

exit "$STATUS"
