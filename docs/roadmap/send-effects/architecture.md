---
feature: send-effects
created: 2026-04-30
based_on:
  - docs/roadmap/send-effects/user-stories.md
  - docs/roadmap/send-effects/existing-state.md
  - docs/roadmap/send-effects/ux-review.md
  - docs/roadmap/send-effects/prototypes/01-mixer-send-knobs.html
  - docs/roadmap/send-effects/prototypes/02-send-bus-insert-chain.html
  - docs/roadmap/send-effects/prototypes/03-signal-flow-overview.html
  - docs/roadmap/mixer-main-out/architecture.md
  - docs/roadmap/mixer-main-out/open-questions.md
  - docs/roadmap/mixer-busses/architecture.md
  - docs/roadmap/mixer-busses/open-questions.md
  - wiki/pages/routing.md
  - wiki/pages/engine-architecture.md
---

# Send Effects — Architecture

Written: 2026-04-30
UX direction: three-prototype composite accepted in `ux-review.md`. Primary layout reference is P01 (`01-mixer-send-knobs.html`). P02 governs insert chain editor design. P03 is a planning artifact only (not a shipped screen).

---

## 1. Design Constraints Carried Forward

The following findings from `existing-state.md` and `ux-review.md` constrain every architectural decision below.

1. **No send bus concept, send tap node, or return path exists anywhere in the codebase.** This feature is entirely net-new audio graph topology. Nothing can be repurposed or minimally extended; every component named below requires creation.

2. **Every track output today connects directly and exclusively to `preMasterMixer`.** Both `AudioInstrumentHost` and `SamplePlaybackEngine` hardcode this connection. Installing a send tap requires rewiring the track output to fan out to both `preMasterMixer` (dry) and one or more send gain nodes (wet tap), using `engine.connect(_:to:[AVAudioConnectionPoint]:fromBus:format:)`.

3. **AVAudioEngine fan-out via `AVAudioConnectionPoint` is already used in `installMasterChains`.** `MainAudioGraph.swift` line 138 proves the pattern is valid in this project's threading model. The send tap reuses this pattern at the track level rather than the master level.

4. **Graph topology changes require engine stop/restart.** Installing the send tap fan-out for a track must follow the `installMasterChains` stop/reconnect/restart pattern. This is a one-time cost per session (send infrastructure is always-on, not per-routing-change).

5. **Send amount changes are real-time-safe parameter changes, not topology changes.** Once `sendGainMixerA` and `sendGainMixerB` nodes are installed per track, adjusting their `outputVolume` follows the same pattern as `setTrackMix` (`SamplePlaybackEngine.swift` line 365). No engine stop/restart is needed for level changes.

6. **The `MasterBusInsert` type and `MasterBusHost` are master-specific.** No generic insert-chain abstraction exists. Reuse requires extraction (same constraint documented in mixer-busses architecture §1.3). Send Effects cannot reuse the existing insert chain UI or host without that extraction; this is a sequencing dependency (see Section 8).

7. **Send bus insert scope must align with mixer-busses Q2.** Mixer Busses open question 2 asks whether bus inserts are global or scene-scoped. Send bus inserts must use the same answer. If bus inserts are global, send bus inserts are also global. If scene-scoped, both must be. The architectural recommendation for both is global (simpler, prototype-consistent), but the decision must come from user input, not be made independently here.

8. **This feature shares the mixer surface with Mixer Main Out (item 4) and Mixer Busses (item 5).** All three features target the same three-zone `MixerWorkspaceView` (tracks | busses | master). Send A and Send B are always-present bus columns that live inside or adjacent to the busses zone. The zone container must not be duplicated across features.

9. **The `routing.md` MIDI routing layer is not involved.** `Route`, `MIDIRouter`, and `RouteEvent` are MIDI fan-out machinery. The send effects feature operates entirely in the AVAudioEngine audio graph layer; it does not interact with `MIDIRouter` or `EngineController`'s MIDI dispatch path.

---

## 2. Application Invariants the Feature Must Preserve

### 2a. Document Is the Single Persisted Truth

The `.seqai` document is the only truth for authored state. The following fields must be persisted:

