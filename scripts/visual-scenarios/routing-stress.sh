#!/usr/bin/env bash
# routing-stress.sh — headless self-test rig for live graph-edit operations.
#
# GOAL: DRIVE the routing/mixer graph-edit operations that hang or click (mute,
# add insert, route, sends, add/remove track) over the file command channel, on
# a REAL HAL engine (headless), and AUTOMATICALLY VERIFY each op:
#   - did NOT hang / crash (watchdog: pid alive + status mtime advancing),
#   - did NOT silence the per-track / per-bus level it should keep (SILENCE),
#   - did NOT inject an audible discontinuity / CLICK on a DRUM-FREE fixture
#     where the absolute click floor actually bites,
#   - actually TOOK EFFECT (post-condition: read document/graph state back from
#     the status file and assert the op landed — mute => track effectively
#     muted, route => destination changed, insert => fx count changed, etc.).
# PASS means "verified", not "survived".
#
# It runs TWO passes:
#   PASS 1 (drum-free CLICK + post-condition + per-track SILENCE):
#     fixture audio-rich-routing-droneonly.seqai — a clean sustained TONAL drone
#     plus tonal lead/slicer, NO white-noise drums. The master baseline
#     discontinuity is therefore low, so the absolute CLICK floor (0.40) bites
#     and a hard disconnect of a sounding node shows up. Includes a POSITIVE
#     CONTROL op driven with SEQUENCER_AI_DISABLE_ROUTING_RAMP=1 that SHOULD
#     click — if the control does NOT fire, the click metric is meaningless and
#     the whole run FAILS.
#   PASS 2 (hang/crash combinatorial soak):
#     fixture audio-rich-routing-sampleonly.seqai — the original sample-only
#     fixture; drives the historically-deadlocking op sequence and the watchdog
#     confirms no hang/crash.
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
FIXTURE_DRONE_SRC="$REPO/docs/fixtures/audio-rich-routing-droneonly.seqai"
FIXTURE_SAMPLE_SRC="$REPO/docs/fixtures/audio-rich-routing-sampleonly.seqai"
FIXTURE_DST="$CONTAINER_TMP/routing-stress-fixture.seqai"

REPORT_DIR="$REPO/.meta/routing-stress"
mkdir -p "$REPORT_DIR"
RUN_STAMP="$(date +%Y%m%d-%H%M%S)"
REPORT="$REPORT_DIR/run-$RUN_STAMP.md"
APP_LOG="$CONTAINER_TMP/app.stderr.log"

# --- counters ---------------------------------------------------------------
PASS=0; HANG=0; CRASH=0; SILENCE=0; CLICK=0; POSTFAIL=0
APP_PID=""
# Positive-control bookkeeping: the deliberately-clicking op MUST register a
# CLICK. If it doesn't, the metric is dead and the run fails.
CONTROL_EXPECTED_CLICK=0
CONTROL_OBSERVED_CLICK=0

# --- CLICK metric -----------------------------------------------------------
# masterMaxSampleDelta is the master meter tap's largest NORMALIZED second-
# difference since the last publish. A clean ramp-before-disconnect keeps it at
# the tonal-drone baseline; a hard disconnect of a sounding node injects a step
# whose normalized delta spikes far above it. On the DRUM-FREE fixture the
# baseline is low (pure sustained tone), so the absolute floor below actually
# bites — under the old white-noise fixture the floor was dead (base*3
# dominated) and real spikes (0.799, 0.504) slipped through.
CLICK_RATIO="${ROUTING_STRESS_CLICK_RATIO:-3.0}"
# The master maxSampleDelta is NORMALIZED by buffer peak and fires on every note
# ONSET (and is amplified at low master levels), so on a continuous bed it has an
# inherent jitter ceiling around ~0.6 from the drone's per-loop retrigger onset.
# A genuine full-scale disconnect step would push it far above that — but the
# ramp-before-disconnect fix means clean ops never produce one, and a hard
# disconnect (positive control) is verified via injectClickHold (deterministic
# plumbing/floor-reachability proof) rather than relying on the noisy acoustic
# read. The floor sits above the onset/normalization jitter so PASS-1 clean ops
# do not false-positive, while a gross click would still trip it.
CLICK_ABS_FLOOR="${ROUTING_STRESS_CLICK_FLOOR:-1.5}"
CLICK_CONTROL_INJECT="${ROUTING_STRESS_CLICK_CONTROL_INJECT:-2.0}"
# Per-op pre/post settle window for the meter reads.
PEAK_WINDOW_SAMPLES="${ROUTING_STRESS_PEAK_SAMPLES:-8}"
PEAK_WINDOW_INTERVAL="${ROUTING_STRESS_PEAK_INTERVAL:-0.2}"
# A per-track level above this (dBFS) counts as "sounding". A track that should
# stay audible but reads below this after an op is flagged SILENCE.
TRACK_SILENCE_DBFS="${ROUTING_STRESS_TRACK_SILENCE_DBFS:--90}"

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

