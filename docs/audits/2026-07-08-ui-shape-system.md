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
| `StudioMetrics.emphasisBorderWidth` | `2` |
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
- Border width token uses: 233
- Raw corner radius literals: 10
- Raw stroke width literals: 38
- Raw shape width helper literals: 2

Most chrome already uses the token scale. The remaining risk is not absence of
tokens; it is inconsistent role mapping and raw exception drift.

## Screenshot Finding

The screenshot mismatch was real in code:

- The track and kit top headers used `CornerRadius.section` (`22`) in
  `CompactTrackDetailHeader` and `DrumKitMatrixView.header`.
- The unified section switcher and tab well underneath used
  `CornerRadius.control` (`12`) by design in `StudioSectionPills` and
  `StudioTabWell`.
- The pattern slot buttons used `CornerRadius.control` (`12`), but their border
  width is routed through `TrackPatternSlotPalette.borderWidth(for:)`, which
  returned raw `1` for normal slots and `2` for destination mode instead of the
  canonical `StudioMetrics.borderWidth` (`1.5`) and a named emphasis token.

Resolved in the follow-up shape pass:

- `CompactTrackDetailHeader` now uses `CornerRadius.control` (`12`).
- `DrumKitMatrixView.header` now uses `CornerRadius.control` (`12`).
- `TrackPatternSlotPalette` now uses `StudioMetrics.borderWidth` (`1.5`) for
  normal slot borders and `StudioMetrics.emphasisBorderWidth` (`2`) for
  destination emphasis.
- `TrackFillPreviewControl` now uses `StudioMetrics.emphasisBorderWidth` for
  its active-state outline.

The top track region no longer mixes `22`, `12`, `1.5`, `1`, and raw `2` in one
visual cluster. It now uses the same 12px corner role as the tab/well cluster
and the same named stroke-width tokens as the rest of the chrome.

## Broader Findings

- `section` (`22`) is rare: now only 5 token uses. It currently behaves like a
  large surface shell and is no longer used by the compact track/kit headers.
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
- Selected/focused emphasis: use `StudioMetrics.emphasisBorderWidth` instead of
  raw `2`.
- Drawing-only exceptions: keep local literals only with a short
  `ux-canon-allow` explanation or move them into component-local named
  constants.

For the reported track surface, the applied fix is:

1. Treat the top header as a peer of the tab strip for shape purposes.
2. Change both `CompactTrackDetailHeader` and `DrumKitMatrixView.header` from
   `CornerRadius.section` to `CornerRadius.control`.
3. Change normal `TrackPatternSlotPalette` borders from raw `1` to
   `StudioMetrics.borderWidth`, and destination emphasis to
   `StudioMetrics.emphasisBorderWidth`.
4. Add the strict shape audit to CI after current raw literals are tokenized or
   annotated.

## New Diagnostic

Added `scripts/diagnostics/ux-shape-audit.sh`.

Default mode reports token usage and raw shape literals without failing. It also
supports `--strict`, which fails when raw radii/strokes/helper widths remain.
This lets us use it now as an audit tool and later ratchet it into the
zero-tolerance UX canon once intentional drawing exceptions are marked.
