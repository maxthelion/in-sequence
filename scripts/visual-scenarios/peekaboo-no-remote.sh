#!/usr/bin/env bash
set -euo pipefail

case "${SEQUENCER_AI_BLOCK_VISUAL_AUTOMATION:-${SEQUENCER_AI_DISABLE_VISUAL_AUTOMATION:-}}" in
  1|true|TRUE|yes|YES|on|ON)
    echo "Peekaboo disabled because SEQUENCER_AI_BLOCK_VISUAL_AUTOMATION is enabled." >&2
    exit 42
    ;;
  *)
    ;;
esac

exec peekaboo "$@" --no-remote
