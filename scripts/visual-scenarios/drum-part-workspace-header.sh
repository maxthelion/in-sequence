#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "$SCRIPT_DIR/peekaboo-common.sh"

output_dir="${PEEKABOO_OUTPUT_DIR:-.meta/multipass/loops/build/drum-parts-as-group/act/phase-4-header-rendered}"
case "$output_dir" in
  /*) ;;
  *) output_dir="$REPO_ROOT/$output_dir" ;;
esac

bundle_id="ai.sequencer.SequencerAI"
app_command_dir="$HOME/Library/Containers/$bundle_id/Data/tmp/sequencer-ai-visual-commands"
run_id="$(basename "$output_dir")"
command_file="${SEQUENCER_AI_VISUAL_COMMAND_FILE:-$app_command_dir/${run_id}-drum-part-header-command.env}"
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
  cat > "$output_dir/scenario-drum-part-workspace-header-notes.md" <<NOTES
# Drum Part Workspace Header Scenario Evidence

This scenario opens the current built SequencerAI app with the production
\`VisualScenarioCommandRunner\` hook, creates a deterministic six-member drum
group fixture, selects grouped drum parts in the Track workspace, and captures
production window screenshots with the shared Peekaboo/window-capture helpers.

Captured states: middle grouped part, first grouped part disabled previous,
last grouped part disabled next, rename editing in the header, Open Kit View
retained-origin command, non-kit fallback header, generator/read-only selected
member with sibling navigation still available, one-member bounded controls,
long kit/part names, and stale/unresolved group fallback.

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
  action_log "Drum part header command written for ${state}: ${payload//$'\n'/; }"
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

ensure_drum_header_document() {
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
  echo "No $APP_NAME process found for Drum Part Workspace Header scenario." >&2
  exit 2
fi

keep_only_pid "$pid"
ensure_drum_header_document "$pid"

capture_state "$pid" "01-middle-part" "drumPartHeaderFixture=kit
drumPartHeaderSelectedIndex=2
drumPartHeaderRename=off" "drumPartHeaderPosition" "3 of 6"

capture_state "$pid" "02-first-part-prev-disabled" "drumPartHeaderFixture=kit
drumPartHeaderSelectedIndex=0
drumPartHeaderRename=off" "drumPartHeaderPreviousEnabled" "false"

capture_state "$pid" "03-last-part-next-disabled" "drumPartHeaderFixture=kit
drumPartHeaderSelectedIndex=5
drumPartHeaderRename=off" "drumPartHeaderNextEnabled" "false"

capture_state "$pid" "04-rename-editing" "drumPartHeaderFixture=kit
drumPartHeaderSelectedIndex=2
drumPartHeaderRename=on" "drumPartHeaderPosition" "3 of 6"

capture_state "$pid" "05-open-kit-view-retained-origin" "drumPartHeaderFixture=kit
drumPartHeaderSelectedIndex=2
drumPartHeaderRename=off
drumPartHeaderOpenKitView=true" "drumPartHeaderPosition" "3 of 6"

capture_state "$pid" "06-non-kit-fallback" "drumPartHeaderFixture=nonKit
drumPartHeaderRename=off" "drumPartHeaderVisible" "false"

capture_state "$pid" "07-generator-read-only-sibling-navigation" "drumPartHeaderFixture=generatorReadOnly
drumPartHeaderSelectedIndex=2
drumPartHeaderRename=off" "selectedPatternHasGenerator" "true"

capture_state "$pid" "08-one-member-bounded-controls" "drumPartHeaderFixture=oneMember
drumPartHeaderRename=off" "drumPartHeaderMemberCount" "1"

capture_state "$pid" "09-long-names-truncation" "drumPartHeaderFixture=longNames
drumPartHeaderSelectedIndex=0
drumPartHeaderRename=off" "selectedTrackGroupName" "Warehouse Breakbeat Kit With Extremely Long Saved Name"

capture_state "$pid" "10-stale-unresolved-group-fallback" "drumPartHeaderFixture=staleGroup
drumPartHeaderRename=off" "drumPartHeaderVisible" "false"

scenario_status="completed drum part workspace header captures"
kill "$pid" >/dev/null 2>&1 || true
sleep 0.2
