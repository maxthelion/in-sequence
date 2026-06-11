# Post-Merge Feedback: Kit Matrix Step Editor Grammar

Date: 2026-06-06
Feature: Drum Parts As A Group
Source: product-owner review of merged Drum Group view

## Feedback

The new Drum Group view generally works well, but the kit matrix does not yet
feel like it shares the same step-editor grammar as the rest of the app.

- The steps in each drum-part row are far too small.
- The kit matrix should share a common interface with the other step sequencer
  element instead of feeling like a separate miniature representation.
- Above the multi-part view, there should be layer controls for the values
  affected by each step: note on/off, velocity, chance, and the other step
  layers that exist in the normal editor.
- Pattern selection should probably be group-level, with a 1-16 pattern row
  across the top, similar to a normal track group.
- Switching pattern should show the contents of that pattern across the running
  drum parts.
- Each part should not have its own prominent `P1` button in this matrix. In
  the current UI, clicking `P1` appears to take the user back to the individual
  track view, which does not support the group-editing workflow.
- It is unclear what should happen if one pattern slot for one drum part
  contains a generator. This likely needs UI exploration rather than a guessed
  final answer.

## Desired Direction

Treat the kit matrix as a grouped step-editor surface, not as a static
overview. It should let the user inspect and edit the same kinds of step-layer
information as the normal step editor, while showing several drum parts
together.

The rework should explore:

- larger, more usable step cells;
- common step-editor layer controls above the matrix;
- a shared pattern selector across the top of the drum group;
- removing per-row `P1` navigation buttons from the matrix;
- how generator-backed pattern slots should appear in a multi-part drum view.

## Attribution

This feedback applies to the landed Drum Parts As A Group feature:

- build loop: `build/drum-parts-as-group`
- branch: `auto/roadmap-12-drum-parts-as-group`
- landed output commit: `472583cf1fed30a085a19ead5fa5d581de12ffc7`
