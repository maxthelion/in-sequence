#!/usr/bin/env bash
set -euo pipefail

# RETIRED SCENARIO
#
# This scenario captured the bespoke tracks Perform LAYER surface — the
# `TRACK LAYER` selector, the "CHOOSE TRACK LAYER" popup (Pattern / Note
# Repeat / Step Order variants, etc.) and the per-track layer mini-grids.
# That surface was removed: tracks Perform is now navigation + selection
# (a card grid with pattern preview + per-card mute + multi-select "Edit
# Set"), and layer perform launches SCOPED from the selection — it reuses
# phrase perform, which is the canonical layer surface now.
#
# The visual commands it used (`trackPerformLayer=`,
# `trackPerformLayerSelector=`, `trackPerformLayerVariant=`) and the status
# fields it asserted (`trackPerformLayerMode`, `trackPerformLayerSelectorVisible`,
# `trackPerformLayerVariant`) no longer exist. Layer-selector coverage now
# lives in the phrase-perform scenarios.

echo "performance-layer-matrix-tracks: RETIRED (tracks-matrix layer surface removed; layers live in phrase perform / scoped perform)." >&2
exit 0
