# Track Setup Surface Compression

PM package for bug-intake `G7: Slicer / Sample Player / Track Header
Compression` plus the capture-backed clip-header report
`docs/bugs/20260706-113305-move-lane-length-layer-chooser-randomize`.

## Builder Slice

- handoff: `builder-slice.md`
- status: initial builder-facing PM package drafted
- target: one compact setup-surface pass across the track detail header, clip
  header controls, slicer source/slice surfaces, and sample-player waveform
  controls.

The slice is visual-economy and control-placement work. It should reduce
duplicated headings, grey helper lines, repeated pills, and stacked control
rows while preserving the authored track setup workflow.

## Scope Boundary

Keep separate from AU runtime safety, mixer/send follow-up, Scenes IA,
Track/Phrase Perform interaction, and broad drum-kit matrix implementation.
The transient-finding quality note
`docs/bugs/20260623-131606-i-feel-like-the-transient-finding-and-se` is deferred
from this setup-surface slice unless a builder finds a tiny visual affordance
gap; actual transient analysis quality is algorithm work and needs its own
route.

## Evidence Base

- G7 bug-intake cluster in `.meta/multipass/state/bug-intake.md`.
- July 6 capture-backed bug note and row `18-track-detail-steps-clip`.
- Prior June/July owner reports that already resolved pieces of the same
  compression intent; treat them as product intent and regression guardrails,
  not as proof that the current clip-header capture is acceptable.