- `StepSequenceTrack.mix.sendA: Double` and `StepSequenceTrack.mix.sendB: Double` — per-track send amounts. Default `0.0`. Added to `TrackMixSettings` with `decodeIfPresent` fallback.
- `Project.sendBusA: SendBusState` and `Project.sendBusB: SendBusState` — the two fixed send buses with their insert lists. Added to `Project` with `decodeIfPresent` fallback (default: empty insert list).
- `SendBusState.inserts: [SendBusInsert]` — insert chain for each send bus. Scope (global vs. scene-scoped) deferred to alignment with mixer-busses Q2; architecture assumes global for now (see Section 5, question 1).

The following must not be persisted:

- Transient send gain node references (`sendGainMixerA`, `sendGainMixerB`) — these are runtime audio graph objects, recreated on session start.
- Any UI-only selection state (active bus in insert chain editor, insert-editor-open flag).

### 2b. No UI-Only Playback Truth

Per the architecture guardrails:

- Send amount knobs in the mixer channel strip must read from `track.mix.sendA` / `track.mix.sendB` (document state) and write through a document mutation that propagates to the engine. They must not maintain local `@State` copies that diverge from the document.
- Send gain node `outputVolume` writes must go through the `performOnMain` path used by `MainAudioGraph`, not from a view gesture handler directly. The mutation path is: view gesture → `session.setTrackSend(trackID:sendA:sendB:)` → `EngineController.applyTrackSend(trackID:)` → `sendGainMixerA.outputVolume` via `performOnMain`.

### 2c. Audio Thread Isolation

- `sendGainMixerA.outputVolume` and `sendGainMixerB.outputVolume` are written from the main thread only, via `performOnMain`.
- Send bus insert chain rebuilds (AU unit construction) follow the `installMasterChains` stop/restart pattern — engine stop on main thread, topology change, engine restart.
- Any metering tap installed by Mixer Main Out (item 4) on `finalOutputMixer` must be removed before engine stop and reinstalled after restart. The send bus infrastructure install must coordinate with the same tap lifecycle, not bypass it.

### 2d. Acyclic Graph Guarantee

The send topology is acyclic by construction:

- The send tap branches from a track-level node (`outputMixer` or `SamplerFilterNode`), never from `preMasterMixer` or any downstream node.
- The send return mixer (`sendReturnMixerA`, `sendReturnMixerB`) connects to `finalOutputMixer` (preferred) or `preMasterMixer`, never back to a track node or to `preMasterMixer` in a way that could re-enter the tap.
- AVAudioEngine validates graph acyclicity on start; a cycle would produce a start failure, not a subtle bug.

### 2e. Persistence Migration Safety

Two additive migrations are required:

- `TrackMixSettings`: add `sendA: Double` and `sendB: Double` with `decodeIfPresent(_:forKey:) ?? 0.0`. Existing sessions decode with zero sends; no routing change occurs.
- `Project`: add `sendBusA: SendBusState` and `sendBusB: SendBusState` with `decodeIfPresent(SendBusState.self, forKey: .sendBusA) ?? SendBusState.defaultA` (empty insert list). Existing sessions decode with empty send buses, which is the correct zero-state (send buses with empty insert chains pass signal through at unity or are inert if no track has a non-zero send amount).

No version bump or migration function is required; the `decodeIfPresent` defaults produce valid state.

---

## 3. Data and Runtime Shape: Persisted vs. Transient

### 3a. Proposed Persisted Types

**`SendBusState`** (new type, two fixed instances on `Project`)

| Field | Type | Default | Notes |
|---|---|---|---|
| `id` | Fixed string or UUID | `"send-a"` / `"send-b"` | Stable identity. Not user-assignable. |
| `name` | `String` | `"Send A"` / `"Send B"` | Fixed display name. Not user-editable in v1. |
| `inserts` | `[SendBusInsert]` | `[]` | Insert chain. See scope question in Section 5. |

**`SendBusInsert`** (new type, structurally identical to `MasterBusInsert`)

The insert representation for send buses. Given the `MasterBusInsert` pattern (`kind: MasterBusInsertKind`, `isEnabled: Bool`, `auPresetData: Data?`, `wetDry: Double`, native filter/bitcrusher cases), `SendBusInsert` should be structurally identical. The architecture guardrail from mixer-busses §3a applies: do not duplicate the type schema unless the two insert kinds genuinely differ. The implementation loop should evaluate whether `MasterBusInsert` can be renamed to a generic `InsertEffect` type shared across master bus, mixer busses, and send buses. This is an implementation decision, not a model difference.

