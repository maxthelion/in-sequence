#!/usr/bin/env bash
set -euo pipefail

case "${SEQUENCER_AI_ALLOW_VISUAL_AUTOMATION:-}" in
  1|true|TRUE|yes|YES|on|ON) ;;
  *)
    echo "Peekaboo disabled for unattended runs; set SEQUENCER_AI_ALLOW_VISUAL_AUTOMATION=1 in an interactive, pre-authorized session." >&2
    exit 42
    ;;
esac

exec peekaboo "$@" --no-remote
