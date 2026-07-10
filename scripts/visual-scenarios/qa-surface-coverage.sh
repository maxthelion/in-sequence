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
#
# Capture recording and gallery publishing are separate steps. This script only
# records PNGs and notes. Publish them with:
#
#   bug-reporter absorb-captures "$PEEKABOO_OUTPUT_DIR" \
#     --project in-sequence \
#     --source qa-surface-coverage

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
caller_peekaboo_output_dir="${PEEKABOO_OUTPUT_DIR-}"
caller_peekaboo_output_dir_set="${PEEKABOO_OUTPUT_DIR+x}"
source "$SCRIPT_DIR/peekaboo-common.sh"
if [ -n "$caller_peekaboo_output_dir_set" ]; then
  PEEKABOO_OUTPUT_DIR="$caller_peekaboo_output_dir"
else
  unset PEEKABOO_OUTPUT_DIR
fi

default_output_dir="${TMPDIR:-/tmp}/in-sequence-captures/qa-${USER:-user}"
output_dir="${PEEKABOO_OUTPUT_DIR:-$default_output_dir}"
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
runtime_fixture_from_env=false
if [ -n "${SEQUENCER_AI_QA_RUNTIME_FIXTURE:-}" ]; then
  runtime_fixture_path="$SEQUENCER_AI_QA_RUNTIME_FIXTURE"
  runtime_fixture_from_env=true
else
  runtime_fixture_path="$app_command_dir/qa-surface-coverage-fixture.seqai"
