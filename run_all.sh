#!/usr/bin/env bash
set -uo pipefail
export PATH="/usr/bin:/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"
cd "$(dirname "$0")"

EXE="/Users/maxwilliams/Library/Developer/Xcode/DerivedData/SequencerAI-bocbvvqbtmzfnoginaalfxcixqzg/Build/Products/Debug/SequencerAI.app/Contents/MacOS/SequencerAI"
OUT_PNG="/tmp/drum-timing-waveform.png"
WAV="$HOME/Library/Containers/ai.sequencer.SequencerAI/Data/tmp/drum-timing/bar-capture.wav"

echo "### capturing one bar ..."
out="$(bash capture_bar.sh "$EXE")"
echo "$out"
BPM="$(printf '%s\n' "$out" | awk -F= '/^BPM=/{print $2}')"
[ -z "$BPM" ] && BPM=120

echo "### waveform peak check ..."
python3 -c "import render_waveform as r,numpy as np; sr,x=r.read_wav('$WAV'); print('peak', float(np.max(np.abs(x))) if len(x) else 0.0)"

echo "### rendering waveform + 16th grid ..."
python3 render_waveform.py "$WAV" "$OUT_PNG" "$BPM" 16
echo "PNG=$OUT_PNG"
