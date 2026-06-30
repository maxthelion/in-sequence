#!/usr/bin/env bash
# Capture 8 bars of the FULL 808 kit while continuously navigating the UI
# (cycling workspace sections) to load the main thread — flam stress test.
set -uo pipefail
export PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"
EXE="$1"; WAV="$2"
T="$HOME/Library/Containers/ai.sequencer.SequencerAI/Data/tmp/drum-timing"; mkdir -p "$T"
CMD="$T/cmd.env"; ST="$CMD.status"; LOG="$T/8bar.log"; NAV="$T/nav.log"
rm -f "$CMD" "$ST" "$WAV"; : > "$NAV"
write_cmd(){ printf '%s\n' "$1" > "$CMD.tmp"; mv "$CMD.tmp" "$CMD"; }

env SEQUENCER_AI_VISUAL_COMMAND_FILE="$CMD" SEQUENCER_AI_HEADLESS_REAL_HAL=1 "$EXE" >"$LOG" 2>&1 &
PID=$!
for _ in $(seq 1 300); do [ -f "$ST" ] && break; sleep 0.1; done
sleep 3
write_cmd "createDefault808=1"
sleep 2.5
write_cmd "masterRender=start:$WAV"
sleep 0.4
write_cmd "transport=play"
sleep 0.6   # let the app's poll read transport=play before nav overwrites it

# Navigate continuously for ~16s (8 bars @120). One section switch every ~0.4s.
SECTIONS=(tracks mixer phrase library song scenes track)
N=40
for k in $(seq 0 $((N-1))); do
  sec=${SECTIONS[$((k % 7))]}
  write_cmd "workspace=$sec"
  echo "$k $sec" >> "$NAV"
  sleep 0.4
done

write_cmd "transport=stop"; sleep 0.2
write_cmd "masterRender=stop"; sleep 0.6
echo "  $(grep -oE 'trackCount=[0-9]+' "$ST" | head -1)  navs=$N"
kill -9 $PID 2>/dev/null