fi
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
startup_wait_seconds="${QA_SURFACE_STARTUP_WAIT_SECONDS:-45}"
launch_grace_seconds="${QA_SURFACE_LAUNCH_GRACE_SECONDS:-1}"
default_settle_seconds="${QA_SURFACE_SETTLE_SECONDS:-0.35}"
slow_settle_seconds="${QA_SURFACE_SLOW_SETTLE_SECONDS:-1.5}"
captured_count=0
executed_row_count=0
skipped_rows=()
app_crashed=false
app_crash_after=""
scenario_status="started; no captures completed yet"
visual_command_sequence=0
last_visual_command_id=""
drum_matrix_mounted=false
drum_matrix_fixture=""

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
02a-tracks-selection-actions|workspace=tracks,tracksSelectionMode=on,tracksSelectionCount=1,documentEditCanCopy=true,documentEditCanPaste=true,documentEditCanClear=true,documentEditClipboardDomain=tracks|workspace=tracks;tracksSelectionMode=on;tracksClearSelection=true;tracksSelect=first;tracksPrimeClipboard=true;transport=stop
02ae-create-track-group|workspace=tracks,tracksCreateTrackGroupModalVisible=true|workspace=tracks;tracksSelectionMode=on;tracksClearSelection=true;tracksSelect=first;tracksCreateTrackGroupModal=open;transport=stop
02aa-tracks-filter-drum-kits|workspace=tracks,tracksFilter=drumKits,drumGroup0MemberCount=4,tracksCreateTrackGroupModalVisible=false|workspace=tracks;tracksCreateTrackGroupModal=close;tracksSelectionMode=off;createDefault808=all;tracksFilter=drumKits;transport=stop
02ab-tracks-filter-drum-parts|workspace=tracks,tracksFilter=drumParts,drumGroup0MemberCount=4|workspace=tracks;tracksSelectionMode=off;tracksFilter=drumParts;transport=stop
02ac-tracks-filter-all|workspace=tracks,tracksFilter=all,drumGroup0MemberCount=4|workspace=tracks;tracksSelectionMode=off;tracksFilter=all;transport=stop
02b-tracks-layer-perform-nav|workspace=phrase,phraseWorkspaceTab=layers,performScopeCount=1|workspace=tracks;tracksSelectionMode=on;tracksClearSelection=true;tracksSelect=first;tracksAction=layerPerform;removeDefault808=true;transport=stop
02c-create-track-modal|workspace=tracks,tracksCreateTrackModalVisible=true|workspace=tracks;tracksCreateTrackModal=open;transport=stop
02d-add-drum-group-modal|workspace=tracks,tracksAddDrumGroupModalVisible=true,tracksAddDrumGroupFixture=blank|workspace=tracks;tracksFilter=all;tracksAddDrumGroupModal=open;tracksAddDrumGroupFixture=blank;transport=stop
02da-add-drum-group-populated|workspace=tracks,tracksAddDrumGroupModalVisible=true,tracksAddDrumGroupFixture=populated|workspace=tracks;tracksAddDrumGroupModal=open;tracksAddDrumGroupFixture=populated;transport=stop
02e-add-slice-track-loop-picker|workspace=tracks,tracksAddSliceTrackModalVisible=true|workspace=tracks;tracksAddDrumGroupModal=close;tracksAddSliceTrackModal=open;transport=stop
02f-create-track-sound-step|workspace=tracks,tracksTrackSoundModalVisible=true|workspace=tracks;tracksAddSliceTrackModal=close;tracksTrackSoundModal=open;transport=stop
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
05ba-scenes-edit-overflow|workspace=scenes,scenesMode=browseEdit,sceneEditorFixture=overflow|scenesMode=browseEdit;sceneEditorFixture=overflow;transport=stop
05c-scenes-add-fx|workspace=scenes,scenesMode=browseEdit,sceneEditorFixture=content,scenesAddFXModalVisible=true|scenesMode=browseEdit;sceneEditorFixture=content;scenesAddFXModal=open;transport=stop
05d-scenes-bitcrusher-editor|workspace=scenes,scenesMode=browseEdit,sceneEditorFixture=content,scenesSelectedInsertIndex=1|scenesMode=browseEdit;sceneEditorFixture=content;scenesAddFXModal=close;scenesSelectInsert=1;transport=stop
05e-scenes-browse-fx|workspace=scenes,scenesMode=browseEdit,sceneEditorFixture=browse-content|scenesMode=browseEdit;sceneEditorFixture=browse-content;transport=stop
06-phrase-scenes-perform|workspace=phrase,workspaceMode=perform,phraseWorkspaceTab=scenes|workspace=phrase;workspaceMode=perform;phraseWorkspaceTab=scenes;transport=stop
# 06a RETIRED: the old phrase-scene selector sheet was replaced by the slot
# surface. `phraseSceneSelect=a` still mutates state for legacy command files,
# but there is no `phraseSceneSelectVisible=true` surface to screenshot.
06b-phrase-scenes-perform-slots|workspace=phrase,phraseWorkspaceTab=scenes,phraseSceneViewMode=slots|workspace=phrase;workspaceMode=perform;phraseWorkspaceTab=scenes;phraseSceneSelect=close;phraseSceneViewMode=slots;transport=stop
06ba-phrase-scenes-hard-switch|workspace=phrase,phraseWorkspaceTab=scenes,phraseSceneViewMode=slots|workspace=phrase;workspaceMode=perform;phraseWorkspaceTab=scenes;phraseSceneViewMode=slots;phraseSceneSelect=b;transport=stop
# 06c RETIRED: `phraseSceneMembershipFixture=split` changes runner/store state
# but the current Scenes tab pixels match the base scenes capture exactly.
07-library|workspace=library|workspace=library;transport=stop
08-phrase-layers-pattern|workspace=phrase,phraseWorkspaceTab=layers,phraseMatrixSelectedLayerID=pattern,phraseCellTool=value|phraseMatrixTrackCount=8;phraseMatrixPhraseCount=8;phraseWorkspaceTab=layers;phraseCellTool=value;phraseMatrixLayerID=pattern;transport=stop
09-phrase-layers-mute|workspace=phrase,phraseWorkspaceTab=layers,phraseMatrixSelectedLayerID=mute|phraseMatrixTrackCount=8;phraseMatrixPhraseCount=8;phraseWorkspaceTab=layers;phraseMatrixLayerID=mute;transport=stop
# 10 RETIRED: the old visible VALUE/AUTOMATION tool pills were removed. Cell
# automation now lives in the context menu for a single phrase-layer selection,
# so this command no longer creates a distinct screenshot from row 08.
# 10a/10b RETIRED: density is no longer a phrase perform layer exposed by the
# current matrix surface. The old command wrote density data but the visible
# layer stayed pattern, producing misleading duplicates.
11-phrase-layer-selector-open|workspace=phrase,phraseWorkspaceTab=layers,phrasePerformLayerSelectorVisible=true|phraseMatrixTrackCount=8;phraseMatrixPhraseCount=8;phraseWorkspaceTab=layers;phrasePerformLayerSelector=open;transport=stop
# 12 RETIRED: duplicate of the canonical phrase-scenes capture in row 06.
13-phrase-global-apply|workspace=phrase,phraseWorkspaceTab=globalApply|phraseMatrixTrackCount=8;phraseMatrixPhraseCount=8;phraseWorkspaceTab=globalApply;transport=stop
13a-phrase-global-apply-track-group|workspace=phrase,phraseWorkspaceTab=globalApply,performanceTrackGroupCount=1,phraseGlobalApplyTrackSelectorVisible=true|phraseMatrixTrackCount=8;phraseMatrixPhraseCount=8;performanceTrackGroupFixture=0;phraseWorkspaceTab=globalApply;phraseGlobalApplyTrackSelector=open;transport=stop
13b-phrase-perform-capture|workspace=phrase,workspaceMode=perform,phraseCaptureVisible=true|phraseMatrixTrackCount=8;phraseMatrixPhraseCount=8;workspaceMode=perform;phraseWorkspaceTab=layers;phraseCapture=open;transport=stop
# 14-17 RETIRED: the tracks Perform LAYER surface (TRACK LAYER selector +
# mute/fill/note-repeat layer cells) was removed. Tracks Perform is now
# navigation + selection; layer perform launches scoped from the selection
# (covered by the phrase-perform rows 08-13b). The trackPerformLayer* status
# fields no longer exist.
18-track-detail-steps-clip|workspace=track,selectedTrackGroupName=none,drumPartHeaderVisible=false,documentEditCanCopy=true,documentEditCanClear=true|selectTrackType=monoMelodic;trackFillSource=clip;trackSourceTab=steps-clip;trackSelectStep=2;transport=stop
19-track-sampler-sound-populated|workspace=track,trackSourceTab=sound,trackSourceEditorRenderedVisible=true,trackSourceEditorRenderedTab=sound,selectedTrackSoundDestinationKind=sample|trackSoundSource=sample;trackSourceTab=sound;transport=stop
19a-track-sound-empty|workspace=track,trackSourceTab=sound,trackSourceEditorRenderedVisible=true,trackSourceEditorRenderedTab=sound,selectedTrackSoundDestinationKind=none|trackSoundSource=empty;trackSourceTab=sound;transport=stop
20-track-fill-preview-active|workspace=track,trackSourceTab=steps-clip,selectedTrackFillPreviewActive=true|trackFillSource=clip;trackFillPreview=on;trackSourceTab=steps-clip;transport=stop
# 20a RETIRED: the old `trackFillEngaged` visual command no longer reaches a
# strict `selectedTrackFillEngaged=true` state in the current track detail flow.
# Keep preview/randomize captures until the fill-engage command path is rebuilt.
20b-track-randomize-settings|workspace=track,trackRandomizeSheet=open|trackFillSource=clip;trackSourceTab=source;trackRandomizeSheet=open;transport=stop
20c-track-randomize-rolled|workspace=track,selectedTrackRandomizePersisted=true|trackFillSource=clip;trackSourceTab=source;trackRandomizeRoll=on;transport=stop
21-track-macros-tab|workspace=track,trackSourceTab=macros|trackRandomizeSheet=closed;trackFillSource=clip;trackFillPreview=off;trackSourceTab=macros;transport=stop
22-track-detail-fx|workspace=track,trackSourceTab=fx|trackFillSource=generator;trackSourceTab=fx;transport=stop
22a-track-add-source-empty|workspace=track,trackSourceTab=source,trackSourceEditorRenderedVisible=true,trackSourceEditorRenderedTab=steps-clip,trackSourceAddSourceVisible=true,selectedPatternSourceMode=clip,selectedPatternHasClip=false|trackFillSource=empty;trackSourceTab=source;transport=stop
22aa-track-clip-history|workspace=track,trackSourceTab=history,trackSourceEditorRenderedVisible=true,trackSourceEditorRenderedTab=history|trackFillSource=clip;trackSourceTab=history;trackClipHistoryFixture=selected;transport=stop
22b-track-detail-mixer|workspace=track,trackSourceTab=mixer|trackFillSource=clip;trackSourceTab=mixer;workspaceMode=setup;transport=stop
22ba-track-routing-scene-selector|workspace=track,trackSourceTab=mixer,selectedTrackSceneMembership=sceneA|trackFillSource=clip;trackSourceTab=mixer;trackSceneMembership=sceneA;workspaceMode=setup;transport=stop
22c-track-pitch-layer|workspace=track,trackSourceTab=steps-clip,trackClipLayer=pitch|trackFillSource=clip;trackSourceTab=steps-clip;trackClipLayer=pitch;transport=stop
22ca-track-length-layer|workspace=track,trackSourceTab=steps-clip,trackClipLayer=length|trackFillSource=clip;trackSourceTab=steps-clip;trackClipLayer=length;transport=stop
22d-track-layer-quick-switch|workspace=track,trackClipLayerSwitcher=open|trackFillSource=clip;trackSourceTab=steps-clip;trackClipLayerSwitcher=open;transport=stop
22e-track-generator-trigger-tab|workspace=track,trackSourceTab=source,trackSourceEditorRenderedVisible=true,trackSourceEditorRenderedTab=steps-clip,trackGeneratorStage=trigger,trackSourceGeneratorRenderedStage=trigger|trackFillSource=generator;trackSourceTab=source;trackGeneratorStage=trigger;transport=stop
22f-track-generator-pitch-tab|workspace=track,trackSourceTab=source,trackSourceEditorRenderedVisible=true,trackSourceEditorRenderedTab=steps-clip,trackGeneratorStage=pitch,trackSourceGeneratorRenderedStage=pitch|trackFillSource=generator;trackSourceTab=source;trackGeneratorStage=pitch;transport=stop
22g-track-generator-chord-instrument|workspace=track,selectedTrackType=chord,trackSourceTab=source,trackGeneratorKind=chordGenerator|addTrack=chord;trackFillSource=generator;trackGeneratorKind=chordGenerator;trackSourceTab=source;trackGeneratorStage=pitch;transport=stop
# 22h RETIRED: the chord-following command currently mutates generator state but
# does not expose a distinct visual from 22g in the Source tab.
23-track-slicer|workspace=track,selectedTrackType=slice|addTrack=slice;transport=stop
23a-track-slicer-populated|workspace=track,selectedTrackType=slice,slicerFixture=populated,slicerSliceCount=8,slicerClipStepCount=16,slicerClipActiveStepCount=8,slicerLayer=steps|slicerFixture=populated;slicerLayer=steps;slicerSelectStep=2;workspaceScroll=top;transport=stop
23b-track-slicer-velocity-layer|workspace=track,selectedTrackType=slice,slicerFixture=populated,slicerSliceCount=8,slicerLayer=velocity|slicerFixture=populated;slicerLayer=velocity;workspaceScroll=bottom;transport=stop
23ba-track-slicer-length-layer|workspace=track,selectedTrackType=slice,slicerFixture=populated,slicerSliceCount=8,slicerLayer=gate|slicerFixture=populated;slicerLayer=gate;workspaceScroll=bottom;transport=stop
23c-track-slicer-chance-layer|workspace=track,selectedTrackType=slice,slicerFixture=populated,slicerSliceCount=8,slicerLayer=chance|slicerFixture=populated;slicerLayer=chance;workspaceScroll=bottom;transport=stop
23d-track-slicer-source-tab|workspace=track,selectedTrackType=slice,slicerFixture=populated,slicerTab=source|slicerFixture=populated;slicerLayer=steps;slicerTab=source;workspaceScroll=bottom;transport=stop
23e-track-slicer-slice-tab|workspace=track,selectedTrackType=slice,slicerFixture=populated,slicerTab=slice|slicerFixture=populated;slicerLayer=steps;slicerTab=slice;workspaceScroll=bottom;transport=stop
23f-slice-source-modal|workspace=track,selectedTrackType=slice,slicerFixture=populated,sliceSourceModal=open|slicerFixture=populated;slicerLayer=steps;slicerTab=source;sliceSourceModal=open;transport=stop
23fa-slice-layer-quick-switch|workspace=track,selectedTrackType=slice,slicerFixture=populated,slicerLayerSwitcher=open|sliceSourceModal=close;slicerFixture=populated;slicerTab=steps;slicerLayer=steps;slicerLayerSwitcher=open;workspaceScroll=bottom;transport=stop
23h-track-chord-steps|workspace=track,selectedTrackType=chord,chordTrackRenderedVisible=true,chordTrackRenderedTab=steps,chordTrackRenderedLayer=chord,chordTrackRenderedActiveStepCount=4|selectTrackType=chord;chordTrackFixture=populated;chordTrackTab=steps;chordTrackLayer=chord;chordTrackSelectStep=4;transport=stop
23i-track-chord-chords-tab|workspace=track,selectedTrackType=chord,chordTrackRenderedVisible=true,chordTrackRenderedTab=chords,chordTrackRenderedPaletteSlotCount=4|chordTrackFixture=populated;chordTrackTab=chords;transport=stop
23j-track-chord-inversion-layer|workspace=track,selectedTrackType=chord,chordTrackRenderedVisible=true,chordTrackRenderedTab=steps,chordTrackRenderedLayer=inversion,chordTrackRenderedActiveStepCount=4|chordTrackFixture=populated;chordTrackTab=steps;chordTrackLayer=inversion;chordTrackSelectStep=4;transport=stop
23ja-track-chord-length-layer|workspace=track,selectedTrackType=chord,chordTrackRenderedVisible=true,chordTrackRenderedTab=steps,chordTrackRenderedLayer=length,chordTrackRenderedActiveStepCount=4|chordTrackFixture=populated;chordTrackTab=steps;chordTrackLayer=length;chordTrackSelectStep=4;transport=stop
23k-track-chord-type-layer|workspace=track,selectedTrackType=chord,chordTrackRenderedVisible=true,chordTrackRenderedTab=steps,chordTrackRenderedLayer=chordType,chordTrackRenderedActiveStepCount=4|chordTrackFixture=populated;chordTrackTab=steps;chordTrackLayer=chordType;chordTrackSelectStep=4;transport=stop
23l-track-chord-config|workspace=track,selectedTrackType=chord,chordTrackRenderedVisible=true,chordTrackRenderedTab=steps,chordTrackRenderedConfigVisible=true|chordTrackFixture=populated;chordTrackTab=steps;chordTrackConfig=open;transport=stop
23m-track-chord-progression-chooser|workspace=track,selectedTrackType=chord,chordTrackRenderedVisible=true,chordTrackRenderedTab=steps,chordTrackRenderedProgressionChooserVisible=true|chordTrackFixture=populated;chordTrackTab=steps;chordTrackProgressionChooser=open;transport=stop
# 23g step-edit rotaries: the StepLayerRotaryRow / StepLayerRotaryDial cluster
# lives in ClipContentPreview (the melodic Steps/Clip tab), shared code gated on
# a step selection — it is NOT rendered by the slicer's own SliceStepStrip. So
# the honest capture of the rotary cluster selects a step on a melodic track's
# Steps/Clip grid. (The slicer step-selection command exists too — slicerSelectStep
# — and highlights a slice step, but shows no rotary cluster.)
23g-step-edit-rotaries|workspace=track,selectedTrackType=monoMelodic,trackSourceTab=steps-clip|addTrack=monoMelodic;trackFillSource=clip;trackSourceTab=steps-clip;trackSelectStep=2;transport=stop
24-audio-idle|workspace=track,selectedTrackType=audioInput|audioInputFixture=idle;audioInputAvailableChannels=0;transport=stop
25-audio-live|workspace=track,audioInputArmState=idle|audioInputState=live;transport=stop
26-audio-recording|workspace=track,audioInputArmState=recording|audioInputState=recording;transport=stop
27-audio-loop-ready|workspace=track,audioInputArmState=hasLoop|audioInputState=completed;transport=stop
27a-audio-source-tab|workspace=track,audioInputTab=source|audioInputState=live;audioInputTab=source;transport=stop
27b-audio-mixer-tab|workspace=track,audioInputArmState=hasLoop,audioInputTab=mixer|audioInputState=completed;audioInputTab=mixer;transport=stop
27c-audio-playback|workspace=track,audioInputArmState=hasLoop,audioInputMonitorMode=loop,audioInputTab=source|audioInputState=playback;audioInputTab=source;transport=stop
# 28b RETIRED: the default kit route now lands on the same kit matrix surface
# as 29; keep the explicit kit-matrix row as the canonical capture.
29-drum-kit-matrix|workspace=track,drumKitMatrixRenderedVisible=true|drumPartHeaderFixture=kit;drumKitMatrixFixture=mixed;drumPartHeaderOpenKitView=true;drumKitMatrixCommand=select-step:0:2;transport=stop
29e-drum-kit-matrix-fill-lane|workspace=track,drumKitMatrixRenderedVisible=true,drumKitMatrixRenderedFillMode=fill|drumPartHeaderFixture=kit;drumKitMatrixFixture=mixed;drumPartHeaderOpenKitView=true;drumKitMatrixCommand=fill-mode:fill;transport=stop
# 30 RETIRED: the kit-matrix 16/32 display toggle was removed; the view ignores
# `display-32`, so this row duplicated row 29 while failing its status wait.
29a-drum-kit-fx-tab|workspace=track,drumKitMatrixRenderedKitTab=fx|drumPartHeaderFixture=kit;drumKitMatrixFixture=mixed;drumPartHeaderOpenKitView=true;drumKitMatrixCommand=tab-fx;transport=stop
29b-drum-kit-macros-tab|workspace=track,drumKitMatrixRenderedKitTab=macros|drumPartHeaderFixture=kit;drumKitMatrixFixture=mixed;drumPartHeaderOpenKitView=true;drumKitMatrixCommand=tab-macros;transport=stop
29c-drum-kit-mixer-tab|workspace=track,drumKitMatrixRenderedKitTab=mixer|drumPartHeaderFixture=kit;drumKitMatrixFixture=mixed;drumPartHeaderOpenKitView=true;drumKitMatrixCommand=tab-mixer;drumKitSceneMembership=sceneA;transport=stop
# 29e/29g RETIRED: chooser sub-surfaces are still useful targets, but the
# current full-suite command channel does not reach their strict rendered
# status reliably. Keep 29d as the generator-mode expanded-row coverage.
29d-drum-kit-expanded-generator|workspace=track,drumKitMatrixRenderedVisible=true,drumKitMatrixRenderedRowExpanded=true,drumKitMatrixRenderedExpandedPartIndex=0,drumKitMatrixRenderedExpandedRowTab=stepsClip,drumKitMatrixRenderedExpandedSourceMode=generator|drumPartHeaderFixture=kit;drumKitMatrixFixture=mixed;drumPartHeaderOpenKitView=true;drumKitMatrixCommands=expand-part:0,row-tab-steps,source-generator;transport=stop
29f-drum-kit-capture-save-slot|workspace=track,drumKitMatrixRenderedCaptureOpen=true,drumKitMatrixRenderedSaveSlotPickerVisible=true|drumPartHeaderFixture=kit;drumKitMatrixFixture=mixed;drumPartHeaderOpenKitView=true;drumKitMatrixCommands=open-capture,history-fixture,history-save-open;transport=stop
35-drum-kit-matrix-velocity-layer|workspace=track,drumKitMatrixRenderedLayer=velocity|drumPartHeaderFixture=kit;drumKitMatrixFixture=mixed;drumPartHeaderOpenKitView=true;drumKitMatrixLayer=velocity;transport=stop
35a-drum-kit-matrix-length-layer|workspace=track,drumKitMatrixRenderedLayer=length|drumPartHeaderFixture=kit;drumKitMatrixFixture=mixed;drumPartHeaderOpenKitView=true;drumKitMatrixLayer=length;transport=stop
36-drum-kit-matrix-chance-layer|workspace=track,drumKitMatrixRenderedLayer=chance|drumPartHeaderFixture=kit;drumKitMatrixFixture=mixed;drumPartHeaderOpenKitView=true;drumKitMatrixLayer=chance;transport=stop
# 37 RETIRED: the pattern-realign command no longer reaches slot 2 in a strict
# full-suite pass; keep layer/template/read-only kit rows until rebuilt.
37a-drum-kit-template-target-prompt|workspace=track,drumKitMatrixRenderedTemplateTargetPrompting=true,drumKitMatrixRenderedTemplateTargetCount=0|drumPartHeaderFixture=kit;drumKitMatrixFixture=mixed;drumPartHeaderOpenKitView=true;drumKitMatrixCommand=template-target-prompt;transport=stop
37b-drum-kit-template-target-single|workspace=track,drumKitMatrixRenderedTemplateTargetCount=1,documentEditCanCopy=true,documentEditCanClear=true|drumPartHeaderFixture=kit;drumKitMatrixFixture=mixed;drumPartHeaderOpenKitView=true;drumKitMatrixCommand=template-target:0;transport=stop
38-drum-kit-matrix-template-chooser|workspace=track,drumKitMatrixRenderedTemplateChooserVisible=true,drumKitMatrixRenderedTemplateTargetCount=2,documentEditCanCopy=false,documentEditCanClear=true|drumPartHeaderFixture=kit;drumPartHeaderOpenKitView=true;drumKitMatrixCommands=template-target:0,template-target-add:2,open-template-chooser;transport=stop
39-drum-kit-matrix-generator-readonly|workspace=track,drumKitMatrixRenderedVisible=true|drumPartHeaderFixture=kit;drumKitMatrixFixture=generatorAndReadOnly;drumPartHeaderOpenKitView=true;drumKitMatrixTemplateChooser=close;transport=stop
32-step-order-unassigned|workspace=phrase,workspaceMode=perform,phrasePerformLayerMode=stepOrder,phrasePerformLayerVariant=Identity,stepOrderFixtureState=unassigned|stepOrderFixture=unassigned;workspaceMode=perform;phraseWorkspaceTab=layers;phrasePerformLayer=stepOrder;phrasePerformLayerVariant=Identity;transport=stop
# 33 RETIRED: assigned/on step-order status is reported, but the current
# capture is pixel-identical to 32; keep one step-order surface screenshot.
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
  visual_command_sequence=$((visual_command_sequence + 1))
  last_visual_command_id="qa-surface-coverage-$$-${visual_command_sequence}"
  mkdir -p "$(dirname "$command_file")"
  printf '%s\nvisualCommandID=%s\n' "$state" "$last_visual_command_id" > "${command_file}.tmp"
  mv "${command_file}.tmp" "$command_file"
  action_log "Visual command written: ${state//$'\n'/; }; visualCommandID=${last_visual_command_id}"
}

