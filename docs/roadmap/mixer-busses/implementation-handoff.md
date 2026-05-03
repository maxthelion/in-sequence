# Mixer Busses - Implementation Handoff

## Feature

- **ID:** 5
- **Title:** Mixer Busses
- **Status:** `inventory`
- **Stage:** `ready-for-build-queue`
- **Source directory:** `docs/roadmap/mixer-busses/`

---

## Authoritative Context

| Artifact | When to open it |
|---|---|
| [plan.md](plan.md) | First build document to read. It sequences verification, persisted model work, graph ownership, shared mixer extraction, and regression coverage. |
| [spec.md](spec.md) | Primary product contract. Use this when behavior, acceptance criteria, or non-goals are in question. |
| [architecture.md](architecture.md) | Bus-routing, persistence, and graph-ownership guardrails. Read before touching document, engine, or mixer code. |
| [architecture-review.md](architecture-review.md) | Accepted architecture verdict. Calls out the authoritative solo-model choice and the need to share insert UI instead of forking it. |
| [existing-state.md](existing-state.md) | Current code reality: all tracks route directly to `preMasterMixer`, bus types do not exist yet, and insert UI is still private to Scenes Perform. |
| [user-stories.md](user-stories.md) | User intent and acceptance signals for bus creation, routing, strip controls, inserts, and naming. |
| [ux-review.md](ux-review.md) | Accepted mixer-lane UX review for the three-zone layout and routing-in-flight treatment. |
| [prototype-approval.md](prototype-approval.md) | User approval and the three locked product decisions for v1. |
| [prototypes/mixer-busses-variant-a.html](prototypes/mixer-busses-variant-a.html) | Selected prototype for the bus lane, strip anatomy, add-bus affordances, and route-change feedback. |
| [decisions.md](decisions.md) | Settled product decisions the build must not reopen. |
| [notes.md](notes.md) | Original product framing and the cross-links to Mixer Main Out and Send Effects. |

The implementation loop should consume this handoff first, then follow the
links above in the order shown unless a plan phase points somewhere more
specific.

---

## Goal

Add ordinary DAW-style mixer busses to the shared mixer surface so a user can
create a bus, route tracks into it, control the grouped signal with bus-level
mix controls and inserts, and keep the whole feature composed inside the same
tracks -> busses -> master workspace. This is a conservative routing extension,
not a new routing paradigm.

---

## Chosen Product Direction

The approved direction is the three-zone mixer lane from
`prototypes/mixer-busses-variant-a.html`: track strips on the left,
user-created busses in the middle, and master out on the right per
`[[feature:mixer-main-out]]`. Solo is additive across tracks and busses, bus
inserts are global in v1, and deleting a routed bus requires confirmation that
lists the affected tracks before rerouting them to master.

Do not add bus-to-bus routing, scene-scoped bus insert chains, or a second
prototype pass unless later feedback explicitly invalidates the approved lane.

---

## Guardrails The Implementer Must Preserve

1. `Project` remains the single persisted owner of authored bus state:
   `buses`, track `outputBusID`, and authored mute/solo state live in the
   document, while effective mute and rewiring-in-flight state stay runtime-only.
2. Bus-host lifecycle and track rewiring belong to the engine / graph layer,
   not SwiftUI. Views may author state and trigger canonical mutations, but
   they must not mutate AVAudioEngine topology directly.
3. Graph topology changes follow the existing stop / reconnect / restart
   discipline used by the master chain. Adding or deleting a bus, rerouting a
   track, and topology-changing insert edits are rebuilds, not parameter-only
   updates.
4. Stable `MixerBus.id` routing identity must survive graph rebuilds even if
   live `AVAudioNode` instances are recreated.
5. Solo remains one persisted authored truth plus runtime-derived effective
   mute. Do not persist shadow solo-membership or exclusion state.
6. Shared mixer and insert UI should be extracted or parameterized instead of
   forking a second mixer shell or a bus-only insert editor.
7. Busses output only to master in v1. Do not introduce bus chaining,
   multi-destination routing, or send-return behavior in this feature.
8. Bus inserts remain global across scene changes, while master inserts stay
   scene-scoped. The UI must keep that scope difference legible.

---

## Implementation Read Order

1. Read this handoff.
2. Read [plan.md](plan.md) and execute in phase order.
3. Use [spec.md](spec.md) as the product contract for behavior and acceptance
   criteria.
