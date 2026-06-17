# Phrase Layer Cell Shape

Raw product-owner clarification:

> In the phrase layers mode, the pattern and bar map should be 2 parts of a
> phrase cell. There should be a matrix of tracks, not a single row of columns.

Interpretation for future PM/build work:

- phrase layers mode should render tracks as a matrix of phrase cells;
- each phrase cell should contain both the selected layer value and the timing
  map for that value;
- the bar map is not a separate layer row; it is part of the cell's temporal
  representation;
- this applies beyond pattern: mute, fill, repeat, and future phrase-layer
  values need the same compound-cell treatment.
