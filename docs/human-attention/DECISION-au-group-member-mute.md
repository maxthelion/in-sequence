# DECISION NEEDED: muting one member of a shared-host AU group

Surfaced by the routing watertight work (adversarial review, 2026-06-26). Not a
regression introduced here — a pre-existing architectural conflict the mute
review exposed. **Does NOT block the rest of the audio work; I'm proceeding with
R3/R4/P0-P3 and will implement your choice when you pick one.**

## The conflict
`.inheritGroup` AU tracks that share a destination resolve to ONE
`AudioInstrumentHost` with ONE output mixer (EngineControllerRoutingHelpers
.group key; AudioInstrumentHost.outputMixer/currentMix). The mixer UI
(MixerView) shows an independent mute per member. But a shared host has a single
output gain — **you cannot gain-mute one member without muting all** — so
per-member mute is unsatisfiable at the gain layer (last-writer-wins clobber).
With routed-audio trigger-gates removed (correct for the gain model), a routed
note into a "muted" group-AU member can sound.

## Options (pick one)
- **(a) Group-level mute for shared-host members** — collapse the per-member
  mute UI for inherit-group AU members; mute = OR of members on the host.
  Simplest; changes UX (no per-member mute when sharing a host).
- **(b) Per-member trigger-gate into the shared host** — keep per-member mute by
  gating that member's note dispatch into the host. Preserves UX; reintroduces a
  trigger-gate shape for this one path (inconsistent with the gain model; "mute"
  there waits for next note, not instant).
- **(c) Per-member gain stage** — give each inherit-group member its own gain
  node before the shared host. Cleanest UX + consistent gain mute; real graph
  change with CPU/voice cost.

Recommendation: (a) if per-member mute of shared-host members isn't a deliberate
feature; (c) if it is and the cost is acceptable.

## Status / coverage
Sample/slicer mute, solo, drum-group, document mute are all correct (ride the
.mixer source through the OR-combine). Only the shared-host AU member case is
affected. `trackAppliedOutputGainForTesting` now works for AU so the gate can
observe it once an AU is present (the unattended rig can't instantiate an AU —
TCC — so this path is covered by EngineControllerRoutedMuteTests + that readout).
