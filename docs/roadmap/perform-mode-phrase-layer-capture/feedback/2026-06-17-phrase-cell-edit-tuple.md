# Phrase Cell Edit Tuple

Raw product-owner clarification:

> Cell edit is pretty messy. Needs some work. It's essentially a tuple of a
> track, layer values and value mode (per bar etc). cell settings in the
> wireframe don't make sense. xfader doesn't apply. Track pattern length etc is
> irrelevant. Probably just have a matrix of layers with the mode in each.
> Clicking on them allows editing the values and when they apply.

Interpretation for future PM/build work:

- phrase cell edit is scoped to a selected phrase, track, and layer;
- each layer cell should show the current value and value mode;
- clicking a layer cell should reveal/edit the value map for when that layer
  applies;
- global scene/crossfader settings and track pattern length do not belong in
  this track-layer cell editor;
- the primary surface should be a matrix of layer cells for the selected track.
