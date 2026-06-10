#!/usr/bin/env bash
set -euo pipefail

# QA surface coverage: deterministic screenshots of every reachable app
# surface, driven entirely through VisualScenarioCommandRunner's command-file
# protocol. No coordinate clicks: tabs, modes, and fixtures are all commands.
#
# Each capture is one line in the CAPTURES table:
#   name | status waits (comma-separated key=value) | command payload (; → newline)
#
# Adding QA coverage = adding a row. Analysis of the output folder is the only
# step that needs human/LLM judgment.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "$SCRIPT_DIR/peekaboo-common.sh"

output_dir="${PEEKABOO_OUTPUT_DIR:-.meta/multipass/runtime/loops/project/observe/qa-surface-coverage}"
case "$output_dir" in
  /*) ;;
  *) output_dir="$REPO_ROOT/$output_dir" ;;
esac
export PEEKABOO_OUTPUT_DIR="$output_dir"

bundle_id="ai.sequencer.SequencerAI"
app_command_dir="$HOME/Library/Containers/$bundle_id/Data/tmp/sequencer-ai-visual-commands"
command_file="${SEQUENCER_AI_VISUAL_COMMAND_FILE:-$app_command_dir/qa-surface-coverage-command.env}"
case "$command_file" in
  /*) ;;
  *) command_file="$REPO_ROOT/$command_file" ;;
esac
status_file="${command_file}.status"
WB="120,80,1100,780"
captured_count=0
scenario_status="started; no captures completed yet"

# ---------------------------------------------------------------------------
# Capture table. Fields separated by |, newlines in payload encoded as ;
# ---------------------------------------------------------------------------
CAPTURES=$(cat <<'TABLE'
01-phrase|workspace=phrase|phraseMatrixTrackCount=6;phraseMatrixPhraseCount=6;phraseMatrixLayerIndex=0;transport=stop
02-tracks-edit|workspace=tracks,tracksMode=edit|tracksMode=edit;transport=stop
03-tracks-perform|workspace=tracks,tracksMode=perform,trackPerformLayerMode=pattern|tracksMode=perform;trackPerformTrackCount=8;trackPerformLayer=pattern;transport=stop
04-mixer|workspace=mixer|workspace=mixer;transport=stop
05-scenes-browse|workspace=scenes,scenesMode=browseEdit|scenesMode=browseEdit;transport=stop
06-scenes-perform|workspace=scenes,scenesMode=perform|scenesMode=perform;transport=stop
07-library|workspace=library|workspace=library;transport=stop
08-phrase-mute-layer|workspace=phrase,phraseMatrixSelectedLayerID=mute|phraseMatrixTrackCount=6;phraseMatrixPhraseCount=6;phraseMatrixLayerID=mute;transport=stop
09-phrase-transpose-layer|workspace=phrase,phraseMatrixSelectedLayerID=transpose|phraseMatrixTrackCount=6;phraseMatrixPhraseCount=6;phraseMatrixLayerID=transpose;transport=stop
10-phrase-controls-open|workspace=phrase,phraseControlsOpenIndex=0|phraseMatrixTrackCount=6;phraseMatrixPhraseCount=6;phraseControlsOpenIndex=0;transport=stop
11-phrase-perform-overlay|workspace=tracks,tracksMode=perform|tracksMode=perform;trackPerformTrackCount=6;phrasePerformOverlay=dirtyOneCell;transport=stop
12-phrase-layer-selector-open|workspace=phrase,phrasePerformLayerSelectorVisible=true|phraseMatrixTrackCount=6;phraseMatrixPhraseCount=6;phrasePerformLayerSelector=open;transport=stop
13-phrase-volume-layer|workspace=phrase,phrasePerformLayerMode=volume|phraseMatrixTrackCount=6;phraseMatrixPhraseCount=6;phrasePerformLayer=volume;transport=stop
14-tracks-perform-layer-selector|workspace=tracks,trackPerformLayerSelectorVisible=true|tracksMode=perform;trackPerformTrackCount=8;trackPerformLayerSelector=open;transport=stop
15-tracks-perform-mute|workspace=tracks,trackPerformLayerMode=mute|tracksMode=perform;trackPerformTrackCount=8;trackPerformLayer=mute;transport=stop
16-tracks-perform-fill|workspace=tracks,trackPerformLayerMode=fill|tracksMode=perform;trackPerformTrackCount=8;trackPerformLayer=fill;transport=stop
17-tracks-perform-note-repeat|workspace=tracks,trackPerformLayerMode=noteRepeat|tracksMode=perform;trackPerformTrackCount=8;trackPerformLayer=noteRepeat;transport=stop
18-track-source-clip|workspace=track|trackFillSource=clip;trackSourceTab=source;transport=stop
19-track-source-generator|workspace=track|trackFillSource=generator;trackSourceTab=source;transport=stop
20-track-fill-preview-active|workspace=track,selectedTrackFillPreviewActive=true|trackFillSource=clip;trackFillPreview=on;transport=stop
21-track-modifier-tab|workspace=track,trackSourceTab=modifiers|trackFillSource=clip;trackFillPreview=off;trackSourceTab=modifiers;transport=stop
22-track-history-tab|workspace=track,trackSourceTab=history|trackFillSource=generator;trackSourceTab=history;transport=stop
23-track-slicer|workspace=track,selectedTrackType=slice|addTrack=slice;transport=stop
24-audio-idle|workspace=track,selectedTrackType=audioInput|audioInputFixture=idle;audioInputAvailableChannels=0;transport=stop
25-audio-live|workspace=track,audioInputArmState=idle|audioInputState=live;transport=stop
26-audio-recording|workspace=track,audioInputArmState=recording|audioInputState=recording;transport=stop
27-audio-loop-ready|workspace=track,audioInputArmState=hasLoop|audioInputState=completed;transport=stop
28-drum-part|workspace=track,drumPartHeaderVisible=true|drumPartHeaderFixture=kit;drumPartHeaderSelectedIndex=2;transport=stop
29-drum-kit-matrix|workspace=track,drumKitMatrixRenderedVisible=true|drumPartHeaderFixture=kit;drumKitMatrixFixture=mixed;drumPartHeaderOpenKitView=true;drumKitMatrixDisplayStepCount=16;transport=stop
30-drum-kit-matrix-32|workspace=track,drumKitMatrixRenderedVisible=true|drumPartHeaderFixture=kit;drumKitMatrixFixture=mixed;drumPartHeaderOpenKitView=true;drumKitMatrixDisplayStepCount=32;transport=stop
31-drum-kit-routing|workspace=track,drumGroupRoutingEditorRenderedVisible=true|drumPartHeaderFixture=kit;drumPartHeaderOpenKitView=true;drumKitMatrixCommand=openRouting;drumGroupRoutingEditorState=channel;transport=stop
32-step-order-unassigned|workspace=phrase,stepOrderFixtureState=unassigned|stepOrderFixture=unassigned;transport=stop
33-step-order-assigned-on|workspace=phrase,stepOrderFixtureState=assignedOn|stepOrderFixture=assignedOn;transport=stop
34-note-repeat-active|workspace=tracks,selectedNoteRepeatActive=true|tracksMode=perform;trackPerformTrackCount=4;trackPerformLayer=noteRepeat;noteRepeatEnsureSecondClipTrack=true;noteRepeatSelectedTrackIndex=0;noteRepeatSource=clip;noteRepeatInterval=repeat16;noteRepeatAction=press;transport=stop
TABLE
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

write_visual_command() {
  local state="$1"
  mkdir -p "$(dirname "$command_file")"
  printf '%s\n' "$state" > "${command_file}.tmp"
  mv "${command_file}.tmp" "$command_file"
  action_log "Visual command written: ${state//$'\n'/; }"
}

status_value() {
  local key="$1"
  if [ ! -f "$status_file" ]; then return 1; fi
  awk -F= -v key="$key" '$1 == key { print substr($0, index($0, "=") + 1); found=1 } END { exit found ? 0 : 1 }' "$status_file"
}

# Non-fatal: a capture with a stale status key beats an aborted run.
wait_for_status() {
  local key="$1"
  local expected="$2"
  local timeout_seconds="${3:-10}"
  local deadline=$((SECONDS + timeout_seconds))
  local actual=""
  while [ "$SECONDS" -lt "$deadline" ]; do
    actual="$(status_value "$key" 2>/dev/null || true)"
    if [ "$actual" = "$expected" ]; then return 0; fi
    sleep 0.2
  done
  action_log "WARN: timed out waiting for ${key}=${expected}; last value was '${actual}'"
  return 0
}

capture_state() {
  local pid="$1"
  local name="$2"
  mkdir -p "$output_dir"
  cp "$command_file" "$output_dir/${name}.command.env" 2>/dev/null || true
  capture_window "$pid" "$output_dir/${name}.png"
  cp "$status_file" "$output_dir/${name}.status" 2>/dev/null || true
  captured_count=$((captured_count + 1))
  action_log "Captured ${name}.png (${captured_count})"
  scenario_status="captured ${name}"
}

run_capture_row() {
  local pid="$1"
  local row="$2"
  local name waits payload
  name="$(printf '%s' "$row" | cut -d'|' -f1)"
  waits="$(printf '%s' "$row" | cut -d'|' -f2)"
  payload="$(printf '%s' "$row" | cut -d'|' -f3- | tr ';' '\n')"

  write_visual_command "windowFrame=$WB
$payload"

  local IFS=','
  for pair in $waits; do
    wait_for_status "${pair%%=*}" "${pair#*=}" 10
  done
  unset IFS

  sleep 0.8
  capture_state "$pid" "$name"
}

# New-document handling without coordinate clicks: if the launch shows the
# Open panel, send Cmd+N via System Events instead of clicking a guessed point.
ensure_new_document_keyboard() {
  local pid="$1"
  "$PEEKABOO_BIN" app switch --to "$APP_NAME" --no-remote >/dev/null || true
  sleep 0.5

  local title
  title="$(window_json "$pid" | jq -r '.data.windows[0].window_title')"
  if [ "$title" = "Open" ]; then
    osascript -e 'tell application "System Events" to keystroke "n" using command down'
    sleep 1
  fi

  wait_for_window_title "$pid" "Untitled"
}

write_notes() {
  mkdir -p "$output_dir"
  {
    echo "# QA Surface Coverage Scenario"
    echo
    echo "Generated by scripts/visual-scenarios/qa-surface-coverage.sh."
    echo "Window bounds: ${WB}. Captures completed: ${captured_count}."
    echo "Final status: ${scenario_status}."
    echo
    echo "Every capture is driven through VisualScenarioCommandRunner commands;"
    echo "there are no coordinate clicks. The capture list is the CAPTURES table"
    echo "at the top of the script — one row per screenshot."
    echo
    echo "Fixture documents: set SEQUENCER_AI_NEW_DOCUMENT_FIXTURE to a JSON"
    echo "Project file before launching to start from canned project state."
    echo
    echo "Not yet covered (no runner command exists): contained source/modifier"
    echo "picker steps, route editor sheet, AU preset/macro sheets (need a live"
    echo "AU destination), Preferences window."
  } > "$output_dir/qa-surface-coverage-notes.md"
}

cleanup() {
  launchctl unsetenv SEQUENCER_AI_VISUAL_COMMAND_FILE >/dev/null 2>&1 || true
  defaults delete "$bundle_id" VisualScenarioCommandFile >/dev/null 2>&1 || true
  write_notes
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------

mkdir -p "$output_dir"
mkdir -p "$app_command_dir"
rm -f "$command_file" "$status_file"

# Kill every existing instance via pgrep (peekaboo's app list can come back
# empty under AX/TCC pressure, which previously left a stale instance alive
# and competing for the command/status files). Escalate to -9: a beachballed
# instance never services SIGTERM.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  existing_pids="$(pgrep -x "$APP_NAME" || true)"
  [ -z "$existing_pids" ] && break
  for existing_pid in $existing_pids; do
    kill "$existing_pid" 2>/dev/null || true
  done
  sleep 1
  for existing_pid in $existing_pids; do
    kill -9 "$existing_pid" 2>/dev/null || true
  done
done
if pgrep -x "$APP_NAME" >/dev/null; then
  echo "Could not terminate existing $APP_NAME instances." >&2
  exit 2
fi

launchctl setenv SEQUENCER_AI_VISUAL_COMMAND_FILE "$command_file" >/dev/null
defaults write "$bundle_id" VisualScenarioCommandFile "$command_file"
export SEQUENCER_AI_VISUAL_COMMAND_FILE="$command_file"

(cd "$REPO_ROOT" && scripts/open-latest-build.sh) >"$output_dir/app-open.log" 2>&1
sleep 2

pid="$(latest_app_pid)"
if [ -z "$pid" ]; then
  echo "No $APP_NAME process found." >&2
  exit 2
fi

# Exactly one instance may be driving; a second one would race the
# command/status protocol and corrupt every wait.
instance_count="$(pgrep -x "$APP_NAME" | wc -l | tr -d ' ')"
if [ "$instance_count" != "1" ]; then
  echo "Expected exactly one $APP_NAME instance, found ${instance_count}." >&2
  exit 2
fi

keep_only_pid "$pid"
ensure_new_document_keyboard "$pid"

while IFS= read -r row; do
  [ -n "$row" ] || continue
  run_capture_row "$pid" "$row"
done <<< "$CAPTURES"

scenario_status="completed – ${captured_count} captures"
action_log "QA surface coverage complete: ${captured_count} screenshots in ${output_dir}"
