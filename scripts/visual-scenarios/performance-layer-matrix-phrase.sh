#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "$SCRIPT_DIR/peekaboo-common.sh"

output_dir="${PEEKABOO_OUTPUT_DIR:-.meta/multipass/runtime/loops/build/performance-layer-matrix/act/phrase-layer-selector-visual}"
case "$output_dir" in
  /*) ;;
  *) output_dir="$REPO_ROOT/$output_dir" ;;
esac
export PEEKABOO_OUTPUT_DIR="$output_dir"

bundle_id="ai.sequencer.SequencerAI"
app_command_dir="$HOME/Library/Containers/$bundle_id/Data/tmp/sequencer-ai-visual-commands"
run_id="$(basename "$output_dir")"
command_file="${SEQUENCER_AI_VISUAL_COMMAND_FILE:-$app_command_dir/${run_id}-performance-layer-matrix-phrase-command.env}"
case "$command_file" in
  /*) ;;
  *) command_file="$REPO_ROOT/$command_file" ;;
esac
status_file="${command_file}.status"
scenario_status="started; no captures completed yet"
app_path="${SEQUENCER_AI_APP_PATH:-}"
window_bounds="${PERFORMANCE_LAYER_MATRIX_WINDOW_BOUNDS:-120,80,980,720}"
track_count="${PERFORMANCE_LAYER_MATRIX_TRACK_COUNT:-6}"
phrase_count="${PERFORMANCE_LAYER_MATRIX_PHRASE_COUNT:-5}"

write_notes() {
  mkdir -p "$output_dir"
  cat > "$output_dir/scenario-performance-layer-matrix-phrase-notes.md" <<NOTES
# Performance Layer Matrix Phrase Scenario Evidence

Feature worktree: \`${REPO_ROOT}\`
Command file: \`${command_file}\`
Status file: \`${status_file}\`
App path override: \`${app_path:-none}\`
Window bounds: \`${window_bounds}\`
Fixture track count: \`${track_count}\`
Fixture phrase count: \`${phrase_count}\`

This scenario opens the built SequencerAI app directly when
\`SEQUENCER_AI_APP_PATH\` is provided, otherwise through
\`scripts/open-latest-build.sh\`. It creates a new production document, switches
to the Phrase workspace through \`VisualScenarioCommandRunner\`, and captures
the Phrase performance-layer selector states.

Status from this script run: ${scenario_status}.

Captured states:

- \`01-default-phrase-surface.png\`: normal Phrase matrix with the default
  Pattern performance layer selected.
- \`02-layer-selection-surface.png\`: temporary Phrase layer-selection surface,
  including inline Pattern, Note Repeat, and Step Order variants.
- \`03-step-order-break-fold-selected.png\`: normal Phrase matrix after
  selecting the inline Step Order / Break Fold variant.

Each \`.status\` sidecar records the workspace, active Phrase perform layer,
selector visibility, and selected inline variant.
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

show_default_phrase_surface() {
  write_visual_command "workspace=phrase
windowFrame=$window_bounds
phraseMatrixTrackCount=$track_count
phraseMatrixPhraseCount=$phrase_count
phrasePerformLayer=pattern
transport=stop"

  wait_for_status workspace phrase 10
  wait_for_status phraseMatrixRenderedVisible true 10
  wait_for_status phrasePerformLayerMode pattern 10
  wait_for_status phrasePerformLayerSelectorVisible false 10
  wait_for_status phrasePerformLayerVariant none 10
}

show_layer_selection_surface() {
  write_visual_command "workspace=phrase
windowFrame=$window_bounds
phraseMatrixTrackCount=$track_count
phraseMatrixPhraseCount=$phrase_count
phrasePerformLayerSelector=open"

  wait_for_status workspace phrase 10
  wait_for_status phraseMatrixRenderedVisible true 10
  wait_for_status phrasePerformLayerMode pattern 10
  wait_for_status phrasePerformLayerSelectorVisible true 10
}

select_step_order_break_fold_variant() {
  write_visual_command "workspace=phrase
windowFrame=$window_bounds
phraseMatrixTrackCount=$track_count
phraseMatrixPhraseCount=$phrase_count
phrasePerformLayer=stepOrder
phrasePerformLayerVariant=Break Fold"

  wait_for_status workspace phrase 10
  wait_for_status phrasePerformLayerMode stepOrder 10
  wait_for_status phrasePerformLayerVariant "Break Fold" 10
  wait_for_status phrasePerformLayerSelectorVisible false 10
}

mkdir -p "$output_dir"
mkdir -p "$app_command_dir"
rm -f "$command_file" "$status_file"
rm -f "$output_dir"/{01-default-phrase-surface,02-layer-selection-surface,03-step-order-break-fold-selected}.{command.env,png,status}

"$PEEKABOO_BIN" app list --json --no-remote \
  | jq -r --arg app "$APP_NAME" '.data.apps[] | select(.name == $app) | .pid' \
  | while read -r existing_pid; do
    [ -n "$existing_pid" ] && kill "$existing_pid" 2>/dev/null || true
  done
sleep 1

launchctl setenv SEQUENCER_AI_VISUAL_COMMAND_FILE "$command_file" >/dev/null
defaults write "$bundle_id" VisualScenarioCommandFile "$command_file"
export SEQUENCER_AI_VISUAL_COMMAND_FILE="$command_file"

if [ -n "$app_path" ]; then
  if [ ! -d "$app_path" ]; then
    echo "SEQUENCER_AI_APP_PATH does not point to an app bundle: $app_path" >&2
    exit 2
  fi
  open "$app_path" >"$output_dir/app-open.log" 2>&1
else
  (
    cd "$REPO_ROOT"
    scripts/open-latest-build.sh
  ) >"$output_dir/app-open.log" 2>&1
fi

sleep 2

pid="$(latest_app_pid)"
if [ -z "$pid" ]; then
  echo "No $APP_NAME process found for performance layer matrix Phrase scenario." >&2
  exit 2
fi

keep_only_pid "$pid"
ensure_new_document "$pid"

show_default_phrase_surface
sleep 0.8
capture_state "$pid" 01-default-phrase-surface
scenario_status="captured default Phrase surface"

show_layer_selection_surface
sleep 0.8
capture_state "$pid" 02-layer-selection-surface
scenario_status="captured layer selection surface"

select_step_order_break_fold_variant
sleep 0.8
capture_state "$pid" 03-step-order-break-fold-selected
scenario_status="captured Step Order Break Fold selected"

scenario_status="completed performance layer matrix Phrase captures"
sleep 0.2
