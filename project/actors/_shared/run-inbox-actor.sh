#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git -C "$(dirname "$0")/../../.." rev-parse --show-toplevel)"
cd "$ROOT"

source "$ROOT/project/lib/inbox.sh"
source "$ROOT/project/lib/codex.sh"

ACTOR_ID="${PROJECT_ACTOR_ID:?PROJECT_ACTOR_ID is required}"
ACTOR_LABEL="${PROJECT_ACTOR_LABEL:-$ACTOR_ID}"
ACTOR_INBOX="${PROJECT_ACTOR_INBOX:?PROJECT_ACTOR_INBOX is required}"
ACTOR_PROMPT="${PROJECT_ACTOR_PROMPT:-}"
ACTOR_ACTIONS="${PROJECT_ACTOR_ACTIONS:-}"
MODE="write"
TIMEOUT_SECONDS="${PROJECT_ACTOR_TIMEOUT_SECONDS:-1500}"

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

INBOX_ABS="$ROOT/$ACTOR_INBOX"
REQUEST="$(project_tick_first_runnable_request "$INBOX_ABS" || true)"
RUNTIME="$ROOT/.meta/project/actors/$ACTOR_ID"
mkdir -p "$RUNTIME"

if [ -z "$REQUEST" ]; then
  cat > "$RUNTIME/last-summary.md" <<EOF
# Actor Run

- actor: $ACTOR_ID
- status: idle
- reason: no runnable request
EOF
  echo "# $ACTOR_LABEL"
  echo
  echo "- status: idle"
  exit 0
fi

RUN_ID="$(project_tick_safe_name "$(basename "$REQUEST" .md)")"
PROMPT_FILE="$RUNTIME/$RUN_ID.prompt.md"
RESULT_FILE="$RUNTIME/$RUN_ID.final.md"
SHARED_PROMPT="$ROOT/project/actors/_shared/loop-actor-prompt.md"

cat > "$PROMPT_FILE" <<EOF
$(cat "$SHARED_PROMPT")

## Invocation Context

- Project root: \`$ROOT\`
- Actor id: \`$ACTOR_ID\`
- Actor label: $ACTOR_LABEL
- Actor inbox: \`$ACTOR_INBOX\`
- Request file: \`$REQUEST\`
- Actor prompt: ${ACTOR_PROMPT:-none}
- Actor actions: ${ACTOR_ACTIONS:-none}
- Final message target: \`$RESULT_FILE\`
- Current time: $(project_tick_now_iso)

Handle exactly this request, then stop.
EOF

if [ "$MODE" = "dry-run" ]; then
  cat > "$RUNTIME/last-summary.md" <<EOF
# Actor Run

- actor: $ACTOR_ID
- status: dry-run
- request: ${REQUEST#$ROOT/}
- prompt: ${PROMPT_FILE#$ROOT/}
- result: ${RESULT_FILE#$ROOT/}
EOF
  cat "$RUNTIME/last-summary.md"
  exit 0
fi

set +e
project_tick_run_codex "$ACTOR_ID" "$PROMPT_FILE" "$RESULT_FILE" "$ROOT" "$TIMEOUT_SECONDS" "$RUNTIME"
STATUS=$?
set -e

if [ "$STATUS" -eq 0 ]; then
  ARCHIVED="$(project_tick_archive_request "$REQUEST")"
  echo "- archived: ${ARCHIVED#$ROOT/}" >> "$RUNTIME/last-summary.md"
  if [ "$ACTOR_ID" != "coordinator" ]; then
    NOTE="$(project_tick_write_note "$ROOT/docs/multi-pass-coordinator/inbox/coordinator" "$ACTOR_ID-completed" "$ACTOR_LABEL Completed" "Actor \`$ACTOR_ID\` completed request \`${REQUEST#$ROOT/}\`.\n\n- archived request: \`${ARCHIVED#$ROOT/}\`\n- result: \`${RESULT_FILE#$ROOT/}\`\n\nCoordinator/decider should inspect the result and decide whether current-work status, holistic status, review coverage, rework, or product-owner attention needs to change.")"
    echo "- coordinator note: ${NOTE#$ROOT/}" >> "$RUNTIME/last-summary.md"
  fi
  exit 0
fi

REASON="actor exited with status $STATUS"
if [ "$STATUS" -eq 124 ]; then
  REASON="actor exceeded ${TIMEOUT_SECONDS}s timeout"
fi
project_tick_mark_blocked "$REQUEST" "$REASON"
NOTE="$(project_tick_write_note "$ROOT/docs/multi-pass-coordinator/inbox/coordinator" "$ACTOR_ID-actor-blocked" "$ACTOR_LABEL Actor Blocked" "Request \`${REQUEST#$ROOT/}\` did not complete: $REASON. Decide whether to retry, split, narrow, or route to process-fixer.")"
echo "- blocked request: ${REQUEST#$ROOT/}" >> "$RUNTIME/last-summary.md"
echo "- coordinator note: ${NOTE#$ROOT/}" >> "$RUNTIME/last-summary.md"
exit "$STATUS"
