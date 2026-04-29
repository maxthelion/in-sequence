# Scenes In Phrases Notes

## Raw Intent

```text
The phrase view should have two modes: tracks and scenes. In the scene version, A and B scene slots should be configurable per phrase, as well as the position of the slider. I imagine a similar matrix with only 3 columns for A, crossfader, and B. Different modes for the crossfader should be allowed, such as value for the whole phrase, or bars within it having different values.
```

## Clarified Concern

Captured from user clarification on 2026-04-29.

## Notes

The phrase view should have two modes: tracks and scenes. In the scene version, A and B scene slots should be configurable per phrase, as well as the position of the slider. I imagine a similar matrix with only 3 columns for A, crossfader, and B. Different modes for the crossfader should be allowed, such as value for the whole phrase, or bars within it having different values.

## Normalized Concept

The Phrase Matrix should support two modes:

- `Tracks`: the existing track/layer phrase matrix.
- `Scenes`: a phrase-scoped scene matrix.

In Scenes mode each phrase row exposes three main columns:

- Scene A slot;
- Crossfader value/automation;
- Scene B slot.

The phrase should be able to define which scene is loaded into A and B, and how the crossfader behaves during the phrase.

Crossfader modes to explore:

- one value for the whole phrase;
- per-bar values inside the phrase;
- possibly richer automation later if the architecture supports it.

This should remain distinct from live Scene Perform: this item is about authored phrase-level scene state, not only a perform-time scene crossfade.
