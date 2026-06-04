#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "$SCRIPT_DIR/peekaboo-common.sh"

output_dir="${PEEKABOO_OUTPUT_DIR:-.meta/multipass/visual-review/input-audio-runtime-states}"
case "$output_dir" in
  /*) ;;
  *) output_dir="$REPO_ROOT/$output_dir" ;;
esac
export PEEKABOO_OUTPUT_DIR="$output_dir"
bundle_id="ai.sequencer.SequencerAI"
app_command_dir="$HOME/Library/Containers/$bundle_id/Data/tmp/sequencer-ai-visual-commands"
run_id="$(basename "$output_dir")"
command_file="${INPUT_AUDIO_RUNTIME_COMMAND_FILE:-$app_command_dir/${run_id}-input-audio-runtime-command.env}"
case "$command_file" in
  /*) ;;
  *) command_file="$REPO_ROOT/$command_file" ;;
esac
status_file="${command_file}.status"
scenario_status="started; no captures completed yet"

write_notes() {
  mkdir -p "$output_dir"
  cat > "$output_dir/scenario-input-audio-runtime-states-notes.md" <<NOTES
# Input Audio Runtime States Scenario Evidence

This scenario opens the current built app with the existing
\`VisualScenarioCommandRunner\` hook, creates or selects an audio-input track,
publishes deterministic runtime capture states through the production
\`EngineController\` audio-input runtime, and captures the selected track detail
panel.

Captured states:

- \`input-audio-live.png\`: idle input with non-silent live levels.
- \`input-audio-recording.png\`: recording in progress with progress overlay and streamed waveform buckets.
- \`input-audio-completed.png\`: completed loop state with completed waveform buckets.

Command file: \`$command_file\`
Status file: \`$status_file\`
Status from this script run: ${scenario_status}.

If captures are missing, inspect \`scenario-actions.log\`,
\`peekaboo-actions.err\`, and \`app-open.log\` in this folder.
NOTES
}

cleanup() {
  launchctl unsetenv SEQUENCER_AI_VISUAL_COMMAND_FILE >/dev/null 2>&1 || true
  launchctl unsetenv SEQUENCER_AI_NEW_DOCUMENT_FIXTURE >/dev/null 2>&1 || true
  defaults delete "$bundle_id" VisualScenarioCommandFile >/dev/null 2>&1 || true
  write_notes
}
trap cleanup EXIT

write_visual_command() {
  local state="$1"
  mkdir -p "$(dirname "$command_file")"
  cat > "${command_file}.tmp" <<COMMAND
workspace=track
audioInputState=$state
audioInputAvailableChannels=2
COMMAND
  mv "${command_file}.tmp" "$command_file"
  action_log "Visual command written: audioInputState=${state}; audioInputAvailableChannels=2"
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

wait_for_positive_number() {
  local key="$1"
  local timeout_seconds="${2:-10}"
  local deadline=$((SECONDS + timeout_seconds))
  local actual=""

  while [ "$SECONDS" -lt "$deadline" ]; do
    actual="$(status_value "$key" 2>/dev/null || true)"
    if awk "BEGIN { exit !($actual > 0) }" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.2
  done

  echo "Timed out waiting for visual automation status ${key}>0; last value was '${actual}'." >&2
  return 1
}

wait_for_progress_between() {
  local key="$1"
  local lower="$2"
  local upper="$3"
  local timeout_seconds="${4:-10}"
  local deadline=$((SECONDS + timeout_seconds))
  local actual=""

  while [ "$SECONDS" -lt "$deadline" ]; do
    actual="$(status_value "$key" 2>/dev/null || true)"
    if awk "BEGIN { exit !(($actual > $lower) && ($actual < $upper)) }" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.2
  done

  echo "Timed out waiting for visual automation status ${key} between ${lower} and ${upper}; last value was '${actual}'." >&2
  return 1
}

ensure_document_window() {
  local pid="$1"
  "$PEEKABOO_BIN" app switch --to "$APP_NAME" --no-remote >/dev/null || true
  sleep 0.5

  local title
  title="$(window_json "$pid" | jq -r '.data.windows[0].window_title')"
  if [ "$title" != "Open" ]; then
    return 0
  fi

  local x y
  x="$(window_field "$pid" x)"
  y="$(window_field "$pid" y)"
  click_point "$pid" "$((x + 227))" "$((y + 421))"
  sleep 1
}

capture_state() {
  local pid="$1"
  local state="$2"
  local expected_arm_state="$3"
  local bucket_key="${4:-}"

  write_visual_command "$state"
  wait_for_status workspace track 6
  wait_for_status selectedTrackType audioInput 6
  wait_for_status audioInputRouteState available 6
  wait_for_status audioInputArmState "$expected_arm_state" 6
  if [ -n "$bucket_key" ]; then
    wait_for_positive_number "$bucket_key" 6
  fi
  if [ "$state" = "live" ]; then
    wait_for_positive_number audioInputLivePeak 6
  elif [ "$state" = "recording" ]; then
    wait_for_progress_between audioInputRecordingProgress 0 1 6
  fi

  sleep 0.8
  capture_window "$pid" "$output_dir/input-audio-${state}.png"
  cp "$status_file" "$output_dir/input-audio-${state}.status"
  cp "$command_file" "$output_dir/input-audio-${state}.command.env"
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
launchctl unsetenv SEQUENCER_AI_NEW_DOCUMENT_FIXTURE >/dev/null 2>&1 || true
defaults write "$bundle_id" VisualScenarioCommandFile "$command_file"
export SEQUENCER_AI_VISUAL_COMMAND_FILE="$command_file"
unset SEQUENCER_AI_NEW_DOCUMENT_FIXTURE

(
  cd "$REPO_ROOT"
  scripts/open-latest-build.sh
) >"$output_dir/app-open.log" 2>&1

sleep 2

pid="$(latest_app_pid)"
if [ -z "$pid" ]; then
  echo "No $APP_NAME process found for Input Audio Runtime States scenario." >&2
  exit 2
fi

keep_only_pid "$pid"
ensure_document_window "$pid"

capture_state "$pid" live idle
capture_state "$pid" recording recording audioInputCaptureBucketCount
capture_state "$pid" completed hasLoop audioInputCompletedBucketCount

scenario_status="completed live/recording/completed captures"
sleep 0.2
