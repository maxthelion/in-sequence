#!/usr/bin/env bash
set -euo pipefail

# Foreman tick: cheap deterministic pre-check, then one headless model
# session with the standing prompt. Schedule via cron/launchd or run by
# hand. --force skips the pre-check.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FOREMAN_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${FOREMAN_DIR}/.." && pwd)"

FOREMAN_MODEL="${FOREMAN_MODEL:-fable}"
FOREMAN_AUTONOMY="${FOREMAN_AUTONOMY:-full}"
HEARTBEAT_SECONDS="${FOREMAN_HEARTBEAT_SECONDS:-21600}" # 6h

mkdir -p "$FOREMAN_DIR/state"
fingerprint_file="$FOREMAN_DIR/state/watch-fingerprint"
heartbeat_file="$FOREMAN_DIR/state/last-tick-epoch"

# ---------------------------------------------------------------------------
# Deterministic pre-check: fingerprint the watched inputs.
# ---------------------------------------------------------------------------
fingerprint() {
  {
    # Bug reports without resolutions.
    find "$REPO_ROOT/docs/bugs" -mindepth 1 -maxdepth 1 -type d 2>/dev/null \
      | while read -r d; do
          [ -f "$d/resolution.md" ] || echo "bug:$d"
        done
    # Post-merge feedback without resolutions.
    find "$REPO_ROOT/docs/roadmap" -path '*/feedback/*.md' ! -name '*.resolution.md' 2>/dev/null \
      | while read -r f; do
          [ -f "${f%.md}.resolution.md" ] || echo "feedback:$f"
        done
    # Feature branches awaiting integration.
    git -C "$REPO_ROOT" branch --list 'feature/*' --format='branch:%(refname:short):%(objectname:short)' 2>/dev/null
  } | sort | shasum -a 256 | cut -d' ' -f1
}

now_epoch="$(date +%s)"
last_epoch="$(cat "$heartbeat_file" 2>/dev/null || echo 0)"
current_fp="$(fingerprint)"
previous_fp="$(cat "$fingerprint_file" 2>/dev/null || echo none)"

if [ "${1:-}" != "--force" ]; then
  if [ "$current_fp" = "$previous_fp" ] && [ $((now_epoch - last_epoch)) -lt "$HEARTBEAT_SECONDS" ]; then
    echo "foreman: nothing new, heartbeat not due. Skipping."
    exit 0
  fi
fi

# Don't compete with an interactive session or running build.
if pgrep -qx xcodebuild; then
  echo "foreman: xcodebuild running; deferring tick."
  exit 0
fi

echo "$current_fp" > "$fingerprint_file"
echo "$now_epoch" > "$heartbeat_file"

# ---------------------------------------------------------------------------
# Model invocation. One session, standing prompt.
# ---------------------------------------------------------------------------
cd "$REPO_ROOT"
FOREMAN_AUTONOMY="$FOREMAN_AUTONOMY" claude -p \
  --model "$FOREMAN_MODEL" \
  --dangerously-skip-permissions \
  "$(cat "$FOREMAN_DIR/PROMPT.md")

This is a scheduled foreman tick at $(date '+%Y-%m-%d %H:%M'). Begin with the read-first list."
