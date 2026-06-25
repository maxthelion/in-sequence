#!/usr/bin/env bash
# routing-stress.sh — headless self-test rig for live graph-edit operations.
#
# GOAL: DRIVE the routing/mixer graph-edit operations that hang (mute, add
# insert, route, sends, add/remove track) over the file command channel, on a
# REAL HAL engine (headless), and DETECT hangs/crashes/silence automatically —
# no human clicking. It is EXPECTED to catch the current mute + add-insert
# deadlocks; capturing them cleanly with a blocked-stack sample is success.
#
# Design:
#  - Launch the built app directly with the command channel wired, a sample-only
#    fixture, fixture-sample materialization, and SEQUENCER_AI_HEADLESS_REAL_HAL=1
#    so MainAudioGraph skips the offline-render force and runs on the real HAL
#    device (sample-only => no mic prompt). transport=play.
#  - WATCHDOG per command: after each command, confirm (a) the pid is alive AND
#    (b) the .status file mtime advanced within ~2s (the app rewrites status on
#    every loop tick). If neither for HANG_TIMEOUT => HANG: `sample` the pid,
#    extract the blocked/triggered stacks, pkill -9, and continue. If the pid
#    died => CRASH: grab the newest crash report frame.
#  - After each op also read masterPeak (~ -inf while playing => SILENCE).
#  - Drive a combinatorial sequence over transport/mute/insert/route/send/
#    scene/add+remove track. Log per-op PASS/HANG/CRASH/SILENCE + stacks to a
#    report under .meta/.
#
# Does NOT depend on peekaboo-common.sh (no screenshots, no TCC). Each shell
# command is simple (no UI automation).

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
APP_NAME="SequencerAI"
BUNDLE_ID="ai.sequencer.SequencerAI"

# --- tunables ---------------------------------------------------------------
HANG_TIMEOUT="${ROUTING_STRESS_HANG_TIMEOUT:-6}"   # secs to wait for status mtime to advance
STATUS_FRESH_WINDOW=2                               # mtime must be this fresh (secs)
SAMPLE_DURATION=3                                   # `sample` capture seconds

# --- working dirs -----------------------------------------------------------
CONTAINER_TMP="$HOME/Library/Containers/$BUNDLE_ID/Data/tmp/routing-stress"
mkdir -p "$CONTAINER_TMP"
CMD_FILE="$CONTAINER_TMP/cmd.env"
STATUS_FILE="$CMD_FILE.status"
FIXTURE_SRC="$REPO/docs/fixtures/audio-rich-routing-sampleonly.seqai"
FIXTURE_DST="$CONTAINER_TMP/audio-rich-routing-sampleonly.seqai"

REPORT_DIR="$REPO/.meta/routing-stress"
mkdir -p "$REPORT_DIR"
RUN_STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="$REPORT_DIR/run-$RUN_STAMP.md"
APP_LOG="$CONTAINER_TMP/app.stderr.log"

# --- counters ---------------------------------------------------------------
PASS=0; HANG=0; CRASH=0; SILENCE=0
APP_PID=""

log() { printf '%s\n' "$*"; }
report() { printf '%s\n' "$*" >> "$REPORT"; }

cleanup() {
  if [ -n "$APP_PID" ] && kill -0 "$APP_PID" 2>/dev/null; then
    kill -9 "$APP_PID" 2>/dev/null || true
  fi
  pkill -9 -x "$APP_NAME" 2>/dev/null || true
}
trap cleanup EXIT

# --- locate the built executable -------------------------------------------
resolve_exe() {
  local settings build_dir exe
  settings="$(cd "$REPO" && xcodebuild -scheme "$APP_NAME" -configuration Debug \
    -destination 'platform=macOS' -showBuildSettings 2>/dev/null)"
  build_dir="$(printf '%s\n' "$settings" | awk -F' = ' '/ TARGET_BUILD_DIR / {print $2; exit}')"
  if [ -z "$build_dir" ]; then
    return 1
  fi
  exe="$build_dir/$APP_NAME.app/Contents/MacOS/$APP_NAME"
  if [ -x "$exe" ]; then
    printf '%s' "$exe"
    return 0
  fi
  return 1
}

# --- command channel helpers -----------------------------------------------
write_command() {
  # newline-separated key=value; atomic write so the app never reads a partial.
  printf '%s\n' "$1" > "$CMD_FILE.tmp"
  mv "$CMD_FILE.tmp" "$CMD_FILE"
}

status_value() {
  local key="$1"
  [ -f "$STATUS_FILE" ] || return 1
  awk -F= -v key="$key" '$1 == key { print substr($0, index($0, "=") + 1); found=1 } END { exit found ? 0 : 1 }' "$STATUS_FILE"
}

