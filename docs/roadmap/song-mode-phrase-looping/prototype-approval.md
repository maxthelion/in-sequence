---
status: accepted
approved: 2026-04-30
recorded: 2026-06-04
selected_prototypes:
  - prototypes/01-transport-phrase-indicator.html
  - prototypes/02-tracks-basis-phrase-tracking.html
source_review: docs/roadmap/song-mode-phrase-looping/ux-review.md
---

# Song Mode And Phrase Looping Prototype Approval

## Approval

Adopt both reviewed prototypes as the approved design basis for this PM lane:

- `prototypes/01-transport-phrase-indicator.html` is the primary transport
  phrase-navigation slice for Stories 1-4.
- `prototypes/02-tracks-basis-phrase-tracking.html` is the companion Tracks UI
  basis-phrase slice for Story 5.

The accepted UX review found the two prototypes complementary rather than
competing. Together they cover the transport current-phrase indicator, queued
next phrase, end-of-cycle phrase switching, immediate phrase switching, and
Tracks UI basis-phrase tracking.

## Approved Design Basis

- The transport bar should expose the currently playing phrase in free-play
  performance context.
- The transport bar should provide a phrase dropdown that can either queue a
  phrase for the next cycle or switch immediately.
- Queued phrase state should remain visible without reopening the dropdown.
- End-of-cycle switching should clear the queue and update the current phrase
  indicator.
- Immediate switching should update the current phrase immediately and clear
  any pending queue.
- The Tracks UI basis phrase should update when a phrase is queued, so edits
  and preview context follow the cued phrase.
- The Tracks UI basis phrase should update again when an immediate or
  end-of-cycle switch makes that phrase active.
- The semantic color vocabulary from the prototypes should carry forward:
  current/active state in blue, queued/preview state in amber, immediate-switch
  affordance in red.

## Screenshot Reconciliation

The artifact screenshot shows an existing top-right `Basis Phrase` panel near
the `Perform` button. Prototype 02 demonstrates an inline basis label inside
the Tracks UI grid. The approval does not choose between those placements.
The spec must reconcile them and preserve the product rule: free-play phrase
selection and phrase cueing update the basis phrase that drives track
performance/editing context.

## Not Resolved By Approval

The approval does not resolve:

- queue clear/cancel behavior;
- queued-basis edit semantics if the queue is cancelled;
- dropdown dismissal details;
- long queued-phrase name treatment in the transport bar;
- stopped-state phrase queue behavior;
- Tracks UI grid resize/scroll behavior for phrases with different bar counts;
- ownership and publication of live phrase state in the engine/model/view
  boundary.

Those items are recorded in `open-questions.md` for the architecture/spec
passes.

## Readiness Effect

This approval closes the prototype-selection gap for the lane. It does not make
the feature builder-ready: accepted architecture, accepted spec, build plan, and
implementation handoff are still required before promotion.
