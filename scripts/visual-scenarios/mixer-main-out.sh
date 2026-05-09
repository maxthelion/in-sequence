#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/peekaboo-common.sh"

output_dir="${PEEKABOO_OUTPUT_DIR:-.claude/state/visual-review}"
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

fader_x="$((x + width - 172))"
fader_unity_y="$((y + height - 250))"
fader_high_y="$((y + height - 300))"
fader_low_y="$((y + height - 130))"

drag_point "$pid" "$fader_x" "$fader_unity_y" "$fader_x" "$fader_high_y"
sleep 0.4
capture_window "$pid" "$output_dir/scenario-mixer-main-out-fader-high.png"

drag_point "$pid" "$fader_x" "$fader_high_y" "$fader_x" "$fader_low_y"
sleep 0.4
capture_window "$pid" "$output_dir/scenario-mixer-main-out-fader-low.png"

drag_point "$pid" "$fader_x" "$fader_low_y" "$fader_x" "$fader_unity_y"
sleep 0.4
capture_window "$pid" "$output_dir/scenario-mixer-main-out-restored.png"

cat > "$output_dir/scenario-mixer-main-out-capture-notes.md" <<'NOTES'
# Mixer Main Out Scenario Evidence

The scenario opens a new document, navigates to the Mixer workspace, captures
the Master Out normal state, drags the combined fader/meter control high and
low, then restores it near unity before the standard window/UI-map capture.

The default new-document fixture has no default audio output, so this scenario
does not deterministically produce moving meter peaks or a latched `CLIP`/`CLR`
state. If UX/IA still needs live meter smoothness or clipped-state evidence from
the production app, the next slice should provide an audible/clipping fixture
document or equivalent capture-only tooling.
NOTES
