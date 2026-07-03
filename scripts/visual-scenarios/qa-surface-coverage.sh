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
# Set QA_SURFACE_CAPTURE_FILTER to run only rows whose names contain that text.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "$SCRIPT_DIR/peekaboo-common.sh"

output_dir="${PEEKABOO_OUTPUT_DIR:-.meta/multipass/runtime/loops/project/observe/qa-surface-coverage}"
case "$output_dir" in
  /*) ;;
  *) output_dir="$REPO_ROOT/$output_dir" ;;
esac
export PEEKABOO_OUTPUT_DIR="$output_dir"

fixture_path="${SEQUENCER_AI_QA_FIXTURE:-docs/roadmap/song-mode-phrase-looping/fixtures/transport-phrase-navigation.seqai}"
case "$fixture_path" in
  /*) fixture_source_path="$fixture_path" ;;
  *) fixture_source_path="$REPO_ROOT/$fixture_path" ;;
esac

bundle_id="ai.sequencer.SequencerAI"
app_command_dir="$HOME/Library/Containers/$bundle_id/Data/tmp/sequencer-ai-visual-commands"
runtime_fixture_path="${SEQUENCER_AI_QA_RUNTIME_FIXTURE:-$app_command_dir/qa-surface-coverage-fixture.seqai}"
command_file_from_env=false
if [ -n "${SEQUENCER_AI_VISUAL_COMMAND_FILE:-}" ]; then
  command_file="$SEQUENCER_AI_VISUAL_COMMAND_FILE"
  command_file_from_env=true
else
  command_file="$app_command_dir/qa-surface-coverage-command.env"
fi
case "$command_file" in
  /*) ;;
  *) command_file="$REPO_ROOT/$command_file" ;;
esac
status_file="${command_file}.status"
WB="120,80,1100,780"
capture_filter="${QA_SURFACE_CAPTURE_FILTER:-}"
captured_count=0
scenario_status="started; no captures completed yet"

# ---------------------------------------------------------------------------
# Capture table. Fields separated by |, newlines in payload encoded as ;
# ---------------------------------------------------------------------------
CAPTURES=$(cat <<'TABLE'
01-phrase|workspace=phrase|phraseMatrixTrackCount=6;phraseMatrixPhraseCount=6;phraseMatrixLayerIndex=0;transport=stop
# Song view (phrase x track matrix). No phraseMatrix* commands here: any of
# those force navigation back to .phrase (applyPhraseMatrixFixture). The store
# still holds the 6x6 population that 01-phrase set up, so the matrix renders
# fully when run as part of the full suite.
01a-song|workspace=song|workspace=song;transport=stop
# Swing is transient runtime state (no document field), so 01b sets a clearly
# non-zero amount for the transport readout capture and row 02 resets it to 0
# so every later capture keeps the neutral transport.
01b-transport-swing-set|workspace=phrase,swing=0.4|workspace=phrase;swing=0.4;transport=stop
02-tracks-navigator|workspace=tracks,tracksSelectionMode=off,swing=0.0|workspace=tracks;tracksSelectionMode=off;swing=0;transport=stop
02a-tracks-selection-actions|workspace=tracks,tracksSelectionMode=on,tracksSelectionCount=1|workspace=tracks;tracksSelectionMode=on;tracksClearSelection=true;tracksSelect=first;transport=stop
02b-tracks-layer-perform-nav|workspace=phrase,phraseWorkspaceTab=layers,performScopeCount=1|workspace=tracks;tracksSelectionMode=on;tracksClearSelection=true;tracksSelect=first;tracksAction=layerPerform;transport=stop
02c-create-track-modal|workspace=tracks,tracksCreateTrackModalVisible=true|workspace=tracks;tracksCreateTrackModal=open;transport=stop
02d-add-drum-group-modal|workspace=tracks,tracksAddDrumGroupModalVisible=true|workspace=tracks;tracksAddDrumGroupModal=open;transport=stop
02e-add-slice-track-loop-picker|workspace=tracks,tracksAddSliceTrackModalVisible=true|workspace=tracks;tracksAddSliceTrackModal=open;transport=stop
02f-create-track-sound-step|workspace=tracks,tracksTrackSoundModalVisible=true|workspace=tracks;tracksTrackSoundModal=open;transport=stop
# 03/03a RETIRED: the tracks view is now a plain NAVIGATOR (track tiles +
# add tile), not a perform surface. There is no Edit/Perform split, no
# BASIS PHRASE banner, no EDIT SET selection bar, no Perform launcher, and
# no scoped-perform entry from the matrix. Layer/scoped perform lives in
# phrase perform (rows 08-13b) and on the single-track detail page. The
# tracksMode=perform / performScopeTrack commands no longer drive a tracks
# surface, so these rows are dropped.
04-mixer|workspace=mixer|workspace=mixer;transport=stop
05-scenes-browse|workspace=scenes,scenesMode=browseEdit|scenesMode=browseEdit;transport=stop
05a-scenes-edit-empty|workspace=scenes,scenesMode=browseEdit,sceneEditorFixture=empty|scenesMode=browseEdit;sceneEditorFixture=empty;transport=stop
05b-scenes-edit-content|workspace=scenes,scenesMode=browseEdit,sceneEditorFixture=content|scenesMode=browseEdit;sceneEditorFixture=content;transport=stop
05c-scenes-add-fx|workspace=scenes,scenesMode=browseEdit,sceneEditorFixture=content,scenesAddFXModalVisible=true|scenesMode=browseEdit;sceneEditorFixture=content;scenesAddFXModal=open;transport=stop
05d-scenes-bitcrusher-editor|workspace=scenes,scenesMode=browseEdit,sceneEditorFixture=content,scenesSelectedInsertIndex=1|scenesMode=browseEdit;sceneEditorFixture=content;scenesAddFXModal=close;scenesSelectInsert=1;transport=stop
05e-scenes-browse-fx|workspace=scenes,scenesMode=browseEdit,sceneEditorFixture=browse-content|scenesMode=browseEdit;sceneEditorFixture=browse-content;transport=stop
06-phrase-scenes-perform|workspace=phrase,workspaceMode=perform,phraseWorkspaceTab=scenes|workspace=phrase;workspaceMode=perform;phraseWorkspaceTab=scenes;transport=stop
06a-phrase-scene-select|workspace=phrase,phraseWorkspaceTab=scenes,phraseSceneSelectVisible=true|phraseMatrixTrackCount=8;phraseMatrixPhraseCount=8;phraseWorkspaceTab=scenes;phraseSceneSelect=a;transport=stop
06b-phrase-scenes-perform-slots|workspace=phrase,phraseWorkspaceTab=scenes,phraseSceneViewMode=slots|workspace=phrase;workspaceMode=perform;phraseWorkspaceTab=scenes;phraseSceneSelect=close;phraseSceneViewMode=slots;transport=stop
07-library|workspace=library|workspace=library;transport=stop
08-phrase-layers-pattern|workspace=phrase,phraseWorkspaceTab=layers,phraseMatrixSelectedLayerID=pattern,phraseCellTool=value|phraseMatrixTrackCount=8;phraseMatrixPhraseCount=8;phraseWorkspaceTab=layers;phraseCellTool=value;phraseMatrixLayerID=pattern;transport=stop
09-phrase-layers-mute|workspace=phrase,phraseWorkspaceTab=layers,phraseMatrixSelectedLayerID=mute|phraseMatrixTrackCount=8;phraseMatrixPhraseCount=8;phraseWorkspaceTab=layers;phraseMatrixLayerID=mute;transport=stop
10-phrase-layers-automation-tool|workspace=phrase,phraseWorkspaceTab=layers,phraseCellTool=automation|phraseMatrixTrackCount=8;phraseMatrixPhraseCount=8;phraseWorkspaceTab=layers;phraseCellTool=automation;phraseMatrixLayerID=pattern;transport=stop
11-phrase-layer-selector-open|workspace=phrase,phraseWorkspaceTab=layers,phrasePerformLayerSelectorVisible=true|phraseMatrixTrackCount=8;phraseMatrixPhraseCount=8;phraseWorkspaceTab=layers;phrasePerformLayerSelector=open;transport=stop
12-phrase-scenes|workspace=phrase,phraseWorkspaceTab=scenes|phraseMatrixTrackCount=8;phraseMatrixPhraseCount=8;phraseWorkspaceTab=scenes;transport=stop
13-phrase-global-apply|workspace=phrase,phraseWorkspaceTab=globalApply|phraseMatrixTrackCount=8;phraseMatrixPhraseCount=8;phraseWorkspaceTab=globalApply;transport=stop
13a-phrase-global-apply-track-selector|workspace=phrase,phraseWorkspaceTab=globalApply,phraseGlobalApplyTrackSelectorVisible=true|phraseMatrixTrackCount=8;phraseMatrixPhraseCount=8;phraseWorkspaceTab=globalApply;phraseGlobalApplyTrackSelector=open;transport=stop
13b-phrase-perform-capture|workspace=phrase,workspaceMode=perform,phraseCaptureVisible=true|phraseMatrixTrackCount=8;phraseMatrixPhraseCount=8;workspaceMode=perform;phraseWorkspaceTab=layers;phraseCapture=open;transport=stop
13c-phrase-global-apply-selected|workspace=phrase,phraseWorkspaceTab=globalApply,phraseGlobalApplyTrackSelectorVisible=true|phraseMatrixTrackCount=8;phraseCapture=close;phraseWorkspaceTab=globalApply;phraseGlobalApplyTrackSelector=open;phraseGlobalApplySelect=2;transport=stop
# 14-17 RETIRED: the tracks Perform LAYER surface (TRACK LAYER selector +
# mute/fill/note-repeat layer cells) was removed. Tracks Perform is now
# navigation + selection; layer perform launches scoped from the selection
# (covered by the phrase-perform rows 08-13b). The trackPerformLayer* status
# fields no longer exist.
18-track-detail-steps-clip|workspace=track|trackFillSource=clip;trackSourceTab=steps-clip;transport=stop
19-track-detail-sound|workspace=track|trackFillSource=generator;trackSourceTab=sound;transport=stop
19a-track-detail-sound-empty|workspace=track,selectedTrackSoundDestinationKind=none|trackSoundSource=empty;trackSourceTab=sound;transport=stop
20-track-fill-preview-active|workspace=track,selectedTrackFillPreviewActive=true|trackFillSource=clip;trackFillPreview=on;transport=stop
21-track-macros-tab|workspace=track,trackSourceTab=macros|trackFillSource=clip;trackFillPreview=off;trackSourceTab=macros;transport=stop
22-track-detail-fx|workspace=track,trackSourceTab=fx|trackFillSource=generator;trackSourceTab=fx;transport=stop
22b-track-detail-mixer|workspace=track,trackSourceTab=mixer|trackFillSource=clip;trackSourceTab=mixer;workspaceMode=setup;transport=stop
23-track-slicer|workspace=track,selectedTrackType=slice|addTrack=slice;transport=stop
23a-track-slicer-populated|workspace=track,selectedTrackType=slice,slicerFixture=populated,slicerSliceCount=8,slicerClipStepCount=16,slicerClipActiveStepCount=8,slicerLayer=steps|slicerFixture=populated;slicerLayer=steps;workspaceScroll=top;transport=stop
23b-track-slicer-velocity-layer|workspace=track,selectedTrackType=slice,slicerFixture=populated,slicerSliceCount=8,slicerLayer=velocity|slicerFixture=populated;slicerLayer=velocity;workspaceScroll=bottom;transport=stop
23c-track-slicer-chance-layer|workspace=track,selectedTrackType=slice,slicerFixture=populated,slicerSliceCount=8,slicerLayer=chance|slicerFixture=populated;slicerLayer=chance;workspaceScroll=bottom;transport=stop
23d-track-slicer-source-tab|workspace=track,selectedTrackType=slice,slicerFixture=populated,slicerTab=source|slicerFixture=populated;slicerLayer=steps;slicerTab=source;workspaceScroll=bottom;transport=stop
23e-track-slicer-slice-tab|workspace=track,selectedTrackType=slice,slicerFixture=populated,slicerTab=slice|slicerFixture=populated;slicerLayer=steps;slicerTab=slice;workspaceScroll=bottom;transport=stop
23f-slice-source-modal|workspace=track,selectedTrackType=slice,slicerFixture=populated,sliceSourceModal=open|slicerFixture=populated;slicerLayer=steps;slicerTab=source;sliceSourceModal=open;transport=stop
# 23g step-edit rotaries: the StepLayerRotaryRow / StepLayerRotaryDial cluster
# lives in ClipContentPreview (the melodic Steps/Clip tab), shared code gated on
# a step selection — it is NOT rendered by the slicer's own SliceStepStrip. So
# the honest capture of the rotary cluster selects a step on a melodic track's
# Steps/Clip grid. (The slicer step-selection command exists too — slicerSelectStep
# — and highlights a slice step, but shows no rotary cluster.)
23g-step-edit-rotaries|workspace=track,trackSourceTab=steps-clip|sliceSourceModal=close;trackFillSource=clip;trackSourceTab=steps-clip;trackSelectStep=2;transport=stop
24-audio-idle|workspace=track,selectedTrackType=audioInput|audioInputFixture=idle;audioInputAvailableChannels=0;transport=stop
25-audio-live|workspace=track,audioInputArmState=idle|audioInputState=live;transport=stop
26-audio-recording|workspace=track,audioInputArmState=recording|audioInputState=recording;transport=stop
27-audio-loop-ready|workspace=track,audioInputArmState=hasLoop|audioInputState=completed;transport=stop
27a-audio-source-tab|workspace=track,audioInputTab=source|audioInputState=live;audioInputTab=source;transport=stop
27b-audio-mixer-tab|workspace=track,audioInputArmState=hasLoop,audioInputTab=mixer|audioInputState=completed;audioInputTab=mixer;transport=stop
27c-audio-playback|workspace=track,audioInputArmState=hasLoop,audioInputMonitorMode=loop,audioInputTab=source|audioInputState=playback;audioInputTab=source;transport=stop
28b-drum-track-default-kit|workspace=track,drumPartHeaderVisible=true,drumTrackDefaultView=kitMatrix,drumKitMatrixRenderedVisible=true|drumPartHeaderFixture=kit;drumPartHeaderSelectedIndex=2;transport=stop
29-drum-kit-matrix|workspace=track,drumKitMatrixRenderedVisible=true,drumTrackDefaultView=kitMatrix,drumKitMatrixRenderedGroupPatternSlot=mixed|drumPartHeaderFixture=kit;drumKitMatrixFixture=mixed;drumPartHeaderOpenKitView=true;drumKitMatrixDisplayStepCount=16;transport=stop
30-drum-kit-matrix-32|workspace=track,drumKitMatrixRenderedVisible=true,drumKitMatrixRenderedDisplayStepCount=32|drumPartHeaderFixture=kit;drumKitMatrixFixture=mixed;drumPartHeaderOpenKitView=true;drumKitMatrixDisplayStepCount=32;transport=stop
31-drum-kit-routing|workspace=track,drumGroupRoutingEditorRenderedVisible=true|drumPartHeaderFixture=kit;drumPartHeaderOpenKitView=true;drumKitMatrixCommand=openRouting;drumGroupRoutingEditorState=channel;transport=stop
29a-drum-kit-fx-tab|workspace=track,drumKitMatrixRenderedVisible=true,drumKitMatrixRenderedKitTab=fx|drumPartHeaderFixture=kit;drumKitMatrixFixture=mixed;drumPartHeaderOpenKitView=true;drumKitMatrixCommand=tab-fx;transport=stop
29b-drum-kit-macros-tab|workspace=track,drumKitMatrixRenderedVisible=true,drumKitMatrixRenderedKitTab=macros|drumPartHeaderFixture=kit;drumKitMatrixFixture=mixed;drumPartHeaderOpenKitView=true;drumKitMatrixCommand=tab-macros;transport=stop
29c-drum-kit-mixer-tab|workspace=track,drumKitMatrixRenderedVisible=true,drumKitMatrixRenderedKitTab=mixer|drumPartHeaderFixture=kit;drumKitMatrixFixture=mixed;drumPartHeaderOpenKitView=true;drumKitMatrixCommand=tab-mixer;transport=stop
29d-drum-kit-fx-chooser|workspace=track,drumKitMatrixRenderedKitFXChooserVisible=true|drumPartHeaderFixture=kit;drumKitMatrixFixture=mixed;drumPartHeaderOpenKitView=true;drumKitMatrixCommands=tab-fx,open-kit-fx-chooser;transport=stop
29e-drum-kit-capture|workspace=track,drumKitMatrixRenderedCaptureOpen=true|drumPartHeaderFixture=kit;drumKitMatrixFixture=mixed;drumPartHeaderOpenKitView=true;drumKitMatrixCommands=close-kit-fx-chooser,open-capture;transport=stop
29f-drum-kit-capture-save-slot|workspace=track,drumKitMatrixRenderedSaveSlotPickerVisible=true|drumPartHeaderFixture=kit;drumKitMatrixFixture=mixed;drumPartHeaderOpenKitView=true;drumKitMatrixCommands=close-kit-fx-chooser,open-capture,history-save-open;transport=stop
29g-drum-kit-expanded-row|workspace=track,drumKitMatrixRenderedRowExpanded=true,drumKitMatrixRenderedExpandedRowTab=sound|drumPartHeaderFixture=kit;drumKitMatrixFixture=mixed;drumPartHeaderOpenKitView=true;drumKitMatrixCommands=close-kit-fx-chooser,expand-part:0,row-tab-sound;transport=stop
35-drum-kit-matrix-velocity-layer|workspace=track,drumKitMatrixRenderedLayer=velocity|drumPartHeaderFixture=kit;drumKitMatrixFixture=mixed;drumPartHeaderOpenKitView=true;drumKitMatrixLayer=velocity;transport=stop
36-drum-kit-matrix-chance-layer|workspace=track,drumKitMatrixRenderedLayer=chance|drumPartHeaderFixture=kit;drumKitMatrixFixture=mixed;drumPartHeaderOpenKitView=true;drumKitMatrixLayer=chance;transport=stop
37-drum-kit-matrix-pattern-realign|workspace=track,drumKitMatrixRenderedGroupPatternSlot=2|drumPartHeaderFixture=kit;drumKitMatrixFixture=mixed;drumPartHeaderOpenKitView=true;drumKitMatrixPattern=2;transport=stop
38-drum-kit-matrix-template-chooser|workspace=track,drumKitMatrixRenderedTemplateChooserVisible=true|drumPartHeaderFixture=kit;drumPartHeaderOpenKitView=true;drumKitMatrixTemplateChooser=open;transport=stop
39-drum-kit-matrix-generator-readonly|workspace=track,drumKitMatrixRenderedVisible=true|drumPartHeaderFixture=kit;drumKitMatrixFixture=generatorAndReadOnly;drumPartHeaderOpenKitView=true;drumKitMatrixTemplateChooser=close;transport=stop
32-step-order-unassigned|workspace=phrase,stepOrderFixtureState=unassigned|stepOrderFixture=unassigned;phrasePerformLayer=stepOrder;transport=stop
33-step-order-assigned-on|workspace=phrase,stepOrderFixtureState=assignedOn|stepOrderFixture=assignedOn;phrasePerformLayer=stepOrder;transport=stop
# 34 RETIRED: note-repeat runtime engagement was driven from the removed
# tracks-matrix note-repeat layer surface (noteRepeatAction=press). Note
# repeat is now a scoped/phrase-perform concern; tracks Perform no longer
# engages it, so the selectedNoteRepeatActive=true capture cannot be driven
# here.
40-library-global|workspace=library,libraryCategory=drumKits|workspace=library;libraryCategory=drumKits;transport=stop
41-library-pool|workspace=library,libraryFixture=pool,libraryPoolCount=4|workspace=library;libraryFixture=pool;libraryCategory=drumKits;transport=stop
42-library-recordings-populated|workspace=library,libraryCategory=recordings,libraryRecordingsCount=2|workspace=library;libraryFixture=recordings;libraryCategory=recordings;transport=stop
# 43/44: the two creation-seed categories. AU Instruments lists the live
# component scan (plus the rescan header); Generators lists the project's
# default generator pool. Both render per-row create-track (+) affordances.
43-library-au-instruments|workspace=library,libraryCategory=auInstruments|workspace=library;libraryCategory=auInstruments;transport=stop
44-library-generators|workspace=library,libraryCategory=generators|workspace=library;libraryCategory=generators;transport=stop
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
  cp "$status_file" "$output_dir/${name}.status" 2>/dev/null || true
  if capture_window "$pid" "$output_dir/${name}.png"; then
    captured_count=$((captured_count + 1))
    action_log "Captured ${name}.png (${captured_count})"
    scenario_status="captured ${name}"
  else
    action_log "WARN: failed to capture ${name}.png; status was still copied"
    scenario_status="failed to capture ${name}; continuing"
  fi
}

run_capture_row() {
  local pid="$1"
  local row="$2"
  local name waits payload
  name="$(printf '%s' "$row" | cut -d'|' -f1)"
  waits="$(printf '%s' "$row" | cut -d'|' -f2)"
  payload="$(printf '%s' "$row" | cut -d'|' -f3- | tr ';' '\n')"

  if [[ "$name" == *drum-kit-matrix* ]] &&
     [[ "$payload" != *"drumKitMatrixCommand=openRouting"* ]] &&
     [[ "$payload" != *"drumKitMatrixCommand=open-routing"* ]]; then
    write_visual_command "windowFrame=$WB
drumKitMatrixCommand=closeRouting
transport=stop"
    wait_for_status "drumKitMatrixRenderedRoutingEditorVisible" "false" 10
  fi

  write_visual_command "windowFrame=$WB
$payload"

  local IFS=','
  for pair in $waits; do
    wait_for_status "${pair%%=*}" "${pair#*=}" 10
  done
  unset IFS

  # Most surfaces render well within 0.8s. The expanded kit-row detail rows
  # build a drum-group fixture AND render all cold when run standalone, so the
  # expanded-row detail mounts (and observes its visual commands) late — the
  # runner re-fires those posts, so give these rows a longer settle so the
  # intended surface is on screen at capture time. Harness-only timing; no
  # product behaviour changes.
  local settle=0.8
  case "$name" in
    29g-*) settle=2.8 ;;
  esac
  sleep "$settle"
  capture_state "$pid" "$name"
}

ensure_document_window() {
  local pid="$1"
  # Generous deadline: a fresh build re-prompts for mic permission (the ad-hoc
  # code signature changes every rebuild, so TCC re-asks), and macOS forbids
  # synthetic clicks on that dialog — so an operator may need to click Allow
  # before warm-up can finish and the document window appears. See
  # docs/bugs/.../qa-capture-mic-permission-workaround.
  local deadline=$((SECONDS + 45))
  local title=""
  while [ "$SECONDS" -lt "$deadline" ]; do
    title="$(window_json "$pid" | jq -r '.data.windows[0].window_title // ""')"
    if [ -n "$title" ] && [ "$title" != "Open" ]; then
      return 0
    fi
    sleep 0.5
  done

  echo "Timed out waiting for a document window; last title was '$title'." >&2
  return 1
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
    echo "Fixture document: ${runtime_fixture_path}"
    echo "Set SEQUENCER_AI_QA_FIXTURE to override the source fixture."
    echo
    echo "Not yet covered (no runner command exists): contained source/modifier"
    echo "picker steps, route editor sheet, AU preset/macro sheets (need a live"
    echo "AU destination), Preferences window."
  } > "$output_dir/qa-surface-coverage-notes.md"
}

cleanup() {
  # Never strand a driven instance: reset the transport, then quit the app.
  # (The note-repeat release cleanup was retired with the tracks-matrix
  # note-repeat surface — note repeat is no longer engaged from here.)
  write_visual_command "transport=stop" 2>/dev/null || true
  sleep 2
  if [ -n "${pid:-}" ]; then
    kill "$pid" 2>/dev/null || true
    sleep 1
    kill -9 "$pid" 2>/dev/null || true
  elif [ -n "${launched_pid:-}" ]; then
    kill "$launched_pid" 2>/dev/null || true
    sleep 1
    kill -9 "$launched_pid" 2>/dev/null || true
  fi
  if [ "$command_file_from_env" != true ]; then
    launchctl unsetenv SEQUENCER_AI_VISUAL_COMMAND_FILE >/dev/null 2>&1 || true
    launchctl unsetenv SEQUENCER_AI_NEW_DOCUMENT_FIXTURE >/dev/null 2>&1 || true
  fi
  if [ "$command_file_from_env" != true ]; then
    defaults delete "$bundle_id" VisualScenarioCommandFile >/dev/null 2>&1 || true
  fi
  write_notes
}
trap cleanup EXIT

# ---------------------------------------------------------------------------
# Run
# ---------------------------------------------------------------------------

mkdir -p "$output_dir"
# A full run starts from a clean output dir so retired/renamed rows never leave
# stale PNGs behind (the gallery shows whatever is in the dir). Filtered runs
# (QA_SURFACE_CAPTURE_FILTER set) only refresh their subset, so they must NOT
# purge the other rows' artifacts.
if [ -z "$capture_filter" ]; then
  rm -f "$output_dir"/*.png "$output_dir"/*.status "$output_dir"/*.command.env
fi
mkdir -p "$(dirname "$command_file")"
mkdir -p "$(dirname "$runtime_fixture_path")"
rm -f "$command_file" "$status_file"
cp "$fixture_source_path" "$runtime_fixture_path"

if [ "$command_file_from_env" != true ]; then
  launchctl setenv SEQUENCER_AI_VISUAL_COMMAND_FILE "$command_file" >/dev/null
  launchctl setenv SEQUENCER_AI_NEW_DOCUMENT_FIXTURE "$runtime_fixture_path" >/dev/null
  defaults write "$bundle_id" VisualScenarioCommandFile "$command_file"
fi
export SEQUENCER_AI_VISUAL_COMMAND_FILE="$command_file"
export SEQUENCER_AI_NEW_DOCUMENT_FIXTURE="$runtime_fixture_path"

app_path="$(
  cd "$REPO_ROOT"
  scripts/open-latest-build.sh --print 2>"$output_dir/app-open.log"
)"
printf 'app_path=%s\n' "$app_path" >>"$output_dir/app-open.log"
app_executable="$app_path/Contents/MacOS/$APP_NAME"
if [ ! -x "$app_executable" ]; then
  echo "App executable not found at $app_executable" >&2
  exit 2
fi
"$app_executable" "$runtime_fixture_path" >>"$output_dir/app-open.log" 2>&1 &
launched_pid="$!"
sleep 3

pid="$launched_pid"

# Size the freshly-launched window BEFORE the peekaboo gate. Without saved
# window state the app opens at a tiny default size that peekaboo filters out
# as "window too small", so the gate never sees it. Send the resize first (the
# command file is consumed once the window exists), then confirm it.
write_visual_command "windowFrame=$WB
workspace=phrase
transport=stop"
ensure_document_window "$pid"
wait_for_status "workspace" "phrase" 15

while IFS= read -r row; do
  [ -n "$row" ] || continue
  # Skip comment lines (e.g. retired-row notes) in the CAPTURES table.
  case "$row" in \#*) continue ;; esac
  if [ -n "$capture_filter" ]; then
    row_name="${row%%|*}"
    [[ "$row_name" == *"$capture_filter"* ]] || continue
  fi
  run_capture_row "$pid" "$row"
done <<< "$CAPTURES"

scenario_status="completed – ${captured_count} captures"
action_log "QA surface coverage complete: ${captured_count} screenshots in ${output_dir}"
