---
feature: autoslice-algorithm
created: 2026-06-07
status: architecture-accepted
sources:
  - README.md
  - docs/roadmap/autoslice-algorithm/notes.md
  - docs/roadmap/autoslice-algorithm/user-stories.md
  - docs/roadmap/autoslice-algorithm/existing-state.md
  - docs/roadmap/autoslice-algorithm/ux-review.md
  - docs/roadmap/autoslice-algorithm/prototypes/bpm-hypothesis.html
  - docs/roadmap/autoslice-algorithm/prototypes/loop-boundary-heuristic.html
---

# Autoslice Algorithm Open Questions

Autoslice Algorithm is an isolated algorithm/prototype lane for turning an
imperfect loop recording into ranked, musically plausible slice and loop
candidates. This reconciliation accepts conservative v1 defaults for the
questions left by the accepted UX review so the architecture can define a
builder-facing contract without pulling the work into the production app.

## Summary

- Architecture-answerable gaps accepted: 4
- Product defaults accepted: 4
- Product-owner lock needed now: no
- Ready for build-loop promotion: no

The lane is ready for a downstream `spec.md` pass after the accepted
architecture. It is not implementation-ready until spec, plan, and
implementation handoff artifacts exist.

## Accepted Answers

### Q1 - Role Classification Scope

**Accepted v1 default: spectral transient role classification is deferred.**

The selected direction may carry optional transient role metadata through the
algorithm contract, but v1 does not require the algorithm to infer kick, snare,
or hat roles from PCM spectral features.

Accepted behavior:

- detected transients default to `unknown` role;
- if a fixture or caller supplies roles, role weighting may use them;
- kick and snare may receive heavier alignment weights than hats or unknown
  transients when role weighting is enabled;
- positional auto-classification from the prototype remains a sandbox/debug
  helper, not production truth;
- no production code should pretend positional roles are spectral
  classification.

Reason:

The accepted prototype demonstrates that role weighting can affect ambiguous
rankings, but `existing-state.md` confirms there is no slice-level role
classifier in the app. Requiring spectral classification would turn this lane
from boundary scoring into a larger audio-classification project. Carrying an
optional role field preserves the future extension without blocking the core
BPM, grid-alignment, and boundary-search stories.

### Q2 - Trim And Search Range

**Accepted v1 default: search for loop starts within a bounded extra-audio
window, defaulting to 500 ms and never exceeding 1000 ms in the algorithm
configuration.**

Accepted behavior:

- candidate loop starts search forward from the sample head;
- the loop end is derived from the selected BPM/bar hypothesis duration;
- candidates whose loop end would exceed the usable sample duration by more
  than a small tolerance are rejected;
- positive duration error means the sample has extra audio that can be trimmed
  or excluded;
- slightly-too-short samples are detected and scored harshly, not repaired in
  v1;
- default search step is 5 ms;
- candidates closer than 20 ms in start offset are de-duplicated.

Reason:

The notes call out 50-200 ms of bleed as the important problem, and the UX
review rejects the one-16th-note cap from the weaker prototype. A 500 ms
default covers the stated adversarial case without making the heuristic search
feel unbounded. A 1000 ms maximum preserves the sandbox's exploratory range
for fixtures while keeping production candidate generation finite.

### Q3 - Multi-Hypothesis BPM Iteration

**Accepted v1 default: automatically evaluate duration-windowed BPM/bar
hypotheses and return one merged ranked candidate list.**

The user should not have to choose one BPM hypothesis before boundary scoring.
The algorithm should generate BPM/bar hypotheses from duration, run the
boundary scorer for each viable hypothesis, then merge candidates by composite
score.

Accepted behavior:

- supported bar counts are 1, 2, 4, and 8;
- supported BPM range defaults to 60-200 BPM;
- BPM hypotheses are generated on a 0.5 BPM grid;
- a BPM/bar pair is viable when its expected loop duration fits within the
  sample duration plus the accepted shortfall tolerance and leaves no more
  than the accepted extra-audio search window;
- exact duration-inversion values may be reported as diagnostics, but the
  production contract must be trim-aware so overlong samples can still surface
  their real BPM;
- the result is a flat ranked list containing the BPM, bar count, loop start,
  loop end, and score components for each candidate.

Reason:

The accepted UX review recommends sandbox 1 as the upstream duration clue and
sandbox 3 as the main boundary direction. Exact duration inversion alone can
understate BPM on overlong recordings, so the accepted production contract
uses duration as a bounded candidate window rather than as the final answer.
Transient-to-grid alignment is the deciding signal.

### Q4 - Candidate Audition Semantics

**Accepted architecture boundary: the algorithm returns auditionable ranges,
but it does not play audio or own UI audition behavior.**

Accepted behavior:

- every candidate includes start and end frame/time values suitable for a
  future preview;
- candidate IDs or ranks are stable within one analysis result;
- the algorithm may include enough detail for a future UI to draw grid and
  transient overlays;
- no current PM artifact assumes an engine command, waveform preview, or
  production slicer UI;
- audition remains a future integration concern for the spec/plan that brings
  the algorithm into the app.

Reason:

All accepted prototypes stub audition. The current request is architecture for
the Swift-facing algorithm contract, not production UI or engine integration.
Defining return data now keeps candidate audition possible later without
inventing a playback path before the algorithm is specified.

## Deferred

- Spectral kick/snare/hat classification from PCM.
- Repairing genuinely too-short samples by stretching, padding, or accepting
  loop ends beyond available audio.
- Production slicer UI, waveform overlay selection, and audition controls.
- Writing `SliceSet`, `SliceMarker`, or `SliceMode` changes.
- In-app persistence of ranked candidate history.
- User-selectable algorithm tuning controls beyond fixture/debug harnesses.

## Product-Owner Attention

No product-owner question is required for the next spec pass.

The accepted defaults preserve the product intent: get usable loop candidates
quickly, show multiple plausible options, and keep happy accidents bounded by
explicit scores. A product-owner lock would only be needed if v1 must include
spectral role classification or a literal in-app audition UI before the
isolated algorithm contract is implemented.
