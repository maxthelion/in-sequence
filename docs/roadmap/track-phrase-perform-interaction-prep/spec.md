---
status: accepted
feature: track-phrase-perform-interaction-prep
slice: track-perform-pattern-mini-cell-targets
updated: 2026-07-05T06:46Z
---

# Track Perform Pattern Mini-Cell Targets Spec

## Intent

Make the Track Perform pattern layer behave like an instrument panel, not a
cycler. In the pattern layer, each visible mini pattern cell is its own click
target. Clicking a mini cell selects that exact pattern slot for the track.

This resolves the smallest current G4 complaint:
`docs/bugs/20260616-110235-the-behaviour-of-pattern-layer-in-a-cell/`.

## User-Facing Contract

- When the Track Perform matrix is showing the pattern layer, a track card
  exposes the available pattern slots as individual mini cells.
- Clicking a mini cell activates that exact pattern for the track.
- Clicking the card background must not increment or cycle the pattern layer.
- The selected pattern mini cell is visually distinct from unselected cells.
- The whole mini cell is the target. Do not add tiny nested buttons, footers, or
  repeated labels inside each mini cell.
- The interaction must work with mouse/tap precision consistent with the rest
  of the matrix, including dense track layouts.
- Keyboard/focus accessibility should identify the target as a pattern slot
  action if the existing control stack supports labels/help.

## Visual Grammar

- Follow `docs/ux-canon.md`:
  - Rule 1: the layer header owns the "Pattern" context; cells show only their
    own slot/value state.
  - Rule 2: the mini cell itself is the control.
  - Rule 3: no explanatory sentences on the working surface.
  - Rule 5: step/pattern grid grammar should match existing grid vocabulary.
  - Rule 12: selection/identity uses solid small elements or outlines, never
    translucent accent container fills.
- Keep the selector compact. The already-resolved Phrase Layers reports prove
  the direction: shorter layer buttons, no "Choose Layer" copy, and controls
  connected to their owning shell.
- If this pass touches shared layer-selector components, keep the same compact
  grammar for Phrase Perform, but do not rework Phrase Global Apply layouts.

## Scope

In scope:

- Track Perform pattern-layer mini-cell direct selection.
- Any local Track Perform matrix hit-testing needed to prevent old
  click-to-cycle behavior.
- Small selector/nav cleanup only when necessary to keep the Track Perform
  pattern layer reachable and legible.
- Shared reusable layer-button sizing only if the Track Perform change uses the
  same component.

Out of scope:

- Reintroducing a bespoke Tracks page perform/layer surface. That was resolved
  by `docs/bugs/20260619-215229-tracks-perform-should-be-navigation-not-layers/`.
- Phrase Global Apply card interactivity, track-selector behavior, and layout
  fixes already resolved by the July 4 Phrase Layers / Global Apply lane.
- Scenes IA, mixer/routing, kit/drum-part work, slicer/header compression,
  AU runtime safety, audio-input reports, and product-code unrelated to Track
  Perform pattern-cell selection.

## Acceptance Criteria

- Given Track Perform is on the pattern layer, clicking mini cell `P4` on a
  track sets that track to pattern slot `P4`.
- Repeated clicks on the same selected mini cell are stable and do not cycle to
  another slot.
- Clicking a different mini cell on the same card changes directly to that slot.
- Clicking non-mini-cell card chrome does not change the pattern slot unless an
  existing explicit control is clicked.
- Visual state distinguishes selected, available, unavailable/empty, hover, and
  focus states without prose or translucent accent floods.
- Existing Phrase Layers / Global Apply resolved behavior is not regressed.
- `scripts/diagnostics/ux-canon-lint.sh` passes for any touched UI files.

## Evidence Sources

- `.meta/multipass/state/bug-intake.md` group `G4`.
- `docs/bugs/20260616-110235-the-behaviour-of-pattern-layer-in-a-cell/note.md`.
- `docs/bugs/20260619-215229-tracks-perform-should-be-navigation-not-layers/note.md`.
- `docs/bugs/20260620-112546-remove-unnecessary-text-in-the-new-nav-b/note.md`.
- `docs/bugs/20260620-135925-choose-phrase-layer-is-unnecessary-text/note.md`.
- `docs/bugs/20260622-130446-the-track-selector-has-several-issues-th/note.md`.
- `docs/bugs/20260704-085618-the-layer-buttons-should-be-less-long-to/note.md`.
- `docs/bugs/20260704-091036-layers-buttons-should-be-narrower/note.md`.
- `docs/ux-canon.md`.
