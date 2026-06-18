# V3 Reasoning

This pass treats the phrase value cell as the reusable unit of the IA. A phrase value cell should always make four things visible:

- scope: which phrase, track, layer, scene slot, macro, or bar it belongs to;
- value: the current value or inherited value;
- mode: whether the value is single, per-bar, continuous, inherited, or live;
- timing: when inside the phrase the value applies.

That grammar is now used across phrase layers, scene editing, cell detail, and capture drawer. The goal is to stop each page inventing its own representation of "a thing that changes in a phrase".

## Changes From V2

- The separate Phrase Overview was removed because it duplicated Layers. Layers is now the default phrase surface.
- Song and phrase cue use the same 8-column cell rhythm so phrase navigation does not introduce a different grid grammar.
- Song mode now keeps the current phrase-page ingredients visible: layer selection, track page context, track headers, phrase controls, and add/duplicate/delete actions.
- In Song mode, the matrix uses explicit `now` and `next` states so it is clear which phrase is currently playing and which phrase is queued for the next cycle.
- App navigation is kept to top-level places. Once Phrase A is selected, Layers, Scenes, and Global Apply become phrase-local tabs under the phrase header.
- Perform is represented as the phrase write mode, not a destination. Capture and Discard live in the phrase header because they operate on the live phrase copy.
- Layers is still matrix-first, but it is framed as editing one selected layer across the same 8-track scope. It shows the current phrase copy and the quantized bars where performance changes will be printed.
- Global Apply is a broader scoped action mode inside the phrase: choose one layer/value and apply it immediately to all tracks in the current selection, or to all tracks when the scope is widened.
- Phrase Scenes is closer to the current scene model: slot A, crossfader, and slot B are phrase value cells, and scene macros are shown as cells tied to the selected scene slot.
- Cell Detail is a contextual drill-in for one track's layers. It uses graphical mode indicators inside the layer cells, then opens an editor modal for choosing single value, per-bar values, or continuous events. It no longer includes unrelated settings such as track pattern length, scene A/B, xfade controls, or a persistent bar editor on the page.
- Capture is shown as printing the live phrase copy, with explicit bar quantize and changed cells. Capture clip is acknowledged as a sibling action but not made the centre of this prototype.
- Track selection remains a scope tool for layer perform. Performance groups are still deferred.

## Open Shape

The key unresolved product question is no longer "what does perform mean?" in the broad sense. In this model, perform means temporarily changing phrase value cells during playback, with optional quantization, and then deciding whether to print those changes into a phrase copy.

The remaining design pressure is how much of this grammar should be visible on production screens at once. The prototype intentionally over-labels scope, mode, and timing so the model can be reviewed. A later production pass can compress the labels once the grammar feels right.
