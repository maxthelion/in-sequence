# Bug: Mixer send-strip FX insert is too heavy — show just a clickable name + open a modal

**Filed:** 2026-06-29 (owner, during the new-bugs verification pass)
**Area:** Mixer → Send / FX-return strips → FX insert row
**Severity:** UI / design — the inline control is too large for the strip width
**Status:** RESOLVED (2026-06-29)

## Resolution (2026-06-29)

`MixerWorkspaceView.swift`: `sendInsertRow` is now a name-only clickable button
(tiny enabled-state dot + name + chevron) that fits the slim strip; tapping it
selects the insert AND opens its editor popover in one tap. The enable/bypass
toggle, ↑/↓ reorder, and remove all moved off the row into `sendInsertEditor`
(which also gained the icon badge + kind summary for context). The separate
"Edit FX" action button + its strip-level popover were removed. No FX capability
lost. Builds; no inline controls remain on the strip row.

## What's wrong

The FX insert in a send/return strip renders a full inline control crammed into
the slim (~96pt) strip: an icon badge + the name + a value summary ("Filter /
12000 Hz") on one row, and an enable toggle + up/down reorder + trash on a second
row. It's too large for the space and reads as a cluttered card (see owner
screenshot: the "Filter / 12000 Hz" card under SEND A with a green switch + two
grey buttons).

The earlier fix (commit `4b9168e5`, bug 20260624-164500) only RE-ARRANGED these
elements (stopped the "8…" truncation by splitting into two rows). It kept the
same heavy inline-control model. The owner wants a different design, not a
relayout.

## Desired design

- The strip should list each insert as **just its name**, clickable.
- Clicking the name **opens a modal/editor** (sheet or popover) that holds the
  controls: enable/bypass, wet/dry + per-kind params, reorder, and remove.
- **Remove from the strip row:** the enable/bypass toggle, the reorder (up/down)
  buttons, and the trash button. (And drop the heavy icon-badge + value-summary
  card treatment — name-only.)

## Where (current code — Sources/UI/Mixer/MixerWorkspaceView.swift)

- `sendInsertList(_:accent:)` (~163) — the "FX" header + the per-insert list
  (`ForEach … sendInsertRow`).
- `sendInsertRow(_:bus:accent:)` (~205) — THIS is the heavy row to slim to a
  name-only clickable button. Currently has the icon badge + name + summary
  (title row) AND the enable toggle + `insertMoveButton` ↑/↓ + trash (control
  row). Tapping it selects the insert (`selectedSendInsertIDs[bus.id] = insert.id`).
- `sendInsertEditor(_:bus:accent:)` (~275) — the editor already exists, shown in a
  **popover** (~117-132) that today only opens via a separate "Edit FX" action
  button after an insert is selected. It currently has Wet slider + `sendKindEditor`
  (filter/bitcrusher/AU params) but does NOT yet have enable/bypass, reorder, or
  remove — those live only in the row.

## Implementation direction (for later)

1. Slim `sendInsertRow` to a name-only button: insert name (truncate/scale as
   needed), maybe a tiny enabled-state dot, full-width tap target → opens the
   editor directly (set `editingSendBusID = bus.id` AND select the insert in one
   tap, instead of the two-step select-then-"Edit FX").
2. Move the controls removed from the row INTO `sendInsertEditor`: add an
   enable/bypass toggle, the ↑/↓ reorder, and a remove (trash) action there, so no
   capability is lost.
3. Keep the existing "Add" / empty "+" tile behavior. The same pattern likely
   applies to the **Scenes** +FX treatment and possibly the master-bus insert row
   — check whether they should share the slim-name + modal grammar (the master-bus
   `insertRow` in MixerView.swift uses a two-row grammar too; decide if it gets the
   same treatment or stays).

## Acceptance

- A send strip shows inserts as compact clickable names that fit the strip width
  with no truncation/clutter.
- Clicking a name opens a modal/editor with enable/bypass + params + reorder +
  remove; none of those controls remain inline in the strip.
- No FX capability is lost vs today.
