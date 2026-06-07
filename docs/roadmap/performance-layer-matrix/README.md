# Performance Layer Matrix

## Raw Direction

The tracks and phrase pages should share a standard grid-backed performance
layer grammar. Instead of each performance modifier inventing its own UI,
users choose a layer such as pattern, mute, fill, note repeat, volume, or step
order, then act on that layer across tracks or phrase cells.

The prototype is:

- `prototypes/tracks-layer-select-balsamiq.html`

## Current Product Shape

- The Tracks page has a compact layer selector.
- Pressing the layer selector temporarily replaces the track cards with layer
  options.
- Layers with variants expose the common variants immediately in that first
  layer-selection screen. They should not require a second click just to choose
  `Off`, a note-repeat rate, a pattern slot, or a Step Order map.
- Selecting a layer or variant returns to the normal track-card surface, with
  that layer active.
- Management and authoring of reusable variants, such as Step Order maps, live
  elsewhere, likely project settings or a dedicated management surface.
- The Phrase page should use the same mental model, but scoped to phrase rows
  and phrase-layer cells rather than track cards.

## Important Intent To Preserve

This is a performance surface, not an administration screen. The user should
be able to switch what they are performing against quickly, without hidden
drawers, modal detours, or two-step selection for common variants.

Step Order should become one selectable performance layer in this system. The
large phrase-level Step Order editor currently in the Phrase page should be
treated as management/editing UI, not the primary performable surface.

Phrase editing should also be simplified: bars and repeat/advance policy can
live directly in the left phrase row header rather than opening a large inline
panel. Song/Free transport mode and phrase repeat/loop policy need to be
reconciled so there is one obvious explanation for whether playback advances
or stays on the current phrase.

## Open Design Questions

- What is the first build slice: Tracks layer selector only, Phrase page
  simplification only, or a shared component used by both?
- Should `Free` in the transport become `Hold`/`Manual`, with phrase
  repeat/loop interpreted as Song-mode arrangement policy?
- Which performance layers ship in the first pass, and which are placeholders?
- Where exactly should variant management live for Step Order and Note Repeat?
