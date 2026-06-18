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
- The transport now treats phrase playback as current plus next. In Song mode, next is proposed by the arrangement but can be overridden; in Free mode, next is empty until the user cues a phrase. A progress strip shows proximity to the next phrase boundary.
- App navigation is kept to top-level places. Once Phrase A is selected, Layers, Scenes, and Global Apply become phrase-local tabs under the phrase header.
- Phrase editing is controlled by one Perform toggle. When Perform is off, the user is editing the phrase baseline directly. When Perform is on, changes go to a temporary live copy/overlay.
- Capture, Discard, and the dirty summary stay visible in the phrase header, but they are disabled when Perform is off because there is no temporary copy to capture or discard.
- Phrase automation is still conceptually separate from the performance overlay, but the explicit Automation On/Off control was removed from this wireframe pass until the scheduled-change model is clearer.
- Layers is still matrix-first, but it is framed as editing one selected layer across the same 8-track scope. It shows the current phrase copy and the quantized bars where performance changes will be printed.
- Global Apply is a broader scoped action mode inside the phrase. It now follows the spirit of the current layer picker: an 8-column matrix of layer/value actions, a compact scope count in the top bar, a track-selector overlay that also uses 8-column cells, and shared Moment/Latch gate controls so MIDI surfaces can map to it quickly.
- Phrase Scenes was pulled back toward the current scene perform model: slot A, crossfader, slot B, and macro assignment wells inside each scene. The more detailed phrase-scene automation model still needs a rethink before it should drive the wireframe.
- Cell Detail is a contextual drill-in for one track's layers. It uses graphical mode indicators inside the layer cells, then opens an editor modal for choosing single value, per-bar values, or continuous events. It no longer includes unrelated settings such as track pattern length, scene A/B, xfade controls, or a persistent bar editor on the page.
- Capture is shown as printing the live phrase copy, with explicit bar quantize and changed cells. Capture clip is acknowledged as a sibling action but not made the centre of this prototype.
- Track selection remains a scope tool for layer perform. Performance groups are still deferred.

## Open Shape

The key unresolved product question is no longer "what does perform mean?" in the broad sense. In this model, perform means temporarily changing phrase value cells during playback, with optional quantization, and then deciding whether to print those changes into a phrase copy.

The remaining design pressure is how much of this grammar should be visible on production screens at once. The prototype intentionally over-labels scope, mode, and timing so the model can be reviewed. A later production pass can compress the labels once the grammar feels right.
