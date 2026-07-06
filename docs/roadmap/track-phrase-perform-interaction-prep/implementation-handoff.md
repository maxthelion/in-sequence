---
status: ready-for-agent
feature: track-phrase-perform-interaction-prep
slice: track-perform-pattern-mini-cell-targets
updated: 2026-07-05T06:46Z
---

# Implementation Handoff: Track Perform Pattern Mini-Cell Targets

## Objective

Make Track Perform pattern-layer mini cells directly clickable. A click on a
mini cell selects that exact pattern slot instead of incrementing/cycling the
track's pattern layer value.

## Binding Scope

Build only the first G4 interaction pass:

- Track Perform pattern mini-cell direct selection.
- The minimum Track Perform matrix hit-testing and selector polish required to
  make that behavior coherent.
- Shared layer-button sizing only if the same component is already used by the
  Track Perform pattern-layer control.

Do not touch:

- the resolved July 4 Phrase Layers / Global Apply lane;
- Phrase Global Apply card editing or track selector behavior;
- Scenes IA, mixer/routing, kit/drum-part, slicer/header, AU runtime safety, or
  audio-input work;
- request lifecycle files or build-loop promotion.

## Product Rules

- Pattern mini cells are controls, not decorations.
- The card background is not a pattern-cycle shortcut.
- The selected mini cell should read immediately as the active pattern slot.
- No repeated "Pattern" labels inside every mini cell.
- No instructional sentences on the surface.
- No translucent accent fills. Use solid small selected states, outline, or
  existing theme tokens.

## Acceptance Checklist

- Direct click on mini cell `P4` sets `P4`.
- Direct click on another mini cell switches to that slot.
- Re-clicking the selected mini cell does not advance/cycle.
- Clicking card chrome outside mini cells does not change the pattern slot.
- Empty/unavailable mini cells have a clear disabled or inert state.
- The compact layer selector remains usable and does not grow wider to explain
  the interaction.
- Existing resolved Phrase Layers / Global Apply behavior still passes relevant
  tests or visual checks.
- `scripts/diagnostics/ux-canon-lint.sh` passes if UI files are touched.

## Suggested Test Names

- `testTrackPerformPatternMiniCellSelectsExactSlot`
- `testTrackPerformPatternMiniCellRepeatedClickDoesNotCycle`
- `testTrackPerformPatternCardBackgroundDoesNotCyclePattern`

Use local naming conventions if existing tests already cover Track/Phrase
perform interactions.

## Source Evidence

Primary:

- `docs/bugs/20260616-110235-the-behaviour-of-pattern-layer-in-a-cell/`

Boundary evidence:

- `docs/bugs/20260619-215229-tracks-perform-should-be-navigation-not-layers/`
- `docs/bugs/20260620-112546-remove-unnecessary-text-in-the-new-nav-b/`
- `docs/bugs/20260620-135925-choose-phrase-layer-is-unnecessary-text/`
- `docs/bugs/20260622-130446-the-track-selector-has-several-issues-th/`
- `docs/bugs/20260704-085618-the-layer-buttons-should-be-less-long-to/`
- `docs/bugs/20260704-091036-layers-buttons-should-be-narrower/`

Canon:

- `docs/ux-canon.md`
- `scripts/diagnostics/ux-canon-lint.sh`
