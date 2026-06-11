# Resolution — 2026-06-10, commit a7e8920 on main

Addressed in the merged UI rework of the Audio Input panel
(Sources/UI/Track/TrackWorkspaceView.swift):

- "state/monitor/channel bubbles feel redundant" → the STATE/MONITOR/CHANNEL
  metric pills are removed; the Monitor and Input segmented controls are the
  single representation of that state.
- "The Arm button appears disabled. The UI should explain why" → one
  stateful button (ARM / Armed — Cancel / Recording — Cancel); when arming is
  unavailable a compact amber label states the reason ("NO INPUTS ON
  INTERFACE" / "INPUT NEEDS 2 CHANNELS"), and input options the interface
  cannot satisfy are greyed with a tooltip.
- "Plugging in a sound source did not visibly change the level indicators" /
  "share more grammar with the slicer: a waveform-style monitor" → live
  input monitoring renders a continuously rolling waveform built from live
  level snapshots (same WaveformView used by the slicer and the
  recording/loop states), with compact L/R peak meters alongside.
- "level indicators are oddly positioned" / "use space efficiently" → the
  monitor surface fills the panel; the explainer eyebrow text is gone.

Open (engine/model work, not UI): "an interface with many physical inputs
needs per-track input selection… including mono inputs and stereo pairs."
AudioInputChannel is a fixed mono1/mono2/stereo enum in the document schema;
arbitrary input/pair selection needs schema + engine routing changes. Logged
in docs/bugs/2026-06-10-qa-surface-review.md for the loop to route.
