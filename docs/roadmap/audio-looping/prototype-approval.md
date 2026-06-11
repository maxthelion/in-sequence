---
feature: audio-looping
created: 2026-06-04
status: approved-target-not-v1-contract
selected_prototype: prototypes/looping-page-primary.html
sources:
  - docs/roadmap/audio-looping/ux-review.md
  - docs/roadmap/audio-looping/open-questions.md
  - docs/roadmap/input-audio/spec.md
  - docs/roadmap/input-audio/architecture.md
---

# Audio Looping Prototype Approval

`prototypes/looping-page-primary.html` remains the accepted product direction
for the Audio Looping macro performance page.

The prototype is approved as target intent because it expresses the right
mental model: a focused live-looping surface that shows loop-capable tracks,
lets a performer arm them, triggers recording from one macro control, exposes
loop playback state, and clears captured loops without making the performer
return to detailed track setup.

## V1 Approval Boundary

This prototype is **not** approved as a literal v1 builder contract yet.

The accepted prototype predates landed Input Audio v1. It assumes multiple
loop-capable tracks and simultaneous global recording across armed tracks.
Input Audio v1 has landed with a one-audio-input-track limit and no shared input
distribution layer.

Before spec or build-loop promotion, the product owner must choose whether:

- Audio Looping v1 narrows to a one-capable-track macro page on top of Input
  Audio v1; or
- Audio Looping waits until multiple audio input tracks and shared input
  distribution are in scope.

Recommended default: narrow v1 to one capable track now, while preserving this
prototype as the target for the later plural live-looping expansion.

## Carry-Forward Intent

Regardless of the Q1 scope answer in `open-questions.md`, the following intent
is approved and should carry forward:

- the page is a performance surface, not an input setup editor;
- the page consumes Input Audio runtime state rather than owning parallel arm,
  monitor, recording, loop, or failure state;
- state must remain legible under live-performance pressure;
- clear loop remains part of the Audio Looping workflow;
- no loop-capable tracks is a required empty state;
- recorded-loop failure or invalid input route must be visible locally on the
  affected card.

## Prototype Adjustments Required Before Build

If the lane proceeds with the recommended one-track v1, builder-facing docs and
any updated design evidence must narrow the prototype as follows:

- render at most one capable track, because Input Audio v1 permits only one;
- show the canonical selected bar length from the Input Audio track;
- replace prototype-local Play/Mute semantics with Input/Loop monitor mode;
- reflect loop-empty, recording, playback, invalid-route, and failure states
  from Input Audio runtime state;
- include the no-capable-track empty state;
- define clear loop as runtime buffer reset, not destructive re-record;
- defer simultaneous multi-track global record and shared input distribution.

## Readiness

Prototype approval is packaged for target intent, but the lane is not ready for
build-loop promotion. It still needs the product-owner scope lock in
`open-questions.md` resolved, then accepted architecture, spec, plan, and
implementation handoff.