4. Use [architecture.md](architecture.md) and
   [architecture-review.md](architecture-review.md) as hard guardrails for
   persistence, graph ownership, solo semantics, and shared-surface extraction.
5. Read [existing-state.md](existing-state.md) before changing document model,
   mixer routing, insert-host code, or mixer UI structure.

Do not reopen decisions already settled in [decisions.md](decisions.md) or
[prototype-approval.md](prototype-approval.md). If current code reality
conflicts with those decisions, capture it as an implementation finding and
stay within the documented guardrails.

---

## Build Sequence

Follow the plan's phases in order:

1. **Phase 0 - verification**
   Confirm the model/codable landing zones, the graph mutation seams, and the
   current mixer / insert reuse seams before writing code.
2. **Phase 1 - persisted bus and solo model**
   Add bus collections, track routing state, solo persistence, and focused
   document/session mutations with legacy-safe decoding.
3. **Phase 2 - engine-owned bus graph and routing**
   Introduce bus hosts, track rerouting, bus insert topology ownership, and
   runtime-derived additive solo behavior.
4. **Phase 3 - shared mixer surface extraction**
   Extract shared strip shell and insert-list surfaces instead of duplicating
   mixer UI or insert editing behavior.
5. **Phase 4 - mixer busses UI and UX**
   Compose the approved bus lane, add-bus flow, routing selectors, bus strips,
   rename, solo banner, and delete confirmation into the mixer workspace.
6. **Phase 5 - regression coverage and polish**
   Add migration, graph, engine, and focused mixer UI coverage for the
   highest-risk routing and solo behaviors.

---

## Files And Modules Expected To Change

| Area | Expected work |
|---|---|
| `Sources/Document/Project.swift`, `Project+Codable.swift`, `StepSequenceTrack.swift`, `TrackMixSettings.swift` | Add persisted bus, routing, and solo state with additive decode defaults |
| Document / session mutation surfaces | Add canonical authored mutations for bus creation, routing, rename, mix state, inserts, and delete-with-reroute |
| `Sources/Audio/MainAudioGraph.swift` plus new or extracted bus-host support | Own bus-host lifecycle, rerouting, insert-topology rebuilds, and parameter updates |
| `Sources/Engine/EngineController.swift` | Coordinate topology rebuilds and derive additive solo state without view-owned playback truth |
| `Sources/UI/Mixer/**` and extracted shared insert/strip views | Compose the track/bus/master surface, routing selectors, in-flight labels, and bus strip states |
| `Tests/SequencerAITests/**` across document, audio, engine, and mixer coverage | Prove migration defaults, rerouting, bus controls, solo derivation, and delete confirmation behavior |

No `docs/specs/**`, `docs/plans/**`, wiki updates, or unrelated roadmap items
belong in this build.

---

## Acceptance Focus

The implementation is ready to ship to review only when these outcomes are
observable:

- Adding a bus immediately inserts a strip in the bus lane and makes the new
  bus available to all routing selectors.
- Each track can route to `Master` or any current bus, and the active selector
  shows `Applying...` during reroute-in-flight rebuilds.
- Bus strips expose inserts, fader, pan, mute, solo, and inline rename while
  keeping bus outputs fixed to `-> Master`.
- Additive solo works coherently for master-routed and bus-routed tracks and
  surfaces one `SOLO ACTIVE` banner with `Clear Solo`.
- Empty busses remain operable, and deleting a routed bus requires
  confirmation before rerouting affected tracks to master.
- Shared insert and strip UI is reused or extracted rather than duplicated.

See [spec.md](spec.md) Section 6 for the full acceptance criteria and
[plan.md](plan.md) for the phase-by-phase verification steps.

---

## Non-Goals And Deferred Follow-Ups

- No bus-to-bus routing or bus chaining.
- No multi-destination or parallel track outputs.
- No scene-scoped bus insert chains in v1.
- No second mixer shell or bus-only insert editor fork.
- No send-effects routing; that remains roadmap item 6.
- No new effect model beyond the approved bus-host reuse or extraction work.
- No arrangement-level or clip-level visualization of busses.

---

## Open Questions

There are no user-blocking product questions left for this item.

The remaining checks are implementation findings already called out in
[plan.md](plan.md):

- confirm the exact model and codable landing zones for bus, routing, and solo
  additions
- confirm which graph changes are topology rebuilds versus parameter updates
- confirm the lightest extraction path for shared strip and insert UI
- confirm the most practical document, graph, engine, and UI test files to
  extend

These are implementation checks, not reasons to relitigate the PM direction.
