Chord track should use normal step-sequencer layer UI

Status: OPEN

Feedback source: user review of `23h-track-chord-steps`, `23i-track-chord-chords-tab`, and `23j-track-chord-inversion-layer` in gallery run `20260708-083510-in-sequence-qa-surface-coverage-main-923a889d`.

Problem:
The chord-track MVP works as a distinct track type, but the UI misses the intended step-sequencer grammar. It currently has a bespoke chord/inversion segmented control and a top-level Bake button. The desired direction is closer to the mono step sequencer and slicer layer model: normal controls at the top, normal layer handling, and chord-specific choices represented as step layers rather than a separate mini-editor.

Acceptance criteria:
- Chord track Steps/Clip uses the same overall step-sequencer UI grammar as mono tracks, including the normal top control area.
- The top controls include length controls in the normal orientation/placement.
- `Chord`, `Inversion`, and `Chord Type` are step-sequencer layers, not bespoke controls outside the layer system.
- The chord palette/progression strip remains above the tabbed area, but removes the top-level Bake action from this surface.
- The chord strip has a config button next to the plus button.
- The config button sets the progression root/scale for this chord track, defaulting to a future project root/scale when that project-level feature exists.
- Next to the plus button there is an option to choose chords from a progression.
- The Chords tab provides chord root selection through a piano-keyboard-style control, based on the pitch-generator piano but adapted for chord/progression work.
- The keyboard marks the progression root and marks scale/progression degrees (`i`, `ii`, etc.) so the user can pick musically rather than from a plain numeric root stepper.
- Chord type selection is also available as a step layer, so users can vary chord type per step using the same step/layer mental model as other lanes.
- Visual QA rows should be updated or added to cover:
  - chord Steps/Clip with normal controls visible,
  - chord layer selection for `Chord`, `Inversion`, and `Chord Type`,
  - chord config/root-scale UI,
  - progression chord picker,
  - keyboard root selection with progression markings.

Notes:
- This supersedes the rough MVP-specific chord/inversion segmented control, not the underlying chord-reference architecture.
- Preserve the architecture shipped in `e55bffc7`: chord palette belongs to the track, steps reference palette/progression data, palette edits update referencing steps, and bake/recipe preservation remain available where appropriate.
