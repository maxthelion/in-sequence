# Bug: routing a track back to master goes silent (loses its voices)

Found: routing-stress rig 2026-06-25. PRE-EXISTING (reproduces on base code,
fix-stashed) — not an R0-R2 regression.

`routeTrack-<idx>-to-master` (after the track was routed to a mixer bus) drops
the track to silence and it never recovers (cumulative -inf masterPeak for the
trailing ops). Root cause (per cycle-fix agent's analysis): the `teardownBus`
branch of `SamplePlaybackEngine.setTrackOutputBus` removes the track's bus voice
pool WITHOUT re-establishing its master voices. The master output chain is
structurally intact (preMaster->...->finalOutput preserved) — it's the track's
SOURCES dropping, a voice-pool surgery bug.

This is part of the in-progress routing-source-mixer-split area. Watertight-
relevant (a routing edit silently loses audio), so fix it in the watertight push.

Acceptance: route a track to a bus, then back to master, during playback — the
track keeps sounding (voices re-established on master). routing-stress reports 0
SILENCE for route/send/scene/add/remove ops.

Status: RESOLVED — route-to-master voice-loss fix (#53/#57)