status_mtime() {
  [ -f "$STATUS_FILE" ] || { echo 0; return; }
  stat -f %m "$STATUS_FILE" 2>/dev/null || echo 0
}

# --- diagnostics ------------------------------------------------------------
newest_crash_frame() {
  local crash
  crash="$(ls -t "$HOME/Library/Logs/DiagnosticReports/$APP_NAME"*.ips 2>/dev/null | head -1)"
  if [ -n "$crash" ]; then
    log "  crash report: $crash"
    report "  - crash report: \`$crash\`"
    # Pull the first faulting-thread frames out of the .ips JSON tail.
    grep -m 8 -E '"imageName"|symbol|"name"' "$crash" 2>/dev/null | sed 's/^/      /' || true
    grep -m 12 -E "$APP_NAME|lockGraphLock|lifecycleLock|withLock|prepareTick|semaphore_wait" "$crash" 2>/dev/null \
      | sed 's/^/      /' | tee -a "$REPORT" || true
  else
    report "  - no crash report found"
  fi
}

sample_blocked_stacks() {
  local op="$1" pid="$2"
  local sfile="$CONTAINER_TMP/hang-${op}.sample"
  log "  sampling pid $pid for ${SAMPLE_DURATION}s -> $sfile"
  sample "$pid" "$SAMPLE_DURATION" -file "$sfile" >/dev/null 2>&1 || true
  report "  - sample: \`$sfile\`"
  if [ -f "$sfile" ]; then
    report ""
    report '  blocked/triggered frames:'
    report '  ```'
    grep -nE 'lockGraphLock|lifecycleLock|withLock|prepareTick|semaphore_wait|effectiveMixerMuteState|setTrackMix|setMix|engine.*connect|mutateTrackFXInserts' "$sfile" 2>/dev/null \
      | head -40 | sed 's/^/  /' | tee -a "$REPORT"
    report '  ```'
  fi
}

# --- the watchdog -----------------------------------------------------------
# Args: op-label, command-payload. Returns 0 PASS, 1 HANG, 2 CRASH.
drive() {
  local op="$1" payload="$2"
  local before after deadline now peak verdict="" silent=""

  before="$(status_mtime)"
  write_command "$payload"

  deadline=$(( $(date +%s) + HANG_TIMEOUT ))
  after="$before"
  while :; do
    if ! kill -0 "$APP_PID" 2>/dev/null; then
      verdict="CRASH"; break
    fi
    after="$(status_mtime)"
    now="$(date +%s)"
    # Fresh = advanced past the pre-command mtime AND written recently.
    if [ "$after" -gt "$before" ] && [ $(( now - after )) -le "$STATUS_FRESH_WINDOW" ]; then
      verdict="PASS"; break
    fi
    if [ "$now" -ge "$deadline" ]; then
      verdict="HANG"; break
    fi
    sleep 0.2
  done

  case "$verdict" in
    PASS)
      peak="$(status_value masterPeak 2>/dev/null || echo n/a)"
      # While playing, masterPeak ~ -inf (or very low) => SILENCE.
      if printf '%s' "$peak" | grep -qiE '^-inf|^-1[0-9][0-9]'; then
        silent=" SILENCE(peak=$peak)"
        SILENCE=$((SILENCE+1))
      fi
      PASS=$((PASS+1))
      log "PASS  $op  (peak=$peak)$silent"
      report "- **PASS** \`$op\` — masterPeak=$peak$silent"
      return 0
      ;;
    HANG)
      HANG=$((HANG+1))
      log "HANG  $op  (status stale > ${HANG_TIMEOUT}s) — sampling then killing"
      report ""
      report "- **HANG** \`$op\` — status mtime did not advance within ${HANG_TIMEOUT}s"
      sample_blocked_stacks "$op" "$APP_PID"
      kill -9 "$APP_PID" 2>/dev/null || true
      return 1
      ;;
    CRASH)
      CRASH=$((CRASH+1))
      log "CRASH $op  (pid gone)"
      report ""
      report "- **CRASH** \`$op\` — process exited"
      newest_crash_frame
      return 2
      ;;
  esac
}

