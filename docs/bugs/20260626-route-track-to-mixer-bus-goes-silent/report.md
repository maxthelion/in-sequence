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

## ROOT CAUSE + FIX (2026-06-26)
Two distinct breaks, both proven by live-graph instrumentation:
1. **Single-track silence:** a freshly-created `AVAudioMixerNode` with ZERO input
   connections has no resolvable output format, so `engine.connect(busInputMixer →
   preMaster)` made at install time (before any track fed the bus) is **silently
   discarded by AVAudioEngine**. Nothing re-established it. Fix:
   `MainAudioGraph.ensureMixerBusTerminalReachesPreMasterOnMain(busID:)` re-asserts
   the bus terminal → preMaster edge once the bus gains an input (resolvable
   format), called from `connectPreparedSampleVoiceOutput`. The fast-path gate
   (`isBusVoicePoolReadyForPlayback`) now also requires
   `mixerBusTerminalReachesPreMaster` so a dropped bus output can't pass silently.
2. **Multi-track / drum-kit collision:** every track routed its 4 voice mixers to
   the SAME bus input buses 0..3 → later tracks overwrote earlier ones. Fix:
   `connectPreparedSampleVoiceOutput` allocates a UNIQUE free input bus per voice
   mixer across the whole bus (`firstFreeInputBus`); teardown frees them (no leak).

Bus meter tap also fixed (re-attached after the bus gains a formatted output).

**Verified:** `BusVoicePoolRoutingTests` (3/3: reaches preMaster; two tracks get
distinct input buses, no collision; reroute frees buses), `MasterRenderTests`
master-RMS (bus-routed track reaches master — the bug). Build + realtime-path +
ownership lints green. The bus-METER assertion is skipped on this CoreAudio-
degraded host (HALC proxy errors make offline meter taps read -inf even though
audio reaches master) — verify the meter on a healthy host (after a coreaudiod
restart) and by ear. Status: FIXED (routing); meter-tap fix pending healthy-host
confirmation.
