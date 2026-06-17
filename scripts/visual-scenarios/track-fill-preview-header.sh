#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "$SCRIPT_DIR/peekaboo-common.sh"

output_dir="${PEEKABOO_OUTPUT_DIR:-.meta/multipass/runtime/loops/build/track-fill-toggle/act/track-fill-preview-header-screenshots}"
case "$output_dir" in
  /*) ;;
  *) output_dir="$REPO_ROOT/$output_dir" ;;
esac
command_file="${SEQUENCER_AI_VISUAL_COMMAND_FILE:-$HOME/Library/Containers/ai.sequencer.SequencerAI/Data/tmp/sequencer-ai-track-fill-preview-command.env}"
case "$command_file" in
  /*) ;;
  *) command_file="$REPO_ROOT/$command_file" ;;
esac
status_file="${command_file}.status"
scenario_status="started; no captures completed yet"

write_notes() {
  mkdir -p "$output_dir"
  cat > "$output_dir/scenario-track-fill-preview-header-notes.md" <<NOTES
# Track Fill Preview Header Scenario Evidence

This scenario opens the current main build with the production
\`VisualScenarioCommandRunner\` hook, drives the selected/open track-source
editor to the requested Fill Preview header states, and captures production
window screenshots with the shared Peekaboo/window-capture helpers.

Captured states: inactive, active, disabled/unavailable, generator-copy,
reset/clear, current-track-only, and unchanged phrase/dirty-state.

Status from this script run: ${scenario_status}.

Each \`.png\` screenshot has a same-named \`.status\` file copied from the app
command runner after that state was applied.
NOTES
}
trap write_notes EXIT

write_visual_command() {
  local state="$1"
  local payload="$2"
  mkdir -p "$(dirname "$command_file")"
  cat > "${command_file}.tmp" <<COMMAND
workspace=track
transport=stop
scenarioToken=$state-$SECONDS-$RANDOM
$payload
COMMAND
  mv "${command_file}.tmp" "$command_file"
  action_log "Track fill preview command written for ${state}: ${payload//$'\n'/; }"
}

status_value() {
  local key="$1"
  if [ ! -f "$status_file" ]; then
    return 1
  fi
  awk -F= -v key="$key" '$1 == key { print substr($0, index($0, "=") + 1); found=1 } END { exit found ? 0 : 1 }' "$status_file"
}

wait_for_status() {
  local key="$1"
  local expected="$2"
  local timeout_seconds="${3:-10}"
  local deadline=$((SECONDS + timeout_seconds))
  local actual=""

  while [ "$SECONDS" -lt "$deadline" ]; do
    actual="$(status_value "$key" 2>/dev/null || true)"
    if [ "$actual" = "$expected" ]; then
      return 0
    fi
    sleep 0.2
  done

  echo "Timed out waiting for visual automation status ${key}=${expected}; last value was '${actual}'." >&2
  return 1
}

capture_state() {
  local pid="$1"
  local state="$2"
  local payload="$3"
  local wait_key="${4:-workspace}"
  local wait_value="${5:-track}"

  write_visual_command "$state" "$payload"
  wait_for_status workspace track 8
  wait_for_status "$wait_key" "$wait_value" 8
  sleep 0.8
  capture_window "$pid" "$output_dir/${state}.png"
  cp "$status_file" "$output_dir/${state}.status"
  scenario_status="captured ${state}"
}

mkdir -p "$output_dir"
rm -f "$command_file" "$status_file"

"$PEEKABOO_BIN" app list --json --no-remote \
  | jq -r --arg app "$APP_NAME" '.data.apps[] | select(.name == $app) | .pid' \
  | while read -r existing_pid; do
    [ -n "$existing_pid" ] && kill "$existing_pid" 2>/dev/null || true
  done
sleep 1

launchctl setenv SEQUENCER_AI_VISUAL_COMMAND_FILE "$command_file" >/dev/null

(
  cd "$REPO_ROOT"
  scripts/open-latest-build.sh
) >"$output_dir/app-open.log" 2>&1

sleep 2

pid="$(latest_app_pid)"
if [ -z "$pid" ]; then
  echo "No $APP_NAME process found for Track Fill Preview Header scenario." >&2
  exit 2
fi

keep_only_pid "$pid"
ensure_new_document "$pid"

capture_state "$pid" "01-inactive" "" "selectedTrackFillPreviewActive" "false"
capture_state "$pid" "02-active" "trackFillPreview=on" "selectedTrackFillPreviewActive" "true"
capture_state "$pid" "03-reset-clear" "trackFillPreview=clear" "selectedTrackFillPreviewActive" "false"
capture_state "$pid" "04-unchanged-phrase-dirty-state" "trackFillPreview=clear" "selectedTrackFillPreviewActive" "false"

capture_state "$pid" "05-current-track-only-prime" "trackFillEnsureSecondClipTrack=true
trackFillSelectedTrackIndex=0
trackFillSource=clip
trackFillPreview=on" "selectedTrackFillPreviewActive" "true"
capture_state "$pid" "06-current-track-only" "trackFillEnsureSecondClipTrack=true
trackFillSelectedTrackIndex=1
trackFillSource=clip" "selectedTrackFillPreviewActive" "false"

capture_state "$pid" "07-disabled-unavailable" "trackFillSource=empty
trackFillPreview=on" "selectedTrackFillPreviewAvailable" "false"
capture_state "$pid" "08-generator-copy" "trackFillSource=generator
trackFillPreview=on" "selectedPatternSourceMode" "generator"

scenario_status="completed track fill preview header captures"
launchctl unsetenv SEQUENCER_AI_VISUAL_COMMAND_FILE >/dev/null 2>&1 || true
kill "$pid" >/dev/null 2>&1 || true
sleep 0.2
