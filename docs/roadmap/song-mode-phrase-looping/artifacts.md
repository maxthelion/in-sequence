# Song Mode And Phrase Looping Artifacts

## 2026-04-29 - Tracks UI Basis Phrase Screenshot

The user attached a Tracks UI screenshot showing:

- a top-right `Basis Phrase` panel displaying `Phrase A`;
- a nearby `Perform` button;
- track cards whose pattern/layer state is interpreted relative to that basis phrase.

Design implication:

- Free-play phrase selection and phrase-cueing should update this Tracks UI basis phrase.
- The basis phrase should represent the phrase currently driving track performance/editing context, not a separate stale selection.