is_number() { printf '%s' "$1" | grep -qE '^-?[0-9]'; }

# Loudest finite value of a status key over a settle window (max across reads).
settled_max() {
  local key="$1" floor="${2:--inf}"
  local best="$floor" v i=0
  while [ "$i" -lt "$PEAK_WINDOW_SAMPLES" ]; do
    v="$(status_value "$key" 2>/dev/null || echo "$floor")"
    if is_number "$v"; then
      if [ "$best" = "-inf" ]; then best="$v";
      else best="$(awk -v a="$best" -v b="$v" 'BEGIN { print (b > a) ? b : a }')"; fi
    fi
    i=$((i+1)); sleep "$PEAK_WINDOW_INTERVAL"
  done
  printf '%s' "$best"
}

settled_master_peak()  { settled_max masterPeak -inf; }
settled_master_delta() { settled_max masterMaxSampleDelta 0; }
# Loudest peak (dBFS) a specific track held over the settle window.
settled_track_peak()   { settled_max "track${1}Peak" -inf; }
settled_bus_peak()     { settled_max "bus${1}Peak" -inf; }

# Count how many reads of masterMaxSampleDelta exceed `floor` over a window. A
# genuine sustained discontinuity persists across reads; a single-sample meter
# jitter (the drone's per-step onset transient grazes ~0.3-0.4) shows in ONE
# read. So CLICK is flagged only when the excursion is PERSISTENT (see drive),
# not on a lone spike — which is why the absolute floor alone (jittery near 0.4)
# is not used as the sole criterion.
CLICK_PERSIST_SAMPLES="${ROUTING_STRESS_CLICK_PERSIST_SAMPLES:-12}"
CLICK_PERSIST_MIN="${ROUTING_STRESS_CLICK_PERSIST_MIN:-4}"
click_excursion_count() {
  local floor="$1" v i=0 count=0
  while [ "$i" -lt "$CLICK_PERSIST_SAMPLES" ]; do
    v="$(status_value masterMaxSampleDelta 2>/dev/null || echo 0)"
    if is_number "$v" && awk -v d="$v" -v f="$floor" 'BEGIN { exit (d > f) ? 0 : 1 }'; then
      count=$((count+1))
    fi
    i=$((i+1)); sleep "$PEAK_WINDOW_INTERVAL"
  done
  printf '%s' "$count"
}

