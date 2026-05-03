---
feature: send-effects
created: 2026-05-03
---

# Send Effects Plan

## Status

PM plan — implementation handoff still required. No production code has been
written.

---

## Overview

Send Effects adds two fixed wet-return buses, `Send A` and `Send B`, to the
shared mixer lane. Each track gets independent send amounts for both buses, and
each send bus owns one global insert chain whose processed return reconnects to
`finalOutputMixer`.

The build should stay narrow and sequence work in this order:

1. verify the current document, graph, and mixer seams before editing
2. add persisted per-track send amounts plus fixed send-bus authored state with
   additive codable defaults
3. route all authored changes through one canonical session/delta path instead
   of inventing overlapping send-specific truth
4. install fixed send infrastructure and send-bus hosts in the engine, keeping
   send level changes as parameter writes and insert edits under the central
   graph rebuild coordinator
5. extend the existing mixer workspace with per-track send controls and
   send-bus detail editing, reusing shared insert semantics instead of forking a
   second bus UI
6. finish with regression coverage around migration, graph topology, session
   propagation, and the core mixer interactions

No user-created send buses, no scene-scoped send inserts, no pre/post-fader
toggle, no alternate wet return destination, and no standalone send screen are
in scope.

---

## Phase 0 — Pre-Build Verification

Phase 0 is read-only. Its job is to confirm the current code still matches the
spec and architecture seams before authored or runtime state is added.

### 0-A. Confirm document and delta landing zones

**What it is.** Verify the exact model types that will absorb authored send
state and the existing delta path that should carry it.

**Files to read.**

- `Sources/Document/TrackMixSettings.swift`
- `Sources/Document/StepSequenceTrack.swift`
- `Sources/Document/Project.swift`
- `Sources/Document/Project+Codable.swift`
- `Sources/Document/ProjectDelta.swift`
- tests covering track mix, project codable, or master-bus codable behavior

**Checks.**

1. Confirm `TrackMixSettings` is still the cleanest landing zone for persisted
   `sendA` / `sendB` values.
2. Confirm `Project` still owns only the master-bus authored insert state and
   has no existing send-bus model.
3. Confirm the additive `decodeIfPresent` default seams for both the track send
   values and the fixed send-bus state.
4. Confirm whether `ProjectDelta.trackMixChanged(trackID:mix:)` can stay the
   single engine-facing authored delta rather than adding a second
   `trackSendChanged` path.

**Acceptance signals.**

- The implementer can name the exact persisted fields and decode defaults.
- The implementer can name the one canonical delta path for track send edits.

### 0-B. Confirm graph-owner and rebuild seams

**What it is.** Validate where send fan-out, send-bus host lifecycle, and
graph rebuild coordination belong.

**Files to read.**

- `Sources/Audio/MainAudioGraph.swift`
- `Sources/Audio/AudioInstrumentHost.swift`
- `Sources/Audio/SamplePlaybackEngine.swift`
- `Sources/Audio/MasterBusHost.swift`
- `Sources/Engine/EngineController.swift`
- `wiki/pages/engine-architecture.md`

**Checks.**

1. Confirm every track output still routes directly to `preMasterMixer` today.
2. Confirm the exact stop / reconnect / restart path already used for master
   topology changes.
3. Confirm where two fixed `SendBusHost` instances can be owned without any
   SwiftUI-driven graph mutation.
4. Confirm where mute and post-fader send semantics should be derived so a
   muted track contributes neither dry nor wet signal.

**Acceptance signals.**

- The implementer can name the single owner for send-bus node lifecycle.
- The implementer knows which send changes are gain writes versus graph
  rebuilds.

### 0-C. Confirm mixer and insert-editor reuse seams

**What it is.** Identify what can be reused from the current mixer, master, and
scene-perform surfaces before new send UI is composed.

**Files to read.**

- `Sources/UI/MixerView.swift`
- `Sources/UI/Mixer/MixerWorkspaceView.swift`
- `Sources/UI/Mixer/ScenesWorkspaceView.swift`
- `Sources/UI/Mixer/ScenesWorkspaceView+AUEffects.swift`
- any existing mixer or insert-editor tests

