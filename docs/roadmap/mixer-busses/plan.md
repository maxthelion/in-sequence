---
feature: mixer-busses
created: 2026-05-03
---

# Mixer Busses Plan

## Status

PM plan — implementation handoff still required. No production code has been
written.

---

## Overview

Mixer Busses adds ordinary DAW-style group buses to the shared mixer surface:
tracks remain on the left, user-created buses sit in the middle, and master
out stays on the right per `[[feature:mixer-main-out]]`.

The build should stay narrow and sequence work in this order:

1. verify current model, graph, mixer-shell, and insert-editor seams before
   editing
2. add persisted bus and solo model support with safe codable migration
3. add session and engine-owned routing / bus-host mutation paths
4. extract shared insert and strip-shell UI instead of forking mixer surfaces
5. compose bus strips, routing selectors, solo behavior, rename, and delete UX
6. finish with regression coverage around migration, graph rewires, and UI
   state

No bus-to-bus routing, no scene-scoped bus inserts, no second mixer shell, and
no new effect model beyond the approved bus-host reuse/extraction are in scope.

---

## Phase 0 — Pre-Build Verification

Phase 0 is read-only. Its purpose is to confirm that the current code still
matches the plan's assumed seams before any mutations are introduced.

### 0-A. Confirm model and codable landing zones

**What it is.** Verify the exact document types that will absorb bus routing
and solo persistence.

**Files to read.**

- `Sources/Document/Project.swift`
- `Sources/Document/Project+Codable.swift`
- `Sources/Document/StepSequenceTrack.swift`
- `Sources/Document/TrackMixSettings.swift`
- any existing tests covering project or track codable round-trips

**Checks.**

1. Confirm `Project` still has no `buses` collection.
2. Confirm `StepSequenceTrack` still has no `outputBusID`.
3. Confirm `TrackMixSettings` is still the cleanest landing zone for
   persisted track solo state.
4. Confirm where backward-compatible `decodeIfPresent` defaults belong for all
   three additions.

**Acceptance signals.**

- The implementer can name the exact persisted fields and decode defaults.
- The implementer can name the test files that should prove legacy document
  compatibility.

### 0-B. Confirm graph and engine mutation seams

**What it is.** Validate where bus host ownership, track rewiring, and solo
derivation should live.

**Files to read.**

- `Sources/Audio/MainAudioGraph.swift`
- `Sources/Audio/AudioInstrumentHost.swift`
- `Sources/Audio/SamplePlaybackEngine.swift`
- `Sources/Audio/MasterBusHost.swift`
- `Sources/Engine/EngineController.swift`
- `wiki/pages/engine-architecture.md`
- `wiki/pages/routing.md`

**Checks.**

1. Confirm every track output still connects directly to `preMasterMixer`.
2. Confirm the current stop / reconnect / restart path for topology changes.
3. Confirm where a new bus-host map can be owned without view-driven graph
   mutation.
4. Confirm where effective mute from additive solo should be derived so the UI
   does not own playback truth.

**Acceptance signals.**

- The implementer can name the single owner for bus-node lifecycle.
- The implementer knows which changes are topology rebuilds versus parameter
  updates.

### 0-C. Confirm mixer-shell and insert reuse seams

**What it is.** Identify what can be shared from the current mixer and
scene-perform surfaces before bus UI code is written.

**Files to read.**

- `Sources/UI/Mixer/MixerWorkspaceView.swift`
- `Sources/UI/MixerView.swift`
- `Sources/UI/Mixer/ScenesWorkspaceView.swift`
- `Sources/UI/Mixer/ScenesWorkspaceView+AUEffects.swift`
- any current mixer UI tests

**Checks.**

1. Confirm the current mixer shell still matches the approved three-zone
   direction from `[[feature:mixer-main-out]]`.
2. Confirm which insert-list UI is currently private to Scenes Perform and
   must be extracted or parameterized.
3. Confirm whether track-strip anatomy is already centralized enough to share
   with bus strips or needs a new common shell.
4. Confirm the lightest practical UI test landing zones for routing selectors,
   bus-strip state, and the solo banner.

**Acceptance signals.**

- The implementer can name what gets extracted versus reused in place.
- The implementer knows whether to extend existing mixer tests or add focused
  new files.

---

## Phase 1 — Persisted Bus and Solo Model

Phase 1 introduces the authored state required to represent buses and routing
without touching the live mixer surface yet.

### 1-A. Add persisted bus and routing fields

**What it is.** Extend the document model with the minimum authored bus data.

**Required behavior.**

1. Add `buses: [MixerBus]` to `Project`.
2. Add `outputBusID: UUID?` to `StepSequenceTrack`, where `nil` means master.
3. Add the new codable keys with additive legacy defaults.

