# Post-Merge Feedback: Input Routing And Monitor UI

Date: 2026-06-06
Feature: Input Audio
Source: product-owner review of the merged UI

## Feedback

The current Input Audio UI appears incomplete for real audio-interface use.

- The project settings menu can select the audio interface, but an interface
  with many physical inputs needs per-track input selection. The Input Audio
  screen needs a way to choose which hardware input or input pair is used,
  including mono inputs and stereo pairs.
- The Arm button appears disabled. The UI should explain why arming is not
  available, or enable it once a valid route exists.
- Plugging in a sound source did not visibly change the level indicators. The
  monitor should provide clear live feedback that audio is arriving.
- The current level indicators are oddly positioned in the layout and do not
  read as a useful monitoring surface.
- The state/monitor/channel bubbles feel redundant and can probably be removed
  or folded into clearer controls.
- The screen may need to share more grammar with the slicer: a waveform-style
  monitor could make input activity and capture state more legible. It may be
  worth trying a few UI variants. If cheap enough, the waveform could render
  continuously; otherwise it should still show enough live signal evidence to
  be useful.

## Rework Shape

Treat this as post-merge product feedback for Input Audio. The loop should
decide whether to reopen a focused build-loop rework or route a smaller
main-branch fix.

The rework should preserve the original Input Audio feature intent, but tighten
the UI around actual recording/monitoring use:

- select the physical input source explicitly;
- distinguish mono input and stereo-pair selection;
- make arming availability understandable;
- make incoming signal visible;
- use space efficiently;
- avoid decorative status pills that do not help the workflow;
- consider a waveform/monitoring surface aligned with the slicer grammar.

## Open Design Question

What is the simplest monitor surface that makes live input trustworthy without
adding expensive audio visualization work or a second slicer-like interface?
