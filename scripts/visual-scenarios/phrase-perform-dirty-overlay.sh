#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "$SCRIPT_DIR/peekaboo-common.sh"

output_dir="${PEEKABOO_OUTPUT_DIR:-.meta/multipass/runtime/loops/build/phrase-features/evidence/phase-4-dirty-overlay}"
case "$output_dir" in
  /*) ;;
  *) output_dir="$REPO_ROOT/$output_dir" ;;
esac
export PEEKABOO_OUTPUT_DIR="$output_dir"

bundle_id="ai.sequencer.SequencerAI"
app_command_dir="$HOME/Library/Containers/$bundle_id/Data/tmp/sequencer-ai-visual-commands"
run_id="$(basename "$output_dir")"
command_file="${SEQUENCER_AI_VISUAL_COMMAND_FILE:-$app_command_dir/${run_id}-phrase-perform-dirty-overlay-command.env}"
case "$command_file" in
  /*) ;;
  *) command_file="$REPO_ROOT/$command_file" ;;
esac
status_file="${command_file}.status"
scenario_status="started; no captures completed yet"

write_notes() {
  mkdir -p "$output_dir"
  cat > "$output_dir/scenario-phrase-perform-dirty-overlay-notes.md" <<NOTES
# Phrase Perform Dirty Overlay Scenario Evidence

Feature worktree: \`${REPO_ROOT}\`
Command file: \`${command_file}\`
Status file: \`${status_file}\`

This scenario opens the built SequencerAI app through
\`scripts/open-latest-build.sh\`, creates a new production document, switches to
the production Tracks Matrix in Perform mode through \`VisualScenarioCommandRunner\`,
stages one phrase perform overlay cell for \`Phrase A\`, and captures the active
app window with the shared Peekaboo/screencapture helpers.

Status from this script run: ${scenario_status}.

Captured state:

- \`tracks-matrix-dirty-overlay.png\`: Tracks Matrix dirty Capture/Revert strip.
- \`tracks-matrix-capture-chooser.png\`: Capture action opened with the 4x4 phrase-slot chooser.

The sidecar \`tracks-matrix-dirty-overlay.status\` records
\`workspace=tracks\`, \`tracksMode=perform\`,
\`phrasePerformOverlayDirty=true\`, \`phrasePerformOverlayBasisPhraseName=Phrase A\`,
\`stagedCellCount=1\`, and enabled Capture/Revert status.
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

ensure_dirty_overlay_state() {
  write_visual_command "workspace=tracks
tracksMode=perform
phrasePerformOverlay=dirtyOneCell
transport=stop"

  wait_for_status workspace tracks 10
  wait_for_status tracksMode perform 10
  wait_for_status phrasePerformOverlayDirty true 10
  wait_for_status phrasePerformOverlayBasisPhraseName "Phrase A" 10
  wait_for_status stagedCellCount 1 10
  wait_for_status phrasePerformOverlayCanSaveBack true 10
  wait_for_status phrasePerformOverlayCanRevert true 10
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
  echo "No $APP_NAME process found for phrase perform dirty overlay scenario." >&2
  exit 2
fi

keep_only_pid "$pid"
ensure_new_document "$pid"
ensure_dirty_overlay_state

sleep 0.8
cp "$command_file" "$output_dir/tracks-matrix-dirty-overlay.command.env"
capture_window "$pid" "$output_dir/tracks-matrix-dirty-overlay.png"
cp "$status_file" "$output_dir/tracks-matrix-dirty-overlay.status"
scenario_status="captured tracks-matrix-dirty-overlay"

# RETIRED: the tracks Perform view no longer hosts the phrase-perform
# capture chooser (the bespoke perform/capture surface was removed; tracks
# Perform is navigation + selection now). The dirty-overlay + Capture flow
# is covered by the phrase-perform scenarios. The former
# `phrasePerformCapture=open` command and `trackPerformCaptureVisible` status
# assertion are gone, so this capture step is dropped.

scenario_status="completed phrase perform dirty overlay capture"
sleep 0.2
