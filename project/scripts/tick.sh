#!/usr/bin/env bash
set -euo pipefail

ROOT="$(git -C "$(dirname "$0")/../.." rev-parse --show-toplevel)"
cd "$ROOT"

ROSTER="${PROJECT_TICK_ROSTER:-$ROOT/project/scripts/loops.tsv}"
RUNTIME="$ROOT/.meta/project-tick"
SUMMARY="$RUNTIME/last-summary.md"
LOCK="$RUNTIME/tick.lock"
MPC_ROOT="${MULTI_PASS_COORDINATOR_ROOT:-/Users/maxwilliams/dev/multi-pass-coordinator}"
SETTINGS="docs/multi-pass-coordinator/settings.yaml"
MAX_STARTS="${PROJECT_TICK_MAX_STARTS:-1}"
MODE="write"

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

now_iso() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

safe_name() {
  printf "%s" "$1" | tr -cs 'A-Za-z0-9._-' '-' | sed 's/^-//; s/-$//'
}

is_terminal_status() {
  case "$1" in
    done|complete|completed|archived|blocked|handled|superseded) return 0 ;;
    *) return 1 ;;
  esac
}

request_status() {
  local file="$1"
  local status
  status="$(sed -n 's/^status:[[:space:]]*//p' "$file" | head -1 | tr '[:upper:]' '[:lower:]' || true)"
  printf "%s" "${status:-pending}"
}

has_runnable_markdown() {
  local dir="$1"
  [ -d "$dir" ] || return 1
  local file status
  while IFS= read -r file; do
    [ "$(basename "$file")" = "README.md" ] && continue
    status="$(request_status "$file")"
    if ! is_terminal_status "$status"; then
      return 0
    fi
  done < <(find "$dir" -maxdepth 1 -type f -name '*.md' ! -name '.*' | sort)
  return 1
}

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
  local file="$inbox/$(date -u +%Y-%m-%dT%H-%M-%SZ)-$(safe_name "$slug").md"
  if [ "$MODE" = "dry-run" ]; then
    echo "- would write note: ${file#$ROOT/}"
    return 0
  fi
  cat > "$file" <<EOF
---
created: $(now_iso)
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
    if has_runnable_markdown "$inbox_abs"; then
      continue
    fi

    case "$id" in
      coordinator)
        local last="$ROOT/.meta/multi-pass-coordinator/last-summary.json"
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

run_coordinator() {
  local args=(run src/cli/tick.ts --project "$ROOT" --settings "$SETTINGS")
  [ "$MODE" = "dry-run" ] && args+=(--dry-run)
  (cd "$MPC_ROOT" && bun "${args[@]}")
}

run_tick_loops() {
  local args=(run src/cli/tick-loops.ts --project "$ROOT" --settings "$SETTINGS")
  [ "$MODE" = "dry-run" ] && args+=(--dry-run)
  (cd "$MPC_ROOT" && bun "${args[@]}")
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
  "$ROOT/$command"
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
        [ "$command" = "coordinator" ] || continue
        if has_runnable_markdown "$ROOT/$inbox"; then
          started+=("$id")
          starts=$((starts + 1))
          run_coordinator
        fi
        ;;
      actor)
        if has_runnable_markdown "$ROOT/$inbox"; then
          started+=("$id")
          starts=$((starts + 1))
          run_tick_loops
        fi
        ;;
      behaviour-tree)
        if [ -f "$ROOT/.claude/state/next-action.md" ] && ! has_runnable_markdown "$ROOT/docs/multi-pass-coordinator/inbox/coordinator"; then
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
  echo "- generated: $(now_iso)"
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
