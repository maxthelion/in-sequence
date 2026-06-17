#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "$SCRIPT_DIR/peekaboo-common.sh"

output_dir="${PEEKABOO_OUTPUT_DIR:-.meta/multipass/runtime/loops/project/observe/holistic-ux/manual/screenshots}"
case "$output_dir" in
  /*) ;;
  *) output_dir="$REPO_ROOT/$output_dir" ;;
esac
bundle_id="ai.sequencer.SequencerAI"
app_command_dir="$HOME/Library/Containers/$bundle_id/Data/tmp/sequencer-ai-visual-commands"
run_id="$(basename "$output_dir")"
command_file="${SEQUENCER_AI_VISUAL_COMMAND_FILE:-$app_command_dir/${run_id}-app-surfaces-command.env}"
case "$command_file" in
  /*) ;;
  *) command_file="$REPO_ROOT/$command_file" ;;
esac
status_file="${command_file}.status"
phrase_controls_open_index="${APP_SURFACES_PHRASE_CONTROLS_OPEN_INDEX:-}"
scenario_status="started; no captures completed yet"

write_notes() {
  mkdir -p "$output_dir"
  cat > "$output_dir/scenario-app-surfaces-capture-notes.md" <<NOTES
# App Surfaces Scenario Evidence

This scenario opens the current main build with the existing
\`VisualScenarioCommandRunner\` hook, creates a new document, switches through
the main workspace sections, and captures production screenshots with the same
Peekaboo/window-capture helpers used by feature UX reviews.

Captured sections: phrase, tracks, track, mixer, scenes, library.

Phrase controls open index: ${phrase_controls_open_index:-none}.

Status from this script run: ${scenario_status}.

If captures are missing, inspect \`scenario-actions.log\`,
\`peekaboo-actions.err\`, and \`app-open.log\` in this folder.
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

drive_workspace() {
  local workspace="$1"
  local command="workspace=$workspace
transport=stop
masterGain=1
meterPeak=0"
  if [ "$workspace" = "phrase" ] && [ -n "$phrase_controls_open_index" ]; then
    command="${command}
phraseControlsOpenIndex=$phrase_controls_open_index"
  fi
  write_visual_command "$command"
  wait_for_status workspace "$workspace" 3
  if [ "$workspace" = "phrase" ] && [ -n "$phrase_controls_open_index" ]; then
    wait_for_status phraseControlsOpenIndex "$phrase_controls_open_index" 3
  fi
}

fallback_click_workspace() {
  local pid="$1"
  local workspace="$2"
  local x y
  x="$(window_field "$pid" x)"
  y="$(window_field "$pid" y)"

  case "$workspace" in
    phrase) click_point "$pid" "$((x + 70))" "$((y + 128))" ;;
    tracks) click_point "$pid" "$((x + 185))" "$((y + 128))" ;;
    track)
      click_point "$pid" "$((x + 185))" "$((y + 128))"
      sleep 0.4
      click_point "$pid" "$((x + 125))" "$((y + 318))"
      ;;
    mixer) click_point "$pid" "$((x + 310))" "$((y + 128))" ;;
    scenes) click_point "$pid" "$((x + 425))" "$((y + 128))" ;;
    library) click_point "$pid" "$((x + 540))" "$((y + 128))" ;;
    *) return 64 ;;
  esac
}

show_workspace() {
  local pid="$1"
  local workspace="$2"
  if drive_workspace "$workspace"; then
    return 0
  fi

  action_log "Visual command status failed for workspace=${workspace}; falling back to Peekaboo click navigation."
  fallback_click_workspace "$pid" "$workspace"
  sleep 0.8
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
  echo "No $APP_NAME process found for App Surfaces scenario." >&2
  exit 2
fi

keep_only_pid "$pid"
ensure_new_document "$pid"

sections=(phrase tracks track mixer scenes library)
for section in "${sections[@]}"; do
  show_workspace "$pid" "$section"
  sleep 0.8
  capture_window "$pid" "$output_dir/app-surface-${section}.png"
  scenario_status="captured ${section}"
done

scenario_status="completed app surface captures"
sleep 0.2
