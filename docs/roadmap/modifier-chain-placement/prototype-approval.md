---
status: approved
approved: 2026-05-03
prototype: prototypes/modifier-chain-placement-slot-well.html
approved_by: user
notes:
  - "Direction looks alright."
  - "Needs stronger progressive disclosure in the IA."
---

# Prototype Approval

The slot-well direction is approved for item 9, Modifier Chain Placement.

## Approval Notes

- Keep the source/modifier slot-well metaphor.
- The current prototype is directionally good, but the final IA should use more progressive disclosure.
- Primary source state and the most likely action should stay visible.
- Secondary choices, such as pool browsing, less common source creation, modifier options, and empty-pool handling, should be disclosed only when the user opens the relevant picker or needs that branch.
- Do not expose all clip/generator/modifier choices at the same hierarchy level if doing so makes the track editor feel busy.

## Implications For Architecture And Spec

- Treat the approved prototype as the structural direction, not a literal production layout.
- Resolve whether remove should auto-open the picker or reveal a plus button first.
- Specify source, generator, clip-pool, generator-pool, and modifier empty states.
- Preserve slot-level semantics: the selected pattern slot changes, not every slot on the track.
