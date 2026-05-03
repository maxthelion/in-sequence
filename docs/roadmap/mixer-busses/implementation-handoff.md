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
| [plan.md](plan.md) | First build document to read. It sequences verification, persisted model work, engine-owned routing, shared UI extraction, and regression coverage. |
| [spec.md](spec.md) | Primary product contract. Use this when behavior, acceptance criteria, or non-goals are in question. |
| [architecture.md](architecture.md) | Routing, graph-ownership, migration, and solo-state guardrails. Read before touching the document model or audio graph. |
| [architecture-review.md](architecture-review.md) | Accepted architecture review. Highlights the final solo-model decision, global bus-insert semantics, and shared insert-shell extraction risk. |
| [existing-state.md](existing-state.md) | Current code reality: direct-to-master routing, master-only insert host/UI, and missing bus persistence. |
| [user-stories.md](user-stories.md) | User intent and observable outcomes behind the bus-routing workflow. |
| [ux-review.md](ux-review.md) | Accepted mixer-lane UX direction for tracks, busses, and master in one surface. |
| [prototype-approval.md](prototype-approval.md) | User approval of the three-zone mixer lane and the settled mixer behavior decisions. |
| [decisions.md](decisions.md) | Final product decisions for additive solo, global bus inserts, and delete-bus confirmation. |
| [prototypes/mixer-busses-variant-a.html](prototypes/mixer-busses-variant-a.html) | Selected prototype for strip order, section treatment, and routing-in-flight states. |
| [notes.md](notes.md) | Original user request and cross-feature framing with mixer-main-out and send-effects. |
| [../mixer-main-out/architecture.md](../mixer-main-out/architecture.md) | Shared mixer-surface context. Use this before duplicating strip shells or re-litigating the three-zone layout. |

The implementation loop should consume this handoff first, then follow the
links above in the order shown unless a plan phase points somewhere more
specific.

---

## Goal

Add DAW-style mixer busses to the shared mixer workspace so tracks can route to
user-created intermediate bus strips before master out. Each bus must persist
its routing identity, mix state, and insert chain; the engine must own bus-host
lifecycles and rerouting; and the mixer UI must present tracks, busses, and
master as one coherent three-zone surface without forking the existing mixer
shell.

---

## Chosen Product Direction

The accepted direction is the three-zone mixer lane: track strips on the left,
user-created bus strips in the middle, and master out on the right. Busses are
ordinary mix-routing objects in v1, not scene variants and not a second routing
paradigm. Tracks route either directly to master or to one bus. Bus inserts are
global across scenes. Solo is additive across tracks and busses, and deleting a
routed bus requires confirmation that reroutes affected tracks back to master
on confirm.

The build should stay conservative: add the minimum persisted bus model, route
ownership through the existing graph/controller layer, extract shared insert and
strip-shell UI where needed, and avoid broad redesign of unrelated mixer or
scene systems.

---

## Guardrails The Implementer Must Preserve

1. The `.seqai` document remains the single persisted truth for authored bus
   state. Persist `Project.buses`, per-track `outputBusID`, and authored mute /
   solo flags; do not persist derived solo-exclusion state.
2. `TrackGroup` is not an audio bus. Do not retrofit MIDI-group concepts into
   mixer-bus ownership, routing, or UI.
3. Bus-node lifecycle and track rerouting belong to the engine / graph layer,
   not SwiftUI. Views may author document state and show in-flight status, but
   they must not mutate `AVAudioEngine` topology directly.
4. Topology changes remain coordinated stop / reconnect / restart operations.
   Bus creation, deletion, rerouting, and insert-topology edits are structural
   graph changes; parameter-only changes should stay lightweight where the
   existing architecture already allows it.
5. `MixerBus.id` is the stable routing identity. Graph rebuilds may recreate
   `AVAudioNode` instances, but authored bus identity and route references must
   survive rebuilds.
6. The shared mixer surface must stay singular. Do not fork a second mixer
   shell for busses; extract or parameterize common strip anatomy and insert UI
   instead.
7. Bus inserts are global in v1 even though master inserts are scene-scoped.
   The UI must communicate that distinction explicitly rather than implying that
   bus strips change with the selected scene.
8. Solo remains additive across tracks and busses, with effective mute derived
   centrally from authored solo flags. Do not introduce shadow solo-membership
   state in views.

---

## Implementation Read Order

1. Read this handoff.
2. Read [plan.md](plan.md) and execute it in phase order.
3. Use [spec.md](spec.md) as the product contract for behavior and acceptance
   criteria.
4. Use [architecture.md](architecture.md) and
   [architecture-review.md](architecture-review.md) as hard guardrails around
   persistence, graph ownership, solo semantics, and UI extraction.
