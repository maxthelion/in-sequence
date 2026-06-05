#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "$SCRIPT_DIR/peekaboo-common.sh"

output_dir="${PEEKABOO_OUTPUT_DIR:-.meta/multipass/loops/build/drum-parts-as-group/act/phase-5-kit-matrix-rendered}"
case "$output_dir" in
  /*) ;;
  *) output_dir="$REPO_ROOT/$output_dir" ;;
esac

bundle_id="ai.sequencer.SequencerAI"
app_command_dir="$HOME/Library/Containers/$bundle_id/Data/tmp/sequencer-ai-visual-commands"
run_id="$(basename "$output_dir")"
command_file="${SEQUENCER_AI_VISUAL_COMMAND_FILE:-$app_command_dir/${run_id}-drum-kit-matrix-command.env}"
case "$command_file" in
  /*) ;;
  *) command_file="$REPO_ROOT/$command_file" ;;
esac
status_file="${command_file}.status"
scenario_status="started; no captures completed yet"

cleanup() {
  launchctl unsetenv SEQUENCER_AI_VISUAL_COMMAND_FILE >/dev/null 2>&1 || true
  launchctl unsetenv SEQUENCER_AI_NEW_DOCUMENT_FIXTURE >/dev/null 2>&1 || true
  defaults delete "$bundle_id" VisualScenarioCommandFile >/dev/null 2>&1 || true
}

write_notes() {
  mkdir -p "$output_dir"
  cat > "$output_dir/scenario-drum-kit-matrix-notes.md" <<NOTES
# Drum Kit Matrix Scenario Evidence

This scenario opens the current built SequencerAI app with the production
\`VisualScenarioCommandRunner\` hook, creates deterministic drum-group fixtures,
opens the pushed kit matrix from a drum-part workspace, and captures production
window screenshots with the shared Peekaboo/window-capture helpers.

Captured states: coherent six-member matrix in 16-step mode, the same matrix in
32-step mode, mixed active pattern slots with mismatch treatment,
generator/non-step read-only rows, row navigation back to a member workspace,
Back behavior to the originating part workspace, long group/part names,
zero-member groups, stale member IDs, routing-editor launch from the matrix, and
return to the matrix after closing routing.

Status from this script run: ${scenario_status}.

Each \`.png\` screenshot has a same-named \`.status\` file copied from the app
command runner after that state was applied.
NOTES
}

trap 'cleanup; write_notes' EXIT

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
  action_log "Drum kit matrix command written for ${state}: ${payload//$'\n'/; }"
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
  local timeout_seconds="${3:-12}"
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

expect_status() {
  local key="$1"
  local expected="$2"
  local actual
  actual="$(status_value "$key" 2>/dev/null || true)"
  if [ "$actual" != "$expected" ]; then
    echo "Expected ${key}=${expected}; got '${actual}'." >&2
    return 1
  fi
}

ensure_matrix_document() {
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

capture_document_window() {
  local pid="$1"
  local output="$2"
  local window_id

  window_id="$(
    window_json "$pid" \
      | jq -r '
          [
            .data.windows[]
            | select(.window_title == "Untitled" or (.bounds.width >= 1000 and .bounds.height >= 700))
          ][0].window_id // .data.windows[0].window_id
        '
  )"

  mkdir -p "$(dirname "$output")"
  screencapture -x -l "$window_id" "$output"
}

capture_state() {
  local pid="$1"
  local state="$2"
  local payload="$3"
  local wait_key="$4"
  local wait_value="$5"

  write_visual_command "$state" "$payload"
  wait_for_status workspace track 12
  wait_for_status "$wait_key" "$wait_value" 12
  if [ "$(status_value drumKitMatrixVisible 2>/dev/null || true)" = "true" ]; then
    wait_for_status drumKitMatrixRenderedVisible true 12
    wait_for_status \
      drumKitMatrixRenderedDisplayStepCount \
      "$(status_value drumKitMatrixDisplayStepCount)" \
      12
    wait_for_status \
      drumKitMatrixRenderedGroupName \
      "$(status_value drumKitMatrixGroupName)" \
      12
    wait_for_status \
      drumKitMatrixRenderedMemberCount \
      "$(status_value drumKitMatrixMemberCount)" \
      12
    wait_for_status \
      drumKitMatrixRenderedRoutingEditorVisible \
      "$(status_value drumKitMatrixRoutingEditorVisible)" \
      12
  fi
  sleep 0.8
  cp "$command_file" "$output_dir/${state}.command.env"
  capture_document_window "$pid" "$output_dir/${state}.png"
  cp "$status_file" "$output_dir/${state}.status"
  scenario_status="captured ${state}"
}

mkdir -p "$output_dir"
mkdir -p "$app_command_dir"
rm -f "$command_file" "$status_file"

"$PEEKABOO_BIN" app list --json --no-remote \
  | jq -r --arg app "$APP_NAME" '.data.apps[] | select(.name == $app) | .pid' \
  | while read -r existing_pid; do
    [ -n "$existing_pid" ] && kill "$existing_pid" 2>/dev/null || true
  done
sleep 1

launchctl setenv SEQUENCER_AI_VISUAL_COMMAND_FILE "$command_file" >/dev/null
defaults write "$bundle_id" VisualScenarioCommandFile "$command_file"
export SEQUENCER_AI_VISUAL_COMMAND_FILE="$command_file"

(
  cd "$REPO_ROOT"
  scripts/open-latest-build.sh
) >"$output_dir/app-open.log" 2>&1

sleep 2

pid="$(latest_app_pid)"
if [ -z "$pid" ]; then
  echo "No $APP_NAME process found for Drum Kit Matrix scenario." >&2
  exit 2
fi

keep_only_pid "$pid"
ensure_matrix_document "$pid"

capture_state "$pid" "01-coherent-16" "drumPartHeaderFixture=kit
drumPartHeaderSelectedIndex=2
drumPartHeaderRename=off
drumPartHeaderOpenKitView=true" "drumKitMatrixVisible" "true"
expect_status drumKitMatrixMemberCount 6
expect_status drumKitMatrixPatternBadges "P1|P1|P1|P1|P1|P1"
expect_status drumKitMatrixPatternMismatch false
expect_status drumKitMatrixDisplayStepCount 16
expect_status drumKitMatrixRenderedVisible true
expect_status drumKitMatrixPreviewActiveCounts "2|2|2|8|2|2"

capture_state "$pid" "02-coherent-32" "drumKitMatrixCommand=display32" "drumKitMatrixDisplayStepCount" "32"
expect_status drumKitMatrixVisible true
expect_status drumKitMatrixRenderedVisible true
expect_status drumKitMatrixPreviewActiveCounts "5|4|4|16|4|4"

capture_state "$pid" "03-mixed-patterns" "drumPartHeaderFixture=kit
drumPartHeaderSelectedIndex=2
drumPartHeaderRename=off
drumKitMatrixFixture=mixedPatterns
drumPartHeaderOpenKitView=true" "drumKitMatrixPatternMismatch" "true"
expect_status drumKitMatrixPatternBadges "P1|P2|P1|P1|P1|P1"

capture_state "$pid" "04-generator-read-only" "drumPartHeaderFixture=kit
drumPartHeaderSelectedIndex=2
drumPartHeaderRename=off
drumKitMatrixFixture=generatorAndReadOnly
drumPartHeaderOpenKitView=true" "drumKitMatrixPreviewKinds" "steps16+|RO|GEN|steps16+|steps16+|steps16+"
expect_status drumKitMatrixSourceModes "clip|clip|generator|clip|clip|clip"

capture_state "$pid" "05-row-navigation-source" "drumPartHeaderFixture=kit
drumPartHeaderSelectedIndex=2
drumPartHeaderRename=off
drumPartHeaderOpenKitView=true" "drumKitMatrixVisible" "true"
capture_state "$pid" "06-row-navigation-to-member" "drumKitMatrixCommand=selectIndex:1" "selectedTrackName" "Snare"
expect_status drumKitMatrixVisible false
expect_status drumPartHeaderVisible true

capture_state "$pid" "07-back-source" "drumPartHeaderFixture=kit
drumPartHeaderSelectedIndex=2
drumPartHeaderRename=off
drumPartHeaderOpenKitView=true" "drumPartHeaderOpenKitOriginPartName" "Clap"
capture_state "$pid" "08-back-to-origin" "drumKitMatrixCommand=back" "selectedTrackName" "Clap"
expect_status drumKitMatrixVisible false
expect_status drumPartHeaderVisible true

capture_state "$pid" "09-long-names" "drumPartHeaderFixture=longNames
drumPartHeaderSelectedIndex=0
drumPartHeaderRename=off
drumPartHeaderOpenKitView=true" "drumKitMatrixGroupName" "Warehouse Breakbeat Kit With Extremely Long Saved Name"
expect_status drumKitMatrixMemberCount 2

capture_state "$pid" "10-zero-members" "drumPartHeaderFixture=kit
drumPartHeaderSelectedIndex=2
drumPartHeaderRename=off
drumPartHeaderOpenKitView=true
drumKitMatrixMutation=zeroMembers" "drumKitMatrixMemberCount" "0"
expect_status drumKitMatrixStaleMemberCount 0

capture_state "$pid" "11-stale-member" "drumPartHeaderFixture=kit
drumPartHeaderSelectedIndex=2
drumPartHeaderRename=off
drumPartHeaderOpenKitView=true
drumKitMatrixMutation=staleMember" "drumKitMatrixStaleMemberCount" "1"
expect_status drumKitMatrixMemberCount 2

capture_state "$pid" "12-routing-launch-source" "drumPartHeaderFixture=kit
drumPartHeaderSelectedIndex=2
drumPartHeaderRename=off
drumPartHeaderOpenKitView=true" "drumKitMatrixVisible" "true"
capture_state "$pid" "13-routing-editor-open" "drumKitMatrixCommand=openRouting" "drumKitMatrixRoutingEditorVisible" "true"
capture_state "$pid" "14-routing-return-to-matrix" "drumKitMatrixCommand=closeRouting" "drumKitMatrixRoutingEditorVisible" "false"
expect_status drumKitMatrixVisible true

scenario_status="completed drum kit matrix captures"
kill "$pid" >/dev/null 2>&1 || true
sleep 0.2
