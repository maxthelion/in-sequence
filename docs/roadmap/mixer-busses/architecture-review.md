---
verdict: accepted
reviewed: 2026-05-03
---

# Mixer Busses — Architecture Review

Sources consulted: `docs/roadmap/mixer-busses/architecture.md`,
`docs/roadmap/mixer-busses/decisions.md`,
`docs/roadmap/mixer-busses/ux-review.md`,
`docs/roadmap/mixer-busses/user-stories.md`,
`docs/roadmap/mixer-busses/existing-state.md`,
`docs/roadmap/mixer-main-out/architecture.md`,
`wiki/pages/architecture-guardrails.md`,
`wiki/pages/engine-architecture.md`,
`wiki/pages/routing.md`,
`Sources/Document/Project+Codable.swift`,
`Sources/Audio/MainAudioGraph.swift`,
`Sources/Audio/MasterBusHost.swift`,
`Sources/Engine/EngineController.swift`,
`Sources/UI/Mixer/MixerWorkspaceView.swift`,
`Sources/UI/Mixer/ScenesWorkspaceView.swift`.

---

## Summary

The architecture is coherent enough to advance to spec. It keeps authored bus
state in the document, keeps graph mutation ownership in `EngineController` and
`MainAudioGraph`, and correctly treats user-created buses as new audio-routing
objects rather than stretching `TrackGroup` or master-bus scene state into a
different responsibility.

The main revisions for spec are about tightening decisions that are already
made. `decisions.md` resolves the biggest product forks, so spec should not
carry those paths forward as open or blocking. The spec also needs one
authoritative answer on how solo persistence is modeled across tracks and
busses so the runtime mute logic does not drift away from document truth.

---

## Approved Guardrails

### 1. Persisted versus transient ownership is in the right place

`Project.buses`, `MixerBus`, and per-track `outputBusID` are the correct
persisted additions. Runtime-only rewiring indicators, effective mute maps, and
live bus-node ownership stay out of the document, which matches the roadmap's
architecture guardrails.

### 2. Graph mutation discipline is correctly conservative

The architecture correctly treats bus creation, deletion, rerouting, and insert
topology changes as engine stop/restart operations coordinated through the
existing graph owner. That is consistent with the current master-chain pattern
and avoids view-driven direct AVAudioEngine mutation.

### 3. Bus identity and migration expectations are sound

Stable `MixerBus.id` routing references plus additive `decodeIfPresent`
migration for `Project.buses` and `StepSequenceTrack.outputBusID` are the right
compatibility story for older `.seqai` documents.

### 4. Shared-surface coordination with Mixer Main Out is framed correctly

The architecture correctly recognizes that `[[feature:mixer-main-out]]` and
this feature target one mixer surface. The outer layout container and strip
anatomy should not be duplicated independently by two implementation passes.

---

## Rejected Or Revised Guardrails

### 1. Resolved mixer decisions should not still read as blockers

Sections 4d, 4f, and 5 still describe solo mode, bus insert scope, and
delete-bus behavior as blocking questions. `decisions.md` already settles all
three:

- additive solo;
- global bus inserts;
- confirmation before deleting a routed bus.

The spec should treat those as fixed inputs and remove the old "blocking"
language so the implementation loop is not invited to reopen them.

### 2. The solo data model needs one authoritative representation

Section 3 introduces a dedicated `BusMixSettings`, then recommends adding
`isSoloed` to `TrackMixSettings` to avoid duplicate types. That can work, but
the spec must choose one final shape explicitly:

- either keep `BusMixSettings` and document why tracks and busses diverge, or
- converge on a shared mix-settings shape with additive migration defaults.

Leaving both stories half-active would create drift between persisted truth,
runtime mute derivation, and UI bindings.

### 3. Global bus inserts need an explicit UI semantics callout

The architecture makes the right product recommendation for v1: bus inserts are
global, while master inserts remain scene-scoped. The spec should say this
plainly in the mixer UI language so users do not infer that the bus column
changes with scene selection just because it sits beside the master/performance
column.

---

## Open Architecture Questions

No user-blocking architecture questions remain after `decisions.md`.

The spec still needs to make a few implementation-shaping choices explicit:

- the exact persisted type shape for track and bus solo state;
- the UX copy and visual treatment for rerouting-in-progress;
- the compact-width rule for the three-zone mixer layout;
- whether bus insert overflow is fixed-height or growth-based.

These are spec choices, not reasons for another architecture pass.

---

## Risks The Architecture Pass Missed

### 1. Track-level solo migration needs an explicit legacy story

If solo state lands on `TrackMixSettings`, the spec should require backward
decode defaults and round-trip tests for old documents that have no solo field.
The architecture implies this, but the migration contract should be explicit.

### 2. Shared insert UI extraction is a prerequisite, not a convenience

The current bus-strip design assumes reuse of insert-list behavior, but
`ScenesWorkspaceView` still owns that UI privately. The spec should treat
extraction or parameterisation of insert-strip UI as part of the feature scope,
not as optional refactoring.

### 3. Solo interaction between bus-routed tracks and master-routed tracks must stay derived

The architecture correctly says a soloed bus should make its routed tracks
audible through the bus path. The spec should keep that as derived effective
mute behavior rather than introducing shadow "solo membership" state on tracks.

---

## Recommendation For The User

Accept the architecture and move to spec with four carry-forwards:

1. additive solo is the settled v1 convention;
2. bus inserts are global even though master inserts are scene-scoped;
3. deleting a routed bus requires confirmation plus reroute-to-master on
   confirm;
4. the spec must choose one authoritative solo-state data model and keep it
   migration-safe.

With those constraints, the feature remains a contained extension of the
current mixer and routing architecture rather than a broad rewrite.

---

## May Advance To Spec

Yes.