5. Read [existing-state.md](existing-state.md) before changing the document
   model, audio graph, or mixer UI.
6. Read [../mixer-main-out/architecture.md](../mixer-main-out/architecture.md)
   before touching shared mixer-shell layout or master-column interactions.

Do not reopen product decisions already settled in `decisions.md` or `spec.md`.
If code reality conflicts with the approved direction, capture that as an
implementation finding and keep the behavior within the documented guardrails.

---

## Build Sequence

Follow the plan's phases in order:

1. **Phase 0 - verification**
   Confirm the current document/codable landing zones, graph/routing ownership
   seams, and mixer-shell/insert reuse seams before writing code.
2. **Phase 1 - persisted bus and solo model**
   Add the authored bus collection, per-track routing field, authored solo
   fields, and the focused session/document mutation surface.
3. **Phase 2 - engine-owned bus graph and routing**
   Introduce bus hosts, reroute tracks through bus or master destinations, and
   centralize additive solo derivation.
4. **Phase 3 - shared mixer UI**
   Extract shared strip and insert-shell components as needed, then compose bus
   strips, routing selectors, add/delete flows, rename, and in-flight states in
   the single mixer workspace.
5. **Phase 4 - regression coverage**
   Finish with model migration tests, graph/routing regression tests, and the
   lightest practical UI coverage for bus-strip state and routing controls.

---

## Files And Modules Expected To Change

| Area | Expected work |
|---|---|
| `Sources/Document/Project.swift` and `Sources/Document/Project+Codable.swift` | Persisted `buses` collection and additive legacy decode defaults |
| `Sources/Document/StepSequenceTrack.swift` and `Sources/Document/TrackMixSettings.swift` | Per-track `outputBusID` and authored solo persistence |
| `Sources/Document/` session/mutation helpers | Explicit add/rename/delete/reroute/solo and bus-mix mutation paths |
| `Sources/Audio/MainAudioGraph.swift`, `Sources/Audio/AudioInstrumentHost.swift`, `Sources/Audio/SamplePlaybackEngine.swift`, `Sources/Audio/MasterBusHost.swift` or extracted peers | Bus-host lifecycle, routing rewires, and insert-topology ownership |
| `Sources/Engine/EngineController.swift` | Coordinated graph rebuilds, routing-in-flight handling, and derived additive solo state |
| `Sources/UI/Mixer/**` and any extracted shared strip/insert views | One shared mixer surface with bus strips, routing selectors, bus insert UI, and solo banner treatment |
| `Tests/**` covering project codable, graph topology, engine routing, and mixer UI | Regression coverage for migration, bus routing, solo semantics, and UI state |

No wiki edits, no `docs/specs/**` or `docs/plans/**` output, no send-effects
scope expansion, and no broad engine redesign belong in this build.

---

## Acceptance Focus

The implementation is ready to ship to review only when these outcomes are
observable:

- Adding a bus creates a persisted bus strip in the mixer and makes it
  immediately available in every track output selector.
- Routing a track to a bus changes the audible signal path from
  `track -> master` to `track -> bus -> master` after a coordinated rebuild.
- Bus level, pan, mute, and additive solo affect only the intended routed
  signal path and restore correctly on reload.
- Bus inserts apply to the summed bus signal, remain global across scenes, and
  reuse shared insert interaction patterns instead of a divergent editor.
- The mixer still reads as one tracks | busses | master surface, with explicit
  copy separating global bus inserts from scene-scoped master inserts.
- Deleting a routed bus prompts for confirmation and reroutes affected tracks
  back to master on confirm.

See [spec.md](spec.md) Sections 5 and 6 for the full behavioral contract.

---

## Non-Goals And Deferred Follow-Ups

- No bus-to-bus routing or bus chaining in v1.
- No parallel / multi-destination track outputs.
- No scene-scoped user-created bus insert chains.
- No second mixer shell or duplicated strip architecture just for bus UI.
- No new effect model beyond reusing or extracting the existing insert-host
  concepts.
- No arrangement-level or clip-level visualization of bus routing.
- No send-effects implementation; item 6 remains separate even if some UI
  affordances later resemble bus routing.

---

## Open Questions

There are no user-blocking product questions left for this item.

Phase 0 in [plan.md](plan.md) intentionally leaves a few implementation checks
to verify in code before edits begin:

- the exact codable landing zones and legacy decode defaults for bus and solo
  persistence
- the single owner for bus-host lifecycle and track rerouting
- the cleanest extraction seam for shared insert and strip-shell UI
- the lightest practical regression-test files for migration, routing, and bus
  strip behavior

These are implementation checks, not reasons to relitigate the PM direction.
