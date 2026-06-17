# Perform Phrase Time Values

Raw product-owner clarification:

> Perform is crystalizing as alternative mode for setting things like layer
> values. Layer values within a phrase either have a single value by default.
> When performing, we are changing values at a specific point within the phrase.
> This dimension needs to be captured if the temporary performance phrase gets
> captured. If quantizing by bar is on, then the bars where it occurs become
> part of the capture.

Interpretation for future PM/build work:

- treat perform mode as a live phrase-editing mode, not a separate workflow;
- phrase-layer values default to one phrase-wide value;
- performed changes have a phrase-cycle position;
- bar quantization converts performed changes into per-bar phrase data;
- capture phrase should preserve whether each layer value is phrase-wide,
  per-bar, or finer event-like performance data.
