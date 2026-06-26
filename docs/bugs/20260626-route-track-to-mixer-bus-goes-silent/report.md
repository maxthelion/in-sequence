# Bug: routing a track's OUTPUT to a mixer bus makes it go silent

**Filed:** 2026-06-26 — found by Max in the real-audio verification pass (#42).
**Severity:** HIGH — core routing: a track routed to a mixer bus is inaudible.
**Status:** Open — record (Max's pass found a cluster; triage/fix later).

## What happens
With a sounding sample track and a mixer bus "FX Bus" (bus0, appliedGain=1.0,
not muted), routing the track's OUTPUT to the FX bus makes the track go SILENT.
Routing it back to master, it plays again. Deterministic (not the intermittent
#57 route-to-master case — this is the route-TO-bus direction, always silent).

Status at the time: `track1OutputBus=FX Bus`, `track1Peak=-inf`, `bus0Peak=-inf`,
`bus0AppliedGain=1.0`, `bus0EffectiveMuted=false`. Back on master:
`track1OutputBus=master`, `track1Peak=-7.0` (audible).

## Why the rig missed it (important)
The routing-stress rig exercises `routeTrackToBus=1:0` and asserts the bus's
applied gain, but the **per-bus meter tap is a known-broken/diag-only gap** — the
rig cannot measure the bus's actual audio, so its route-to-bus check could not
detect that the track went silent through the bus. A human ear caught it. The bus
audibility is a real rig blind spot.

## Fix direction (later — needs root-cause)
Trace `setTrackOutputBus(busID:)` → `prepareBusVoicePool` (sample path) and the
bus→master wiring (`installMixerBuses` should connect each bus input mixer →
preMaster). Candidates: (a) the track→bus connection isn't established (the
track's terminal/voice output not connected to the bus input mixer), or (b) the
bus input mixer isn't connected through to preMaster/master, or (c) the bus voice
pool is built but not wired. Verify bus→master is actually connected and the
track's output reaches the bus input.

ALSO: fix the per-bus meter tap (or add a bus→master audibility assertion) so the
rig can catch this class — currently `bus<N>Peak` is -inf even with signal, which
is why this slipped through. Without that, route-to-bus is effectively unverified
by automation.

## Relates to
R1/R2 (track output routing to mixer buses), #53/#57 (route-to-master silence —
sibling direction). The bus-meter-tap gap is noted in
wiki/pages/app-command-channel.md as a coarse-metric caveat.
