#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${APP_NAME:-SequencerAI}"
PEEKABOO_BIN="${PEEKABOO_BIN:-peekaboo}"

latest_app_pid() {
  "$PEEKABOO_BIN" app list --json --no-remote \
    | jq -r --arg app "$APP_NAME" '.data.apps[] | select(.name == $app) | .pid' \
    | sort -n \
    | tail -1
}

keep_only_pid() {
  local keep="$1"
  "$PEEKABOO_BIN" app list --json --no-remote \
    | jq -r --arg app "$APP_NAME" --argjson keep "$keep" '.data.apps[] | select(.name == $app and .pid != $keep) | .pid' \
    | while read -r pid; do
      [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
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
  "$PEEKABOO_BIN" click --coords "${x},${y}" --pid "$pid" --no-remote --json >/dev/null
}

drag_point() {
  local pid="$1"
  local from_x="$2"
  local from_y="$3"
  local to_x="$4"
  local to_y="$5"
  "$PEEKABOO_BIN" drag \
    --from-coords "${from_x},${from_y}" \
    --to-coords "${to_x},${to_y}" \
    --duration 350 \
    --steps 14 \
    --pid "$pid" \
    --no-remote \
    --json >/dev/null
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
