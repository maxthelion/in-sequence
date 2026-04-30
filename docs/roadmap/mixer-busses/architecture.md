---
feature: mixer-busses
created: 2026-04-30
based_on:
  - docs/roadmap/mixer-busses/user-stories.md
  - docs/roadmap/mixer-busses/existing-state.md
  - docs/roadmap/mixer-busses/ux-review.md
  - docs/roadmap/mixer-busses/prototypes/mixer-busses-variant-a.html
  - docs/roadmap/mixer-main-out/architecture.md
  - docs/roadmap/mixer-main-out/open-questions.md
  - wiki/pages/engine-architecture.md
  - wiki/pages/routing.md
  - wiki/pages/architecture-guardrails.md
---

# Mixer Busses — Architecture

Written: 2026-04-30
UX direction: Variant A (three-zone layout: tracks | busses | master, accepted in `ux-review.md`).

---

## 1. Design Constraints Carried Forward

The following findings from `existing-state.md` and `ux-review.md` constrain every architectural
decision below.

1. **No intermediate bus node exists in the audio graph.** Every track output connects directly
   to `preMasterMixer`. Introducing buses is a net-new audio graph topology change, not a
   configuration of an existing system. This is the largest single structural change in this feature.

2. **`StepSequenceTrack` has no output-routing field.** Track-to-bus assignment must be added to
   the document model as a new `outputBusID: UUID?` field. `nil` means "route to master."

3. **`MasterBusInsert` and `MasterBusHost` are master-specific.** No generic insert-chain
   abstraction exists. The user-story assumption that buses "reuse the same insert-chain component"
   is technically incorrect — the UI and host for insert chains are tightly coupled to
   `MasterBusState`/`MasterBusScene`. Reuse requires extraction and parametrisation, which is a
   refactor, not a drop-in.

