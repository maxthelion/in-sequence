#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${APP_NAME:-SequencerAI}"
PEEKABOO_BIN="${PEEKABOO_BIN:-peekaboo}"
PEEKABOO_ACTION_TIMEOUT_SECONDS="${PEEKABOO_ACTION_TIMEOUT_SECONDS:-8}"
PEEKABOO_OUTPUT_DIR="${PEEKABOO_OUTPUT_DIR:-.meta/multipass/visual-review}"

require_visual_automation_allowed() {
  case "${SEQUENCER_AI_ALLOW_VISUAL_AUTOMATION:-}" in
    1|true|TRUE|yes|YES|on|ON)
      return 0
      ;;
  esac

  mkdir -p "$PEEKABOO_OUTPUT_DIR"
  cat > "$PEEKABOO_OUTPUT_DIR/visual-automation-blocked.md" <<BLOCKED
# Visual Automation Blocked

Visual automation was not started because \`SEQUENCER_AI_ALLOW_VISUAL_AUTOMATION\`
is not enabled.

This guard prevents unattended Foreman/Codex agents from triggering macOS TCC
permission prompts such as "bun would like to access data from other apps".

To run this scenario in an interactive, pre-authorized session:

\`\`\`sh
SEQUENCER_AI_ALLOW_VISUAL_AUTOMATION=1 PEEKABOO_OUTPUT_DIR="$PEEKABOO_OUTPUT_DIR" <visual-scenario-command>
\`\`\`

Unattended actors should treat this as \`capture-permission-or-focus\` /
\`evidence-insufficient\` and route a bounded interactive capture or process
repair instead of retrying.
BLOCKED

  echo "Visual automation disabled; set SEQUENCER_AI_ALLOW_VISUAL_AUTOMATION=1 only in an interactive, pre-authorized session." >&2
  exit 42
}

require_visual_automation_allowed

action_log() {
  local output_dir="$PEEKABOO_OUTPUT_DIR"
  mkdir -p "$output_dir"
  printf '%s\n' "$*" >> "$output_dir/scenario-actions.log"
}

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
  if run_with_timeout "$PEEKABOO_ACTION_TIMEOUT_SECONDS" \
    "$PEEKABOO_BIN" click --coords "${x},${y}" --pid "$pid" --no-remote --json >/dev/null 2>>"${PEEKABOO_OUTPUT_DIR:-.meta/multipass/visual-review}/peekaboo-actions.err"; then
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
  if run_with_timeout "$PEEKABOO_ACTION_TIMEOUT_SECONDS" "$PEEKABOO_BIN" drag \
    --from-coords "${from_x},${from_y}" \
    --to-coords "${to_x},${to_y}" \
    --duration 350 \
    --steps 14 \
    --pid "$pid" \
    --no-remote \
    --json >/dev/null 2>>"${PEEKABOO_OUTPUT_DIR:-.meta/multipass/visual-review}/peekaboo-actions.err"; then
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
  "$PEEKABOO_BIN" app switch --to "$APP_NAME" --no-remote >/dev/null || true
  sleep 0.5

  local title
  title="$(window_json "$pid" | jq -r '.data.windows[0].window_title')"
  if [ "$title" = "Open" ]; then
    local x y
    x="$(window_field "$pid" x)"
    y="$(window_field "$pid" y)"
    click_point "$pid" "$((x + 227))" "$((y + 421))"
    sleep 1
  fi

  wait_for_window_title "$pid" "Untitled"
}

capture_window() {
  local pid="$1"
  local output="$2"
  local window_id
  window_id="$(window_json "$pid" | jq -r '.data.windows[0].window_id')"
  mkdir -p "$(dirname "$output")"
  screencapture -x -l "$window_id" "$output"
}
