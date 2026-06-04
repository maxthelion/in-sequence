#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "$SCRIPT_DIR/peekaboo-common.sh"

fixture_path="${SEQUENCER_AI_TRANSPORT_PHRASE_FIXTURE:-docs/roadmap/song-mode-phrase-looping/fixtures/transport-phrase-navigation.seqai}"
case "$fixture_path" in
  /*) fixture_source_path="$fixture_path" ;;
  *) fixture_source_path="$REPO_ROOT/$fixture_path" ;;
esac
output_dir="${PEEKABOO_OUTPUT_DIR:-.meta/multipass/loops/build/song-mode-phrase-looping/evidence/transport-phrase-navigation-captures}"
case "$output_dir" in
  /*) ;;
  *) output_dir="$REPO_ROOT/$output_dir" ;;
esac
export PEEKABOO_OUTPUT_DIR="$output_dir"
bundle_id="ai.sequencer.SequencerAI"
app_command_dir="$HOME/Library/Containers/$bundle_id/Data/tmp/sequencer-ai-visual-commands"
run_id="$(basename "$output_dir")"
command_file="${SEQUENCER_AI_TRANSPORT_COMMAND_FILE:-$app_command_dir/${run_id}-transport-phrase-navigation-command.env}"
case "$command_file" in
  /*) ;;
  *) command_file="$REPO_ROOT/$command_file" ;;
esac
status_file="${command_file}.status"
runtime_fixture_path="$app_command_dir/${run_id}-transport-phrase-navigation.seqai"
scenario_status="started; no captures completed yet"

write_notes() {
  mkdir -p "$output_dir"
  cat > "$output_dir/scenario-transport-phrase-navigation-notes.md" <<NOTES
# Transport Phrase Navigation Scenario Evidence

Feature worktree: \`${REPO_ROOT}\`
Source fixture: \`${fixture_source_path}\`
Runtime fixture: \`${runtime_fixture_path}\`
Command file: \`${command_file}\`
Status file: \`${status_file}\`

This scenario launches the built SequencerAI app through \`scripts/open-latest-build.sh\`,
creates a fixture-backed new document, drives the production transport phrase
navigation UI with \`VisualScenarioCommandRunner\`, and captures the active app
window with the shared Peekaboo/screencapture helpers.

Status from this script run: ${scenario_status}.

Captured states:

- \`transport-running-current.png\`: playback running with current phrase visible.
- \`transport-picker-open.png\`: picker open with separate Queue and Now row actions.
- \`transport-queue-dismissed-chip.png\`: queue action dismissed the picker and retained the queued chip.
- \`transport-immediate-now-clears-queue.png\`: Now action updated current phrase and cleared queued state.
- \`transport-stopped-picker-disabled-queue.png\`: stopped picker state with disabled Queue and available Now actions.
- \`transport-crowded-long-label.png\`: long current phrase in a narrowed transport without label overlap.
- \`transport-empty-no-phrases.png\`: empty/no-phrase state.
- \`transport-keyboard-space-picker.png\` and \`transport-keyboard-escape-dismissed.png\`: focus/keyboard attempt and post-Escape state.

The status sidecar records phrase count, phrase names, current phrase, queued phrase,
and whether queue/now actions are enabled after each command.
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
$state
COMMAND
  mv "${command_file}.tmp" "$command_file"
  action_log "Visual command written: ${state//$'\n'/; }"
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

send_key_code() {
  local key_code="$1"
  run_with_timeout 4 osascript \
    -e "tell application \"System Events\" to key code ${key_code}" \
    >/dev/null 2>&1 || true
}

focus_phrase_control() {
  local pid="$1"
  local x y width
  x="$(window_field "$pid" x)"
  y="$(window_field "$pid" y)"
  width="$(window_field "$pid" width)"
  run_with_timeout "$PEEKABOO_ACTION_TIMEOUT_SECONDS" \
    cg_click_point "$((x + width - 620))" "$((y + 62))" || true
}

try_resize_window() {
  run_with_timeout 4 osascript \
    -e "tell application \"$APP_NAME\" to activate" \
    -e "tell application \"$APP_NAME\" to set bounds of front window to {80, 80, 1080, 720}" \
    >/dev/null 2>&1 || true
  sleep 0.5
}

ensure_transport_document() {
  local pid="$1"
  if ensure_new_document "$pid"; then
    return 0
  fi

  action_log "Shared new-document helper did not reach Untitled; requesting File > New through System Events."
  osascript \
    -e "tell application \"$APP_NAME\" to activate" \
    -e "tell application \"System Events\" to tell process \"$APP_NAME\" to click menu item \"New\" of menu \"File\" of menu bar 1" \
    >/dev/null 2>&1 || true
  wait_for_window_title "$pid" "Untitled"
}

capture_state() {
  local pid="$1"
  local name="$2"
  sleep 0.6
  capture_window "$pid" "$output_dir/${name}.png"
  cp "$status_file" "$output_dir/${name}.status"
  cp "$command_file" "$output_dir/${name}.command.env"
  scenario_status="captured ${name}"
}

mkdir -p "$output_dir"
mkdir -p "$app_command_dir"
rm -f "$command_file" "$status_file"
cp "$fixture_source_path" "$runtime_fixture_path"

"$PEEKABOO_BIN" app list --json --no-remote \
  | jq -r --arg app "$APP_NAME" '.data.apps[] | select(.name == $app) | .pid' \
  | while read -r existing_pid; do
    [ -n "$existing_pid" ] && kill "$existing_pid" 2>/dev/null || true
  done
sleep 1

launchctl setenv SEQUENCER_AI_VISUAL_COMMAND_FILE "$command_file" >/dev/null
launchctl setenv SEQUENCER_AI_NEW_DOCUMENT_FIXTURE "$runtime_fixture_path" >/dev/null
defaults write "$bundle_id" VisualScenarioCommandFile "$command_file"
export SEQUENCER_AI_VISUAL_COMMAND_FILE="$command_file"
export SEQUENCER_AI_NEW_DOCUMENT_FIXTURE="$runtime_fixture_path"

(
  cd "$REPO_ROOT"
  scripts/open-latest-build.sh
) >"$output_dir/app-open.log" 2>&1

sleep 2

pid="$(latest_app_pid)"
if [ -z "$pid" ]; then
  echo "No $APP_NAME process found for transport phrase navigation scenario." >&2
  exit 2
fi

keep_only_pid "$pid"
ensure_transport_document "$pid"

write_visual_command "workspace=tracks
transport=play"
wait_for_status phraseCount "4" 8
wait_for_status transport "play" 8
wait_for_status currentPhraseName "Intro Lift" 8
capture_state "$pid" "transport-running-current"

write_visual_command "workspace=tracks
phrasePicker=open"
sleep 0.6
capture_state "$pid" "transport-picker-open"

write_visual_command "workspace=tracks
phraseAction=queue:1"
wait_for_status queuedPhraseName "Verse - Pocket With A Very Long Name For Truncation" 8
capture_state "$pid" "transport-queue-dismissed-chip"

write_visual_command "workspace=tracks
phrasePicker=open"
sleep 0.4
write_visual_command "workspace=tracks
phraseAction=now:2"
wait_for_status currentPhraseName "Chorus Drop" 8
wait_for_status queuedPhraseName "none" 8
capture_state "$pid" "transport-immediate-now-clears-queue"

write_visual_command "workspace=tracks
transport=stop
phrasePicker=open"
wait_for_status transport "stop" 8
wait_for_status phraseQueueEnabled "false" 8
sleep 0.6
capture_state "$pid" "transport-stopped-picker-disabled-queue"

write_visual_command "workspace=tracks
transport=play"
wait_for_status transport "play" 8
write_visual_command "workspace=tracks
phraseAction=now:3"
wait_for_status currentPhraseName "Outro Texture With Extended Label For Crowded Transport Verification" 8
try_resize_window
capture_state "$pid" "transport-crowded-long-label"

focus_phrase_control "$pid"
send_key_code 53
sleep 0.3
send_key_code 49
sleep 0.6
capture_state "$pid" "transport-keyboard-space-picker"
send_key_code 53
sleep 0.5
capture_state "$pid" "transport-keyboard-escape-dismissed"

write_visual_command "workspace=tracks
phraseFixture=empty"
wait_for_status phraseCount "0" 8
capture_state "$pid" "transport-empty-no-phrases"

scenario_status="completed transport phrase navigation captures"
sleep 0.2
