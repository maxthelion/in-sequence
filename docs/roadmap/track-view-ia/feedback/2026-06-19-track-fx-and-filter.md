# Per-Track FX Chain + Filter Plugin Redesign

Raw product-owner bugs (docs/bugs/20260618-*):

> Instead of the dropdown, make a plus button in the inserts section. Call it fx,
> rather than insert. Get rid of the big "Empty scene" text that's wasting space.
> Tidy up the Fx on the left. Draggable handle to change order, rather than
> arrows. Cross button to remove, on the same line as the bypass toggle. No need
> for the "enabled" text.
> Make the Filter plugin less ugly. Use radial controls where possible. More
> kinds of filters. Remove wet/dry. Have a visualisation of the shape of the
> filter curve.

Interpretation for build:

- FX chain (per track, and per kit bus): each insert row has a **drag handle to
  reorder** (not arrows), a **bypass toggle + remove ✕ on one line**, no
  "Enabled"/"Empty" filler text, and a **"+ FX"** add button (not an "Insert"
  dropdown).
- Filter plugin: **radial controls**, **more filter types**
  (LP/HP/BP/Notch/Peak/Comb/Formant…), **no wet/dry**, and a **filter-curve
  visualization**.
- Applies wherever FX live: the per-track FX tab, the kit-bus FX tab, and the
  Scenes inserts panel.
</content>