**Guardrails.**

- Do not overload `TrackGroup` into an audio bus.
- Do not introduce bus-to-bus routing fields.

**Acceptance signals.**

- Old documents decode with `buses == []` and `outputBusID == nil`.
- New documents round-trip authored bus and routing state cleanly.

### 1-B. Add authoritative mix-state shapes

**What it is.** Lock in the persisted mute / solo representation for both
tracks and buses.

**Required behavior.**

1. Add `isSoloed: Bool` to `TrackMixSettings` with a legacy default of `false`.
2. Introduce a bus mix shape that carries level, pan, mute, and solo.
3. Keep authored mute / solo state persisted while leaving effective mute
   derived at runtime.

**Guardrails.**

- Do not persist derived solo-exclusion state.
- Do not let view-local state become the source of solo truth.

**Acceptance signals.**

- Track and bus solo state have one clear persisted representation.
- Legacy documents without solo flags still decode predictably.

### 1-C. Add focused session/document mutations

**What it is.** Give the UI and engine explicit mutations for bus creation,
routing, naming, mix changes, and deletion.

**Likely mutation surface.**

- add bus
- rename bus
- set bus color
- set track output bus
- set bus level / pan / mute / solo
- set track solo
- delete bus with coordinated reroute-to-master

**Guardrails.**

- Document/session mutations author state first; they do not mutate graph nodes
  directly.
- Delete-bus mutation must surface the affected-track set needed by the
  confirmation UX.

**Acceptance signals.**

- The mixer has one canonical mutation path per authored action.
- Delete-bus behavior is expressible without ad hoc view logic.

---

## Phase 2 — Engine-Owned Bus Graph and Routing

Phase 2 makes the new model audible by introducing bus hosts and routing
ownership inside the audio graph layer.

### 2-A. Introduce bus host lifecycle

**What it is.** Add a `BusHost`-style owner for each authored bus.

**Required behavior.**

1. Create one live bus mixer/insert host per persisted `MixerBus`.
2. Key host ownership by stable `MixerBus.id`.
3. Rebuild host topology safely across add/remove/insert changes.

**Guardrails.**

- Bus host ownership belongs to the graph / engine layer, not SwiftUI.
- Stable bus identity must survive graph rebuilds even if AVAudioNode instances
  do not.

**Acceptance signals.**

- New buses produce a real summing point between tracks and `preMasterMixer`.
- Bus deletion tears down the host cleanly without leaving stale graph state.

### 2-B. Add track rerouting and bus insert topology mutations

**What it is.** Route track output through a selected bus or directly to
master.

**Required behavior.**

1. Rewire tracks to `preMasterMixer` or a bus node based on `outputBusID`.
2. Treat add/remove/reorder bus inserts as graph-topology rebuilds.
3. Treat bus level, pan, mute, and bypass-only changes as parameter updates.

**Guardrails.**

- Use the existing stop / reconnect / restart discipline for topology changes.
- Do not expose direct AVAudioEngine mutation to views.

**Acceptance signals.**

- Changing a track route audibly changes the signal path after a coordinated
  rebuild.
- Bypass-only insert toggles avoid unnecessary full graph rebuilds when the
  existing architecture allows it.

### 2-C. Derive additive solo behavior centrally

**What it is.** Implement the runtime-only solo state machine for tracks and
buses.

**Required behavior.**

1. When no strip is soloed, explicit mute alone determines audibility.
2. When any strip is soloed, unsoloed strips become effectively muted.
3. Tracks routed through a soloed bus remain audible through that bus even if
   the track is not itself soloed.
4. `Clear Solo` can clear every persisted `isSoloed` flag through the existing
   mutation surface.

**Guardrails.**

- Effective mute remains derived runtime state.
- The engine controller, not the UI, decides what is effectively muted.

**Acceptance signals.**

- Solo is additive across tracks and buses exactly as approved in
  `decisions.md`.
- The UI can read one coherent "solo active" truth without reimplementing the
  state machine.

---

## Phase 3 — Shared Mixer Surface Extraction

Phase 3 removes the biggest implementation risk called out in the architecture
review: duplicating strip or insert UI.

### 3-A. Extract a shared strip shell

**What it is.** Factor any common strip anatomy needed by track, bus, and
master surfaces into one reusable path.

**Required behavior.**

1. Share the vertical strip rhythm where practical: output area, inserts,
   fader, pan, mute / solo, name.
2. Keep bus-specific and master-specific controls injectable rather than
   branching one monolithic view.

**Acceptance signals.**

- Mixer bus work does not fork `MixerWorkspaceView` into a second shell.
- Track and bus strips can evolve without copy-pasted anatomy.

