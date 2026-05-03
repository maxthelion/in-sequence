# Scenes In Phrases Prototypes

> Advisory: Superseded by [[feedback:20260503-153024-prototypes-feedback]]. The next prototype pass must extend the existing track-oriented Phrase Matrix shape: tracks across the top, phrases down the rows, phrase controls plus track paging, and scene authoring folded into that workspace. Do not treat the current files as the accepted direction.

- `scene-matrix-inline.html`: keeps editing anchored in the phrase row by expanding an inline editor under the selected phrase.
- `scene-matrix-drawer.html`: keeps the grid compact and moves detailed scene editing into a right-hand drawer.

Both variants use the same adversarial fixture data:

- long phrase titles;
- long scene names;
- a phrase with no B scene yet;
- whole-phrase and per-bar crossfader modes.

Review focus:

- whether `Tracks / Scenes` mode-switching feels understandable inside the existing phrase matrix;
- whether story 5 benefits more from inline action locality or from a denser, more scannable matrix;
- whether the crossfader column reads clearly enough before opening deeper controls.