**Checks.**

1. Confirm where the current track-strip anatomy can absorb two compact send
   controls without forking the strip.
2. Confirm which insert-editor components are still private to
   `ScenesWorkspaceView` and must be extracted or parameterized for send-bus
   editing.
3. Confirm the lightest practical UI test landing zones for send controls,
   empty bus states, and bus-detail selection.

**Acceptance signals.**

- The implementer can name what gets extracted versus reused in place.
- The implementer knows which UI tests to extend or create.

---

## Phase 1 — Authored Send State

Phase 1 introduces the persisted state and mutation surface needed to represent
send levels and send-bus inserts without making them audible yet.

### 1-A. Add persisted per-track send amounts

**What it is.** Extend the existing track-mix authored state with send values.

**Required behavior.**

1. Add `sendA: Double` and `sendB: Double` to `TrackMixSettings`.
2. Default both values to `0.0` for new and legacy documents.
3. Clamp authored writes to `0.0...1.0`.
4. Keep the send amounts in the same persisted mix authority as level, pan, and
   mute.

**Guardrails.**

- Do not create a second per-track send model beside `TrackMixSettings`.
- Do not introduce pre/post-fader toggles in this phase.

**Acceptance signals.**

- Old documents decode with silent sends.
- New documents round-trip authored send levels cleanly.

### 1-B. Add fixed send-bus authored state

**What it is.** Persist the two fixed wet-return buses and their insert chains.

**Required behavior.**

1. Add fixed authored state for `Send A` and `Send B` on `Project`.
2. Give each bus one global insert chain.
3. Reuse or deliberately wrap the existing insert schema so master, bus, and
   send inserts do not fork into three incompatible document shapes.
4. Default legacy documents to two empty send buses.

**Guardrails.**

- Do not make send buses user-creatable or user-renamable in v1.
- Do not add scene-scoped send inserts.

**Acceptance signals.**

- The document has one authoritative authored home for both fixed send buses.
- Insert persistence semantics stay aligned with the rest of the mixer
  architecture.

### 1-C. Add focused session and delta mutations

**What it is.** Give the UI and engine one canonical authored mutation path per
send action.

**Likely mutation surface.**

- set track send amounts
- add / remove / reorder / bypass send-bus inserts
- select the active send bus for editing in the UI layer, if needed

**Guardrails.**

- Reuse the existing track-mix authored mutation path rather than inventing a
  parallel source of truth for send values.
- Insert mutations author document state first; they do not mutate AVAudioNodes
  directly from the view layer.

**Acceptance signals.**

- Track send edits have one canonical authored mutation path.
- Send-bus insert edits are expressible without UI-owned runtime truth.

---

## Phase 2 — Engine-Owned Send Topology

Phase 2 makes the authored send state audible by introducing fixed send routing
and wet-return hosts inside the graph layer.

### 2-A. Install fixed send infrastructure per session

**What it is.** Add the always-present send fan-out and send-bus host
infrastructure.

**Required behavior.**

1. Fan each track's post-fader output to the dry path plus the `Send A` and
   `Send B` gain nodes.
2. Create one `SendBusHost` per fixed bus during session start.
3. Connect both wet returns to `finalOutputMixer`.
4. Keep the graph acyclic and coordinated by the same central owner that
   already rebuilds master-bus topology.

**Guardrails.**

- Do not lazily create or destroy send infrastructure when a knob crosses zero.
- Do not let a send host stop or restart the engine in isolation.

**Acceptance signals.**

- The send graph exists for the session even when all sends are zero.
- Wet returns follow the approved `finalOutputMixer` path.

### 2-B. Apply track send changes as parameter writes

**What it is.** Make send knob edits lightweight and real-time-safe.

**Required behavior.**

1. Propagate send amount edits to the per-track send gain nodes only.
2. Keep mute semantics authoritative: muted tracks contribute neither dry nor
   wet signal.
