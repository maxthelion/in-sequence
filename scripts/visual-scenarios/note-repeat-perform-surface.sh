#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "$SCRIPT_DIR/peekaboo-common.sh"

output_dir="${PEEKABOO_OUTPUT_DIR:-.meta/multipass/runtime/loops/build/note-repeat/act/phase-5-note-repeat-perform-visual}"
case "$output_dir" in
  /*) ;;
  *) output_dir="$REPO_ROOT/$output_dir" ;;
esac
export PEEKABOO_OUTPUT_DIR="$output_dir"

bundle_id="ai.sequencer.SequencerAI"
app_command_dir="$HOME/Library/Containers/$bundle_id/Data/tmp/sequencer-ai-visual-commands"
run_id="$(basename "$output_dir")"
command_file="${SEQUENCER_AI_VISUAL_COMMAND_FILE:-$app_command_dir/${run_id}-note-repeat-perform-command.env}"
case "$command_file" in
  /*) ;;
  *) command_file="$REPO_ROOT/$command_file" ;;
esac
status_file="${command_file}.status"
scenario_status="started; no captures completed yet"

write_notes() {
  mkdir -p "$output_dir"
  cat > "$output_dir/scenario-note-repeat-perform-surface-notes.md" <<NOTES
# Note Repeat Perform Surface Scenario Evidence

Feature worktree: \`${REPO_ROOT}\`
Command file: \`${command_file}\`
Status file: \`${status_file}\`

This scenario opens the built SequencerAI app through
\`scripts/open-latest-build.sh\`, creates a new production document, switches to
the production Tracks Matrix in Perform mode through
\`VisualScenarioCommandRunner\`, and captures Note Repeat perform states with
the shared Peekaboo/screencapture helpers.

Status from this script run: ${scenario_status}.

Captured states:

- \`supported-inactive.png\`: selected clip-backed track, Note Repeat available
  and inactive.
- \`supported-active.png\`: selected clip-backed track with momentary Note
  Repeat engaged.
- \`interval-next-engagement.png\`: active Repeat keeps its captured interval
  while the stored interval has been changed for the next engagement.
- \`released.png\`: selected supported track after releasing momentary Note
  Repeat.
- \`unsupported.png\`: selected generator-backed track, Note Repeat unavailable,
  and press is a safe no-op.

Each \`.status\` sidecar records the selected pattern source, stored interval,
availability, active runtime state, active interval, and active track names.
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

capture_state() {
  local pid="$1"
  local name="$2"
  cp "$command_file" "$output_dir/${name}.command.env"
  capture_window "$pid" "$output_dir/${name}.png"
  cp "$status_file" "$output_dir/${name}.status"
  action_log "Captured ${name}.png"
}

ensure_supported_inactive_state() {
  write_visual_command "workspace=tracks
tracksMode=perform
trackPerformLayer=noteRepeat
noteRepeatSelectedTrackIndex=0
noteRepeatSource=clip
transport=stop
noteRepeatInterval=1/16
noteRepeatAction=clear"

  wait_for_status workspace tracks 10
  wait_for_status tracksMode perform 10
  wait_for_status trackPerformLayerMode noteRepeat 10
  wait_for_status selectedPatternSourceMode clip 10
  wait_for_status selectedPatternHasClip true 10
  wait_for_status selectedNoteRepeatAvailable true 10
  wait_for_status selectedNoteRepeatStoredInterval "1/16" 10
  wait_for_status selectedNoteRepeatActive false 10
}

ensure_supported_active_state() {
  write_visual_command "workspace=tracks
tracksMode=perform
trackPerformLayer=noteRepeat
noteRepeatAction=press"

  wait_for_status trackPerformLayerMode noteRepeat 10
  wait_for_status selectedNoteRepeatAvailable true 10
  wait_for_status selectedNoteRepeatActive true 10
  wait_for_status selectedNoteRepeatActiveInterval "1/16" 10
  wait_for_status noteRepeatActiveTrackNames "Main Track" 10
}

ensure_interval_next_engagement_state() {
  write_visual_command "workspace=tracks
tracksMode=perform
trackPerformLayer=noteRepeat
noteRepeatInterval=1/32"

  wait_for_status selectedNoteRepeatStoredInterval "1/32" 10
  wait_for_status selectedNoteRepeatActive true 10
  wait_for_status selectedNoteRepeatActiveInterval "1/16" 10
}

ensure_released_state() {
  write_visual_command "workspace=tracks
tracksMode=perform
trackPerformLayer=noteRepeat
noteRepeatAction=release"

  wait_for_status selectedNoteRepeatAvailable true 10
  wait_for_status selectedNoteRepeatStoredInterval "1/32" 10
  wait_for_status selectedNoteRepeatActive false 10
  wait_for_status noteRepeatActiveTrackNames none 10
}

ensure_unsupported_state() {
  write_visual_command "workspace=tracks
tracksMode=perform
trackPerformLayer=noteRepeat
noteRepeatSource=generator
noteRepeatAction=press"

  wait_for_status selectedPatternSourceMode generator 10
  wait_for_status selectedNoteRepeatAvailable false 10
  wait_for_status selectedNoteRepeatActive false 10
  wait_for_status noteRepeatActiveTrackNames none 10
}

mkdir -p "$output_dir"
mkdir -p "$app_command_dir"
rm -f "$command_file" "$status_file"
rm -f "$output_dir"/{supported-inactive,supported-active,interval-next-engagement,released,unsupported}.{command.env,png,status}

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
  echo "No $APP_NAME process found for note repeat perform scenario." >&2
  exit 2
fi

keep_only_pid "$pid"
ensure_new_document "$pid"

ensure_supported_inactive_state
sleep 0.8
capture_state "$pid" supported-inactive
scenario_status="captured supported inactive"

ensure_supported_active_state
sleep 0.8
capture_state "$pid" supported-active
scenario_status="captured supported active"

ensure_interval_next_engagement_state
sleep 0.8
capture_state "$pid" interval-next-engagement
scenario_status="captured interval next engagement"

ensure_released_state
sleep 0.8
capture_state "$pid" released
scenario_status="captured released"

ensure_unsupported_state
sleep 0.8
capture_state "$pid" unsupported
scenario_status="captured unsupported"

scenario_status="completed note repeat perform surface capture"
sleep 0.2
