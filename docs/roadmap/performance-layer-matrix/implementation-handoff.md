# Performance Layer Matrix Implementation Handoff

Build the approved low-fidelity performance layer selector as a focused product slice.

## Intent

Tracks and Phrase should share a common performance-layer grammar. The performer should be able to choose what each track card or phrase cell is controlling without leaving performance context.

The layer selector temporarily replaces the track cards with layer choices. When a layer is chosen, the surface returns to the normal cards with that layer active.

## Approved Direction

- Primary prototype: `docs/roadmap/performance-layer-matrix/prototypes/tracks-layer-select-balsamiq.html`
- Product note: `docs/roadmap/performance-layer-matrix/README.md`
- Important correction: options with variants should show those variants inline on the first layer-selection screen. Do not require a second picker step for common choices.

Examples:

- Pattern exposes P1-P16 inline.
- Note Repeat exposes Off and common repeat/roll/hold variants inline.
- Step Order exposes Off and named maps inline.

## First Slice

Implement the Tracks page layer-selection mechanism first.

Expected behavior:

- A visible layer control opens a temporary layer-selection surface.
- Selecting a plain layer immediately changes the active performance layer and returns to track cards.
- Selecting an inline variant changes the active performance layer plus variant and returns to track cards.
- The selected layer/variant is legible on the track cards.
- Existing track-card behavior should be preserved unless it conflicts with this shared performance grammar.

Keep variant authoring and detailed Step Order map management out of this slice. Those belong in a management/settings surface, not in the performance selector.

## Quality Bar

- This is performance UI, not administration UI.
- Do not add a second-step modal/picker for common variants.
- Do not duplicate existing pattern/track controls if the same affordance can be reused.
- Keep the layout close to the prototype, but adapt to the app's current visual system.
- Produce screenshots showing the default track cards, the layer-selection surface, and at least one inline variant selection.

## Later

After the Tracks slice is coherent, the same grammar should be applied to Phrase so phrase rows/cells can use the same layer-selection idea.
