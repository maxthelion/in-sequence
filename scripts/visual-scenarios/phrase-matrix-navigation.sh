#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "$SCRIPT_DIR/peekaboo-common.sh"

output_dir="${PEEKABOO_OUTPUT_DIR:-.meta/multipass/runtime/loops/build/phrase-features/evidence/phase-5-matrix-navigation}"
case "$output_dir" in
  /*) ;;
  *) output_dir="$REPO_ROOT/$output_dir" ;;
esac
export PEEKABOO_OUTPUT_DIR="$output_dir"

bundle_id="ai.sequencer.SequencerAI"
app_command_dir="$HOME/Library/Containers/$bundle_id/Data/tmp/sequencer-ai-visual-commands"
run_id="$(basename "$output_dir")"
command_file="${SEQUENCER_AI_VISUAL_COMMAND_FILE:-$app_command_dir/${run_id}-phrase-matrix-navigation-command.env}"
case "$command_file" in
  /*) ;;
  *) command_file="$REPO_ROOT/$command_file" ;;
esac
status_file="${command_file}.status"
scenario_status="started; no captures completed yet"

write_notes() {
  mkdir -p "$output_dir"
  cat > "$output_dir/scenario-phrase-matrix-navigation-notes.md" <<NOTES
# Phrase Matrix Navigation Scenario Evidence

Feature worktree: \`${REPO_ROOT}\`
Command file: \`${command_file}\`
Status file: \`${status_file}\`

This scenario opens the built SequencerAI app through
\`scripts/open-latest-build.sh\`, creates a new production document, ensures a
12-track phrase matrix fixture, and captures the production Phrase Matrix with
first-page, second-page, and layer-switch states.

Status from this script run: ${scenario_status}.

Captured state:

- \`phrase-matrix-page-1-pattern.png\`: first page, previous arrow disabled,
  next arrow enabled with adjacent occupancy.
- \`phrase-matrix-page-2-pattern.png\`: second page, previous arrow enabled with
  occupancy, next arrow disabled.
- \`phrase-matrix-page-2-fx-send.png\`: fixed selector after switching to FX Send.
- \`phrase-matrix-page-2-mute.png\`: fixed selector after switching to Mute.

The copied \`.status\` sidecars record page index/count, enabled/disabled arrow
states, adjacent occupancy, selected layer, selector width, and track grid
width. The selector and grid width values should stay unchanged across layer
switch captures.
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
    sleep 0.2
  done

  echo "Timed out waiting for visual automation status ${key}=${expected}; last value was '${actual}'." >&2
  return 1
}

drive_phrase_matrix() {
  local page_index="$1"
  local layer_id="$2"
  write_visual_command "workspace=phrase
transport=stop
phraseMatrixTrackCount=12"

  wait_for_status workspace phrase 10
  wait_for_status phraseMatrixRenderedVisible true 10
  wait_for_status phraseMatrixTrackCount 12 10

  write_visual_command "workspace=phrase
transport=stop
phraseMatrixTrackCount=12
phraseMatrixPageIndex=$page_index
phraseMatrixLayerID=$layer_id"

  wait_for_status phraseMatrixPageIndex "$page_index" 10
  wait_for_status phraseMatrixSelectedLayerID "$layer_id" 10
}

capture_state() {
  local pid="$1"
  local name="$2"
  sleep 0.8
  cp "$command_file" "$output_dir/${name}.command.env"
  cp "$status_file" "$output_dir/${name}.status"
  capture_window "$pid" "$output_dir/${name}.png"
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
  echo "No $APP_NAME process found for phrase matrix navigation scenario." >&2
  exit 2
fi

keep_only_pid "$pid"
ensure_new_document "$pid"

drive_phrase_matrix 0 pattern
wait_for_status phraseMatrixPreviousEnabled false 10
wait_for_status phraseMatrixNextEnabled true 10
wait_for_status phraseMatrixNextOccupancy 4 10
capture_state "$pid" "phrase-matrix-page-1-pattern"

drive_phrase_matrix 1 pattern
wait_for_status phraseMatrixPreviousEnabled true 10
wait_for_status phraseMatrixPreviousOccupancy 8 10
wait_for_status phraseMatrixNextEnabled false 10
capture_state "$pid" "phrase-matrix-page-2-pattern"

drive_phrase_matrix 1 fx-send
capture_state "$pid" "phrase-matrix-page-2-fx-send"

drive_phrase_matrix 1 mute
capture_state "$pid" "phrase-matrix-page-2-mute"

scenario_status="completed phrase matrix navigation captures"
sleep 0.2