4. **Graph topology changes require engine stop/restart.** `installMasterChains` in
   `MainAudioGraph.swift` stops and restarts the `AVAudioEngine` for topology changes. Track
   output re-routing (changing a track's bus assignment) must follow the same stop/reconnect/restart
   pattern. This is a user-visible latency event and must be communicated in the UI (the
   routing-change-in-flight state from the prototype).

5. **The `TrackGroup` type is not a bus.** `TrackGroup` provides MIDI grouping and drum-kit note
   mapping with mute/solo booleans for playback control. It has no audio graph presence, no fader,
   no pan, and no insert chain. It must not be retrofitted to become a bus; a new `MixerBus` model
   type is required.

6. **Solo logic does not exist anywhere in the codebase.** No track or bus has audio-level solo
   today. `TrackGroup.isSoloed` is a MIDI playback flag, not an audio mute. The solo state machine
   is entirely new.

7. **The insert chain UI in `ScenesWorkspaceView` is not extracted.** The existing insert-list
   rendering, bypass toggles, and per-insert editors are private to the scenes workspace view.
   They cannot be embedded in a bus strip without extraction into a reusable component.

8. **This feature shares the mixer surface with Mixer Main Out (item 4).** Both features are
   designed to produce a single `MixerWorkspaceView` with three zones. Neither feature should
   implement zone layout independently; the layout must be composed or deferred to a shared
   container. The architecture of each feature must leave room for the other without duplicating
   strip anatomy code.

---

## 2. Application Invariants the Feature Must Preserve

### 2a. Document Is the Single Persisted Truth

The `.seqai` document is the only truth for authored state. The following fields must be
persisted:

- `Project.buses: [MixerBus]` — the ordered list of user-created bus channels.
- `MixerBus.id: UUID` — stable identity for routing references.
- `MixerBus.name: String` — user-visible label; propagated to track output selectors.
- `MixerBus.color: String?` — optional colour tag.
- `MixerBus.mix: BusMixSettings` — fader level, pan, isMuted, isSoloed.
- `MixerBus.inserts: [MixerBusInsert]` — insert chain. Scope (global vs. scene-scoped) is an
  open question; see Section 5, question 2.
- `StepSequenceTrack.outputBusID: UUID?` — routing assignment; `nil` = routes to master.

The following must not be persisted:

- Transient solo exclusion state (which other buses are currently being muted because of an
  active solo). This is a derived, runtime-only state computed from `isSoloed` flags.
- UI-only state: selected bus, insert-editor-open flag, rename-in-progress flag.

### 2b. No UI-Only Playback Truth

The architecture guardrail "view-local state becoming the source of playback truth" applies:

- Bus fader, pan, and mute must not be driven by view-local `@State` variables. The view must
  read from `project.buses[i].mix` (document state) and write through a document mutation that
  triggers engine apply.
- Solo state (which buses/tracks are muted due to an active solo) must be computed by the engine
  controller from document-level `isSoloed` flags, not by UI gesture handlers accumulating
  transient mute overrides.

### 2c. Audio Thread Isolation

Bus mixer nodes (`AVAudioMixerNode` instances managed per-bus by `BusHost`) live in the audio
graph. Their `outputVolume` and `pan` must be written only from the main thread via
`performOnMain`, never from a view gesture handler or from a background serial queue without
dispatch.

Graph topology changes (adding a bus, removing a bus, rewiring a track to a different bus) must
follow the `installMasterChains` stop/restart pattern: engine is stopped, topology is modified,
engine is restarted. These operations must be coordinated through `EngineController` so that any
in-flight audio tap callbacks (from Mixer Main Out metering, if item 4 is implemented) are
removed before stop and reinstalled after restart.

### 2d. Stable Bus Identity Through Graph Rebuilds

Each `MixerBus.id: UUID` must remain stable across engine stop/restart cycles. `BusHost`
instances are keyed by bus ID. Rebuilding the graph must not create new `AVAudioMixerNode`
instances for buses that did not change their routing topology. Node identity is not required to
be stable (AVAudioNode instances can be recreated), but the mapping from bus ID to graph node
must be re-established correctly after every restart.

### 2e. Persistence Migration Safety

`Project+Codable.swift` uses `decodeIfPresent` for all optional collections. Two additive
migrations are required:

- `Project`: add `buses: [MixerBus]` with `decodeIfPresent([MixerBus].self, forKey: .buses) ?? []`.
  Existing documents decode with an empty bus list; all tracks implicitly route to master.
- `StepSequenceTrack`: add `outputBusID: UUID?` with `decodeIfPresent(UUID.self, forKey: .outputBusID)`.
  Existing tracks decode with `nil`; `nil` = route to master.

No migration function or version bump is required for these changes; the `decodeIfPresent`
defaults produce a valid state.

---

## 3. Data and Runtime Shape: Persisted vs. Transient

### 3a. Proposed Persisted Types

**`MixerBus`** (new type, owned by `Project.buses`)

| Field | Type | Notes |
|---|---|---|
| `id` | `UUID` | Stable identity. Generated at creation, never changed. |
| `name` | `String` | Default: "Bus N" (counter). Must be non-empty after normalisation. |
| `color` | `String?` | Optional hex or named colour. `nil` = use default color. |
| `mix` | `BusMixSettings` | See below. |
| `inserts` | `[MixerBusInsert]` | Flat list if global scope; see question 2. |

**`BusMixSettings`** (new type, analogous to `TrackMixSettings`)

| Field | Type | Default | Notes |
|---|---|---|---|
| `level` | `Double` | `1.0` | Applied to `busNode.outputVolume`. |
| `pan` | `Double` | `0.0` | Applied to `busNode.pan`. |
| `isMuted` | `Bool` | `false` | Explicit user mute. |
| `isSoloed` | `Bool` | `false` | Explicit user solo. |

`TrackMixSettings` currently lacks `isSoloed`. Two options:
- Add `isSoloed: Bool` to `TrackMixSettings` (re-use).
- Create `BusMixSettings` as a separate type with the same fields plus `isSoloed`.

Architecture recommendation: add `isSoloed` to `TrackMixSettings` to avoid duplicate types and
allow the solo state machine to handle tracks and buses uniformly. This is a model change that
affects existing track persistence; `decodeIfPresent` with default `false` handles migration.

**`MixerBusInsert`** (new type)

The insert representation for buses. Given the `MasterBusInsert` pattern, this should be a
structurally identical type (`kind: MixerBusInsertKind`, `isEnabled: Bool`, `auPresetData: Data?`,
`wetDry: Double`, native filter/bitcrusher cases). Whether to reuse `MasterBusInsert` by renaming
it generic, or to define `MixerBusInsert` as a parallel type, is an implementation decision. The
architecture guardrail is: do not duplicate the type schema unless the two insert kinds genuinely
differ.

### 3b. Transient Runtime State

| Field | Owner | Notes |
|---|---|---|
| `busNodes: [UUID: AVAudioMixerNode]` | `BusHost` or `MainAudioGraph` | Map from bus ID to live audio node. Rebuilt on graph restart. |
| `effectiveMuteState: [UUID: Bool]` | Computed by `EngineController` | Derived from `isMuted`, `isSoloed` flags across all buses and tracks. Not persisted. |
| `isRewiring: Bool` (per-track) | `MixerViewModel` or strip state | Set during the engine stop/rewire/restart cycle; drives the "Applying…" disabled state in the UI. Not persisted. |

### 3c. Bus Host Lifecycle

A `BusHost` (new type, analogous to `MasterBusHost`) is required per `MixerBus` instance. Its
responsibilities:

- Owns the `AVAudioMixerNode` for the bus summing point.
- Owns the insert chain node sequence (AU units) for the bus.
- Applies `BusMixSettings` (level, pan, mute effective state) to the bus mixer node.
- Manages insert chain construction and AU caching for bus inserts.
- Is created when a bus is added; is torn down when a bus is deleted.

`BusHost` instances are owned by `EngineController` (or `MainAudioGraph`) and keyed by `MixerBus.id`.

### 3d. Signal Path With Buses

The new signal path after this feature:

```
[track outputMixer, outputBusID == nil] ──────────────────────┐
[track outputMixer, outputBusID == busA.id] ──┐               │
[track outputMixer, outputBusID == busA.id] ──┤               │
                                              ↓               │
                                      busA AVAudioMixerNode   │
                                      [busA insert chain]     │
                                              │               │
[track outputMixer, outputBusID == busB.id] ──┐               │
                                              ↓               │
                                      busB AVAudioMixerNode   │
                                      [busB insert chain]     │
                                              │               │
                                              └───────────────┤
                                                              ↓
                                                    preMasterMixer
                                                              ↓
                                              [MasterBus insert chain]
                                                              ↓
                                                    finalOutputMixer
                                                              ↓
                                                engine.mainMixerNode
```

Tracks with `outputBusID == nil` connect directly to `preMasterMixer`, preserving today's
behavior for un-bused tracks. Buses always output to `preMasterMixer`; bus chaining (bus-to-bus
routing) is explicitly out of scope for this item.

---

## 4. Mutation Paths and Ownership

### 4a. Add Bus

1. UI: "Add Bus" button → `session.addMixerBus(name: "Bus N")`.
2. `SequencerDocumentSession+Mutations`: appends a new `MixerBus` with a stable UUID and default
   `BusMixSettings` to `project.buses`. Persists.
3. `EngineController` observes `project.buses` change → creates a new `BusHost` → stops engine →
   inserts the new bus mixer node and its (empty) insert chain between track outputs and
   `preMasterMixer` → restarts engine.
4. `MixerView` observes the new bus in `project.buses` → renders a new bus strip.
5. All track output selectors observe `project.buses` → add the new bus as a menu option.

Step 3 requires engine stop/restart even for an empty bus with no tracks routed to it yet, because
a new mixer node is inserted into the graph topology. This is consistent with the existing
`installMasterChains` pattern.

### 4b. Route Track to Bus

1. UI: track output selector → user picks a bus → `session.setTrackOutputBus(trackID:, busID:)`.
2. `SequencerDocumentSession+Mutations`: sets `track.outputBusID = busID` (or `nil` for master).
   Persists.
3. `EngineController` observes the track's `outputBusID` change → sets `isRewiring` for that track →
   stops engine → disconnects track outputMixer from its current destination → connects to the new
   destination (bus node or `preMasterMixer`) → restarts engine → clears `isRewiring`.
4. Track strip shows "Applying…" disabled state during step 3 (driven by `isRewiring`).

The engine stop/restart must happen on the main thread. The UI must not allow a second routing
change while `isRewiring` is true for any track.

### 4c. Bus Fader, Pan, Mute

1. UI gesture → `session.updateBusMix(busID:, mix:)`.
2. Mutation sets `project.buses[id].mix`. Persists.
3. `EngineController` applies via `BusHost.applyMix(_:effectiveMute:)` → writes
   `busNode.outputVolume` and `busNode.pan` via `performOnMain`. No engine stop/restart required.

`effectiveMute` is the combined result of `mix.isMuted` and the solo state machine output.

### 4d. Solo

Solo is the most complex mutation path. The solo state machine must:

1. On `session.toggleSolo(busID:)` or `session.toggleSolo(trackID:)`:
   - Set `isSoloed = true` on the target; set `isSoloed = false` on all other buses and tracks
     (exclusive solo model, per prototype default — see open question 1).
   - Persist the `isSoloed` flags.
2. `EngineController` recomputes `effectiveMuteState` for every bus and track:
   - If any bus or track is soloed: every non-soloed bus and every non-soloed track that routes
     directly to master is effectively muted.
   - Apply the effective mute to each `BusHost` and each track `outputMixer.outputVolume`.
3. UI: strips that are effectively muted (not the soloed strip) show the dimmed visual.
   "SOLO ACTIVE" banner appears. "Clear Solo" button → `session.clearAllSolos()`.

The solo exclusion scope must include both buses and tracks in a unified pass. Tracks that route
to a soloed bus are effectively audible through the bus; they must not be independently muted by
the solo pass unless they also route directly to master.

**Open question 1 (blocking): exclusive vs. additive solo convention.** The exclusive model
(only one strip soloed at a time, matching the prototype) is the simpler state machine. Additive
solo (multiple strips can be soloed simultaneously, like a typical DAW) is more powerful but
requires the effective-mute derivation to handle the "any soloed" condition differently. This
decision must be made before the solo state machine is specified.

### 4e. Bus Insert Chain (Add, Remove, Bypass, Reorder)

If bus inserts are global (non-scene-scoped):

1. UI: insert zone → add/remove/bypass/reorder → `session.mutateBusInserts(busID:, ...)`.
2. Mutation modifies `project.buses[id].inserts`. Persists.
3. `EngineController` → `BusHost.rebuildInsertChain(inserts:)` → stops engine → reconstructs AU
   node chain → restarts engine.

The insert chain rebuild follows the same stop/restart requirement as `MasterBusHost.installMasterChains`.
The insert chain for buses and the master bus share this constraint; both require engine stop/restart
for topology changes (AU unit addition/removal). Bypassing an already-constructed AU can be done
without a stop (it is a parameter, not a topology change) if `AUAudioUnit.shouldBypassEffect` is
used instead of disconnecting the node. This pattern should be confirmed against the existing
`MasterBusHost` implementation.

If bus inserts are scene-scoped, the `MixerBus` model must gain a `scenes: [MixerBusScene]`
collection analogous to `MasterBusState.scenes`. This substantially increases model complexity
and the insert chain host lifecycle. This path is only valid if the product decision (open question
2) requires it.

### 4f. Delete Bus

No delete affordance exists in the prototype. The delete mutation must resolve what happens to
tracks currently routed to the deleted bus. Two options:

- **A. Re-route orphaned tracks to master automatically.** Orphaned tracks have their `outputBusID`
  set to `nil`. No warning is shown; the routing change fires silently. This is simple and
  recoverable (the user can re-route the tracks).
- **B. Block deletion if tracks are routed to the bus.** Show a confirmation warning listing the
  affected tracks. Require the user to re-route or confirm deletion with auto-reroute.

**Open question 3 (blocking): delete-bus behavior.** Both options are architecturally feasible.
Option A is simpler but potentially surprising. Option B is conventional in DAWs (Logic, Ableton
warn before deleting a bus with routed tracks). A product decision is required before spec.

After the product decision, the mutation path is:

1. `session.deleteBus(busID:)`:
   - If option A: set `outputBusID = nil` for all tracks where `outputBusID == busID`, then
     remove the bus from `project.buses`. Persists.
   - If option B: check for routed tracks; surface warning in the UI before proceeding.
2. `EngineController` → disconnect bus node from graph → stop engine → remove nodes → restart →
   tear down `BusHost`.

### 4g. Rename Bus

1. UI: inline rename → `session.renameBus(busID:, name:)`.
2. Mutation sets `project.buses[id].name`. Persists.
3. `MixerView` observes `project.buses` → updates bus strip label.
4. All track output selector menus observe `project.buses` → update the bus option label for
   the renamed bus.

No audio graph involvement. No engine stop/restart required.

---

## 5. Open Questions: Resolved vs. Requiring User Input

### Question 1 — Solo convention: exclusive vs. additive (REQUIRES USER INPUT)

**Which solo model should buses and tracks use?**

- **A. Exclusive (one strip soloed at a time):** Soloing any strip clears all other solos. The
  solo state machine is simple: a single "active solo ID" pointer. The prototype implements this
  model. This is common in small-format and hardware-style mixers.
- **B. Additive (multiple strips can be simultaneously soloed):** Soloing a strip adds it to the
  "soloed set." Any strip in the set is audible; all others are effectively muted. This is the
  standard DAW model (Logic, Ableton, Pro Tools). More powerful but slightly more complex to
  implement and communicate in the UI.

Architecture impact: the exclusive model requires tracking one `activeSoloID: UUID?` per mixer
surface; the additive model requires computing the "any solo active" set across all tracks and
buses. Both are manageable. The UI difference (one highlighted strip vs. multiple highlighted
strips) is visible and must be communicated via strip styling.

This question must be resolved before the solo state machine is specified. It is recorded in
`open-questions.md`.

### Question 2 — Bus insert scope: global vs. scene-scoped (REQUIRES USER INPUT)

**Should bus inserts be global (a flat list that applies in all scenes) or scene-scoped (each
scene has its own insert chain, analogous to `MasterBusScene.inserts`)?**

Architecture analysis:

- **Global (flat `MixerBus.inserts: [MixerBusInsert]`):** Simpler model. The bus insert chain is
  one list; it applies regardless of which master bus scene is active. `BusHost` manages one insert
  chain per bus. This is what the prototype shows and what the UX review assumed.
- **Scene-scoped (`MixerBus.scenes: [MixerBusScene]`):** Mirrors the master bus architecture.
  Each master scene would have a corresponding bus-scene state, allowing per-scene bus insert
  chains. This greatly increases model complexity: `MixerBus` becomes analogous to `MasterBusState`,
  requiring scene creation, scene switching, and scene-aware insert chain rebuilds.

Cross-feature alignment with Mixer Main Out (item 4): that feature's architecture explicitly notes
that master inserts are per-scene, and that the mixer-busses insert scope decision could either
align or diverge. If bus inserts are global and master inserts are per-scene, the mixer surface
will show two different semantic models side by side. This may require a label distinction
("Inserts" for buses vs. "Inserts (Scene: X)" for master) and must be called out explicitly in
both feature specs. The mixer-main-out architecture (section 6) warns that a global-chain decision
in mixer-busses would supersede the active-scene display rule adopted for the master column.

This question must be resolved before `MixerBus` is modeled in the spec. It is recorded in
`open-questions.md`. The architectural recommendation is **global inserts** for buses: they are
simpler, consistent with the prototype, and bus insert chains being scene-independent is
consistent with how most hardware mixers and many DAWs handle group buses.

### Question 3 — Delete bus behavior (REQUIRES USER INPUT)

**When the user deletes a bus that has tracks routed to it, what happens to those tracks?**

- **A. Auto-reroute to master silently:** Simple. No blocking step. Potentially surprising.
- **B. Confirmation prompt listing affected tracks, then auto-reroute on confirm:** Conventional
  DAW behavior. Adds one interaction step.

This determines whether the delete mutation is a two-step (confirm) or one-step action and whether
the UI needs a confirmation sheet. It is recorded in `open-questions.md`.

### Question 4 — Bus chaining scope (RESOLVABLE IN SPEC)

The bus output selector is a static "→ Master" label in this item. Bus-to-bus routing (chaining)
is explicitly out of scope. The spec must state this explicitly to prevent implementers from
leaving a placeholder dropdown or hook for bus chaining in the output selector slot. This is a
spec-level constraint, not a user question.

### Question 5 — Routing-change visual (RESOLVABLE IN SPEC)

The prototype shows a brief disabled state with "Applying…" label on the track strip during engine
stop/rewire/restart, followed by a toast. The architecture is compatible with any of the four
options noted in the UX review (no visual, brief disabled, toast only, modal). The engine
stop/restart must happen on the main thread regardless of the visual choice. Architecture
recommendation: implement the brief disabled state + toast as shown in the prototype; no user
input required. This is a spec-level decision.

### Question 6 — Track strip rename scope (RESOLVABLE IN SPEC)

The prototype enables inline rename on track strips (double-click). Track strip rename is not
in the user stories for this item. The spec must explicitly state whether track rename lands with
this item or is deferred. Architecture has no preference; the rename interaction and mutation path
would be identical to bus rename. Recommendation: defer to a separate "Track Strip Rename" item
to keep this feature scoped to bus creation and routing. This is a spec-level decision.

### Question 7 — Auto-focus bus name on creation (RESOLVABLE IN SPEC)

Should "Add Bus" auto-focus the name field of the new bus strip? This is a UX discoverability
decision with no architecture implications beyond exposing a `focusedBusID: UUID?` transient
state for the inline rename. Recommendation: auto-focus is the better default (avoids user
confusion about whether the strip is renameable); spec should include it. Spec-level decision.

### Question 8 — Bus insert zone height (RESOLVABLE IN SPEC)

Should bus strips have a fixed-height insert zone (clipping overflow) or grow with insert count?
Architecture has no preference; this is a layout decision. A fixed-height zone (matching the
track strip height) is simpler and keeps the bus section height uniform. Growing zones are more
informative but produce uneven strip heights. Recommendation: fixed-height insert zone with
overflow scroll or count badge (e.g., "+2 more"). Spec-level decision.

---

## 6. Relationship to Mixer Main Out (Item 4)

Both features produce sections of the same mixer surface. The following constraints apply to
their co-existence:

- The three-zone layout (tracks | busses | master) must be composed in a shared container, not
  duplicated. Both features target `MixerWorkspaceView`; the container must allow the bus section
  (this feature) and the master column (item 4) to coexist.
- The bus insert chain's global vs. scene-scoped decision (question 2) directly affects the
  mixer-main-out active-scene display rule. The mixer-main-out architecture (section 6) warns that
  a global insert decision here would supersede the master column's scene-label logic. Both feature
  specs must cross-reference this dependency.
- If Mixer Main Out implements `MasterMeterPublisher` with an audio tap on `finalOutputMixer`, and
  this feature introduces bus node insertion between tracks and `preMasterMixer`, the tap placement
  is unaffected (it remains post-chain, before `mainMixerNode`). No conflict.
- If the engine stop/restart triggered by bus operations invalidates a meter tap installed by
  item 4, the tap lifecycle must be coordinated through `EngineController`. The existing
  `installMasterChains` pattern is the right model; both features must plug into the same
  stop/restart coordination, not bypass it.

---

## 7. Existing Patterns to Follow

| Concern | Existing Pattern | Source |
|---|---|---|
| Persisted insert list | `MasterBusScene.inserts`, `MasterBusInsert` | `Sources/Document/MasterBus.swift` |
| Insert chain host lifecycle | `MasterBusHost` (rebuild on topology change) | `Sources/Audio/MasterBusHost.swift` |
| Audio graph mutation dispatch | `performOnMain` in `MainAudioGraph` | `Sources/Audio/MainAudioGraph.swift:164` |
| Engine stop/restart for topology changes | `installMasterChains` pattern | `Sources/Audio/MainAudioGraph.swift:88–145` |
| Per-track mix application | `AudioInstrumentHost` outputMixer volume/pan | `Sources/Audio/AudioInstrumentHost.swift:458–465` |
| Document-level mutations | `SequencerDocumentSession+Mutations.swift` | `Sources/Document/SequencerDocumentSession+Mutations.swift:297–324` |
| Insert list UI (extraction target) | `ScenesWorkspaceView` insert list | `Sources/UI/Mixer/ScenesWorkspaceView.swift` |
| Codable additive migration | `decodeIfPresent` with default | `Sources/Document/Project+Codable.swift` |
| TrackGroup codable pattern | `TrackGroup` Codable conformance | `Sources/Document/TrackGroup.swift` |

---

## 8. Risks

| Risk | Severity | Mitigation |
|---|---|---|
| Insert chain UI is not a reusable component | High | The implementation loop must extract the insert list view from `ScenesWorkspaceView` into a generic component before or alongside this feature. This cannot be a copy-paste; it must be a parametrised extraction. |
| `MasterBusHost` is not generic | High | Either extract a generic `InsertChainHost` protocol from `MasterBusHost`, or duplicate its structure for `BusHost`. Duplication increases maintenance cost; extraction is preferred but requires coordination with mixer-main-out. |
| Engine stop/restart on every routing change | Medium | Each track-to-bus assignment change stops and restarts the engine. In sessions with many tracks being re-routed in sequence, this multiplies latency. Batch routing changes where possible; a dedicated "apply routing changes" action (vs. per-strip change) may be preferable in the spec. |
| Solo state machine scope | Medium | Solo must mute non-soloed buses and non-soloed tracks that route to master. The interaction between track solo and bus solo (does soloing a bus implicitly solo its member tracks?) must be resolved in spec. The architecture here does not decide this boundary. |
| Bus node insertion between tracks and preMasterMixer | Medium | This changes the signal path for every track and requires graph rewiring for all existing tracks that route to the new bus. The implementation must correctly disconnect and reconnect all affected track outputMixers in a single stop/restart cycle. |
| Shared mixer surface layout duplication | Medium | If item 4 and item 5 are built independently without a shared layout container, the zone layout may be duplicated or inconsistent. The implementation handoff must coordinate that one item owns the outer mixer container. |
| `isSoloed` added to `TrackMixSettings` | Low | An additive model change; `decodeIfPresent` with default `false` handles migration safely. Risk is minimal. |
| Bus name propagation to track output selectors | Low | Bus rename must propagate to all track output selectors. If selectors cache bus names rather than reading from `project.buses` reactively, renames will not propagate. The implementation must ensure output selector options are derived from `project.buses` directly, not from a local copy. |

---

## 9. Architecture Questions Gating Spec

Questions 1, 2, and 3 from Section 5 require user input before the spec is authoritative.
Questions 4–8 are resolvable within the spec without user escalation.

| # | Question | Resolution path |
|---|---|---|
| 1 | Solo convention: exclusive vs. additive? | User input required — see `open-questions.md` |
| 2 | Bus insert scope: global vs. scene-scoped? | User input required — see `open-questions.md` |
| 3 | Delete bus behavior: silent auto-reroute vs. confirmation? | User input required — see `open-questions.md` |
| 4 | Bus chaining explicitly deferred | Resolvable in spec (static "→ Master" label, no dropdown) |
| 5 | Routing-change visual | Resolvable in spec (brief disabled + toast as in prototype) |
| 6 | Track strip rename scope | Resolvable in spec (recommend defer to separate item) |
| 7 | Auto-focus bus name on creation | Resolvable in spec (recommend auto-focus) |
| 8 | Bus insert zone height | Resolvable in spec (recommend fixed-height with overflow indicator) |