**`TrackMixSettings` additions**

| Field | Type | Default | Notes |
|---|---|---|---|
| `sendA` | `Double` | `0.0` | Amount of signal sent to Send A. Range `0.0–1.0`. |
| `sendB` | `Double` | `0.0` | Amount of signal sent to Send B. Range `0.0–1.0`. |

`sendA` and `sendB` are clamped to `[0.0, 1.0]` on write. Pre/post-fader toggle is explicitly deferred (user story 5, stretch goal).

**`ProjectDelta` additions**

| Delta case | Payload | Notes |
|---|---|---|
| `trackSendChanged(trackID: UUID, sendA: Double, sendB: Double)` | Per-track send amounts | Allows incremental engine apply without re-applying the full mix state. Analogous to existing `trackMixChanged`. |
| `sendBusInsertChanged(bus: SendBusID, inserts: [SendBusInsert])` | Full insert list for one bus | Triggers insert chain rebuild in `SendBusHost`. |

### 3b. Transient Runtime State

| Field | Owner | Notes |
|---|---|---|
| `sendGainMixerA: AVAudioMixerNode` (per track) | `AudioInstrumentHost` / `SamplePlaybackEngine` | The send tap gain node for Send A. `outputVolume` = `track.mix.sendA`. Recreated on session start. |
| `sendGainMixerB: AVAudioMixerNode` (per track) | `AudioInstrumentHost` / `SamplePlaybackEngine` | The send tap gain node for Send B. `outputVolume` = `track.mix.sendB`. |
| `sendBusHostA: SendBusHost` | `EngineController` or `MainAudioGraph` | Owns the Send A summing mixer, insert chain nodes, and return connection. |
| `sendBusHostB: SendBusHost` | `EngineController` or `MainAudioGraph` | Owns the Send B summing mixer, insert chain nodes, and return connection. |

### 3c. Send Bus Host Lifecycle

A `SendBusHost` (new type, analogous to `MasterBusHost`) is required per send bus. Its responsibilities:

- Owns the `sendSumMixer: AVAudioMixerNode` that receives signal from all per-track `sendGainMixerA` (or B) nodes.
- Owns the insert chain node sequence (AU units) constructed from `SendBusState.inserts`.
- Owns the `sendReturnMixer: AVAudioMixerNode` that connects the post-chain output to the return destination (`finalOutputMixer` — see Section 5, question 2).
- Applies `outputVolume` to `sendSumMixer` (bus return level; initially always 1.0, no user control in v1).
- Manages insert chain construction and AU caching.
- Is created once at session start; torn down at session end.
- Coordinated with `MasterBusHost` for engine stop/restart ordering.

### 3d. Signal Path With Send Buses

```
[track outputMixer / SamplerFilterNode]
        │
        ├──────────────────────────────────────────────────► preMasterMixer (dry)
        │
        ├── sendGainMixerA (outputVolume = track.mix.sendA) ─► sendSumMixerA
        │                                                              │
        │                                                    [Send A insert chain]
        │                                                              │
        │                                                    sendReturnMixerA
        │                                                              │
        │                                                    finalOutputMixer (return)
        │
        └── sendGainMixerB (outputVolume = track.mix.sendB) ─► sendSumMixerB
                                                                       │
                                                             [Send B insert chain]
                                                                       │
                                                             sendReturnMixerB
                                                                       │
                                                             finalOutputMixer (return)
```

The fan-out from the track output node to both `preMasterMixer` (dry) and the send gain nodes (wet tap) uses `engine.connect(_:to:[AVAudioConnectionPoint]:fromBus:format:)`, the same mechanism used for the A/B master chain fan-out in `installMasterChains`.

Tracks with `sendA == 0.0` and `sendB == 0.0` still have the gain nodes installed (the infrastructure is always-on), but `outputVolume = 0.0` means they contribute no signal. This avoids per-track graph rewiring when the user increases a send from zero.

**Return path (preferred):** `sendReturnMixerA` and `sendReturnMixerB` connect to `finalOutputMixer`. This means the send returns bypass the master insert chain — the wet signal is not re-processed by master EQ or compression. This is standard DAW behavior (return is post-master chain). See Section 5, question 2 for the unresolved decision.

