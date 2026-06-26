# Implementation plan — AU instrument as a drum-part sound source

Derived from a read-only architecture pass (2026-06-26). The hard engine work is
already done; this is mostly UI surfacing + one independent bug fix.

## Key finding
A drum part is a standalone `StepSequenceTrack` (groupID → kit `TrackGroup`)
carrying its own `Destination`. `Destination.auInstrument(componentID:stateBlob:)`
**already exists** (`Sources/Document/Destination.swift:30`) and the engine already
routes a `.sample → .auInstrument` destination change through
`setEditedDestination` → `.fullEngineApply` → `syncAudioOutputs` (builds an
`AudioInstrumentHost` keyed `.track(memberID)`) + `syncSampleMixers` (ramp-removes
the old sample voice via `rampMixersToSilenceThenDetach`, Hard-Rule-5 safe).
Per-part AU preset persistence exists via `writeStateBlob(_, target: .track(id))`.

So: no new model/engine type is needed. The gap is UI + the X-click wiring.

## Step 1 — X-click bug (smallest, independent, machine-verifiable)
The drum-part Sound mini-tab passes **`onRemove: {}`** (a no-op) at
`Sources/UI/DrumGroup/DrumKitMatrixView+Accordion.swift:333`, so clicking the
sampler card's X (`Sources/UI/SamplerDestinationWidget.swift:138-143`) does
nothing. The report's "capture of empty part if the cross is clicked" is the
*intended, missing* behaviour. Fix: wire `onRemove` to
`session.setEditedDestination(.none, for: memberID)` (mirror
`TrackDestinationEditor.swift:691`) + record the empty-part capture through the
existing capture path (`DrumKitMatrixView+Capture.swift`), guarded so a transient
empty is NOT silently written into the `.seqai` document (Document-truth-vs-runtime
guardrail). Verification: machine (session-mutation + capture unit test).

## Step 2 — engine regression-lock (no/tiny new code, machine-verifiable)
Tests proving `.sample → .auInstrument → .sample` for a part yields the right
`pipelineShape`, AU host keyed `.track(memberID)`, sample-voice removal, and that
the sampler chokepoint ramps to silence before detach on swap-to-AU. Use the
`audioOutputFactory` hook (`EngineController.swift:239`) — no real AU needed.

## Step 3 — UI: surface AU + preset picker in the Sound tab (mixed tier)
Branch `expandedSoundTab` (`DrumKitMatrixView+Accordion.swift:309-335`) on the
member's resolved destination kind:
- `.sample` → today's `SamplerDestinationWidget` + a "Load AU…" affordance
  (reuse `AddDestinationSheet.swift:20-75`) → `setEditedDestination(.auInstrument(...), for: memberID)`.
- `.auInstrument` → an AU panel reusing the per-track flow bound to `memberID`:
  `PresetBrowserSheet` + `AUPresetRowView` + `engineController.loadPreset(_, for: memberID)`
  + `presetReadout(for: memberID)` + `writeStateBlob(_, target: .track(memberID))`,
  with an X to remove the AU.
Keep `filter` dormant-but-stored for an AU part (hide, don't delete — restores on
toggle back to sampler). Verification: machine (builds, view-model tests, visual
render) but **real AU instantiate/preset/sound is human-tier**.

## Step 4 — human acoustic pass (gating, human-only)
Real AU on a drum part during playback: live sampler↔AU swap (clicks/hung notes),
preset persistence across save/reload, X-click clear. Unattended agents cannot
instantiate a real AU or hear audio (AGENTS.md audio tier); the routing-stress rig
cannot reach `.auInstrument`.

## Hazards
- Rule 3: AU notes already sample-stamped via `host.play(noteOnSampleTime:)`; do
  NOT add a main hop (the existing `AudioInstrumentHost.performOnMain` is debt).
- Rule 5: sampler-voice removal on swap uses the fixed `removeTrack` ramp path
  (good); the AU *attach* during playback is the unproven leg → human pass.
  Ensure the swap does not route through the still-hard-cutting route-switch
  teardown (`docs/bugs/20260626-route-switch-teardown-hard-cut/`).
- `.inheritGroup` + group-member mute intersects an open product decision
  (`docs/human-attention/DECISION-au-group-member-mute.md`) — keep Step 3 scoped to
  per-part own-AU; defer inherit-aware behaviour.

## Critical files
- `Sources/UI/DrumGroup/DrumKitMatrixView+Accordion.swift` (Sound tab + X no-op — Steps 1 & 3)
- `Sources/UI/SamplerDestinationWidget.swift` (sampler card + X; sampler-vs-AU branch point)
- `Sources/UI/TrackDestinationEditor.swift` (per-track AU + preset-browser flow to reuse)
- `Sources/Engine/EngineControllerMixSync.swift` (`syncAudioOutputs`/`syncSampleMixers`)
- `Sources/App/SequencerDocumentSession+Mutations.swift` (`setEditedDestination`, `writeStateBlob(.track:)`, `setFilterSettings`)
