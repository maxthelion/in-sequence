# Tracks navigator: selection + actions nav (navigate to phrase views)

Raw product-owner clarification (2026-06-20):

> Tracks navigation page is fixed re layers, but not re making selections — that
> was in the prototype. Actions should appear in a nav when a selection is made.
> Layer perform, or "global perform" (bad name) should be available as options,
> but it should NAVIGATE TO THE VIEWS IN PHRASES, rather than being a version of
> this view. Also there was a deferred item about creating performance groups.

## Authoritative IA (docs/specs/ux-rethink-2.md)
- **Tracks (simple track view):** Selection mode on/off; actions include creating
  a performance group; clicking opens the track; add new tracks.
- **Performance group** limits a selection of tracks for performing either a
  single layer or the same value — and lives under the *phrase* view
  (Named current phrase → Phrase layers / Performance groups).

## Build now
- Tracks navigator gains a **Selection mode** (on/off). With it off, tapping a
  tile opens the track detail (current behavior). With it on, tapping toggles
  multi-selection (tiles highlight).
- When ≥1 track is selected, an **actions nav** appears with:
  - **Layer perform** → set the selection as the phrase perform scope, switch the
    top-level workspace to **Phrase**, and open the **Layers** tab. (Navigate to
    the existing phrase view — NOT a tracks-local perform surface.)
  - **Same value** (the better name for "global perform" / global apply) → switch
    to **Phrase → Global Apply** with the selected tracks pre-set in its track
    selector.
- These reuse `SequencerDocumentSession.performTrackScope` and navigate via the
  workspace `section` binding + the phrase tab. No bespoke perform/layers UI in
  the tracks view.

## Still deferred (do NOT build the object yet)
- The durable **performance-group** object (defer note
  `perform-mode-phrase-layer-capture/feedback/2026-06-17-defer-performance-groups.md`:
  "needs more thought… separate exploration before build"). Surface a
  **Create performance group** action in the selection nav, but as a
  not-yet-built / disabled affordance until the performance-group spec lands.
