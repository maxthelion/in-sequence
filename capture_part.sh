#!/usr/bin/env bash
# Capture one bar of a SINGLE-PART 808 kit (real sample + factory clip pattern).
# usage: capture_part.sh <EXE> <out.wav> <tag>   (tag: kick|snare|hat-closed|clap)
set -uo pipefail
export PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"
EXE="$1"; WAV="$2"; TAG="$3"
T="$HOME/Library/Containers/ai.sequencer.SequencerAI/Data/tmp/drum-timing"; mkdir -p "$T"
CMD="$T/cmd.env"; ST="$CMD.status"; LOG="$T/part.log"
rm -f "$CMD" "$ST" "$WAV"
write_cmd(){ printf '%s\n' "$1" > "$CMD.tmp"; mv "$CMD.tmp" "$CMD"; }

env SEQUENCER_AI_VISUAL_COMMAND_FILE="$CMD" SEQUENCER_AI_HEADLESS_REAL_HAL=1 "$EXE" >"$LOG" 2>&1 &
PID=$!
for _ in $(seq 1 300); do [ -f "$ST" ] && break; sleep 0.1; done
sleep 3
write_cmd "createDefault808=$TAG"
sleep 2.5
write_cmd "masterRender=start:$WAV"; sleep 0.4
write_cmd "transport=play"; sleep 2.4
write_cmd "transport=stop"; sleep 0.2
write_cmd "masterRender=stop"; sleep 0.6
echo "  $TAG: $(grep -oE 'trackCount=[0-9]+' "$ST" | head -1)  $(grep -E 'masterPeak=' "$ST" | head -1)"
kill -9 $PID 2>/dev/null
