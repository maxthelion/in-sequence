# Scenes In Phrases Prototypes

Current replacement pass:

- `03-selected-phrase-scene-rail.html`: keeps the current Phrase Matrix shell intact and uses a selected-phrase scene rail beneath the row for detailed scene editing.
- `04-inline-scene-strip-matrix.html`: keeps track cells visible while every phrase row gets a compact scene strip and the selected phrase expands inline for per-bar authoring.

Archived comparison files:

- `01-inline-bars-matrix.html`
- `02-summary-row-detail-drawer.html`
- `scene-matrix-inline.html`
- `scene-matrix-drawer.html`

Those files are historical context only. They were useful for exploring compact summaries and detail-edit affordances, but the active pass needed to preserve the real track-oriented Phrase Matrix instead of collapsing into a scene-only grid.

Both current variants use the same adversarial fixture data:

- track page `1 / 2`, so the user can see how scene authoring coexists with paging instead of replacing it;
- long phrase titles;
- mixed track types across the visible page;
- long scene names;
- a phrase with no B scene yet;
- whole-phrase and per-bar crossfader modes.

Review focus:

- whether `Tracks / Scenes` mode-switching now feels like an extension of the current Phrase Matrix rather than a separate page;
- whether scene detail belongs in a selected-phrase rail or in a per-row inline strip;
- whether phrase rows expose enough scene intent while preserving track-cell comparison;
- whether the interaction budget for static vs per-bar editing stays within two or three deliberate clicks.
