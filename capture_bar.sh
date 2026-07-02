#!/usr/bin/env bash
# Headless capture of one bar of the REAL default-808 kit + factory 808 clip,
# built via the app's own session.addDrumGroup path (no synthetic fixture).
set -uo pipefail
export PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"

EXE="$1"
BUNDLE_ID="ai.sequencer.SequencerAI"
CONTAINER_TMP="$HOME/Library/Containers/$BUNDLE_ID/Data/tmp/drum-timing"
mkdir -p "$CONTAINER_TMP"
CMD_FILE="$CONTAINER_TMP/cmd.env"
STATUS_FILE="$CMD_FILE.status"
WAV="$CONTAINER_TMP/bar-capture.wav"
LOG="$CONTAINER_TMP/app.stderr.log"
rm -f "$CMD_FILE" "$STATUS_FILE" "$WAV"

write_cmd() { printf '%s\n' "$1" > "$CMD_FILE.tmp"; mv "$CMD_FILE.tmp" "$CMD_FILE"; }

# No fixture / no materialize: SampleLibraryBootstrap installs the bundled
# starter drum samples on launch, so the real 808 kit resolves to real samples.
env \
  SEQUENCER_AI_VISUAL_COMMAND_FILE="$CMD_FILE" \
  SEQUENCER_AI_HEADLESS_REAL_HAL=1 \
  "$EXE" >"$LOG" 2>&1 &
APP_PID=$!

for _ in $(seq 1 300); do [ -f "$STATUS_FILE" ] && break; sleep 0.1; done
sleep 3   # settle: starter-sample bootstrap + library scan + engine build

write_cmd "createDefault808=1"
sleep 2.5   # kit creation + engine rebuild + sample-voice connect

write_cmd "masterRender=start:$WAV"
sleep 0.4
write_cmd "transport=play"
sleep 2.4    # one bar @120 BPM = 2.0s + margin
write_cmd "transport=stop"
sleep 0.2
write_cmd "masterRender=stop"
sleep 0.6

BPM=$(grep -oE 'bpm=[0-9.]+' "$STATUS_FILE" 2>/dev/null | head -1 | cut -d= -f2)
GRP=$(grep -oE 'selectedTrackGroupName=[^ ]+' "$STATUS_FILE" 2>/dev/null | head -1)
PEAK_LINE=$(grep -E 'masterPeak=' "$STATUS_FILE" 2>/dev/null | head -1)
kill -9 "$APP_PID" 2>/dev/null

echo "WAV=$WAV"
echo "BPM=${BPM:-unknown}"
echo "group=${GRP:-none}  ${PEAK_LINE:-}"
ls -la "$WAV" 2>&1 | head -1
