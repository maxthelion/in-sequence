---
status: accepted
feature: track-phrase-perform-interaction-prep
slice: track-perform-pattern-mini-cell-targets
updated: 2026-07-05T06:46Z
---

# Track Perform Pattern Mini-Cell Targets Plan

## Build Slice

Implement one interaction pass: Track Perform pattern-layer mini cells are
direct hit targets for pattern selection.

Do not broaden the slice into Phrase Global Apply, Scenes IA, or a new Tracks
page perform mode.

## Suggested Implementation Steps

1. Find the current Track Perform pattern-layer card/cell renderer and the
   handler that increments/cycles the pattern value.
2. Replace the pattern-layer card-level cycle gesture with per-mini-cell
   actions that select a specific pattern slot.
3. Keep non-pattern layers on their current behavior unless they share the same
   broken card-level pattern handler.
4. Preserve the compact layer-selector grammar. If shared components are
   touched, make sizing changes through the shared selector rather than
   one-off widths.
5. Add focused tests around direct pattern selection and no accidental cycling.
6. Run the UX canon lint if UI files change.

## Verification

Minimum deterministic checks:

- Unit or view-model test proving direct slot selection from mini cell `P1`,
  another slot such as `P4`, and repeated click stability.
- Regression test proving a card-background click no longer cycles the pattern
  value in pattern layer.
- Existing relevant Track/Phrase perform tests.
- `scripts/diagnostics/ux-canon-lint.sh` when `Sources/UI` changes.

Visual evidence:

- Preferred when interactive permissions are available: capture the Track
  Perform pattern layer before/after selecting a non-default mini cell.
- If unattended visual automation is gated, record `capture-permission-or-focus`
  instead of retrying.

## Guardrails

- Do not use document writes as a hot path for performance interaction.
- Do not add explainer copy to justify the changed interaction.
- Do not use translucent accent fills for selected mini cells or containers.
- Do not create a new Tracks Perform/layer surface; the Tracks page is a plain
  navigator after the June 20 resolution.

## Deferred G4 Items

These are intentionally not in this first build slice:

- Phrase Global Apply cards becoming value controls.
- Global Apply track-selector refinements, already resolved on June 22.
- Phrase layer-selector text/placement fixes, already resolved on June 20.
- July 4 layer-button narrowing, already resolved by `27bfe80a` and
  `4c1259e3`.
