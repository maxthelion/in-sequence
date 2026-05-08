#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git -C "$(dirname "$0")/../.." rev-parse --show-toplevel)"
cd "$ROOT"

ROSTER="${PROJECT_TICK_ROSTER:-$ROOT/project/scripts/loops.tsv}"
RUNTIME="$ROOT/.meta/project-tick"
SUMMARY="$RUNTIME/last-summary.md"
LOCK="$RUNTIME/tick.lock"
MAX_STARTS="${PROJECT_TICK_MAX_STARTS:-1}"
MODE="write"

source "$ROOT/project/lib/inbox.sh"

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

mkdir -p "$RUNTIME"

if ! mkdir "$LOCK" 2>/dev/null; then
  echo "# Project Tick"
  echo
  echo "- status: skip"
  echo "- reason: project tick already running"
  exit 0
fi
trap 'rm -rf "$LOCK"' EXIT

is_recent_file() {
  local file="$1"
  local minutes="$2"
  [ -f "$file" ] || return 1
  [ -n "$(find "$file" -mmin "-$minutes" -print 2>/dev/null)" ]
}

write_inbox_note() {
  local inbox="$1"
  local slug="$2"
  local title="$3"
  local body="$4"
  mkdir -p "$inbox"
  local file="$inbox/$(date -u +%Y-%m-%dT%H-%M-%SZ)-$(project_tick_safe_name "$slug").md"
  if [ "$MODE" = "dry-run" ]; then
    echo "- would write note: ${file#$ROOT/}"
    return 0
  fi
  cat > "$file" <<EOF
---
created: $(project_tick_now_iso)
source: project-tick
status: pending
priority: medium
---

# $title

$body
EOF
  echo "- wrote note: ${file#$ROOT/}"
}

ensure_due_top_loop_notes() {
  local wrote=0
  local id kind inbox cadence command
  while IFS=$'\t' read -r id kind inbox cadence command; do
    case "$id" in ''|\#*) continue ;; esac
    [ "$kind" = "top" ] || continue
    [ "$cadence" -gt 0 ] || continue

    local inbox_abs="$ROOT/$inbox"
    if project_tick_has_runnable_request "$inbox_abs"; then
      continue
    fi

    case "$id" in
      coordinator)
        local last="$ROOT/.meta/project/actors/coordinator/last-summary.md"
        if ! is_recent_file "$last" "$cadence"; then
          write_inbox_note "$inbox_abs" "coordinator-cadence" "Coordinator Cadence Tick" \
            "Run one coordinator tick. Read project state, existing inboxes, and any blocked requests before deciding the next action."
          wrote=$((wrote + 1))
        fi
        ;;
      process-fixer)
        if find "$ROOT/docs/multi-pass-coordinator/inbox" -maxdepth 3 -type f -name '*.md' -exec grep -l '^status:[[:space:]]*blocked' {} \; 2>/dev/null | grep -q .; then
          write_inbox_note "$inbox_abs" "process-fixer-blockers" "Process Fixer Blocker Sweep" \
            "Inspect blocked loop requests and repair the local harness or actor instructions if a deterministic bug is preventing coordinator recovery."
          wrote=$((wrote + 1))
        fi
        ;;
    esac
  done < "$ROSTER"
  return 0
}

run_behaviour_tree() {
  local command="$1"
  if [ "$MODE" = "dry-run" ]; then
    echo "# Behaviour Tree Tick"
    echo
    echo "- status: dry-run"
    echo "- command: $command"
    return 0
  fi
  "$ROOT/$command" --write
}

run_project_command() {
  local command="$1"
  "$ROOT/$command" "--$MODE"
}

starts=0
started=()

dispatch_roster() {
  local id kind inbox cadence command
  while IFS=$'\t' read -r id kind inbox cadence command; do
    case "$id" in ''|\#*) continue ;; esac
    [ "$starts" -lt "$MAX_STARTS" ] || break

    case "$kind" in
      top)
        if project_tick_has_runnable_request "$ROOT/$inbox"; then
          started+=("$id")
          starts=$((starts + 1))
          run_project_command "$command"
        fi
        ;;
      actor)
        if project_tick_has_runnable_request "$ROOT/$inbox"; then
          started+=("$id")
          starts=$((starts + 1))
          run_project_command "$command"
        fi
        ;;
      behaviour-tree)
        if [ -f "$ROOT/.claude/state/next-action.md" ] && ! project_tick_has_runnable_request "$ROOT/docs/multi-pass-coordinator/inbox/coordinator"; then
          started+=("$id")
          starts=$((starts + 1))
          run_behaviour_tree "$command"
        fi
        ;;
    esac
  done < "$ROSTER"
}

{
  echo "# Project Tick"
  echo
  echo "- generated: $(project_tick_now_iso)"
  echo "- mode: $MODE"
  echo "- root: $ROOT"
  echo "- roster: ${ROSTER#$ROOT/}"
  echo "- max starts: $MAX_STARTS"
  echo
  echo "## Due Notes"
  ensure_due_top_loop_notes
  echo
  echo "## Dispatch"
  dispatch_roster
  if [ "${#started[@]}" -eq 0 ]; then
    echo "- idle"
  else
    printf -- "- started: %s\n" "${started[*]}"
  fi
} | tee "$SUMMARY"