3. Keep post-fader behavior authoritative for v1.

**Guardrails.**

- No graph rebuild for ordinary send level changes.
- No UI-local send state that can drift from the document.

**Acceptance signals.**

- Changing a send amount updates only the targeted track's wet contribution.
- Mute and fader behavior matches the settled product decisions.

### 2-C. Rebuild send-bus insert chains through the coordinator

**What it is.** Make send-bus effect editing audible while preserving the
existing topology-rebuild discipline.

**Required behavior.**

1. Route send-bus insert add/remove/reorder changes through the central graph
   rebuild coordinator.
2. Keep bypass-only changes as lightweight as the existing architecture allows.
3. Ensure edits to `Send A` do not touch `Send B`, and vice versa.

**Guardrails.**

- Do not fork a second graph-rebuild discipline beside the master-bus path.
- Do not duplicate insert-host ownership patterns without a documented reason.

**Acceptance signals.**

- Send-bus insert edits rebuild only the affected wet-return chain.
- The engine restart path remains coordinated and deterministic.

---

## Phase 3 — Mixer UI

Phase 3 exposes the authored and runtime send behavior in the shared mixer
workspace without inventing a second bus/editor surface.

### 3-A. Extend the track strip with send controls

**What it is.** Add two compact per-track send controls to the existing mixer
strip.

**Required behavior.**

1. Show clearly labeled `A` and `B` send controls on each track strip.
2. Make zero and non-zero states legible at a glance.
3. Keep editing in the mixer lane without navigation away from the strip.

**Acceptance signals.**

- Users can set independent send amounts per track directly from the strip.
- The track strip remains readable at normal mixer density.

### 3-B. Add fixed send-bus detail surfaces

**What it is.** Surface `Send A` and `Send B` as fixed bus-detail lanes within
the shared mixer workspace.

**Required behavior.**

1. Expose both buses as always-present editable destinations.
2. Show an explicit empty state when a bus has no inserts.
3. Reuse extracted/shared insert-editor surfaces instead of forking a send-only
   editor.

**Acceptance signals.**

- Each send bus can be selected and edited in place.
- Empty and populated insert-chain states both read clearly.

### 3-C. Preserve the shared mixer information architecture

**What it is.** Integrate sends into the existing mixer shell without
duplicating workspace structure.

**Required behavior.**

1. Keep tracks, buses, sends, and master within one coherent mixer workspace.
2. Make it obvious that send returns are special wet-return lanes, not ordinary
   user-routable dry buses.
3. Reuse the approved shared mixer visual language from Mixer Main Out and
   Mixer Busses.

**Acceptance signals.**

- Send lanes feel like an extension of the shared mixer rather than a second
  subsystem.
- The UI does not imply unsupported routing options.

---

## Phase 4 — Regression Coverage And Verification

Phase 4 locks the feature down with the minimum focused coverage needed to keep
the new routing and authored-state behavior trustworthy.

### 4-A. Document and mutation coverage

**Required tests.**

1. Legacy document decode defaults `sendA`, `sendB`, and empty send buses.
2. New document round-trips authored send values and send-bus inserts.
3. Session mutations clamp authored send values and persist only the targeted
   bus or track.

### 4-B. Graph and engine coverage

**Required tests.**

1. Track fan-out preserves the dry path while feeding both send buses.
2. Track send amount changes update only the targeted send gain values.
3. Muted tracks contribute no wet signal.
4. Send-bus insert edits rebuild only the affected wet-return chain.

### 4-C. Focused UI coverage and manual smoke

**Required checks.**

1. Track strips render both send controls and reflect zero/non-zero state.
2. Send-bus empty states and insert-detail states render predictably.
3. Manual smoke verifies: dry path still works, send returns are audible through
   `finalOutputMixer`, and save/reload preserves the authored mix.

**Acceptance signals.**

- The feature is covered at the document, engine, and focused UI levels.
- Manual smoke is limited to genuinely audio-hosted behavior the current test
  harness cannot prove end to end.