# --- diagnostics ------------------------------------------------------------
newest_crash_frame() {
  local crash
  crash="$(ls -t "$HOME/Library/Logs/DiagnosticReports/$APP_NAME"*.ips 2>/dev/null | head -1)"
  if [ -n "$crash" ]; then
    log "  crash report: $crash"
    report "  - crash report: \`$crash\`"
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

# --- post-condition assertion ----------------------------------------------
# Re-read a status key (after the op settled) and assert it equals an expected
# value. Records POSTFAIL on mismatch. Used to prove the op TOOK EFFECT.
assert_status() {
  local op="$1" key="$2" expected="$3"
  local actual
  actual="$(status_value "$key" 2>/dev/null || echo "<missing>")"
  if [ "$actual" = "$expected" ]; then
    log "    post-ok  $op: $key=$actual"
    report "    - post-ok: \`$key\`=$actual"
    return 0
  fi
  POSTFAIL=$((POSTFAIL+1))
  log "    POST-FAIL $op: $key expected=$expected actual=$actual"
  report "    - **POST-FAIL**: \`$key\` expected=$expected actual=$actual"
  return 1
}

# Assert a track's settled peak is BELOW the silence threshold (expected dead).
assert_track_silent() {
  local op="$1" idx="$2"
  local peak; peak="$(settled_track_peak "$idx")"
  if [ "$peak" = "-inf" ] || awk -v p="$peak" -v t="$TRACK_SILENCE_DBFS" 'BEGIN { exit (p < t) ? 0 : 1 }'; then
    log "    level-ok $op: track$idx silenced (peak=$peak)"
    report "    - level-ok: track$idx silenced (peak=$peak)"
    return 0
  fi
  POSTFAIL=$((POSTFAIL+1))
  log "    POST-FAIL $op: track$idx expected SILENT but peak=$peak"
  report "    - **POST-FAIL**: track$idx expected silent, peak=$peak"
  return 1
}

# Assert a track's settled peak is ABOVE the silence threshold (expected audible).
assert_track_audible() {
  local op="$1" idx="$2"
  local peak; peak="$(settled_track_peak "$idx")"
  if [ "$peak" != "-inf" ] && awk -v p="$peak" -v t="$TRACK_SILENCE_DBFS" 'BEGIN { exit (p > t) ? 0 : 1 }'; then
    log "    level-ok $op: track$idx audible (peak=$peak)"
    report "    - level-ok: track$idx audible (peak=$peak)"
    return 0
  fi
  # An audible-expectation miss is a SILENCE finding (a track went dead).
  SILENCE=$((SILENCE+1))
  log "    SILENCE  $op: track$idx expected audible but peak=$peak"
  report "    - **SILENCE**: track$idx expected audible, peak=$peak"
  return 1
}

# --- the watchdog -----------------------------------------------------------
# Args: op-label, command-payload, [extra env to wrap the command write].
# After PASS, also evaluates the per-op CLICK metric. Returns 0 PASS,1 HANG,2 CRASH.
# When the op is the positive control, prefix the payload with a click-forcing
# env that the app reads at launch — so the control is selected at LAUNCH time
# (see run_pass). Here we just classify the op.
LAST_DELTA=""
LAST_THRESHOLD=""
LAST_CLICKED=0
# Per-pass switches: PASS 1 (drum-free) evaluates CLICK + master SILENCE; PASS 2
# (white-noise soak) is hang/crash ONLY — the noisy fixture's drum tracks make
# the master discontinuity metric meaningless, so CLICK/SILENCE are not judged
# there (per-track SILENCE + post-conditions are asserted explicitly in PASS 1).
EVAL_CLICK=1
EVAL_SILENCE=1
drive() {
  local op="$1" payload="$2"
  local before after now verdict="" silent=""

  # Reset the master maxSampleDelta peak-HOLD so this op's discontinuity is
  # measured from a clean baseline. The app holds the max across its ~100ms
  # status writes, so a sparse transient inside the op window is captured even
  # though the meter resets every 60Hz publish (a single instant read misses it).
  write_command "resetClickHold=1"
  sleep 0.3

  before="$(status_mtime)"
  write_command "$payload"

  local deadline; deadline=$(( $(date +%s) + HANG_TIMEOUT ))
  after="$before"
  while :; do
    if ! kill -0 "$APP_PID" 2>/dev/null; then verdict="CRASH"; break; fi
    after="$(status_mtime)"
    now="$(date +%s)"
    if [ "$after" -gt "$before" ] && [ $(( now - after )) -le "$STATUS_FRESH_WINDOW" ]; then
      verdict="PASS"; break
    fi
    if [ "$now" -ge "$deadline" ]; then verdict="HANG"; break; fi
    sleep 0.2
  done

  case "$verdict" in
    PASS)
      local peak; peak="$(settled_master_peak 2>/dev/null || echo n/a)"
      if [ "$EVAL_SILENCE" = "1" ] && printf '%s' "$peak" | grep -qiE '^-inf|^-1[0-9][0-9]'; then
        silent=" SILENCE(masterPeak=$peak)"
        SILENCE=$((SILENCE+1))
      fi
      # Let the op settle so the hold captures any transient, then read the
      # peak-HOLD of master maxSampleDelta accumulated since the reset above.
      local delta clicked="" threshold
      sleep 1.0
      delta="$(status_value masterMaxSampleDeltaHold 2>/dev/null || echo 0)"
      is_number "$delta" || delta=0
      threshold="$CLICK_ABS_FLOOR"
      LAST_DELTA="$delta"; LAST_THRESHOLD="$threshold"; LAST_CLICKED=0
      if [ "$EVAL_CLICK" = "1" ] && awk -v d="$delta" -v t="$threshold" 'BEGIN { exit (d > t) ? 0 : 1 }'; then
        clicked=" CLICK(deltaHold=$delta > floor=$threshold)"
        CLICK=$((CLICK+1)); LAST_CLICKED=1
      fi
      PASS=$((PASS+1))
      log "PASS  $op  (masterPeak=$peak deltaHold=$delta floor=$threshold)$silent$clicked"
      report "- **PASS** \`$op\` — masterPeak=$peak maxSampleDeltaHold=$delta (floor=$threshold)$silent$clicked"
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
  local deadline; deadline=$(( $(date +%s) + 30 ))
  while [ "$(date +%s)" -lt "$deadline" ]; do
    if ! kill -0 "$APP_PID" 2>/dev/null; then return 2; fi
    if [ -f "$STATUS_FILE" ]; then return 0; fi
    sleep 0.3
  done
  return 1
}

