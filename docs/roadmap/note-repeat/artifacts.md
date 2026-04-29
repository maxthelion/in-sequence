# Note Repeat Artifacts

## 2026-04-29 - Track Perform Page Screenshot

The user attached a screenshot of the current Track Perform page showing:

- the active perform layer set to `FILL`;
- track cards with large on/off perform controls;
- a drum group section with child part cards;
- the `Basis Phrase` panel and `Perform` button.

Design implication:

- Note Repeat should appear as a perform-page option analogous to Fill.
- The UX should support holding or latching repeat state per track while preserving the fast on/off card interaction model.
- The interval selection belongs in the layer model, with options such as repeat 16, repeat 32, and repeat 64.
- Sub-step repeat intervals require architecture investigation into how the sequencer represents timing below the current step grid.
