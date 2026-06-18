# V3 Reasoning

This pass treats the phrase value cell as the reusable unit of the IA. A phrase value cell should always make four things visible:

- scope: which phrase, track, layer, scene slot, macro, or bar it belongs to;
- value: the current value or inherited value;
- mode: whether the value is single, per-bar, continuous, inherited, or live;
- timing: when inside the phrase the value applies.

That grammar is now used across the phrase overview, layer perform, scene editing, cell detail, and capture drawer. The goal is to stop each page inventing its own representation of "a thing that changes in a phrase".

## Changes From V2

- Phrase Overview is an 8-track matrix of card-like cells. Each cell is a single track card with compact layer chips inside it, rather than a vertical stack of nested layer wrappers or a separate table axis.
- Song and phrase cue use the same 8-column cell rhythm so phrase navigation does not introduce a different grid grammar.
- Song mode now keeps the current phrase-page ingredients visible: layer selection, track page context, track headers, phrase controls, and add/duplicate/delete actions.
- In Song mode, the matrix uses explicit `now` and `next` states so it is clear which phrase is currently playing and which phrase is queued for the next cycle.
- Prototype navigation is kept in a compact top mode strip. There is no persistent left rail, so the matrix remains the main object on screen.
- Layer Perform is still matrix-first, but it is framed as editing one selected layer across the same 8-track scope. It shows the current phrase copy and the quantized bars where performance changes will be printed.
- Phrase Scenes is closer to the current scene model: slot A, crossfader, and slot B are phrase value cells, and scene macros are shown as cells tied to the selected scene slot.
- Cell Detail is a contextual drill-in for one track's layers. It uses graphical mode indicators inside the layer cells, then opens an editor modal for choosing single value, per-bar values, or continuous events. It no longer includes unrelated settings such as track pattern length, scene A/B, xfade controls, or a persistent bar editor on the page.
- Capture is shown as printing the live phrase copy, with explicit bar quantize and changed cells. Capture clip is acknowledged as a sibling action but not made the centre of this prototype.
- Track selection remains a scope tool for layer perform. Performance groups are still deferred.

## Open Shape

The key unresolved product question is no longer "what does perform mean?" in the broad sense. In this model, perform means temporarily changing phrase value cells during playback, with optional quantization, and then deciding whether to print those changes into a phrase copy.

The remaining design pressure is how much of this grammar should be visible on production screens at once. The prototype intentionally over-labels scope, mode, and timing so the model can be reviewed. A later production pass can compress the labels once the grammar feels right.
