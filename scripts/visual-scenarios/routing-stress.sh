#!/usr/bin/env bash
#
# routing-stress.sh — headless audio-routing stress harness.
#
# Launches SequencerAI wired to the SAMPLE-ONLY audio-rich fixture in offline
# manual-rendering mode (no HAL / no mic-TCC prompt), starts the transport, and
# drives a sequence of SAFE sample-only / native mutations through the visual
# command file. After EACH op it checks:
#   - app pid still alive  (dead => CRASH; newest .ips faulting frame captured)
#   - masterPeak from the status file (~ -inf while playing => SILENCE)
# and logs per-op PASS / SILENCE / CRASH to a report under .meta/.
#
# UNATTENDED-SAFE: only sample/native sources are exercised — never third-party
# AUs (their permission modal blocks headless runs). No screenshots/peekaboo.
#
# This is a self-contained audio driver: it launches the app itself (it does
# NOT reuse an already-running instance) so the offline-render pump is the only
# thing pulling the graph and masterPeak reflects real playback.
#
# Usage:
#   scripts/visual-scenarios/routing-stress.sh
#
# Env overrides:
#   ROUTING_STRESS_APP   path to the built SequencerAI binary
#   ROUTING_STRESS_OP_SETTLE  seconds to wait after each op before sampling (default 2)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
FIXTURE_SRC="$REPO_ROOT/docs/fixtures/audio-rich-routing-sampleonly.seqai"

DERIVED="$HOME/Library/Developer/Xcode/DerivedData"
DEFAULT_APP="$(ls -dt "$DERIVED"/SequencerAI-*/Build/Products/Debug/SequencerAI.app/Contents/MacOS/SequencerAI 2>/dev/null | head -1 || true)"
APP="${ROUTING_STRESS_APP:-$DEFAULT_APP}"

OP_SETTLE="${ROUTING_STRESS_OP_SETTLE:-2}"

CONTAINER_TMP="$HOME/Library/Containers/ai.sequencer.SequencerAI/Data/tmp/sequencer-ai-visual-commands"
CMDFILE="$CONTAINER_TMP/routing-stress-cmd.env"
STATUS="$CMDFILE.status"
# The sandboxed app cannot read the repo fixture directly (TCC); copy it into
# the container tmp dir and point the loader at the in-container path.
FIXTURE_IN_CONTAINER="$CONTAINER_TMP/routing-stress-fixture.seqai"

REPORT_DIR="$REPO_ROOT/.meta/multipass/state/build-loops"
REPORT="$REPORT_DIR/routing-stress-report.md"

CRASH_DIR="$HOME/Library/Logs/DiagnosticReports"

if [ -z "$APP" ] || [ ! -x "$APP" ]; then
  echo "SequencerAI binary not found. Build first or set ROUTING_STRESS_APP." >&2
  exit 2
fi
if [ ! -f "$FIXTURE_SRC" ]; then
  echo "Fixture missing: $FIXTURE_SRC" >&2
  exit 2
fi

mkdir -p "$CONTAINER_TMP" "$REPORT_DIR"
cp "$FIXTURE_SRC" "$FIXTURE_IN_CONTAINER"
rm -f "$CMDFILE" "$STATUS"
printf 'transport=stop\nworkspace=mixer\n' > "$CMDFILE"

APP_STDERR="$(mktemp -t routing-stress-app)"

cleanup() {
  pkill -9 -x SequencerAI 2>/dev/null || true
}
trap cleanup EXIT

# --- launch ---------------------------------------------------------------
SEQUENCER_AI_VISUAL_COMMAND_FILE="$CMDFILE" \
SEQUENCER_AI_NEW_DOCUMENT_FIXTURE="$FIXTURE_IN_CONTAINER" \
SEQUENCER_AI_MATERIALIZE_FIXTURE_SAMPLES=1 \
  "$APP" > "$APP_STDERR" 2>&1 &
APP_PID=$!

# wait for the status file (app booted + command runner watching)
boot_deadline=$((SECONDS + 20))
while [ "$SECONDS" -lt "$boot_deadline" ]; do
  [ -f "$STATUS" ] && break
  sleep 0.5
done
if [ ! -f "$STATUS" ]; then
  echo "App never produced a status file; boot failed. stderr:" >&2
  tail -20 "$APP_STDERR" >&2
  exit 3
fi

status_value() {
  awk -F= -v k="$1" '$1==k{print substr($0,index($0,"=")+1); f=1} END{exit f?0:1}' "$STATUS" 2>/dev/null
}

app_alive() { pgrep -x SequencerAI >/dev/null 2>&1; }

newest_crash_frame() {
  local ips
  ips="$(ls -t "$CRASH_DIR"/SequencerAI*.ips 2>/dev/null | head -1 || true)"
  [ -z "$ips" ] && { echo "(no .ips found)"; return; }
  echo "ips=$ips"
  # faulting frame: first AVFAudio/app frame after the exception preprocess
  grep -m1 -E "AVFAudio|SequencerAI" "$ips" 2>/dev/null | sed 's/^[[:space:]]*/    /' || true
  grep -m1 -E "reason:|required condition" "$ips" 2>/dev/null | sed 's/^[[:space:]]*/    /' || true
}

# --- report header --------------------------------------------------------
{
  echo "# Routing Stress Report"
  echo
  echo "- Date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "- App: $APP"
  echo "- Fixture: audio-rich-routing-sampleonly.seqai (sample-only)"
  echo "- Mode: offline manual-rendering (HAL suppressed) + offline-render pump"
  echo "- Op settle: ${OP_SETTLE}s"
  echo
  echo "| # | op | result | masterPeak |"
  echo "|---|----|--------|------------|"
} > "$REPORT"