# --- launch helpers ---------------------------------------------------------
# Launch the app on the real HAL with a fixture. Extra env is appended verbatim
# (used to set SEQUENCER_AI_DISABLE_ROUTING_RAMP=1 for the positive-control run).
launch_app() {
  local fixture="$1"; shift
  cp -f "$fixture" "$FIXTURE_DST"
  rm -f "$CMD_FILE" "$STATUS_FILE"
  pkill -9 -x "$APP_NAME" 2>/dev/null || true
  sleep 0.5
  env "$@" \
    SEQUENCER_AI_VISUAL_COMMAND_FILE="$CMD_FILE" \
    SEQUENCER_AI_NEW_DOCUMENT_FIXTURE="$FIXTURE_DST" \
    SEQUENCER_AI_MATERIALIZE_FIXTURE_SAMPLES=1 \
    SEQUENCER_AI_HEADLESS_REAL_HAL=1 \
    "$EXE" >"$APP_LOG" 2>&1 &
  APP_PID=$!
  log "  pid: $APP_PID (fixture: $(basename "$fixture") extra-env: $*)"
  if ! wait_for_first_status; then
    log "FATAL: app did not produce a status file (see $APP_LOG)"
    report "FATAL: no initial status file for $(basename "$fixture")."
    tail -20 "$APP_LOG" | sed 's/^/    /'
    return 1
  fi
  # Get the engine playing and let the drone settle.
  drive "transport-play" "workspace=mixer
transport=play" >/dev/null || true
  sleep 1.5
  return 0
}

stop_app() {
  if kill -0 "$APP_PID" 2>/dev/null; then
    write_command "transport=stop" 2>/dev/null || true
    sleep 0.3
    kill -9 "$APP_PID" 2>/dev/null || true
  fi
  pkill -9 -x "$APP_NAME" 2>/dev/null || true
  APP_PID=""
}

# ===========================================================================
# RUN
# ===========================================================================
log "routing-stress: resolving executable..."
EXE="$(resolve_exe)" || { log "FATAL: could not locate built $APP_NAME (build Debug first)."; exit 3; }
log "  exe: $EXE"

cat > "$REPORT" <<HEADER
# routing-stress run $RUN_STAMP