status_value() {
  local key="$1"
  if [ ! -f "$status_file" ]; then return 1; fi
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
    if [ "$actual" = "$expected" ]; then return 0; fi
    sleep 0.2
  done
  action_log "WARN: timed out waiting for ${key}=${expected}; last value was '${actual}'"
  return 1
}

wait_for_visual_command_ack() {
  local timeout_seconds="${1:-10}"
  [ -n "$last_visual_command_id" ] || return 0
  wait_for_status "visualCommandID" "$last_visual_command_id" "$timeout_seconds"
}

copy_row_evidence() {
  local name="$1"
  mkdir -p "$output_dir"
  cp "$command_file" "$output_dir/${name}.command.env" 2>/dev/null || true
  cp "$status_file" "$output_dir/${name}.status" 2>/dev/null || true
}

record_skipped_row() {
  local name="$1"
  local reason="$2"
  skipped_rows+=("${name} (${reason})")
}

skip_capture_state() {
  local name="$1"
  local reason="$2"
  copy_row_evidence "$name"
  record_skipped_row "$name" "$reason"
  action_log "SKIP: ${name}.png (${reason})"
  scenario_status="skipped ${name}: ${reason}"
}

capture_state() {
  local pid="$1"
  local name="$2"
  local output="$output_dir/${name}.png"
  local window_number=""
  copy_row_evidence "$name"
  window_number="$(status_value "visualCommandWindowNumber" 2>/dev/null || true)"
  if [ -n "$window_number" ] && [ "$window_number" != "-1" ] && [ "$window_number" != "0" ] &&
     screencapture -x -l "$window_number" "$output"; then
    captured_count=$((captured_count + 1))
    action_log "Captured ${name}.png (${captured_count}) from command window ${window_number}"
    scenario_status="captured ${name}"
    return 0
  fi
  if capture_window "$pid" "$output"; then
    captured_count=$((captured_count + 1))
    action_log "Captured ${name}.png (${captured_count})"
    scenario_status="captured ${name}"
    return 0
  else
    record_skipped_row "$name" "capture-window-failed"
    action_log "WARN: failed to capture ${name}.png; status was still copied"
    scenario_status="failed to capture ${name}; continuing"
    return 1
  fi
}

