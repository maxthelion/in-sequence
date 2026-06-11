#!/usr/bin/env bash
set -euo pipefail

# Foreman pre-check, shared by every trigger mechanism (tick.sh, /loop,
# scheduled sessions). Deterministically decides whether a tick is worth
# spending judgment on.
#
# Exit 0  => work to do (prints what changed)
# Exit 1  => nothing new and heartbeat not due
# Exit 2  => environment busy (build running); defer

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FOREMAN_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${FOREMAN_DIR}/.." && pwd)"
HEARTBEAT_SECONDS="${FOREMAN_HEARTBEAT_SECONDS:-21600}" # 6h

mkdir -p "$FOREMAN_DIR/state"
fingerprint_file="$FOREMAN_DIR/state/watch-fingerprint"
heartbeat_file="$FOREMAN_DIR/state/last-tick-epoch"

watched_inputs() {
  # Bug reports without resolutions.
  find "$REPO_ROOT/docs/bugs" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
    | while read -r d; do
        [ -f "$d/resolution.md" ] || echo "bug:${d#"$REPO_ROOT"/}"
      done
  # Post-merge feedback without resolutions.
  find "$REPO_ROOT/docs/roadmap" -path '*/feedback/*.md' ! -name '*.resolution.md' 2>/dev/null \
    | while read -r f; do
        [ -f "${f%.md}.resolution.md" ] || echo "feedback:${f#"$REPO_ROOT"/}"
      done
  # Owner intent files awaiting processing.
  find "$REPO_ROOT/docs/intents/inbox" -name '*.md' -type f 2>/dev/null \
    | while read -r f; do echo "intent:${f#"$REPO_ROOT"/}"; done
  # Feature branches awaiting integration.
  git -C "$REPO_ROOT" branch --list 'feature/*' --format='branch:%(refname:short):%(objectname:short)' 2>/dev/null
}

if pgrep -qx xcodebuild; then
  echo "busy: xcodebuild running"
  exit 2
fi

now_epoch="$(date +%s)"
last_epoch="$(cat "$heartbeat_file" 2>/dev/null || echo 0)"
inputs="$(watched_inputs | sort)"
current_fp="$(printf '%s' "$inputs" | shasum -a 256 | cut -d' ' -f1)"
previous_fp="$(cat "$fingerprint_file" 2>/dev/null || echo none)"

if [ "${1:-}" != "--force" ] && [ "$current_fp" = "$previous_fp" ] \
   && [ $((now_epoch - last_epoch)) -lt "$HEARTBEAT_SECONDS" ]; then
  echo "idle: nothing new, heartbeat not due ($(( (HEARTBEAT_SECONDS - now_epoch + last_epoch) / 60 ))m remaining)"
  exit 1
fi

echo "$current_fp" > "$fingerprint_file"
echo "$now_epoch" > "$heartbeat_file"

if [ "$current_fp" = "$previous_fp" ]; then
  echo "heartbeat: no new inputs; spend this tick on one standing lens"
else
  echo "changed inputs:"
  printf '%s\n' "$inputs"
fi
exit 0
