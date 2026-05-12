#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/peekaboo-common.sh"

output_dir="${PEEKABOO_OUTPUT_DIR:-.claude/state/visual-review}"
command_file="${SEQUENCER_AI_VISUAL_COMMAND_FILE:-$PWD/.claude/state/visual-review/mixer-main-out-command.env}"
status_file="${command_file}.status"
scenario_status="started; no captures completed yet"
write_notes() {
  cat > "$output_dir/scenario-mixer-main-out-capture-notes.md" <<NOTES
# Mixer Main Out Scenario Evidence

The scenario opens a new document, navigates to the Mixer workspace, drives
the Master Out meter readout, moves the combined fader/meter control high and
low, restores it near unity, then clears the clip latch.

For deterministic visual evidence, the visual-review environment points new
documents at \`docs/roadmap/mixer-main-out/fixtures/mixer-main-out-live-meter.seqai\`.
The scenario uses the app's visual command hook to feed the production
\`MasterMeterPublisher\` while the app remains on the real Mixer/Master Out
surface. This avoids relying on fragile coordinate clicks or unavailable
transport/audio input during screenshot capture.

Status from this script run: ${scenario_status}.

If the run stops before all screenshots are written, inspect
\`scenario-actions.log\`, the visual command status file, and \`app.stderr.log\`
in the same capture folder.
NOTES
}
trap write_notes EXIT

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

drive_state() {
  local state="$1"
  write_visual_command "$state"
  wait_for_status workspace mixer 10
}

rm -f "$command_file" "$status_file"

pid="$(latest_app_pid)"
if [ -z "$pid" ]; then
  echo "No $APP_NAME process found for Mixer Main Out scenario." >&2
  exit 2
fi

keep_only_pid "$pid"
ensure_new_document "$pid"

drive_state "workspace=mixer
transport=stop
masterGain=1
meterPeak=0
clearClip=false"
sleep 1
capture_window "$pid" "$output_dir/scenario-mixer-main-out-normal.png"
scenario_status="captured normal mixer state; live-meter capture pending"

drive_state "workspace=mixer
transport=stop
masterGain=1
meterPeak=0.45"
sleep 1.2
capture_window "$pid" "$output_dir/scenario-mixer-main-out-live-meter.png"
scenario_status="captured live meter state; fader-high/clip capture pending"

drive_state "workspace=mixer
transport=stop
masterGain=2
meterPeak=1.35"
wait_for_status clipLatched true 8
sleep 1.2
capture_window "$pid" "$output_dir/scenario-mixer-main-out-fader-high.png"
capture_window "$pid" "$output_dir/scenario-mixer-main-out-clipped.png"
scenario_status="captured high fader and clipped states; low/restore/clear capture pending"

drive_state "workspace=mixer
transport=stop
masterGain=0.25
meterPeak=0.15"
sleep 0.4
capture_window "$pid" "$output_dir/scenario-mixer-main-out-fader-low.png"
scenario_status="captured low fader state; restore/clear capture pending"

drive_state "workspace=mixer
transport=stop
masterGain=1
meterPeak=0.45"
sleep 0.4
capture_window "$pid" "$output_dir/scenario-mixer-main-out-restored.png"
scenario_status="captured restored state; clear capture pending"

drive_state "workspace=mixer
transport=stop
masterGain=1
meterPeak=0.45
clearClip=true"
wait_for_status clipLatched false 8
sleep 0.4
capture_window "$pid" "$output_dir/scenario-mixer-main-out-clipped-cleared.png"
scenario_status="completed normal/live-meter/fader-high/clipped/fader-low/restored/clipped-cleared captures"

drive_state "workspace=mixer
transport=stop
masterGain=1"
launchctl unsetenv SEQUENCER_AI_VISUAL_COMMAND_FILE >/dev/null 2>&1 || true
launchctl unsetenv SEQUENCER_AI_NEW_DOCUMENT_FIXTURE >/dev/null 2>&1 || true
sleep 0.2
