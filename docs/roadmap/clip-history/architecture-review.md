# Clip History Architecture Review

## Outcome

Approved with revisions.

The feature may advance to spec using the guardrails in `architecture.md` plus the decisions below.

## Approved Guardrails

- Audition uses a transient per-track pseudo-clip override.
- Audition does not mutate document truth.
- The pseudo clip becomes a real clip only when the user saves it to a pattern slot.
- The capture target is what the user heard, so post-modifier note output is the right default.
- Sixteen bars of history is enough for the initial version.
- History should be represented in a step-addressed format because pseudo-clip playback needs step-style data anyway.
- Sparse/event-style storage may be considered later as an optimization, but the first architecture should prefer the simplest representation that supports stable pseudo-clip playback and UI selection.

## Circular Buffer UI Decision

Opening Clip History should freeze a review snapshot of the circular history buffer.

While the modal is open:

- the history matrix should not drift as new notes arrive;
- selected bars should remain stable while the user auditions and chooses a pattern slot;
- new incoming generated notes can continue to be captured by the engine, but they should not mutate the modal's frozen review snapshot.

Live-follow or refresh-to-latest behavior is deferred. If added later, it must be explicit.

## Remaining Product Decision

Occupied pattern slots should not be silently overwritten.

The preferred direction is:

- empty slots save immediately;
- occupied slots require an explicit replace action.

The spec should make that interaction concrete.

## May Advance To Spec

Yes.
