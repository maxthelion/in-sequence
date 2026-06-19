#!/usr/bin/env bash
set -euo pipefail

# RETIRED SCENARIO
#
# This scenario drove the bespoke note-repeat RUNTIME trigger surface that
# lived on the tracks Perform matrix (the TRACK LAYER selector + per-card
# note-repeat hold/latch cells). That surface was removed: tracks Perform is
# now navigation + selection, and layer perform — including note repeat —
# launches SCOPED from the selection (it reuses phrase perform), not as a
# bespoke tracks-matrix layer.
#
# The visual commands this scenario used (`trackPerformLayer=noteRepeat`,
# `noteRepeatAction=press|release|clear`) and the status fields it asserted
# (`trackPerformLayerMode`, ...) no longer exist, so the scenario is retired
# rather than left to time out. Note-repeat coverage now belongs with the
# scoped / phrase-perform scenarios.

echo "note-repeat-perform-surface: RETIRED (tracks-matrix note-repeat layer surface removed; note repeat is now scoped/phrase perform)." >&2
exit 0