### 3-B. Extract or parameterize insert-list UI

**What it is.** Reuse the existing insert interaction model instead of building
an unrelated bus-only editor.

**Required behavior.**

1. Lift the relevant insert-list surface from Scenes Perform into a reusable
   component or narrow abstraction.
2. Allow master and bus insert contexts to differ in copy and data source while
   sharing interaction behavior.
3. Preserve global bus-insert semantics versus scene-scoped master semantics in
   the labels and data wiring.

**Acceptance signals.**

- Bus insert editing does not duplicate the Scenes Perform insert UI.
- The master column can continue to show scene-scoped context while bus strips
  stay global.

---

## Phase 4 — Mixer Busses UI and UX

Phase 4 composes the authored model and engine behavior into the approved
three-zone mixer experience.

### 4-A. Add the bus section and creation flow

**What it is.** Render the bus lane between tracks and master and allow live
creation of new buses.

**Required behavior.**

1. Add the `Busses` section with a header `Add Bus` affordance.
2. Add the trailing `+ Add Bus` tile at the end of the bus strip row.
3. Insert the new strip immediately and auto-focus inline rename.

**Acceptance signals.**

- The bus lane is visibly distinct from tracks and master without becoming a
  separate modal or page.
- Adding a bus immediately makes it available to routing selectors.

### 4-B. Add per-track routing selectors and in-flight state

**What it is.** Let each track route to master or any current bus.

**Required behavior.**

1. Each track strip lists `Master` plus all current bus names.
2. Changing the route disables the active selector and shows `Applying...`
   during the rebuild window.
3. Renamed buses update every selector label consistently.

**Acceptance signals.**

- The routing selector reflects authored bus order and labels.
- In-flight graph rebuild state is visible and localized to the track being
  rerouted.

### 4-C. Implement bus strip controls and global insert semantics

**What it is.** Render the bus strip itself.

**Required behavior.**

1. Show the fixed `-> Master` output label.
2. Render bus inserts, fader, pan, mute, solo, and name.
3. Show an explicit empty-bus state when no tracks currently route there.
4. Keep bus inserts global across scene changes and label the master column
   distinctly so the scope difference stays legible.

**Acceptance signals.**

- Bus controls affect the grouped signal in real time.
- Empty buses remain operable rather than disappearing.

### 4-D. Implement rename, solo banner, and delete confirmation

**What it is.** Finish the user-facing state transitions that complete the
feature.

**Required behavior.**

1. Support inline rename with enter, escape, blur, and empty-name
   normalization.
2. Show one `SOLO ACTIVE` banner with `Clear Solo` while any track or bus is
   soloed.
3. Delete an unrouted bus immediately.
4. Delete a routed bus only after confirmation that lists affected tracks and
   explains the reroute-to-master consequence.

**Acceptance signals.**

- The approved product decisions in `prototype-approval.md` are all visible in
  the final mixer flow.
- No delete path silently drops routing information.

---

## Phase 5 — Regression Coverage and Polish

Phase 5 proves the feature without broadening scope.

### 5-A. Add document and migration tests

**Tests to add.**

1. Legacy documents decode without buses, `outputBusID`, or track solo flags.
2. New documents round-trip bus collections, routing, colors, mix state, and
   solo flags.
3. Delete-bus mutations reroute affected tracks to master before removing the
   bus.

### 5-B. Add graph and engine tests

**Tests to add.**

1. Bus creation adds an intermediate bus host / node path.
2. Track rerouting reconnects to the expected destination.
3. Bus level / pan / mute apply to the bus mixer node.
4. Additive solo derives the correct effective mute set for master-routed and
   bus-routed tracks.
5. Bus insert topology rebuilds and bypass behavior follow the intended graph
   paths.

### 5-C. Add focused mixer UI tests

**Tests to add.**

1. Bus creation inserts a strip and starts rename.
2. Routing selectors list all buses plus `Master`.
3. `Applying...` appears during reroute-in-flight state.
4. The solo banner appears only when any strip is soloed.
5. Deleting a routed bus requires confirmation.
6. Renaming a bus updates every routing selector reference.

**Acceptance signals.**

- The highest-risk regressions are covered at document, graph, and UI layers.
- Coverage proves the feature without requiring a second implementation pass to
  rediscover core behavior.

---

## Ready-For-Handoff Notes

The implementation handoff should preserve these sequencing constraints:

1. land model and codable support before graph rewiring
2. keep bus-host ownership in the engine / graph layer
3. share insert and strip UI rather than duplicating the mixer surface
4. coordinate bus-lane composition with `[[feature:mixer-main-out]]`
5. leave buses global and bus outputs fixed to master in v1
