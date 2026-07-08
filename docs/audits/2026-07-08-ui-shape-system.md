# UI Shape System Audit

Date: 2026-07-08

## Trigger

The drum-kit track screenshot showed the top header/pattern element reading as
rounder and slightly different in stroke weight than the tab well and matrix
elements underneath.

## Current Tokens

Defined in `Sources/UI/Theme/StudioMetrics.swift`:

| Token | Value |
| --- | ---: |
| `StudioMetrics.borderWidth` | `1.5` |
| `CornerRadius.workspace` | `30` |
| `CornerRadius.chrome` | `28` |
| `CornerRadius.section` | `22` |
| `CornerRadius.panel` | `18` |
| `CornerRadius.subPanel` | `16` |
| `CornerRadius.tile` | `14` |
| `CornerRadius.control` | `12` |
| `CornerRadius.chip` | `10` |
| `CornerRadius.badge` | `8` |
| `CornerRadius.mini` | `4` |

## Audit Snapshot

`scripts/diagnostics/ux-shape-audit.sh` currently reports:

- Files scanned: 147
- Corner radius token uses: 459
- Border width token uses: 230
- Raw corner radius literals: 10
- Raw stroke width literals: 39
- Raw shape width helper literals: 3

Most chrome already uses the token scale. The remaining risk is not absence of
tokens; it is inconsistent role mapping and raw exception drift.

## Screenshot Finding

The screenshot mismatch is real in code:

- The track and kit top headers use `CornerRadius.section` (`22`) in
  `CompactTrackDetailHeader` and `DrumKitMatrixView.header`.
- The unified section switcher and tab well underneath use
  `CornerRadius.control` (`12`) by design in `StudioSectionPills` and
  `StudioTabWell`.
- The pattern slot buttons use `CornerRadius.control` (`12`), but their border
  width is routed through `TrackPatternSlotPalette.borderWidth(for:)`, which
  returns raw `1` for normal slots and `2` for destination mode instead of the
  canonical `StudioMetrics.borderWidth` (`1.5`).

So the top region mixes `22`, `12`, `1.5`, `1`, and `2` in one visual cluster.
That is why the header/pattern strip reads as if it came from a different
corner and stroke system than the elements below.

## Broader Findings

- `section` (`22`) is rare: only 9 token uses. It currently behaves like a large
  surface shell, but it is being used for compact headers that sit directly
  beside `control`-radius tab chrome.
- `panel`, `subPanel`, `tile`, and `control` are the dominant working-surface
  radii. The app has enough tokens, but no rule that says which surface tier
  gets which token.
- Raw tiny radii (`1.5`, `2`, `6`) mostly appear in miniature previews, piano
  rolls, and grid cells. Some are legitimate drawing geometry; some should be
  promoted to named tokens or annotated.
- Raw stroke widths mostly represent selected/focused emphasis (`2`) and drawing
  geometry (`0.5`, `2.5`, `3`, `4`). Some of these are fine, but they should not
  be allowed to silently appear in shared chrome.

## Recommendation

Adopt a shape-role rule before doing piecemeal fixes:

- Workspace/window shells: `workspace` or `chrome`.
- Page-level peer modules inside a workspace: one shared radius, preferably
  `control` for the current tab grammar cluster or a newly named role if the
  owner wants a larger header style.
- Content cards/panels inside wells: `panel`, `subPanel`, or `tile`.
- Buttons, pattern slots, tabs, and value controls: `control`, `chip`, `badge`,
  or `mini`.
- Standard chrome strokes: always `StudioMetrics.borderWidth`.
- Selected/focused emphasis: introduce a token such as
  `StudioMetrics.emphasisBorderWidth` instead of raw `2`.
- Drawing-only exceptions: keep local literals only with a short
  `ux-canon-allow` explanation or move them into component-local named
  constants.

For the reported track surface, the robust fix is:

1. Decide whether the top header is a peer of the tab strip or a larger enclosing
   page shell.
2. If it is a peer, change both `CompactTrackDetailHeader` and
   `DrumKitMatrixView.header` from `CornerRadius.section` to the same role used
   by the tab/well cluster.
3. Change normal `TrackPatternSlotPalette` borders from raw `1` to
   `StudioMetrics.borderWidth`, and selected/destination emphasis to a named
   token.
4. Add the strict shape audit to CI after current raw literals are tokenized or
   annotated.

## New Diagnostic

Added `scripts/diagnostics/ux-shape-audit.sh`.

Default mode reports token usage and raw shape literals without failing. It also
supports `--strict`, which fails when raw radii/strokes/helper widths remain.
This lets us use it now as an audit tool and later ratchet it into the
zero-tolerance UX canon once intentional drawing exceptions are marked.