app_is_alive() {
  local pid="$1"
  kill -0 "$pid" 2>/dev/null
}

run_capture_row() {
  local pid="$1"
  local row="$2"
  local name waits payload
  name="$(printf '%s' "$row" | cut -d'|' -f1)"
  waits="$(printf '%s' "$row" | cut -d'|' -f2)"
  payload="$(printf '%s' "$row" | cut -d'|' -f3- | tr ';' '\n')"

  # The track-group chooser is a sheet. Dismiss it in its own acknowledged
  # command before the following phrase Capture sheet is requested; swapping
  # two sheets in one SwiftUI update can strand the second presentation.
  if [ "$name" = "13b-phrase-perform-capture" ]; then
    write_visual_command "windowFrame=$WB
phraseGlobalApplyTrackSelector=close
transport=stop"
    wait_for_visual_command_ack 10
    wait_for_status "phraseGlobalApplyTrackSelectorVisible" "false" 10
  fi

  if [[ "$payload" == *"drumPartHeaderOpenKitView=true"* ]]; then
    local requested_fixture
    requested_fixture="$(printf '%s\n' "$payload" | awk -F= '$1 == "drumKitMatrixFixture" { print $2; exit }')"
    if [ -z "$requested_fixture" ]; then
      requested_fixture="${drum_matrix_fixture:-default}"
    fi

    local prime_payload="drumPartHeaderFixture=kit
drumPartHeaderOpenKitView=true
transport=stop"
    if [ "$requested_fixture" = "generatorAndReadOnly" ]; then
      prime_payload="drumPartHeaderFixture=kit
drumKitMatrixFixture=generatorAndReadOnly
drumPartHeaderOpenKitView=true
transport=stop"
    elif [ "$requested_fixture" = "mixed" ]; then
      prime_payload="drumPartHeaderFixture=kit
drumKitMatrixFixture=mixed
drumPartHeaderOpenKitView=true
transport=stop"
    fi

    if [ "$drum_matrix_mounted" = true ] && [ "$drum_matrix_fixture" = "$requested_fixture" ]; then
      write_visual_command "windowFrame=$WB
drumKitMatrixCommand=reset-for-capture
transport=stop"
      wait_for_visual_command_ack 10
    else
      write_visual_command "windowFrame=$WB
$prime_payload"
      # Mount once per fixture. The row payload below deliberately omits the
      # fixture/open keys so it cannot trigger a second rebuild.
      if wait_for_visual_command_ack 25; then
        drum_matrix_mounted=true
        drum_matrix_fixture="$requested_fixture"
        sleep "$default_settle_seconds"
      fi
    fi

    if [ "$drum_matrix_mounted" = true ] && [ "$drum_matrix_fixture" = "$requested_fixture" ]; then
      payload="$(printf '%s\n' "$payload" | awk -F= '
        $1 != "drumPartHeaderFixture" &&
        $1 != "drumKitMatrixFixture" &&
        $1 != "drumPartHeaderOpenKitView"
      ')"
    fi
  fi

  local wait_failed=false
  local row_wait_seconds=10
  case "$name" in
    *drum-kit-matrix*) row_wait_seconds=25 ;;
  esac

  write_visual_command "windowFrame=$WB
