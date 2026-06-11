---
status: open
created: 2026-06-03T15:21:28Z
source: product-owner-review
applies_to: post-merge-step-sequencer
related_build_loop: build/step-sequencer
related_merge: b2977d51e63992f6e8089c47ed0e448c5255be1a
---

# Step Sequencer Post-Merge Feedback

The current Track Source clip editor does not appear to fully carry through the
approved Step Sequencer intent.

Original intent to preserve:

- Do not use a pop-up or modal as the primary way to inspect/edit a step.
- The step cell remains the editing surface.
- The selected-step layer controls appear above the grid as the Variant D
  rotary row.
- Step cells should compactly express playing, selected, active/enabled, and
  current value without wasting space or requiring secondary inspection.

Current observed issues:

- The Track Source clip editor step cells are spatially wasteful: each step has
  a large outer rounded container with a small inner control, leaving much of
  the cell empty.
- Double-click/context-menu inspection still opens `ClipStepInspectorSheet`,
  which contradicts the earlier feedback: "I don't want a UI to pop up when a
  step is selected."
- The rotary selected-step editing path exists in the slicer workspace, but it
  does not appear in the Track Source clip editor shown by the product owner.
- `StepGridView` appears to hard-code `isSelected: false`, so the generic clip
  grid cannot compose selected state with active/playing/value state.

Relevant artifacts:

- `docs/roadmap/step-sequencer/feedback/20260430-103803-prototypes-feedback.md`
- `docs/roadmap/step-sequencer/prototypes/variant-d-rotary-layer-row.html`
- `docs/roadmap/step-sequencer/spec.md`
- `docs/roadmap/step-sequencer/implementation-handoff.md`
- `Sources/UI/StepGridView.swift`
- `Sources/UI/TrackSource/Clip/ClipContentPreview.swift`
- `Sources/UI/Slicer/SliceTrackWorkspaceView.swift`

Suggested next work:

Treat this as a Step Sequencer follow-up or Track Source step-grid polish slice.
Do not build a parallel inspector. Simplify the current Track Source step grid
towards the approved Variant D interaction: selected steps should expose
editable layer controls inline above the grid, and secondary inspect/modal flows
should be removed unless they are strictly diagnostic or accessibility-only.
