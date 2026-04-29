# Drum Parts As A Group Artifacts

## 2026-04-29 - Individual Drum Part Page Screenshot

The user attached a screenshot of the current `Kick` drum-part page showing:

- a single drum part presented as its own track/page;
- a pattern slot row for that part only;
- a clip step editor for the selected part;
- a destination/sample panel on the right;
- no visible relationship to sibling drum parts in the same kit/group.

Design implications:

- The part page needs controls near the top to move left/right through sibling parts in the drum group.
- The part page needs an entry point for opening the drum track/group view.
- The group view likely needs a matrix with part names on the left and steps across the row.
- Pattern independence between parts must be represented honestly; a kit-level pattern selector may need to map to a set of part pattern IDs.
- Some rows may be clips, generators, or different layers, so the group matrix may need mixed editable/read-only states rather than pretending everything has the same editor.