$payload"
  if ! wait_for_visual_command_ack "$row_wait_seconds"; then
    wait_failed=true
  fi

  local IFS=','
  for pair in $waits; do
    if ! wait_for_status "${pair%%=*}" "${pair#*=}" "$row_wait_seconds"; then
      wait_failed=true
    fi
  done
  unset IFS
  if [ "$wait_failed" = true ]; then
    case "${QA_SURFACE_CAPTURE_ON_STATUS_TIMEOUT:-}" in
      1|true|TRUE|yes|YES|on|ON)
        action_log "WARN: capturing ${name}.png after status-timeout because QA_SURFACE_CAPTURE_ON_STATUS_TIMEOUT is set"
        sleep 0.8
        capture_state "$pid" "$name"
        return 0
        ;;
    esac
    skip_capture_state "$name" "status-timeout"
    return 1
  fi

  # Status acknowledgement means the command reached the mounted runner, so
  # ordinary SwiftUI surfaces only need one short render settle. Expanded
  # kit-row detail rows
  # build a drum-group fixture AND render all cold when run standalone, so the
  # expanded-row detail mounts (and observes its visual commands) late — the
  # runner re-fires those posts, so give these rows a longer settle so the
  # intended surface is on screen at capture time. Harness-only timing; no
  # product behaviour changes.
  local settle="$default_settle_seconds"
  case "$name" in
    01-*|01a-*|01b-*|02-*|02a-*|02b-*) settle="$slow_settle_seconds" ;;
    19-*|19a-*|22a-*|22e-*|22f-*|29d-*) settle="$slow_settle_seconds" ;;
    29g-*) settle=1.4 ;;
  esac
  sleep "$settle"
  capture_state "$pid" "$name"
}

