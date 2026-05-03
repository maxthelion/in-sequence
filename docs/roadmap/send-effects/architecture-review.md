---
verdict: accepted
reviewed: 2026-05-03
---

# Send Effects — Architecture Review

Sources consulted: `docs/roadmap/send-effects/architecture.md`,
`docs/roadmap/send-effects/decisions.md`,
`docs/roadmap/send-effects/prototype-approval.md`,
`docs/roadmap/send-effects/ux-review.md`,
`docs/roadmap/send-effects/user-stories.md`,
`docs/roadmap/send-effects/existing-state.md`,
`wiki/pages/engine-architecture.md`,
`wiki/pages/routing.md`,
`Sources/Audio/MainAudioGraph.swift`,
`Sources/Audio/AudioInstrumentHost.swift`,
`Sources/Audio/SamplePlaybackEngine.swift`,
`Sources/Audio/MasterBusHost.swift`,
`Sources/Document/Project.swift`,
`Sources/Document/Project+Codable.swift`,
`Sources/Document/TrackMixSettings.swift`,
`Sources/Document/ProjectDelta.swift`.

---

## Summary

The architecture is coherent enough to advance to spec. The proposed split
between persisted send settings and transient AVAudioEngine nodes matches the
current document and engine boundaries, and the recommended track-level fan-out
is consistent with the graph pattern already used for master A/B branching.

The main revision to carry into spec is that the user-approved decisions from
May 3, 2026 are no longer open questions: send inserts are global, send returns
connect to `finalOutputMixer`, and muted tracks do not contribute wet send
signal in v1. The spec should treat those as settled inputs and tighten the
delta/mutation contract so there is one canonical way to propagate send changes.

---

## Approved Guardrails

### 1. Persisted versus transient state split is correct

The document should own authored send amounts and authored send-bus insert
state only. Runtime mixers, return nodes, and any editor-selection state remain
transient. That follows the same boundary the project already uses for
`MasterBusState` versus `MasterBusHost` and avoids UI-only playback truth.

### 2. Track-level fan-out is the right audio-graph direction

`MainAudioGraph.installMasterChains` already proves this codebase can use
`AVAudioConnectionPoint` fan-out safely. Applying the same pattern at the
track-output boundary is the credible way to preserve a full dry path to
`preMasterMixer` while feeding Send A and Send B in parallel. The architecture
is right to keep send amount changes as gain writes, not graph rewires.

### 3. A dedicated send host is the correct ownership boundary

The current `MasterBusHost` is explicitly master-specific. A separate
`SendBusHost` per bus is the right v1 ownership split, provided it reuses the
same graph-rebuild discipline, AU caching pattern, and main-thread mutation
rules instead of forking a second, inconsistent insert-hosting model.

### 4. Shared mixer-lane coordination is correctly called out

The architecture correctly recognizes that Send Effects, Mixer Busses, and
Mixer Main Out all target the same mixer surface. The send feature must extend
that shared workspace rather than introducing a second bus/editor surface with
duplicated truth.

---

## Rejected Or Revised Guardrails

### 1. Resolved product decisions must not stay framed as blockers

`architecture.md` still presents insert scope, return destination, and muted
track send behavior as open questions. They were explicitly approved on
May 3, 2026 in `prototype-approval.md` and restated in `decisions.md`.
The spec should treat these as fixed:

- Send A and Send B inserts are global in v1.
- Send returns connect to `finalOutputMixer`.
- Muted tracks contribute neither dry nor wet signal in v1.

### 2. The change-propagation contract needs one canonical path

The architecture proposes `TrackMixSettings.sendA/sendB` and also proposes a
new `ProjectDelta.trackSendChanged`. The current codebase already has
`ProjectDelta.trackMixChanged(trackID:mix:)`. The spec should choose one
contract and stick to it. Duplicating both paths would create avoidable drift
between document mutations and engine apply logic.

### 3. Mute and post-fader semantics need to be specified together

The accepted decision says muted tracks do not feed sends, and the user stories
assume post-fader sends in v1. The spec should therefore place the send tap
after the same level/mute control that defines the audible dry path. If the tap
lands on the wrong side of mute or fader application, the implementation can
accidentally ship pre-mute or pre-fader behavior while still looking correct in
the UI.

---

## Open Architecture Questions

No user-blocking architecture questions remain.

The spec still needs to settle three implementation-level choices explicitly:

- whether send amounts extend `TrackMixSettings` or move into a dedicated nested
  send-settings type;
- whether the existing `MasterBusInsert` schema is generalized now or wrapped
  behind a send-specific adapter first;
- the exact UI contract between the mixer strip send knobs and the bus-detail
  editor surface so the implementation does not invent a second bus UI.

These are spec decisions, not reasons for another architecture pass.

---

## Risks The Architecture Pass Missed

### 1. Delta duplication between mix changes and send changes

If the implementation adds `trackSendChanged` while also widening
`TrackMixSettings`, there are two plausible hot paths for the same authored
state. That is a maintainability and correctness risk. The spec should require
exactly one engine-facing delta path for per-track send changes.

### 2. Insert-model duplication across master, bus, and send hosts

The architecture notes that `MasterBusInsert` is master-specific, but it does
not make the non-duplication bar explicit enough. Shipping separate but nearly
identical insert schemas for master, user busses, and sends would fork the
document model and the editor surface. The spec should require either a shared
insert model or a deliberate, documented reason to keep them distinct.

### 3. Engine restart coordination across hosts

`MasterBusHost` already rebuilds graph topology, and Mixer Main Out introduces
metering concerns around the same final output path. A send-host rebuild cannot
stop and restart the engine in isolation without coordinating with the existing
graph owner. The spec should assign one restart coordinator so send-bus rebuilds
do not race meter taps or master-chain updates.

---

## Recommendation For The User

Accept the architecture direction and move to spec, but carry three hard
constraints forward:

1. treat the May 3, 2026 send decisions as authoritative inputs;
2. define a single delta/mutation path for send-level changes;
3. keep send-host graph rebuilds under the same central engine coordinator as
   the master-bus path.

With those constraints, Send Effects remains an additive extension of the
current mixer and audio-graph model rather than a broad rewrite.

---

## May Advance To Spec

Yes.