---

## 4. Mutation Paths and Ownership

### 4a. Per-Track Send Amount

1. View gesture (send knob in `MixerChannelStrip`) → `session.setTrackSend(trackID:sendA:sendB:)`.
2. `SequencerDocumentSession+Mutations`: clamps values to `[0.0, 1.0]`, sets `track.mix.sendA` and `track.mix.sendB`. Persists. Emits `trackSendChanged` delta.
3. `EngineController` observes `trackSendChanged` → `applyTrackSend(trackID:)` → writes `sendGainMixerA.outputVolume` and `sendGainMixerB.outputVolume` via `performOnMain`.

No engine stop/restart required. This is a real-time-safe parameter write identical to the existing `setTrackMix` path.

### 4b. Send Bus Insert Chain (Add, Remove, Bypass, Reorder)

1. View interaction in the send bus insert chain editor → `session.mutateSendBusInserts(bus:inserts:)`.
2. `SequencerDocumentSession+Mutations`: updates `project.sendBusA.inserts` (or B). Persists. Emits `sendBusInsertChanged` delta.
3. `EngineController` observes `sendBusInsertChanged` → `SendBusHost.rebuildInsertChain(inserts:)` → stops engine → reconstructs AU node chain between `sendSumMixer` and `sendReturnMixer` → restarts engine.

Insert chain rebuild requires engine stop/restart. This matches the `MasterBusHost.installMasterChains` pattern. Bypassing an already-instantiated AU unit can be done without stop/restart if `AUAudioUnit.shouldBypassEffect` is used (same investigation note as mixer-busses §4e).

### 4c. Session Start — Send Infrastructure Install

At session start (`EngineController.startSession` or equivalent), after the existing track and master graph is built:

1. Create `SendBusHostA` and `SendBusHostB` from `project.sendBusA` and `project.sendBusB`.
2. For each track host (`AudioInstrumentHost`, `SamplePlaybackEngine`): create and connect `sendGainMixerA` and `sendGainMixerB` as parallel outputs from the track's post-fader output node, in addition to the existing `preMasterMixer` connection. Fan-out uses `AVAudioConnectionPoint`.
3. Connect all per-track `sendGainMixerA` outputs to `SendBusHostA.sendSumMixer`.
4. Connect all per-track `sendGainMixerB` outputs to `SendBusHostB.sendSumMixer`.
5. Build insert chains in each `SendBusHost`.
6. Connect `SendBusHostA.sendReturnMixer` and `SendBusHostB.sendReturnMixer` to `finalOutputMixer`.
7. Set `sendGainMixerA.outputVolume` and `sendGainMixerB.outputVolume` for each track from `track.mix.sendA` / `track.mix.sendB`.