count_pngs() {
  local count=0
  local png
  for png in "$output_dir"/*.png; do
    [ -e "$png" ] || continue
    count=$((count + 1))
  done
  printf '%s\n' "$count"
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

ensure_single_document_window() {
  local pid="$1"
  local windows_json
  local document_window_count
  windows_json="$(window_json "$pid")"
  document_window_count="$(
    printf '%s\n' "$windows_json" \
      | jq '[.data.windows[] | select((.window_title // "") != "" and .window_title != "Open")] | length'
  )"
  if [ "$document_window_count" -ne 1 ]; then
    action_log "ERROR: expected one driven document window, found ${document_window_count}"
    printf '%s\n' "$windows_json" \
      | jq -r '.data.windows[] | "window \(.window_id): \(.window_title // "untitled")"' \
      | while IFS= read -r description; do action_log "  ${description}"; done
    return 1
  fi
}

write_notes() {
  mkdir -p "$output_dir"
  {
    echo "# QA Surface Coverage Scenario"
    echo
    echo "Generated by scripts/visual-scenarios/qa-surface-coverage.sh."
    echo "Window bounds: ${WB}."
    echo "Rows executed: ${executed_row_count}."
    echo "PNG captures: ${captured_count}."
    echo "Skipped rows: ${#skipped_rows[@]}."
    echo "Final status: ${scenario_status}."
    if [ "${#skipped_rows[@]}" -gt 0 ]; then
      echo
      echo "Skipped row list:"
      local skipped
      for skipped in "${skipped_rows[@]}"; do
        echo "- ${skipped}"
      done
    fi
    echo
    echo "Every capture is driven through VisualScenarioCommandRunner commands;"
    echo "there are no coordinate clicks. The capture list is the CAPTURES table"
    echo "at the top of the script — one row per screenshot."
    echo
    echo "To publish these captures to the bug-reporter gallery/R2 store, run:"
    echo
    echo "  bug-reporter absorb-captures \"${output_dir}\" --project in-sequence --source qa-surface-coverage"
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
  launchctl unsetenv SEQUENCER_AI_MATERIALIZE_FIXTURE_SAMPLES >/dev/null 2>&1 || true
  launchctl unsetenv LLVM_PROFILE_FILE >/dev/null 2>&1 || true
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

if [ -n "${SEQUENCER_AI_VISUAL_APP_PATH:-}" ]; then
  app_path="$SEQUENCER_AI_VISUAL_APP_PATH"
  : >"$output_dir/app-open.log"
  printf 'using SEQUENCER_AI_VISUAL_APP_PATH=%s\n' "$app_path" >>"$output_dir/app-open.log"
else
  app_path="$(
    cd "$REPO_ROOT"
    scripts/open-latest-build.sh --print 2>"$output_dir/app-open.log"
  )"
fi
printf 'app_path=%s\n' "$app_path" >>"$output_dir/app-open.log"
app_executable="$app_path/Contents/MacOS/$APP_NAME"
if [ ! -x "$app_executable" ]; then
  echo "App executable not found at $app_executable" >&2
  exit 2
fi

# Unsigned/ad-hoc debug builds are not sandboxed. Sending those builds into
# ~/Library/Containers triggers macOS's protected app-data consent dialog on
# every rebuilt signature, which makes unattended capture impossible. Keep
# their command channel in ordinary temp storage; signed sandboxed builds still
# use their own container because the sandbox cannot watch an arbitrary path.
if ! codesign -d --entitlements :- "$app_path" 2>&1 \
  | grep -q 'com.apple.security.app-sandbox'; then
  app_command_dir="${TMPDIR:-/tmp}/in-sequence-visual-commands/qa-${USER:-user}"
  if [ "$command_file_from_env" != true ]; then
    command_file="$app_command_dir/qa-surface-coverage-command.env"
    status_file="${command_file}.status"
  fi
  if [ "$runtime_fixture_from_env" != true ]; then
    runtime_fixture_path="$app_command_dir/qa-surface-coverage-fixture.seqai"
  fi
  printf 'command_storage=ordinary-temp (unsandboxed app)\n' >>"$output_dir/app-open.log"
else
  printf 'command_storage=app-container (sandboxed app)\n' >>"$output_dir/app-open.log"
fi

# A full run starts from a clean output dir so retired/renamed rows never leave
# stale PNGs behind (the gallery shows whatever is in the dir). Filtered runs
# (QA_SURFACE_CAPTURE_FILTER set) only refresh their subset, so they must NOT
# purge the other rows' artifacts.
if [ -z "$capture_filter" ]; then
  rm -f "$output_dir"/*.png "$output_dir"/*.status "$output_dir"/*.command.env
  : > "$output_dir/scenario-actions.log"
fi
mkdir -p "$(dirname "$command_file")"
mkdir -p "$(dirname "$runtime_fixture_path")"
rm -f "$command_file" "$status_file"
cp "$fixture_source_path" "$runtime_fixture_path"

if [ "$command_file_from_env" != true ]; then
  launchctl setenv SEQUENCER_AI_VISUAL_COMMAND_FILE "$command_file" >/dev/null
  defaults write "$bundle_id" VisualScenarioCommandFile "$command_file"
fi
launchctl setenv SEQUENCER_AI_MATERIALIZE_FIXTURE_SAMPLES 1 >/dev/null
export SEQUENCER_AI_VISUAL_COMMAND_FILE="$command_file"
export SEQUENCER_AI_MATERIALIZE_FIXTURE_SAMPLES=1
# Launch through Launch Services so the app receives the normal macOS app
# lifecycle. Invoking the executable directly can exit before SwiftUI creates a
# document window on current macOS builds. Opening the sandboxed fixture as the
# document bypasses the Open chooser and mounts exactly one command runner.
launchctl setenv LLVM_PROFILE_FILE "$output_dir/SequencerAI-%p.profraw" >/dev/null
existing_app_pids="$(pgrep -x "$APP_NAME" || true)"
open -na "$app_path" "$runtime_fixture_path" --args \
  -ApplePersistenceIgnoreState YES \
  -NSQuitAlwaysKeepsWindows NO \
  >>"$output_dir/app-open.log" 2>&1
launched_pid=""
launch_deadline=$((SECONDS + startup_wait_seconds))
while [ "$SECONDS" -lt "$launch_deadline" ]; do
  while IFS= read -r candidate_pid; do
    [ -n "$candidate_pid" ] || continue
    if ! printf '%s\n' "$existing_app_pids" | grep -qx "$candidate_pid"; then
      launched_pid="$candidate_pid"
      break
    fi
  done < <(pgrep -x "$APP_NAME" | sort -nr)
  [ -n "$launched_pid" ] && break
  sleep 0.25
done
if [ -z "$launched_pid" ]; then
  echo "Timed out waiting for $APP_NAME to launch from $app_path." >&2
  exit 1
fi
sleep "$launch_grace_seconds"

pid="$launched_pid"
last_completed_row="startup"

# The fixture is the sole document argument, so no chooser interaction or
# synthetic click is needed before the command runner can acknowledge work.
ensure_document_window "$pid"

# Size the freshly-launched window BEFORE the peekaboo gate. Without saved
# window state the app opens at a tiny default size that peekaboo filters out
# as "window too small", so the gate never sees it. Send the resize first (the
# command file is consumed once the window exists), then confirm it.
write_visual_command "windowFrame=$WB
workspace=phrase
transport=stop"
wait_for_visual_command_ack "$startup_wait_seconds"
wait_for_status "workspace" "phrase" "$startup_wait_seconds"
ensure_single_document_window "$pid"

while IFS= read -r row; do
  [ -n "$row" ] || continue
  # Skip comment lines (e.g. retired-row notes) in the CAPTURES table.
  case "$row" in \#*) continue ;; esac
  if [ -n "$capture_filter" ]; then
    row_name="${row%%|*}"
    [[ "$row_name" == *"$capture_filter"* ]] || continue
  fi
  row_name="${row%%|*}"
  if ! app_is_alive "$pid"; then
    app_crashed=true
    app_crash_after="$last_completed_row"
    scenario_status="APP CRASHED after ${app_crash_after}"
    action_log "$scenario_status"
    break
  fi
  executed_row_count=$((executed_row_count + 1))
  run_capture_row "$pid" "$row" || true
  if ! app_is_alive "$pid"; then
    app_crashed=true
    app_crash_after="$row_name"
    scenario_status="APP CRASHED after ${app_crash_after}"
    action_log "$scenario_status"
    break
  fi
  last_completed_row="$row_name"
done <<< "$CAPTURES"

png_count="$(count_pngs)"
final_exit_status=0
if [ "$app_crashed" = true ]; then
  final_exit_status=1
fi
if [ -z "$capture_filter" ]; then
  if [ "$png_count" -ne "$executed_row_count" ]; then
    final_exit_status=1
    if [ "$app_crashed" != true ]; then
      scenario_status="failed - ${png_count} PNGs for ${executed_row_count} executed rows"
    fi
  fi
  if [ "${#skipped_rows[@]}" -gt 0 ]; then
    final_exit_status=1
  fi
fi

if [ "$final_exit_status" -eq 0 ]; then
  scenario_status="completed - ${captured_count} captures from ${executed_row_count} rows"
  action_log "QA surface coverage complete: ${captured_count} screenshots in ${output_dir}"
  action_log "Publish with: bug-reporter absorb-captures \"${output_dir}\" --project in-sequence --source qa-surface-coverage"
else
  action_log "QA surface coverage FAILED: executed=${executed_row_count} png=${png_count} skipped=${#skipped_rows[@]} status=${scenario_status}"
  if [ "${#skipped_rows[@]}" -gt 0 ]; then
    action_log "Skipped rows:"
    for skipped in "${skipped_rows[@]}"; do
      action_log "  ${skipped}"
    done
  fi
fi

exit "$final_exit_status"