PASS=0; SILENCE=0; CRASH=0; HANG=0
CRASHED=0

run_op() {
  local idx="$1"; shift
  local label="$1"; shift
  local payload="$1"
  if [ "$CRASHED" = "1" ]; then return; fi

  printf '%s\n' "$payload" > "$CMDFILE"
  sleep "$OP_SETTLE"

  if ! app_alive; then
    CRASH=$((CRASH+1)); CRASHED=1
    local frame; frame="$(newest_crash_frame)"
    echo "| $idx | $label | **CRASH** | n/a |" >> "$REPORT"
    {
      echo
      echo "## CRASH after op $idx ($label)"
      echo '```'
      echo "$frame"
      echo '```'
      echo
      echo "App stderr tail:"
      echo '```'
      tail -25 "$APP_STDERR"
      echo '```'
    } >> "$REPORT"
    echo "op $idx ($label): CRASH"
    return
  fi

  # HANG detection: the command runner rewrites the status file every ~100ms.
  # If its mtime hasn't advanced across the settle window, the app is wedged
  # (e.g. main thread blocked) even though the pid is still alive.
  local age; age=$(( $(date +%s) - $(stat -f %m "$STATUS" 2>/dev/null || echo 0) ))
  if [ "$age" -gt 3 ]; then
    HANG=$((HANG+1)); CRASHED=1
    echo "| $idx | $label | **HANG** | stale ${age}s |" >> "$REPORT"
    {
      echo
      echo "## HANG after op $idx ($label) — status file stale ${age}s (pid alive)"
      echo "App stderr tail:"
      echo '```'
      tail -25 "$APP_STDERR"
      echo '```'
    } >> "$REPORT"
    echo "op $idx ($label): HANG (status stale ${age}s)"
    return
  fi

  local mp; mp="$(status_value masterPeak || echo '?')"
  local verdict
  case "$mp" in
    -inf|"") verdict="SILENCE"; SILENCE=$((SILENCE+1)) ;;
    *)       verdict="PASS"; PASS=$((PASS+1)) ;;
  esac
  echo "| $idx | $label | $verdict | $mp |" >> "$REPORT"
  echo "op $idx ($label): $verdict (masterPeak=$mp)"
}

# --- op sequence (existing command keys only) -----------------------------
# 0: start transport (baseline play)
run_op 0  "transport=play"              $'transport=play\nworkspace=mixer'
run_op 1  "workspace=tracks"            $'transport=play\nworkspace=tracks'
run_op 2  "masterGain=0.5"              $'transport=play\nworkspace=mixer\nmasterGain=0.5'
run_op 3  "masterGain=1.5"             $'transport=play\nworkspace=mixer\nmasterGain=1.5'
run_op 4  "masterGain=1"               $'transport=play\nworkspace=mixer\nmasterGain=1'
run_op 5  "sendAInserts=filter"        $'transport=play\nworkspace=mixer\nsendAInserts=filter'
run_op 6  "sendBInserts=filter"        $'transport=play\nworkspace=mixer\nsendAInserts=filter\nsendBInserts=filter'
run_op 7  "sendA=filter,bitcrusher"    $'transport=play\nworkspace=mixer\nsendAInserts=filter,bitcrusher\nsendBInserts=filter'
run_op 8  "sendInserts=cleared"        $'transport=play\nworkspace=mixer\nsendAInserts=none\nsendBInserts=none'
run_op 9  "addTrack=monoMelodic"       $'transport=play\nworkspace=tracks\naddTrack=monoMelodic'
run_op 10 "addTrack=polyMelodic"       $'transport=play\nworkspace=tracks\naddTrack=polyMelodic'
run_op 11 "addTrack=slice"             $'transport=play\nworkspace=tracks\naddTrack=slice'
run_op 12 "scenesMode=browseEdit"      $'transport=play\nworkspace=scenes\nscenesMode=browseEdit'
run_op 13 "scenesAddFXModal=open"      $'transport=play\nworkspace=scenes\nscenesMode=browseEdit\nscenesAddFXModal=open'
run_op 14 "scenesSelectInsert=0"       $'transport=play\nworkspace=scenes\nscenesMode=browseEdit\nscenesSelectInsert=0'
run_op 15 "scenesAddFXModal=close"     $'transport=play\nworkspace=scenes\nscenesMode=browseEdit\nscenesAddFXModal=close'
run_op 16 "transport=stop"             $'transport=stop\nworkspace=mixer'
run_op 17 "transport=play (restart)"   $'transport=play\nworkspace=mixer'
run_op 18 "transport=stop (final)"     $'transport=stop\nworkspace=mixer'

# --- summary --------------------------------------------------------------
{
  echo
  echo "## Summary"
  echo
  echo "- PASS: $PASS"
  echo "- SILENCE: $SILENCE"
  echo "- CRASH: $CRASH"
  echo "- HANG: $HANG"
  if [ "$CRASHED" = "1" ]; then
    echo "- Run aborted at first crash/hang."
  fi
  echo
  echo "## Command-vocab gaps (block fuller coverage; NOT implemented here)"
  echo
  echo "- per-track native insert add/remove (only send-bus inserts have a key)"
  echo "- routeTrackToBus (assign a track output to a specific mixer bus)"
  echo "- send routing mode A / A+B / B selection per track"
  echo "- remove-track / remove-bus"
} >> "$REPORT"

echo
echo "Report: $REPORT"
echo "PASS=$PASS SILENCE=$SILENCE CRASH=$CRASH HANG=$HANG"
