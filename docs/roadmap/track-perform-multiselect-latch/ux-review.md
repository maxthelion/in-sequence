---
verdict: accepted
selected_prototype: 01-inline-matrix-editing.html
reviewed: 2026-05-03
prototypes_reviewed:
  - prototypes/01-inline-matrix-editing.html
  - prototypes/02-edit-set-sidecar.html
feedback_applied: []
---

# Track Perform Multi-Select And Latch - UX Review

## What Works

### 01-inline-matrix-editing.html (selected direction)

This variant best matches the v1 product shape already implied by the notes and
user stories. Track selection stays on the same row as the perform values, so
the performer can assemble an edit set and then act on a real cell without
detouring into another region of the screen. That directly supports
[[story:1]], [[story:2]], and the acceptance signal that the first usable
version should prefer direct matrix interaction over a side inspector.

The shared latch switch is in the right conceptual place. It is one page-level
mode that applies consistently to Fill and Repeat, which is the cleanest
expression of [[story:4]], [[story:5]], and [[story:6]]. The prototype also
demonstrates the critical interaction difference rather than only describing it:
momentary mode uses mouse-down and mouse-up, while latched mode toggles on
click.

Selection scope is legible enough for live use. Selected rows get a distinct
background, the header lists the current selection, and the interaction log
confirms which tracks received the linked edit. That is sufficient to make the
blast radius of a linked edit predictable before the user clicks.

### 02-edit-set-sidecar.html (useful comparison, not the recommended direction)

This variant proves a real trade-off rather than a cosmetic alternative. The
sidecar makes selection membership and shared settings unmistakable, so it is
strong on caution and reviewability. It is useful as a rejected comparison
because it shows what the safer but slower version looks like.

Its main value is to demonstrate that the roadmap item is not only about
"showing selected tracks clearly." It is also about preserving a fast
performer loop once the set exists.

## What Fails or Is Missing

### 1. Variant B breaks the intended v1 interaction model

The sidecar makes ordinary shared edits take an extra trip away from the row
the performer is touching. That weakens the direct-manipulation feel and cuts
against the explicit acceptance signal that linked edits should begin from the
matrix itself. It is safer, but it is not the right default for a live
performance surface.

### 2. The selected direction still needs stronger mode visibility at spec time

Prototype A places the latch mode correctly, but the risk is mode carry-over:
the performer could leave the page in latched mode and not notice immediately
on the next gesture. The prototype is good enough to approve, but the spec
should require latch state to stay visible even when the page is scrolled or
the selection summary becomes crowded.

### 3. Release behavior is demonstrated for mouse input, not broader exit cases

The prototype correctly shows pointer-down and pointer-up for momentary binary
controls, but it does not yet show what happens if the press is cancelled or
the pointer leaves the hit target before release. That is not a reason to send
the prototypes back, but it is a concrete follow-up for the spec and
implementation handoff.

## UX Checklist

| Criterion | Result |
|-----------|--------|
| Direct matrix editing remains the happy path | Pass for variant A; fail for variant B |
| Selected-track scope is visible before a linked edit | Pass |
| Latch semantics are shared across binary controls | Pass |
| Momentary versus latched behavior is demonstrated, not only described | Pass for variant A; partial for variant B because Repeat is edited from the sidecar rather than from the row context |
| Variants are strategically different rather than cosmetic | Pass |
| Off-path UI is clearly prototype-grade and stubbed | Pass |
| Primary interaction budget stays tight after selection | Pass for variant A; fail for variant B |

## User-Story Goal Coverage

| Story | Coverage |
|-------|----------|
| [[story:1]] Select an edit set of tracks | Covered in both variants |
| [[story:2]] Apply one change to every selected track | Covered well by variant A; covered more slowly by variant B |
| [[story:3]] Understand which tracks will change | Covered in both variants, strongest in variant B |
| [[story:4]] Momentary behavior for binary controls | Covered in variant A |
| [[story:5]] Latched behavior for binary controls | Covered in variant A |
| [[story:6]] Shared latch model across controls | Covered in variant A |

## Recommended Direction

Accept `01-inline-matrix-editing.html` for human prototype review.

It is the only variant that keeps all three of the v1 priorities aligned:

1. the performer builds a temporary edit set on the Track Perform surface,
2. the linked edit happens directly on the matrix row they are touching, and
3. the latch model stays shared across binary controls instead of drifting
   control by control.

Keep `02-edit-set-sidecar.html` as a rejected comparison point. It is useful
evidence for why a side inspector is not the right default, but it should not
lead the implementation.

## Questions or Required Follow-up

1. Human review should specifically confirm that the header-level latch control
   stays discoverable enough once the matrix is dense and the user is moving
   quickly.
2. The next spec should define cancellation and pointer-exit behavior for
   momentary presses so the "release turns it back off" rule is not underspecified.
3. The implementation handoff should preserve the distinction already called
   out in `existing-state.md`: multi-select fan-out for authored matrix values
   is separate from the runtime overlay needed for Fill and Repeat semantics.
