#!/usr/bin/env bash
#
# auto-capture-watch.sh — ONE staleness check + (re)capture if the UI source is
# newer than the captures. Built to be fired on a ~5-min timer (launchd
# StartInterval=300, or `while :; do auto-capture-watch.sh; sleep 300; done`).
#
# It is deliberately cheap on the common path: a couple of `stat` calls and an
# exit. It only does the expensive thing (force build + full capture sweep) when
# UI source has actually changed since the last capture AND edits have settled.
#
# Guards: single-instance lock, skips if a capture is already running, and a
# debounce so it never fires mid-edit. A failed/partial capture is NOT recorded
# as fresh, so it simply retries on the next tick.
#
# Note: captures need an unlocked screen with the GUI session active (peekaboo
# brings the app to the front). On a locked screen the capture will fail; the
# watcher logs it and retries next tick rather than recording bad PNGs.

set -euo pipefail

REPO="/Users/maxwilliams/dev/in-sequence"
REVIEW_DIR="$REPO/.meta/multipass/visual-review/main"
STATE_DIR="$REPO/.meta/multipass/visual-review"
LOCK_DIR="$STATE_DIR/.auto-capture.lock"
LOG="$STATE_DIR/.auto-capture.log"

# Watch these for changes; a newer mtime here than the newest PNG => stale.
WATCH_PATHS=("$REPO/Sources/UI" "$REPO/scripts/visual-scenarios")

DEBOUNCE_SECONDS=120   # don't capture while source changed in the last 2 min

log() { printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG"; }

mkdir -p "$REVIEW_DIR"

# --- single-instance lock (mkdir is atomic; reclaim if clearly stale) --------
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  lock_mtime=$(stat -f '%m' "$LOCK_DIR" 2>/dev/null || echo 0)
  if [ "$(( $(date +%s) - lock_mtime ))" -gt 3600 ]; then
    log "reclaiming stale lock (>1h old)"
    rmdir "$LOCK_DIR" 2>/dev/null || true
    mkdir "$LOCK_DIR" 2>/dev/null || { log "skip: lock contended"; exit 0; }
  else
    exit 0   # another run is in progress; quiet exit
  fi
fi
trap 'rmdir "$LOCK_DIR" 2>/dev/null || true' EXIT

# --- don't collide with a manually/loop-launched capture --------------------
if pgrep -f 'qa-surface-coverage.sh' >/dev/null 2>&1; then
  log "skip: a capture is already running"
  exit 0
fi

# --- newest capture PNG mtime (0 if none captured yet) ----------------------
newest_png_mtime=0
newest_png=$(ls -t "$REVIEW_DIR"/*.png 2>/dev/null | head -1 || true)
[ -n "$newest_png" ] && newest_png_mtime=$(stat -f '%m' "$newest_png")

# --- newest watched-source mtime --------------------------------------------
newest_src_mtime=0
for p in "${WATCH_PATHS[@]}"; do
  [ -e "$p" ] || continue
  m=$(find "$p" -type f \( -name '*.swift' -o -name '*.sh' \) -exec stat -f '%m' {} + 2>/dev/null | sort -n | tail -1 || true)
  [ -n "${m:-}" ] && [ "$m" -gt "$newest_src_mtime" ] && newest_src_mtime="$m"
done

# --- staleness decision -----------------------------------------------------
if [ "$newest_src_mtime" -le "$newest_png_mtime" ]; then
  exit 0   # captures are current; nothing to do (cheap path)
fi

# Debounce: if source changed very recently, wait for the edit burst to settle.
now=$(date +%s)
if [ "$(( now - newest_src_mtime ))" -lt "$DEBOUNCE_SECONDS" ]; then
  log "stale but within debounce (last edit $(( now - newest_src_mtime ))s ago); deferring"
  exit 0
fi

log "stale: source newer than captures (src=$newest_src_mtime png=$newest_png_mtime) — building + capturing"

# --- force a fresh build (open-latest-build fingerprint-skips stale binaries) -
build_log="$STATE_DIR/.auto-capture.build.log"
if ! DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
     xcodebuild -project "$REPO/SequencerAI.xcodeproj" -scheme SequencerAI \
     -destination 'platform=macOS,arch=arm64' build >"$build_log" 2>&1; then
  log "ABORT: build failed (see $build_log) — leaving captures stale for retry"
  exit 1
fi

# --- full capture sweep (no filter => purge + regenerate every surface) ------
if SEQUENCER_AI_ALLOW_VISUAL_AUTOMATION=1 \
   bash "$REPO/scripts/visual-scenarios/qa-surface-coverage.sh" >>"$LOG" 2>&1; then
  log "capture sweep OK"
else
  log "capture sweep returned non-zero — will retry next tick"
  exit 1
fi
