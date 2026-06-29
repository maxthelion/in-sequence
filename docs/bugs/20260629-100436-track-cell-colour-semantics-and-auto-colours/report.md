# Track cell colour semantics — clarify selection border + auto-assign track colours (kit + parts shared)

**Filed:** 2026-06-29 (owner, during the new-bugs verification pass)
**Area:** Tracks page → track / kit grid cells (`Sources/UI/TracksMatrixView.swift`)
**Severity:** UX / design (clarity + feature)
**Status:** OPEN

Two related items, prompted by the owner asking why the "Snare" cell had a
different border colour than the others in the tracks grid (see screenshot:
"808" kit = green border, "Snare" = cyan border, the rest = grey).

## Part A — Attention item: what does the cell border colour mean?

Investigation finding (already traced):
- A **normal track cell** (`TrackMatrixCard`) draws its selected/focused outline
  in its **accent**, which is `StudioTheme.cyan` for a plain track (or the group
  colour if grouped) — `accent` ~line 871-877; selection stroke at ~line 680-682
  (`isSelected ? accent : (isFocused ? … : border)`, 2px when selected/focused).
- A **kit cell** (`KitMatrixCard`) draws its outline in its **group colour**,
  defaulting to `StudioTheme.success` (green) — `accent` ~line 603-604.

So in the screenshot **Snare is the selected track** (cyan) and **808 is the
selected/expanded kit** (green) — i.e. the SAME state ("selected") is shown in
TWO different colours depending on cell type. That's the ambiguity: a viewer
can't tell that cyan-Snare and green-808 mean the same thing, and grey = not
selected. Decide the intended semantics:
- Should "selected" be ONE consistent treatment regardless of cell type?
- Or does the colour intentionally encode identity (track/kit colour) and
  selection is encoded some other way (width/glow/checkmark)?
This decision should be made BEFORE Part B (it sets what colour means).

## Part B — Feature: auto-assign colours to tracks; kit + parts share a colour

Owner request: automatically assign a colour to each track, and make a **drum-kit
cell and its member parts the SAME colour** so they read as one group.

- Infra already exists: `TrackGroup.color` is consumed via
  `Color(hex: group.color)` (KitMatrixCard ~603; TrackMatrixCard grouped-accent
  ~871-873). So a grouped part can already inherit the kit's colour — verify part
  cells actually use the group colour today (the screenshot's Kick/Hat/Clap parts
  show grey, so they're likely NOT yet inheriting it when unselected).
- Needed:
  1. Auto-assign a stable colour per track on creation (palette cycling / hash),
     persisted on the track/group model.
  2. Kit cell + its part cells use that shared colour as their identity (e.g. the
     icon badge / a colour accent), so the grouping is visible at a glance — not
     only when selected.
  3. Reconcile with Part A so identity-colour vs selection-state don't collide
     (e.g. identity = badge/fill tint, selection = outline width/glow).

## Acceptance
- The meaning of a cell's border/colour is consistent and documented (selection
  vs identity disambiguated).
- Tracks get auto-assigned colours; a kit and its parts share one colour and read
  as a group in the tracks grid.

Evidence: image-1-track-borders.png (808 green, Snare cyan, others grey).
