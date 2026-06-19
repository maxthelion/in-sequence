# Expand A Kit Row Into Inline Part Controls (Accordion)

Raw product-owner clarification:

> we want to be able to expand a row in the kit view and then get the options
> from the normal track view (sound, routing, fx, macros), or maybe we re-use
> that other view. ... When it expands, it should be to the right of the part
> title. It should be like an accordion, where the other parts shrink vertically.
> The steps should be on a tab like in the track view, potentially allowing
> switching between a clip and a generator (with modifier).

Interpretation for build:

- A kit part row **expands as an accordion**: the detail panel opens **to the
  right of the part name** (in the row's step area); the row grows vertically and
  the other parts stay compact. The user never leaves the kit matrix.
- The panel **reuses the single-track detail surfaces** inline (no second
  editor): Steps/Clip · Sound · FX · Macros · Mixer, plus an "Open full editor"
  affordance for the full dive-in.
- **Steps/Clip is a tab** (like the track view) with a **Clip ↔ Generator**
  switch; the generator can carry a **modifier**.
- Sound/FX/Macros/Mixer never contradict the linked kit pattern; only Steps/Clip
  can, resolved by **break** (see linking item).
</content>