This entire setup requires one engine stop/restart (or can be done before the engine's first start in a session). It does not repeat unless the session is torn down and rebuilt.

### 4d. Engine Stop/Restart Coordination

Any operation that stops the engine must also:
- Remove any meter tap installed by Mixer Main Out (`MasterMeterPublisher`) before stop.
- Reinstall the tap after restart.

This coordination responsibility belongs to `EngineController` (or `MainAudioGraph`). `SendBusHost.rebuildInsertChain` must call into the coordinator, not directly stop the engine from an isolated context.

---

## 5. Open Questions: Resolved vs. Requiring User Input

### Question 1 — Send bus insert scope: global vs. scene-scoped (BLOCKED on mixer-busses Q2)

**This question cannot be resolved independently.** It must align with the mixer-busses open question 2 (bus insert scope: global vs. scene-scoped).

Architecture position: The strongly recommended answer for both features is **global inserts** (flat `SendBusState.inserts: [SendBusInsert]`, not scene-scoped). Rationale:
- The prototype (P02) treats send bus inserts as global.
- Send buses in almost every DAW (Logic, Ableton, Pro Tools) have a single, scene-independent insert chain. Scene-scoped send bus inserts are an unusual design.
- Global inserts are substantially simpler to model and host (`SendBusHost` manages one insert chain, not a list of scene-insert chains).

If the user confirms global inserts for mixer-busses (Q2-A), the same answer applies here automatically.

If the user chooses scene-scoped inserts for mixer-busses (Q2-B), `SendBusState` must gain a `scenes: [SendBusScene]` collection, each containing an insert list. This substantially increases model complexity and must be designed in parallel with the mixer-busses scene model. The spec cannot be written until this is resolved.

This question is recorded in `open-questions.md` and blocks spec.

### Question 2 — Return path: `finalOutputMixer` vs. `preMasterMixer` (REQUIRES USER INPUT)

**Should the send bus return connect to `finalOutputMixer` (bypasses master insert chain) or `preMasterMixer` (wet signal passes through master inserts)?**

Architecture analysis:
- **`finalOutputMixer` (preferred):** Standard DAW behavior. The send return (reverb, delay wet signal) is not re-processed by the master bus compressor or EQ. The wet signal is blended with the post-chain output of the master. Implementation: `sendReturnMixer → finalOutputMixer` using `AVAudioConnectionPoint`. There is no loop risk since the tap originates from a track-level node.
- **`preMasterMixer`:** The wet signal passes through the master insert chain along with the dry tracks. This may produce undesirable double-compression of reverb tails. However, the graph wiring is simpler (only one summing node to connect to). If the master insert chain is empty, the two options are equivalent.

Recommendation: `finalOutputMixer`. This is the conventional behavior and matches the architecture that `existing-state.md` §3 recommends. The `finalOutputMixer` path is acyclic and already receives the master chain output, making it the natural return point.

This is a product decision with audible consequences. It is recorded in `open-questions.md` and must be confirmed before spec, because it determines which node `SendBusHost` connects `sendReturnMixer` to during session start.

### Question 3 — Muted track and send taps (REQUIRES USER INPUT)

**Does a muted track contribute signal to Send A and Send B?**

Architecture analysis:

The current mute implementation sets `outputMixer.outputVolume = 0.0` for the track (or equivalent in `SamplePlaybackEngine`). The position of the send tap node relative to this mute point determines the answer:

- **Option A — Mute cuts the send tap (send tap is post-mute):** The send gain node is placed after the muted output node. When `outputVolume = 0.0`, no signal reaches the send gain node; the send contributes nothing. This is standard DAW behavior: muting a track silences it everywhere — dry and wet. The fan-out from the track's `outputMixer` (which applies mute/level) to both `preMasterMixer` and `sendGainMixerA`/`B` naturally achieves this because the muted `outputVolume = 0.0` applies before the fan-out point.

- **Option B — Mute does not cut the send tap (send tap is pre-mute):** The send gain node is placed on a branch from before the mute gain stage. A muted track would still contribute its wet signal to the send bus (the reverb tail of a muted track would be audible). This requires placing the send tap between the raw instrument output and the track's output fader — a different graph wiring that also exposes a pre-fader tap (similar in implementation to the pre-fader story 5 stretch goal).

Architecture recommendation: **Option A (mute cuts the send tap)**. This is the standard, expected behavior. It is the natural result of fanning out from `outputMixer` (which already applies the mute gain). It requires no special wiring. Option B is a deliberate choice that adds graph complexity and delivers an unintuitive result by default.

This must be confirmed before spec, as it determines the tap point. If Option B is desired, the spec must describe the pre-mute tap wiring, which substantially changes the send infrastructure install sequence.

This question is recorded in `open-questions.md`.

### Question 4 — Send bus placement in the three-zone mixer layout (RESOLVABLE IN SPEC)

**Where do Send A and Send B columns sit in the tracks | busses | master layout?**

Architecture position: Send A and Send B should sit in the busses zone, after user-created bus strips and before the master column. They are always-present, always-visible columns (no user creation required). Because they are fixed, they do not need the "Add Bus" affordance that user buses have.

Options:
- **A. Inside the user-bus section with a type badge** (e.g., "SEND" label in the strip header).
- **B. As fixed columns between the user-bus section and the master column** (a sub-zone with a separator).

P01 shows option B (dashed separator, rightmost send bus columns before the master). This is the recommended layout and is consistent with how Send A/B are semantically distinct from user-created buses. Spec-level decision; no model impact.

### Question 5 — Send control: rotary knob vs. mini fader (RESOLVABLE IN SPEC)

P01 uses a rotary knob with click-to-popover slider. The prototype notes raise the iPad touch-friendliness concern. The spec should confirm the control type. The architecture supports either — both result in a `Double` value written to `track.mix.sendA`/`sendB`. A mini horizontal fader (same as the channel fader, smaller) may be more touch-friendly and consistent with existing mixer controls. Spec-level decision.

### Question 6 — Zero-value knob visual (RESOLVABLE IN SPEC)

Should a send control at `0.0` appear visually inert (greyed border, pointer) or identical to an active control? Spec-level decision; no architecture impact.

### Question 7 — Insert reorder: arrow buttons vs. drag handles (RESOLVABLE IN SPEC)

P02 provides drag handles (non-functional). The existing project convention uses arrow buttons in `ScenesWorkspaceView`. The spec must pick one. Architecture recommendation: arrow buttons, matching the existing pattern, lower implementation risk. Spec-level decision.

### Question 8 — Insert bypass toggle style (RESOLVABLE IN SPEC)

P02 uses a text button ("Bypass" / "Bypassed", yellow). Mixer Main Out uses a filled/hollow circle symbol. One pattern must be used across all insert chains. Spec-level decision; must align with the choice made in mixer-main-out and mixer-busses specs.

### Question 9 — Signal flow diagram as app screen (RESOLVED: planning artifact only)

P03 raised whether the signal flow diagram should be an app screen. The recommendation from `ux-review.md` is that P03 is a planning artifact only. No other mixer feature has a dedicated signal flow view. This architecture confirms: P03 is not a shipped screen. The spec should not include it as a UI surface.

---

## 6. Relationship to Mixer Main Out (Item 4) and Mixer Busses (Item 5)

### With Mixer Main Out

- If Mixer Main Out installs a `MasterMeterPublisher` tap on `finalOutputMixer`, the send return mixer also connects to `finalOutputMixer`. The meter tap placement is unaffected (it reads the mixed output, which now includes send returns — correct behavior).
- When `SendBusHost.rebuildInsertChain` stops the engine, the meter tap lifecycle must be coordinated through `EngineController` (same constraint as mixer-busses §6).
- The insert bypass toggle style must match the Mixer Main Out convention. One pattern across the whole mixer surface.
- The three-zone mixer container must accommodate the send bus columns without duplicating zone layout code.

### With Mixer Busses

- **Critical dependency: mixer-busses Q2 (insert scope) must be resolved before the send-effects spec can be written.** The `SendBusState` model shape depends on this answer. If scene-scoped, the model grows substantially. This is not an advisory note — it is a hard gate.
- The generic insert chain component extraction (mixer-busses risk §8, "Insert chain UI is not a reusable component") directly affects send effects. If the mixer-busses implementation extracts a generic `InsertChainView` and a generic `InsertChainHost` protocol, send effects should reuse them. If that extraction is deferred or skipped, send effects faces the same duplication risk independently.
- Muted-track send behavior (Section 5, question 3) must be consistent with how mixer-busses handles muted tracks and user bus routing. Standard DAW behavior (mute cuts all sends) should be the answer for both.
- Solo state: if mixer-busses introduces a solo state machine and a muted track contributing to send buses would interact with solo behavior, the solo exclusion logic must account for send bus signal as well. This is out of scope for send-effects v1 but must not be contradicted by the send tap wiring.

---

## 7. Existing Patterns to Follow

| Concern | Existing Pattern | Source |
|---|---|---|
| Multi-output fan-out from one node | `engine.connect(_:to:[AVAudioConnectionPoint]:fromBus:format:)` for A/B master branches | `Sources/Audio/MainAudioGraph.swift:138` |
| Real-time-safe gain write | `outputMixer.outputVolume` via `performOnMain` | `Sources/Audio/SamplePlaybackEngine.swift:365` |
| Insert chain host lifecycle | `MasterBusHost` (stop/rebuild AU chain/restart) | `Sources/Audio/MasterBusHost.swift` |
| Audio graph mutation dispatch | `performOnMain` in `MainAudioGraph` | `Sources/Audio/MainAudioGraph.swift:164` |
| Document-level mutations | `SequencerDocumentSession+Mutations.swift` | `Sources/Document/SequencerDocumentSession+Mutations.swift:297–324` |
| Codable additive migration | `decodeIfPresent` with default | `Sources/Document/StepSequenceTrack.swift:125–144` |
| Per-track mix application delta | `trackMixChanged` delta → `EngineController.setTrackMix` | `Sources/Document/ProjectDelta.swift` |
| Insert list UI (extraction target) | `ScenesWorkspaceView` insert list | `Sources/UI/Mixer/ScenesWorkspaceView.swift` |

---

## 8. Risks and Dependencies

| Risk | Severity | Mitigation |
|---|---|---|
| Insert scope alignment with mixer-busses Q2 | **Blocking** | Spec cannot be written until mixer-busses Q2 is resolved. `SendBusState` model shape is undefined until then. Do not begin spec in parallel. |
| Generic insert chain component not extracted | High | If mixer-busses does not extract `InsertChainView` and `InsertChainHost`, send effects must either wait or build its own chain editor (duplication). The implementation handoff must capture sequencing: mixer-busses chain extraction must precede or accompany send-effects implementation. |
| Engine stop/restart on insert chain edit | Medium | Every insert add/remove stops the engine (same as master bus). User-visible latency. Mitigation: same as mixer-busses — use `AUAudioUnit.shouldBypassEffect` for bypass without stop where possible. |
| Send tap fan-out wiring at session start | Medium | Installing the per-track fan-out for all tracks in one stop/restart is the correct approach, but must be implemented atomically. Partial installation (some tracks fanned out, others not) would produce inconsistent routing. The implementation must fan out all tracks in a single reconnect pass. |
| Meter tap invalidation on send insert rebuild | Medium | Send insert chain rebuilds stop the engine. If Mixer Main Out's meter tap is installed on `finalOutputMixer`, it must be removed before stop and reinstalled after restart. Coordination through `EngineController` is required. |
| Muted-track send behavior determines tap wiring point | Medium | The mute-cuts-send recommendation (architecture §5, Q3) means the tap is from the post-mute output node. If the user confirms pre-mute behavior (Option B), the tap point changes to before the track fader — this is a fundamentally different graph topology that must be revisited before implementation. Confirm Q3 before implementation begins. |
| Return path determines `sendReturnMixer` connection | Medium | If `preMasterMixer` is chosen over `finalOutputMixer` for the return (Q2), the wet signal passes through master inserts. This is architecturally simple but may produce undesirable audio behavior. Confirm Q2 before implementation begins. |
| Pre/post-fader toggle (story 5, deferred) | Low | Pre-fader tap requires branching before the track fader, which is a different graph node than the post-fader tap used in v1. Adding it later requires engine stop/restart and a graph rewiring per track. Ensure the implementation does not make the pre-fader position structurally impossible (the current post-mute fan-out is compatible with adding a pre-fader branch later). |
| `TrackMixSettings` codable migration | Low | `decodeIfPresent` with default `0.0` is a proven zero-cost migration. Existing sessions will decode correctly. |

---

## 9. Architecture Questions Gating Spec

| # | Question | Resolution path |
|---|---|---|
| 1 | Send bus insert scope: global vs. scene-scoped? | **Blocked on mixer-busses Q2** — must be resolved by user first; see `open-questions.md` |
| 2 | Return path: `finalOutputMixer` vs. `preMasterMixer`? | User input required — recommendation is `finalOutputMixer`; see `open-questions.md` |
| 3 | Muted-track send behavior: mute cuts send tap (Option A) or pre-mute tap (Option B)? | User input required — recommendation is Option A; see `open-questions.md` |
| 4 | Send bus placement in three-zone layout | Resolvable in spec (recommendation: fixed columns in busses zone, before master) |
| 5 | Send control: rotary knob vs. mini fader | Resolvable in spec (recommendation: align with mixer surface control conventions) |
| 6 | Zero-value knob visual | Resolvable in spec |
| 7 | Insert reorder: arrow buttons vs. drag handles | Resolvable in spec (recommendation: arrow buttons, matching existing pattern) |
| 8 | Insert bypass toggle style | Resolvable in spec (must align with mixer-main-out / mixer-busses choice) |
| 9 | Signal flow diagram as app screen | Resolved: planning artifact only, not shipped |

Questions 1, 2, and 3 must be resolved before the spec is authoritative. Question 1 (insert scope) is the highest-priority blocker because it determines the `SendBusState` model shape and is in turn blocked by mixer-busses Q2.