wait_for_first_status() {
  local deadline=$(( $(date +%s) + 30 ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    if ! kill -0 "$APP_PID" 2>/dev/null; then
      return 2
    fi
    if [ -f "$STATUS_FILE" ]; then
      return 0
    fi
    sleep 0.3
  done
  return 1
}

# ===========================================================================
# RUN
# ===========================================================================
log "routing-stress: resolving executable..."
EXE="$(resolve_exe)" || { log "FATAL: could not locate built $APP_NAME (build Debug first)."; exit 3; }
log "  exe: $EXE"

cp -f "$FIXTURE_SRC" "$FIXTURE_DST"
rm -f "$CMD_FILE" "$STATUS_FILE"
pkill -9 -x "$APP_NAME" 2>/dev/null || true
sleep 0.5

cat > "$REPORT" <<HEADER
# routing-stress run $RUN_STAMP

- exe: \`$EXE\`
- fixture: \`$FIXTURE_DST\` (sample-only, 7 tracks, 1 bus)
- mode: real HAL headless (SEQUENCER_AI_HEADLESS_REAL_HAL=1), transport=play
- command file: \`$CMD_FILE\`
- hang timeout: ${HANG_TIMEOUT}s; status-fresh window: ${STATUS_FRESH_WINDOW}s

## Per-op results
HEADER

log "routing-stress: launching app on real HAL (headless)..."
SEQUENCER_AI_VISUAL_COMMAND_FILE="$CMD_FILE" \
SEQUENCER_AI_NEW_DOCUMENT_FIXTURE="$FIXTURE_DST" \
SEQUENCER_AI_MATERIALIZE_FIXTURE_SAMPLES=1 \
SEQUENCER_AI_HEADLESS_REAL_HAL=1 \
  "$EXE" >"$APP_LOG" 2>&1 &
APP_PID=$!
log "  pid: $APP_PID"

if ! wait_for_first_status; then
  log "FATAL: app did not produce a status file (see $APP_LOG)"
  report ""
  report "FATAL: no initial status file — app may have crashed at launch."
  tail -20 "$APP_LOG" | sed 's/^/    /'
  exit 4
fi
log "  status channel live."

# Get the engine playing first.
drive "transport-play" "workspace=mixer
transport=play" || true
sleep 1.0
log "initial masterPeak=$(status_value masterPeak 2>/dev/null || echo n/a)"
report ""
report "initial masterPeak (playing): $(status_value masterPeak 2>/dev/null || echo n/a)"
report ""

# Combinatorial sequence. Each entry: label|payload. Ordered so the suspected
# deadlock ops (mute, add-insert) come early; if the app dies the watchdog
# aborts the rest with the run still reported.
run_op() {
  # drive returns: 0 PASS, 1 HANG (app killed), 2 CRASH. Any non-zero means the
  # app is gone/killed, so the sequence should stop — the watchdog already
  # classified and (for HANG) sampled + killed it. Returning the drive status
  # avoids a spurious CRASH classification of the next op against the dead pid.
  drive "$1" "$2"
}

SEQUENCE=(
  "trackMute-0-on|trackMute=0:on"
  "trackMute-0-off|trackMute=0:off"
  "busMute-0-on|busMute=0:on"
  "busMute-0-off|busMute=0:off"
  "trackAddInsert-0-filter|trackAddInsert=0:native-filter"
  "trackAddInsert-1-bitcrusher|trackAddInsert=1:native-bitcrusher"
  "trackRemoveInsert-0|trackRemoveInsert=0:0"
  "masterAddInsert-filter|masterAddInsert=native-filter"
  "routeTrack-1-to-bus0|routeTrackToBus=1:0"
  "routeTrack-1-to-master|routeTrackToBus=1:master"
  "trackSend-2-A|trackSend=2:A=0.7"
  "trackSend-2-AB|trackSend=2:A=0.5,B=0.5"
  "trackSend-2-B|trackSend=2:B=0.9"
  "sceneSwitch-edit|scenesMode=browseEdit"
  "addTrack|addTrack=monoMelodic"
  "removeTrack-last|removeTrack=6"
)

for entry in "${SEQUENCE[@]}"; do
  label="${entry%%|*}"
  payload="${entry#*|}"
  if ! run_op "$label" "$payload"; then
    log "app gone/killed after '$label' (HANG or CRASH) — ending sequence."
    report ""
    report "_Sequence aborted after \`$label\` (app killed by watchdog / crashed)._"
    break
  fi
  sleep 0.5
done

# --- summary ----------------------------------------------------------------
report ""
report "## Summary"
report ""
report "- PASS: $PASS"
report "- HANG: $HANG"
report "- CRASH: $CRASH"
report "- SILENCE (PASS but masterPeak ~= -inf while playing): $SILENCE"

log ""
log "==== routing-stress summary ===="
log "PASS=$PASS HANG=$HANG CRASH=$CRASH SILENCE=$SILENCE"
log "report: $REPORT"

# stop transport / quiesce if still alive (best-effort; ignore races with a
# concurrent watchdog kill).
if kill -0 "$APP_PID" 2>/dev/null; then
  write_command "transport=stop" 2>/dev/null || true
  sleep 0.3
fi