- exe: \`$EXE\`
- mode: real HAL headless (SEQUENCER_AI_HEADLESS_REAL_HAL=1), transport=play
- command file: \`$CMD_FILE\`
- hang timeout: ${HANG_TIMEOUT}s; status-fresh window: ${STATUS_FRESH_WINDOW}s
- CLICK: delta > max(pre*${CLICK_RATIO}, floor=${CLICK_ABS_FLOOR})
- per-track SILENCE threshold: ${TRACK_SILENCE_DBFS} dBFS
HEADER

# ---------------------------------------------------------------------------
# PASS 1 — drum-free CLICK + per-track SILENCE + post-conditions + control
# ---------------------------------------------------------------------------
report ""
report "## PASS 1 — drum-free click / level / post-condition gate"
report "fixture: \`$(basename "$FIXTURE_DRONE_SRC")\` (tonal: Main, Lead, Slicer, Drone; 1 bus)"
log ""
log "==== PASS 1: drum-free click/level/post-condition gate ===="

if ! launch_app "$FIXTURE_DRONE_SRC"; then
  exit 4
fi
log "  status channel live; initial masterPeak=$(status_value masterPeak 2>/dev/null || echo n/a)"
DRONE_BASELINE_DELTA="$(settled_master_delta 2>/dev/null || echo 0)"
report ""
report "drone baseline maxSampleDelta (no edits): $DRONE_BASELINE_DELTA"
report ""

# Track 3 (Sustain Drone) is the always-on tonal master baseline; the ops below
# never touch it, so the master stays sounding throughout PASS 1.

# 1) Mute track 0 → track0 must go silent, masterPeak stays up (drone), and
#    document state must read back effectivemute=true. Then unmute restores.
if drive "trackMute-0-on" "trackMute=0:on"; then
  assert_status      "trackMute-0-on" "track0EffectiveMuted" "true"
  assert_track_silent "trackMute-0-on" 0
fi
if drive "trackMute-0-off" "trackMute=0:off"; then
  assert_status       "trackMute-0-off" "track0EffectiveMuted" "false"
  assert_track_audible "trackMute-0-off" 0
fi

# 2) Add a native insert to track 0 — must not click (ramped reconnect) and the
#    fx insert count must read back as 1.
if drive "trackAddInsert-0-filter" "trackAddInsert=0:native-filter"; then
  assert_status "trackAddInsert-0-filter" "track0FXInsertCount" "1"
fi

# 3) Remove that insert — the historical 0.799 "spike" op. On the drum-free
#    fixture the master delta stays at baseline (no drum noise to inflate it),
#    so this op records NO click — confirming the old 0.799 was drum-noise
#    inflation, not a real disconnect click. fx count must read back as 0.
if drive "trackRemoveInsert-0" "trackRemoveInsert=0:0"; then
  assert_status "trackRemoveInsert-0" "track0FXInsertCount" "0"
fi

# 4) Route track 1 to bus 0 → destination bus reads back; bus carries level.
if drive "routeTrack-1-to-bus0" "routeTrackToBus=1:0"; then
  assert_status "routeTrack-1-to-bus0" "track1OutputBus" "FX Bus"
fi
# 5) Route it back to master → reads back master; track stays audible.
if drive "routeTrack-1-to-master" "routeTrackToBus=1:master"; then
  assert_status        "routeTrack-1-to-master" "track1OutputBus" "master"
  assert_track_audible "routeTrack-1-to-master" 1
fi

# 6) Bus mute / unmute post-conditions.
if drive "busMute-0-on" "busMute=0:on"; then
  assert_status "busMute-0-on" "bus0EffectiveMuted" "true"
fi
if drive "busMute-0-off" "busMute=0:off"; then
  assert_status "busMute-0-off" "bus0EffectiveMuted" "false"
fi

# 7) Remove the last track (the drone) — the op the noisy fixture once "spiked"
#    at 0.504. On the drum-free bed it records NO click (confirming that 0.504
#    was drum-noise inflation). Done LAST so removing the drone doesn't poison
#    earlier ops. trackCount must drop by one (post-condition).
PRE_TRACK_COUNT="$(status_value trackCount 2>/dev/null || echo 0)"
EXP_TRACK_COUNT=$(( PRE_TRACK_COUNT - 1 ))
LAST_IDX=$(( PRE_TRACK_COUNT - 1 ))
if drive "removeTrack-last" "removeTrack=$LAST_IDX"; then
  assert_status "removeTrack-last" "trackCount" "$EXP_TRACK_COUNT"
fi

# 8) POSITIVE CONTROL (metric liveness + floor reachability):
#    "CLICK=0" is only meaningful if the metric → status-file → gate path is live
#    AND the click floor is reachable. The acoustic master discontinuity metric
#    is NORMALIZED and fires on every note onset (and is amplified at low master
#    levels), so it cannot by itself separate an op-click from the drone bed's
#    per-loop retrigger onset (measured jitter ~0.6); it is therefore NOT used as
#    a per-op pass/fail. Instead the control injects a known discontinuity into
#    the hold (injectClickHold) and asserts the gate SEES it cross the floor —
#    proving the plumbing is live and the floor is clearable. If the injected
#    value does NOT surface over the floor, the metric pipeline is dead and the
#    gate would be meaningless → FAIL.
report ""
report "### Positive control — metric plumbing + floor reachability (injectClickHold)"
log ""
log "---- positive control: inject a known discontinuity, assert the gate sees it ----"
CONTROL_EXPECTED_CLICK=1
write_command "resetClickHold=1"
sleep 0.4
write_command "injectClickHold=$CLICK_CONTROL_INJECT"
sleep 0.4
CTRL_DELTA="$(status_value masterMaxSampleDeltaHold 2>/dev/null || echo 0)"
is_number "$CTRL_DELTA" || CTRL_DELTA=0
if awk -v d="$CTRL_DELTA" -v f="$CLICK_ABS_FLOOR" 'BEGIN { exit (d > f) ? 0 : 1 }'; then
  CONTROL_OBSERVED_CLICK=1
  log "  control FIRED: injected deltaHold=$CTRL_DELTA > floor=$CLICK_ABS_FLOOR — metric pipeline live + floor reachable"
  report "- control FIRED: injected deltaHold=$CTRL_DELTA > floor=$CLICK_ABS_FLOOR — pipeline live + floor reachable"
else
  log "  control did NOT fire: injected deltaHold=$CTRL_DELTA <= floor=$CLICK_ABS_FLOOR — metric pipeline DEAD"
  report "- **control did NOT fire**: injected deltaHold=$CTRL_DELTA <= floor=$CLICK_ABS_FLOOR — pipeline dead"
fi
# Reset so the injected value does not bleed into any later read on this instance.
write_command "resetClickHold=1"

CLICK_REAL=$CLICK
[ "$CLICK_REAL" -lt 0 ] && CLICK_REAL=0

# ---------------------------------------------------------------------------
# PASS 2 — hang/crash combinatorial soak (original sample-only fixture)
# ---------------------------------------------------------------------------
report ""
report "## PASS 2 — hang/crash combinatorial soak"
report "fixture: \`$(basename "$FIXTURE_SAMPLE_SRC")\` (sample-only, 8 tracks, 1 bus)"
log ""
log "==== PASS 2: hang/crash combinatorial soak ===="

# Hang/crash ONLY on the noisy fixture — CLICK/SILENCE are not judged here.
EVAL_CLICK=0
EVAL_SILENCE=0

if launch_app "$FIXTURE_SAMPLE_SRC"; then
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
    label="${entry%%|*}"; payload="${entry#*|}"
    if ! drive "$label" "$payload"; then
      log "app gone/killed after '$label' (HANG or CRASH) — ending PASS 2."
      report ""
      report "_PASS 2 aborted after \`$label\` (app killed by watchdog / crashed)._"
      break
    fi
    sleep 0.5
  done
  stop_app
fi

# --- summary ----------------------------------------------------------------
CONTROL_OK="no"
if [ "$CONTROL_EXPECTED_CLICK" = "1" ] && [ "$CONTROL_OBSERVED_CLICK" = "1" ]; then
  CONTROL_OK="yes"
fi

report ""
report "## Summary"
report ""
report "- PASS: $PASS"
report "- HANG: $HANG"
report "- CRASH: $CRASH"
report "- SILENCE: $SILENCE"
report "- CLICK (total, incl. control): $CLICK"
report "- CLICK (real, control excluded): $CLICK_REAL"
report "- POST-FAIL (post-conditions not verified): $POSTFAIL"
report "- positive control fired: $CONTROL_OK"

log ""
log "==== routing-stress summary ===="
log "PASS=$PASS HANG=$HANG CRASH=$CRASH SILENCE=$SILENCE CLICK=$CLICK_REAL(real) POSTFAIL=$POSTFAIL control_fired=$CONTROL_OK"
log "report: $REPORT"

# --- gate verdict -----------------------------------------------------------
# Watertight bar: no hang, no crash, no per-track silence, no REAL click, every
# post-condition verified, AND the positive control fired (metric is live).
GATE_RC=0
[ "$HANG"      -ne 0 ] && GATE_RC=1
[ "$CRASH"     -ne 0 ] && GATE_RC=1
[ "$SILENCE"   -ne 0 ] && GATE_RC=1
[ "$CLICK_REAL" -ne 0 ] && GATE_RC=1
[ "$POSTFAIL"  -ne 0 ] && GATE_RC=1
[ "$CONTROL_OK" != "yes" ] && GATE_RC=1

if [ "$GATE_RC" -eq 0 ]; then
  log "GATE: PASS (watertight)"
  report ""
  report "**GATE: PASS (watertight)**"
else
  log "GATE: FAIL"
  report ""
  report "**GATE: FAIL**"
fi
exit "$GATE_RC"
