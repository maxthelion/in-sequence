# Phrase Scene Macro Events

Raw product-owner clarification:

> phrase scenes is a bit janky. I'd imagine we want it more similar to the
> current model. The macros for each scene should be recordable as events. We'd
> ideally have a cell based view that has the macro values. Also, the actual
> scene in each slot (A or B) should be configurable as single value, bar, or
> continuous. We also need to consider that the values for each macro knob are
> tied to the scene that is being used. This makes it a bit complicated.

Interpretation for future PM/build work:

- phrase scene mode should not be a simple A/crossfader/B table;
- A and B slot scene IDs are phrase values with single, per-bar, or continuous
  timing modes;
- crossfader value is also a phrase value with the same timing modes;
- scene macro values should be recordable as events;
- macro value cells need scene context, because `Scene 02 / M1` and
  `Scene 07 / M1` are different authored values;
- if a phrase slot changes scenes over time, the UI must clarify which scene's
  macro values are being edited or captured.
