# Bug: route-switch teardown hard-cuts a sounding sample track (click)

**Filed:** 2026-06-26 (adversarial review of the R3 drum-part verification)
**Severity:** CLICK (Hard Rule 5 violation) — audible glitch when re-routing a
sounding track between a bus and master.
**Status:** Open, backlog. Removal (the common case) is fixed; this route-switch
variant is deferred.

## What happens
Two sample-track *route-switch* teardown paths detach a potentially-sounding
node with no gain ramp (the exact shape Hard Rule 5 — "never disconnect a
sounding node; ramp to silence first" — forbids):

1. `SamplePlaybackEngine.setTrackOutputBus` → `.teardownBus(pool)` (bus → master):
   `teardownBusVoicePool(pool)` hard-disconnects the bus voice mixers.
2. `SamplePlaybackEngine.prepareBusVoicePool` stale / master → bus teardown:
   `teardownBusVoicePool(existingBusPool)` and the `staleTrackPool` / `staleMixer`
   / `staleFilter` detach all hard-cut.

These are the same class as the `removeTrack` hard-cut fixed on 2026-06-26 — but
they sit on a *rebuild* path (the track persists; the old route's nodes are torn
down and a new route's nodes are built in the same call).

## Why the obvious fix doesn't work
The naïve fix (mirror `removeTrack`: ramp the chokepoint, defer the teardown to
ramp completion via `rampMixersToSilenceThenDetach`, rebuild immediately)
**regressed route-to-master to full silence** — the routing-stress rig caught it:
`routeTrack-1-to-master` stayed silent across the entire 5 s audibility poll.
The route-switch rebuild (`prepareTrack` / new bus pool) depends on the old pool
being torn down **synchronously before** the rebuild runs; deferring the teardown
behind a ~12 ms ramp leaves the rebuilt voices not sounding. Reverted to the
original synchronous teardown (rig back to `SILENCE=0`, `GATE: PASS`).

Pure removal (`removeTrack`) tolerates the defer because nothing is rebuilt and
the dictionary removal is already synchronous; route-switch does not.

## Fix direction (when picked up)
A real crossfade that preserves teardown→rebuild ordering: build the new route's
nodes first (started at silence), bring them up while ramping the *old* route's
chokepoint down, and only then detach the old nodes — rather than deferring the
whole teardown. Needs care that the new voices are selectable by the tick path
*before* the old nodes go silent so there's no audible gap. Verify with the
routing-stress rig's `routeTrack-1-to-bus0` / `routeTrack-1-to-master` ops (they
already assert audibility) plus a click check on a quiet single-track fixture.

## Acceptance
Re-route a sounding sample track bus↔master with no click and no silence; rig
`routeTrack-*` ops stay audible; a quiet-fixture click check shows no
discontinuity on the switch.
## RESOLVED (2026-06-26)
Fixed with a real crossfade (not the previously-reverted defer): rampOutgoingThenSwitch ramps the outgoing chokepoint (bus trackSumMixer / master track mixer) to silence, then runs the ENTIRE teardown->rebuild block as one atomic unit (preserving ordering — avoids the route-to-master silence regression), then ramps the new route up from 0. Only engaged when the chokepoint is genuinely sounding (engine running + live in/out edges); setup/repair/offline splice synchronously. Also resolves #61 (route-to-bus click — same unramped reconnect). Verified: routing-stress GATE PASS x3, route-to-master + route-to-bus audible (no silence); RampBeforeDisconnectTests crossfade tests (ramp-taken + faded-to-silence + no-residual-silence). Final click confirmation is by-ear (Max).
