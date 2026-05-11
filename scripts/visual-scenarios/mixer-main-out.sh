#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/peekaboo-common.sh"

output_dir="${PEEKABOO_OUTPUT_DIR:-.claude/state/visual-review}"
scenario_status="started; no captures completed yet"
write_notes() {
  cat > "$output_dir/scenario-mixer-main-out-capture-notes.md" <<NOTES
# Mixer Main Out Scenario Evidence

The scenario opens a new document, navigates to the Mixer workspace, starts
transport playback, captures the live Master Out meter, drags the combined
fader/meter control high and low, restores it near unity, then clicks \`CLR\`.

For deterministic live evidence, the visual-review environment points new
documents at \`docs/roadmap/mixer-main-out/fixtures/mixer-main-out-live-meter.seqai\`.
That fixture uses the app's starter kick sample as a one-step sample track with
high sample gain so the production master meter moves and the \`CLIP\` latch can
be observed on the real Mixer/Master Out surface.

Status from this script run: ${scenario_status}.

If the run stops after \`scenario-mixer-main-out-normal.png\`, inspect
\`app.stderr.log\` in the same capture folder. The known blocker observed on
2026-05-11 is the app terminating on transport start with
\`player started when in a disconnected state\` from \`AVAudioPlayerNode.play()\`
inside \`SamplePlaybackEngine.play(...)\`.
NOTES
}
trap write_notes EXIT

pid="$(latest_app_pid)"
if [ -z "$pid" ]; then
  echo "No $APP_NAME process found for Mixer Main Out scenario." >&2
  exit 2
fi

keep_only_pid "$pid"
ensure_new_document "$pid"

x="$(window_field "$pid" x)"
y="$(window_field "$pid" y)"
width="$(window_field "$pid" width)"
height="$(window_field "$pid" height)"

# Top navigation: Mixer tab.
click_point "$pid" "$((x + 320))" "$((y + 164))"
sleep 1
capture_window "$pid" "$output_dir/scenario-mixer-main-out-normal.png"
scenario_status="captured normal mixer state; transport live-meter capture pending"

play_x="$((x + 300))"
play_y="$((y + 101))"
fader_x="$((x + width - 172))"
fader_unity_y="$((y + height - 250))"
fader_high_y="$((y + height - 300))"
fader_low_y="$((y + height - 130))"
clear_clip_x="$((x + width - 32))"
clear_clip_y="$((y + height - 76))"

sleep 3
click_point "$pid" "$play_x" "$play_y"
sleep 1.2
capture_window "$pid" "$output_dir/scenario-mixer-main-out-live-meter.png"
scenario_status="captured live meter state; fader-high/clip capture pending"

drag_point "$pid" "$fader_x" "$fader_unity_y" "$fader_x" "$fader_high_y"
sleep 1.2
capture_window "$pid" "$output_dir/scenario-mixer-main-out-fader-high.png"
capture_window "$pid" "$output_dir/scenario-mixer-main-out-clipped.png"
scenario_status="captured high fader and clipped states; low/restore/clear capture pending"

drag_point "$pid" "$fader_x" "$fader_high_y" "$fader_x" "$fader_low_y"
sleep 0.4
capture_window "$pid" "$output_dir/scenario-mixer-main-out-fader-low.png"
scenario_status="captured low fader state; restore/clear capture pending"

drag_point "$pid" "$fader_x" "$fader_low_y" "$fader_x" "$fader_unity_y"
sleep 0.4
capture_window "$pid" "$output_dir/scenario-mixer-main-out-restored.png"
scenario_status="captured restored state; clear capture pending"

click_point "$pid" "$clear_clip_x" "$clear_clip_y"
sleep 0.4
capture_window "$pid" "$output_dir/scenario-mixer-main-out-clipped-cleared.png"
scenario_status="completed normal/live-meter/fader-high/clipped/fader-low/restored/clipped-cleared captures"

click_point "$pid" "$play_x" "$play_y"
sleep 0.2
