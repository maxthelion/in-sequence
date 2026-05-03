---
verdict: accepted
reviewed: 2026-05-03
---

# Mixer Main Out — Architecture Review

Sources consulted: `docs/roadmap/mixer-main-out/architecture.md`,
`docs/roadmap/mixer-main-out/decisions.md`,
`docs/roadmap/mixer-main-out/ux-review.md`,
`docs/roadmap/mixer-main-out/user-stories.md`,
`docs/roadmap/mixer-main-out/existing-state.md`,
`wiki/pages/architecture-guardrails.md`,
`wiki/pages/engine-architecture.md`,
`wiki/pages/routing.md`,
`Sources/Document/MasterBus.swift`,
`Sources/Audio/MainAudioGraph.swift`,
`Sources/Audio/MasterBusHost.swift`,
`Sources/Engine/EngineController.swift`,
`Sources/UI/Mixer/MixerWorkspaceView.swift`,
`Sources/UI/Mixer/ScenesWorkspaceView+Perform.swift`.

---

## Summary

The architecture is coherent enough to advance to spec. It keeps document truth,
runtime overlay state, and realtime metering responsibilities in the right
places, and it does not require a broad rewrite of the existing master-bus
model. The user-resolved decisions in `decisions.md` settle the two main product
forks: a single global post-blend master fader and a higher-weight scene rule
for insert display during crossfade.

The main revision to carry into spec is tighter coupling between the chosen
master-gain node and the metering tap point. If those land on different sides of
the final-output gain stage, the meter can stop reflecting what the user
actually hears.

---

## Approved Guardrails

### 1. Persisted versus transient state split is correct

The document should own authored master-bus state only: scene insert chains,
crossfader authored value, and the new global master output gain. Meter peaks,
clip latch state, and crossfader live overrides remain transient runtime state.
That matches the architecture guardrails and the existing `EngineController`
overlay pattern.

### 2. Reusing scene-scoped inserts is the right v1 boundary

The architecture correctly avoids inventing a new global insert-chain model for
this feature. `MasterBusScene.inserts` already exists, mutation helpers already
exist, and the approved "show the scene with the higher crossfader weight" rule
keeps the mixer column aligned with the current model.

### 3. Crossfader ownership is correctly preserved

The mixer master column must read and write the same
`masterBusPerformanceOverlay.crossfaderOverride` path the Scene Perform view
uses now. Extracting the crossfader into a shared view component is the right
presentation refactor; introducing a second local crossfader state would be a
regression.

### 4. Realtime metering isolation is correctly framed

The proposed `MasterMeterPublisher` boundary is credible. The architecture
correctly treats tap callbacks as realtime-thread work, keeps publication to the
main thread explicit, and avoids moving metering into document truth.

### 5. Engine graph mutation discipline is correct

Master-bus topology and gain changes should continue to flow through
`performOnMain` and the existing `MainAudioGraph` ownership. The architecture
does not propose view-driven direct writes into AVAudioEngine nodes, which is
the right constraint.

---

## Rejected Or Revised Guardrails

### 1. Meter tap placement must be coupled to the master-fader node

The architecture accepts a **global post-blend master gain** and also recommends
metering from `finalOutputMixer`. That is only correct if the final audible
master gain is applied on `finalOutputMixer` itself. If implementation instead
adds a new dedicated gain node *after* `finalOutputMixer`, a tap on
`finalOutputMixer` becomes pre-fader metering and no longer reflects the actual
main output level after master-fader moves.

Spec requirement:

- if `finalOutputMixer.outputVolume` becomes the global master output gain, tap
  `finalOutputMixer`;
- if a new post-fader node is introduced, move the tap post-fader so the meter
  reflects audible output.

### 2. Resolved decisions should not remain framed as blocking questions

`architecture.md` still refers to questions 1, 2, and 6 as if they require
`open-questions.md`. `decisions.md` already resolves them. The spec should treat
those decisions as settled inputs, not reopen them or block on a missing
questions file.

### 3. Narrow-width collapse policy is new behavior, not an existing one

The proposed compact-strip fallback below 540 pt is plausible, but
`MixerWorkspaceView` does not currently have a narrow-width adaptation pattern to
inherit. The spec may adopt the compact-strip behavior, but it should describe
it as a new UI requirement rather than as continuity with an existing mixer
behavior.

---

## Open Architecture Questions

No user-blocking architecture questions remain.

The spec still needs to make three implementation-level choices explicit:

- whether the global master gain reuses `finalOutputMixer.outputVolume` or adds
  a dedicated post-fader node;
- the exact dB scale / Unity labeling for the fader and meter;
- the compact-width presentation rule for the master column.

These are spec decisions, not reasons for another architecture pass.

---

## Risks The Architecture Pass Missed

### 1. Backward-compatible decoding for `masterOutputGain`

Adding `MasterBusState.masterOutputGain` changes the document model. The
architecture notes migration implications, but the spec should explicitly
require default-on-decode behavior for older `.seqai` documents plus round-trip
tests proving the new field is optional for legacy data and persisted for new
documents.

### 2. Post-fader versus pre-fader metering mismatch

If the spec does not lock the tap point to the chosen gain-node placement, the
feature can ship with a meter that ignores master-fader moves or clip latches at
the wrong point in the chain. This is a product-visible correctness risk, not
just an implementation detail.

### 3. Duplicate action affordances between Scenes Perform and Mixer

The current Scenes Perform crossfader includes `Reset` and `Save Blend`
behaviors. Story 4 only requires inline visibility and control from the mixer.
The spec should decide whether the mixer column includes those extra actions or
only the live crossfader, so the product does not end up with two superficially
similar but behaviorally different master-performance surfaces.

---

## Recommendation For The User

Accept the architecture direction and move to spec with two explicit carry
forwards:

1. keep the conservative DAW-standard product decisions from `decisions.md`;
2. define the master-fader node and meter tap as one coupled design choice.

With those constraints, the feature remains a focused extension of the current
master-bus path rather than a rewrite.

---

## May Advance To Spec

Yes.
