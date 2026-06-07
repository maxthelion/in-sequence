#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "$SCRIPT_DIR/peekaboo-common.sh"

output_dir="${PEEKABOO_OUTPUT_DIR:-.meta/multipass/runtime/loops/build/step-order/observe/step-order-supported-states}"
case "$output_dir" in
  /*) ;;
  *) output_dir="$REPO_ROOT/$output_dir" ;;
esac

bundle_id="ai.sequencer.SequencerAI"
app_command_dir="$HOME/Library/Containers/$bundle_id/Data/tmp/sequencer-ai-visual-commands"
run_id="$(basename "$output_dir")"
command_file="${SEQUENCER_AI_VISUAL_COMMAND_FILE:-$app_command_dir/${run_id}-step-order-command.env}"
case "$command_file" in
  /*) ;;
  *) command_file="$REPO_ROOT/$command_file" ;;
esac
status_file="${command_file}.status"
scenario_status="started; no captures completed yet"

write_notes() {
  mkdir -p "$output_dir"
  cat > "$output_dir/step-order-supported-states-notes.md" <<NOTES
# Step Order Supported-State Scenario Evidence

This scenario opens the current main build with the project
\`VisualScenarioCommandRunner\` hook, creates a new document, seeds deterministic
Step Order phrase/map states, and captures production screenshots with the same
Peekaboo/window-capture helpers used by feature UX reviews.

Captured states:

- 16-step unassigned map controls
- assigned Off
- assigned On
- populated editor
- Pending On
- Pending Off
- invalid saved map
- missing assigned map
- delete-blocked assigned map
- delete-available unused map

The invalid saved-map state is seeded through the visual fixture's temporary
project import to represent a decoded/quarantined production document. Normal
live map mutations still reject invalid Step Order values.

Status from this script run: ${scenario_status}.

If captures are missing, inspect \`scenario-actions.log\`,
\`peekaboo-actions.err\`, \`app-open.log\`, and \`status-*.txt\` in this folder.
NOTES
}

cleanup() {
  launchctl unsetenv SEQUENCER_AI_VISUAL_COMMAND_FILE >/dev/null 2>&1 || true
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
    sleep 0.1
  done

  echo "Timed out waiting for visual automation status ${key}=${expected}; last value was '${actual}'." >&2
  return 1
}

capture_state() {
  local pid="$1"
  local name="$2"
  local fixture="$3"
  local expected_status="$4"

  write_visual_command "workspace=phrase
phraseControlsOpenIndex=0
stepOrderFixture=$fixture"
  wait_for_status workspace phrase 4
  wait_for_status phraseControlsOpenIndex 0 4
  wait_for_status stepOrderFixtureState "$fixture" 4
  wait_for_status stepOrderStatus "$expected_status" 4
  cp "$status_file" "$output_dir/status-${name}.txt"
  sleep 0.25
  capture_window "$pid" "$output_dir/step-order-${name}.png"
  scenario_status="captured ${name}"
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
  echo "No $APP_NAME process found for Step Order supported-state scenario." >&2
  exit 2
fi

keep_only_pid "$pid"
ensure_new_document "$pid"

capture_state "$pid" "16-step-unassigned" "unassigned" "Unassigned"
capture_state "$pid" "assigned-off" "assignedOff" "Off"
capture_state "$pid" "assigned-on" "assignedOn" "On"
capture_state "$pid" "populated-editor" "populatedEditor" "Off"
capture_state "$pid" "pending-on" "pendingOn" "Pending On"
capture_state "$pid" "pending-off" "pendingOff" "Pending Off"
capture_state "$pid" "invalid-map" "invalidMap" "Invalid"
capture_state "$pid" "missing-assigned-map" "missingAssignedMap" "Invalid"
capture_state "$pid" "delete-blocked-assigned-map" "deleteBlocked" "Off"
capture_state "$pid" "delete-available-unused-map" "deleteAvailable" "Off"

write_visual_command "workspace=phrase
phraseControlsOpenIndex=0
transport=stop"
wait_for_status transport stop 4

scenario_status="completed Step Order supported-state captures"
sleep 0.2
