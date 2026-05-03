# Selective Scene Inputs Notes

## Raw Intent

```text
Scenes are basically like special busses that contain all tracks by default.
But we could make them more selective about the inputs, so that a signal from
an input only goes to B, and we can crossfade to it.
```

## Normalized Concept

In the v1 mixer model, ordinary mix sources feed both master Scene A and Scene B
by default. Scenes differ by master insert chain and crossfader value, not by
source membership.

This deferred feature explores a later routing extension where each source can
feed:

- Scene A only;
- Scene B only;
- both scenes.

Example use case:

```text
sequenced tracks -> Scene A + Scene B
live input       -> Scene B only
crossfader       -> morph from sequenced material into live input treatment
```

## Deferred Rationale

Selective scene input membership touches routing, metering, mixer UI,
persistence, and performance workflows. It should stay out of the first
mixer/main-out pass, where all ordinary sources feed both scenes and only the
master insert treatment differs.
