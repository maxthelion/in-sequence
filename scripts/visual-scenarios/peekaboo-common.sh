#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${APP_NAME:-SequencerAI}"
PEEKABOO_BIN="${PEEKABOO_BIN:-peekaboo}"
PEEKABOO_ACTION_TIMEOUT_SECONDS="${PEEKABOO_ACTION_TIMEOUT_SECONDS:-8}"
PEEKABOO_OUTPUT_DIR="${PEEKABOO_OUTPUT_DIR:-${TMPDIR:-/tmp}/in-sequence-captures/peekaboo-${USER:-user}}"
VISUAL_CAPTURE_LOCK_PATH="${SEQUENCER_AI_VISUAL_CAPTURE_LOCK:-${TMPDIR:-/tmp}/in-sequence-visual-capture.lock}"
VISUAL_CAPTURE_LOCK_TIMEOUT_SECONDS="${SEQUENCER_AI_VISUAL_CAPTURE_LOCK_TIMEOUT_SECONDS:-900}"

visual_automation_blocked() {
  case "${SEQUENCER_AI_BLOCK_VISUAL_AUTOMATION:-${SEQUENCER_AI_DISABLE_VISUAL_AUTOMATION:-}}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

require_visual_automation_not_blocked() {
  if ! visual_automation_blocked; then
    return 0
  fi

  mkdir -p "$PEEKABOO_OUTPUT_DIR"
  cat > "$PEEKABOO_OUTPUT_DIR/visual-automation-blocked.md" <<BLOCKED
# Visual Automation Blocked

Visual automation was not started because \`SEQUENCER_AI_BLOCK_VISUAL_AUTOMATION\`
is enabled.

This opt-out guard is for coordinators that intentionally run parallel
sub-agents and do not want those workers to steal focus, launch apps, or
interfere with one another's visual automation.

To block visual automation for a coordinator run:

\`\`\`sh
SEQUENCER_AI_BLOCK_VISUAL_AUTOMATION=1 <coordinator-command>
\`\`\`

Normal interactive and single-agent capture runs do not need to set an allow
variable. \`SEQUENCER_AI_ALLOW_VISUAL_AUTOMATION=1\` is still accepted by older
runbooks, but it is no longer required.
BLOCKED

  echo "Visual automation disabled because SEQUENCER_AI_BLOCK_VISUAL_AUTOMATION is enabled." >&2
  exit 42
}

action_log() {
  local output_dir="$PEEKABOO_OUTPUT_DIR"
  mkdir -p "$output_dir"
  printf '%s\n' "$*" >> "$output_dir/scenario-actions.log"
}

visual_capture_lock_disabled() {
  case "${SEQUENCER_AI_DISABLE_VISUAL_CAPTURE_LOCK:-}" in
    1|true|TRUE|yes|YES|on|ON) return 0 ;;
    *) return 1 ;;
  esac
}

acquire_visual_capture_lock() {
  if visual_capture_lock_disabled; then
    action_log "Visual capture mutex disabled by SEQUENCER_AI_DISABLE_VISUAL_CAPTURE_LOCK."
    return 0
  fi

  mkdir -p "$(dirname "$VISUAL_CAPTURE_LOCK_PATH")"
  action_log "Waiting for visual capture mutex: ${VISUAL_CAPTURE_LOCK_PATH}"
  exec 9>"$VISUAL_CAPTURE_LOCK_PATH"
  if lockf -s -t "$VISUAL_CAPTURE_LOCK_TIMEOUT_SECONDS" 9; then
    action_log "Acquired visual capture mutex: ${VISUAL_CAPTURE_LOCK_PATH}"
    return 0
  fi

  {
    echo "Visual capture mutex is busy: ${VISUAL_CAPTURE_LOCK_PATH}"
    echo "Timed out after ${VISUAL_CAPTURE_LOCK_TIMEOUT_SECONDS}s."
    echo "Set SEQUENCER_AI_VISUAL_CAPTURE_LOCK_TIMEOUT_SECONDS to wait longer,"
    echo "or SEQUENCER_AI_DISABLE_VISUAL_CAPTURE_LOCK=1 only for intentional debugging."
  } >&2
  action_log "Timed out waiting for visual capture mutex after ${VISUAL_CAPTURE_LOCK_TIMEOUT_SECONDS}s."
  exit 75
}

require_visual_automation_not_blocked
acquire_visual_capture_lock

run_with_timeout() {
  local seconds="$1"
  shift

  "$@" &
  local child_pid="$!"
  local elapsed=0

  while kill -0 "$child_pid" 2>/dev/null; do
    if [ "$elapsed" -ge "$seconds" ]; then
      kill "$child_pid" 2>/dev/null || true
      sleep 1
      kill -9 "$child_pid" 2>/dev/null || true
      wait "$child_pid" 2>/dev/null || true
      return 124
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done

  wait "$child_pid"
}

post_mouse_event() {
  local type="$1"
  local x="$2"
  local y="$3"

  swift -e '
import CoreGraphics
import Foundation

let type = CommandLine.arguments[1]
let x = Double(CommandLine.arguments[2])!
let y = Double(CommandLine.arguments[3])!
let button = CGMouseButton.left
let source = CGEventSource(stateID: .hidSystemState)
let point = CGPoint(x: x, y: y)

let mouseType: CGEventType
switch type {
case "down":
  mouseType = .leftMouseDown
case "up":
  mouseType = .leftMouseUp
case "drag":
  mouseType = .leftMouseDragged
default:
  exit(64)
}

CGEvent(
  mouseEventSource: source,
  mouseType: mouseType,
  mouseCursorPosition: point,
  mouseButton: button
)?.post(tap: .cghidEventTap)
' "$type" "$x" "$y"
}

cg_click_point() {
  local x="$1"
  local y="$2"

  post_mouse_event down "$x" "$y"
  sleep 0.05
  post_mouse_event up "$x" "$y"
}

cg_drag_point() {
  local from_x="$1"
  local from_y="$2"
  local to_x="$3"
  local to_y="$4"

  post_mouse_event down "$from_x" "$from_y"

  local steps=14
  local step
  for step in $(seq 1 "$steps"); do
    local x=$((from_x + ((to_x - from_x) * step / steps)))
    local y=$((from_y + ((to_y - from_y) * step / steps)))
    post_mouse_event drag "$x" "$y"
    sleep 0.025
  done

  post_mouse_event up "$to_x" "$to_y"
}

latest_app_pid() {
  # pgrep, not peekaboo app list: the latter can return empty under AX/TCC
  # pressure even while the app is running.
  pgrep -x "$APP_NAME" | sort -n | tail -1
}

keep_only_pid() {
  local keep="$1"
  pgrep -x "$APP_NAME" \
    | while read -r pid; do
      if [ -n "$pid" ] && [ "$pid" != "$keep" ]; then
        kill "$pid" 2>/dev/null || true
        sleep 1
        kill -9 "$pid" 2>/dev/null || true
      fi
    done
}

window_json() {
  local pid="$1"
  "$PEEKABOO_BIN" window list --pid "$pid" --json --no-remote
}

window_field() {
  local pid="$1"
  local field="$2"
  window_json "$pid" | jq -r ".data.windows[0].bounds.$field"
}

click_point() {
  local pid="$1"
  local x="$2"
  local y="$3"
  local status
  mkdir -p "$PEEKABOO_OUTPUT_DIR"
  if run_with_timeout "$PEEKABOO_ACTION_TIMEOUT_SECONDS" \
    "$PEEKABOO_BIN" click --coords "${x},${y}" --pid "$pid" --no-remote --json >/dev/null 2>>"$PEEKABOO_OUTPUT_DIR/peekaboo-actions.err"; then
    return 0
  else
    status="$?"
  fi

  action_log "Peekaboo click at ${x},${y} for pid ${pid} failed or timed out with status ${status}; falling back to CoreGraphics click."
  run_with_timeout "$PEEKABOO_ACTION_TIMEOUT_SECONDS" cg_click_point "$x" "$y"
}

drag_point() {
  local pid="$1"
  local from_x="$2"
  local from_y="$3"
  local to_x="$4"
  local to_y="$5"
  local status
  mkdir -p "$PEEKABOO_OUTPUT_DIR"
  if run_with_timeout "$PEEKABOO_ACTION_TIMEOUT_SECONDS" "$PEEKABOO_BIN" drag \
    --from-coords "${from_x},${from_y}" \
    --to-coords "${to_x},${to_y}" \
    --duration 350 \
    --steps 14 \
    --pid "$pid" \
    --no-remote \
    --json >/dev/null 2>>"$PEEKABOO_OUTPUT_DIR/peekaboo-actions.err"; then
    return 0
  else
    status="$?"
  fi

  action_log "Peekaboo drag from ${from_x},${from_y} to ${to_x},${to_y} for pid ${pid} failed or timed out with status ${status}; falling back to CoreGraphics drag."
  run_with_timeout "$PEEKABOO_ACTION_TIMEOUT_SECONDS" cg_drag_point "$from_x" "$from_y" "$to_x" "$to_y"
}

wait_for_window_title() {
  local pid="$1"
  local title="$2"
  local deadline=$((SECONDS + 10))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if window_json "$pid" | jq -e --arg title "$title" '.data.windows[0].window_title == $title' >/dev/null; then
      return 0
    fi
    sleep 0.5
  done
  echo "Timed out waiting for $APP_NAME window title '$title'." >&2
  return 1
}

ensure_new_document() {
  local pid="$1"
  sleep 0.5

  local title
  title="$(window_json "$pid" | jq -r '.data.windows[0].window_title')"
  if [ "$title" = "Open" ]; then
    action_log "Open chooser visible; invoking New Document with Cmd-N."
    if run_with_timeout "$PEEKABOO_ACTION_TIMEOUT_SECONDS" \
      "$PEEKABOO_BIN" hotkey --keys "cmd,n" --pid "$pid" \
      --space-switch --no-remote --json \
      >/dev/null 2>>"$PEEKABOO_OUTPUT_DIR/peekaboo-actions.err"; then
      sleep 1
      title="$(window_json "$pid" | jq -r '.data.windows[0].window_title')"
    fi
  fi

  if [ "$title" = "Open" ]; then
    local x y height click_x click_y
    x="$(window_field "$pid" x)"
    y="$(window_field "$pid" y)"
    height="$(window_field "$pid" height)"
    click_x="$((x + 230))"
    click_y="$((y + height - 30))"
    action_log "Cmd-N did not dismiss the chooser; clicking New Document at ${click_x},${click_y}."
    if ! run_with_timeout "$PEEKABOO_ACTION_TIMEOUT_SECONDS" \
      "$PEEKABOO_BIN" click --coords "${click_x},${click_y}" --pid "$pid" \
      --space-switch --no-remote --json \
      >/dev/null 2>>"$PEEKABOO_OUTPUT_DIR/peekaboo-actions.err"; then
      action_log "PID-targeted New Document click failed; falling back to CoreGraphics."
      run_with_timeout "$PEEKABOO_ACTION_TIMEOUT_SECONDS" cg_click_point "$click_x" "$click_y"
    fi
    sleep 1
  fi

  wait_for_window_title "$pid" "Untitled"
}

capture_window() {
  local pid="$1"
  local output="$2"
  local window_id
  mkdir -p "$(dirname "$output")"
  local attempt
  for attempt in 1 2 3; do
    window_id="$(window_json "$pid" | jq -r '.data.windows[0].window_id')"
    if [ -n "$window_id" ] && [ "$window_id" != "null" ] &&
       screencapture -x -l "$window_id" "$output"; then
      return 0
    fi
    action_log "screencapture attempt ${attempt} failed for pid ${pid} window ${window_id:-unknown}; retrying"
    sleep 0.7
  done
  return 1
}
