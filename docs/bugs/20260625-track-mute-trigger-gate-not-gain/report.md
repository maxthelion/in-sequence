# Bug: track mute is a trigger-gate, not a gain (wrong shape)

Found: adversarial review 2026-06-25.

Track mute gates note *firing* (EngineController guards :1937/:1980/:2347/:2361/
:2383 — `guard !effectiveMutedTrackIDs.contains(track.id)`), it does NOT set a
mixer gain. So a sound already ringing isn't cut, and on unmute nothing returns
until the next trigger ("returns on next note"). BUS mute, by contrast, IS gain
(`MixerBusHost.applyMix:73` `inputMixer.outputVolume = effectiveMute ? 0`). The
two mutes mean different things. The perform-mode LAYER mute shares the same
trigger-gate guard (`currentLayerSnapshot.isMuted`).

Fix: track mute → ramped gain (mirror bus mute), unify mixer + layer mute on it;
keep MIDI/external gated (no gain). Task #49. See
docs/plans/2026-06-25-audio-graph-watertight.md.

Status: RESOLVED — mute-as-gain (#49)
