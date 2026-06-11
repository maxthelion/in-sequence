---
feature: input-audio
created: 2026-06-03
gate: prototype
verdict: accepted
source_review: docs/roadmap/input-audio/ux-review.md
selected_prototype: docs/roadmap/input-audio/prototypes/02-audio-input-track-page.html
---

# Input Audio Prototype Approval

## Verdict

Accepted.

The accepted UX review plus selected prototype
`prototypes/02-audio-input-track-page.html` are sufficient v1 prototype evidence
for the audio input track workflow. No further prototype rework is required
before `spec.md`.

This approval is PM/readiness evidence only. It does not promote a build loop,
approve production UI details, or replace the need for `spec.md`, `plan.md`,
and `implementation-handoff.md`.

## Basis

- `ux-review.md` carries `verdict: accepted` and selects
  `02-audio-input-track-page.html`.
- The selected track-page prototype covers the core v1 workflow for stories
  2-7: create/monitor an audio input track, choose bar length, quantized arm,
  record to a loop buffer, toggle input versus loop monitoring, and show
  waveform feedback.
- The prototype demonstrates the expected state lifecycle: idle, monitoring,
  armed, recording, loop, and loop-input.
- The UX review's prototype-level limitations were surfaced explicitly rather
  than hidden as implementation assumptions.
- `open-questions.md` reconciles the UX review's twelve questions to zero
  still-open product questions for v1.
- `architecture-review.md` accepts the architecture gate and carries the
  relevant prototype limitations into required spec constraints.

## Approval Scope

Approved v1 prototype evidence:

- Audio input track workspace centered on live input monitoring, loop recording,
  input/loop mode, bar length, arm/record state, and waveform feedback.
- Quantized ARM -> record -> loop interaction as the primary performance path.
- Per-track hardware channel selection as a v1 affordance.
- Slicer-like waveform presence without v1 waveform editing.

Not approved or inferred from the prototype:

- A step-sequencer grid on the audio input track.
- Overdub support.
- Sample-rate or buffer-size controls.
- BPM-change time-stretching or pitch-shifting.
- Literal production styling, spacing, or implementation structure from the
  HTML prototype.

## Required Carry-Forward

`spec.md` should preserve the accepted prototype intent while carrying the
resolved v1 constraints from `open-questions.md` and `architecture-review.md`:
one audio input track in v1, destructive replace, bar-locked loop playback,
command-queue runtime mutations, failed/missing device behavior, main-thread
waveform snapshots, and explicit v1 exclusions.

## Product-Owner Attention

No product-owner attention is needed for prototype approval. The current UX
review, selected prototype, open-question reconciliation, and accepted
architecture review are enough for PM to proceed to `spec.md`.
