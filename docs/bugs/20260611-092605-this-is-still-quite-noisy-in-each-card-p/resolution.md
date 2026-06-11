# Resolution

Fixed.

- `Sources/UI/PhraseCells/PatternIndexCellPreview.swift` — the pattern cell is
  now a 4×4 matrix of 16 pills (one per pattern slot, matching the 16
  options), with the active slot lit in that pattern's identity colour and
  the cell tinted to match. The "P1" / "Pattern slot" caption is gone — the
  lit pill and the colour are the value (ux-canon rules 1/3/11). Because this
  is the shared component, the phrase matrix, tracks edit grid, and live view
  all pick up the same fix.
- `Sources/UI/Theme/StudioTheme.swift` — new `patternPalette` /
  `patternColor(_:)` tokens: 16 stable hues so P3 is the same colour on every
  surface.
- `Sources/UI/TracksMatrixView.swift` (`TrackMatrixCard`) — the
  "PAT… / SIN… / LIVE" chip row above each card's value is removed entirely:
  the action-bar layer control already names the active layer, inherit/single
  shows as the muted cell variant, and linked-to-edit-set state was already
  carried by the amber card chrome. When the pattern layer drives the card in
  perform mode, the whole card takes the selected pattern's colour.

Deliberately not done: the owner floated that in the phrase view the pills
"can represent the value per bar of the layer" — that is a new visualisation
concept (per-bar value readout inside matrix cells) and is not built here;
phrase-view pattern cells show the same 4×4 slot matrix as everywhere else.
