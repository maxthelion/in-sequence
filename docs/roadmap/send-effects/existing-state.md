# Send Effects — Existing State

Inspected 2026-04-29. Read scope: audio graph, instrument hosts, sampler playback engine, document model, mixer UI, project delta layer, tests.

Cross-reference: `docs/roadmap/mixer-busses/existing-state.md` documents the shared constraints — no generic insert-chain component, no solo anywhere, routing changes are graph stop/rewire/restart. The notes below cover only what is additionally true for the send topology.

---

## 1. Current Architecture

### Signal Path Relevant to Sends

Every track output already terminates at a single node: `preMasterMixer` (`MainAudioGraph`, line 27). The path is:

```
[AU instrument outputMixer] ──────────────────┐
[Sampler trackMixer → SamplerFilterNode] ──────┤
                                               ↓
                                      preMasterMixer
                                               ↓
                                [MasterBus insert chain]
                                               ↓
                                      finalOutputMixer
                                               ↓
                                  engine.mainMixerNode
```

There is no secondary tap point, no auxiliary bus node, and no parallel path of any kind between the track output and `preMasterMixer`. Every track's signal is summed and irrecoverably mixed before any downstream processing.

### Fan-Out Capability in AVAudioEngine

`installMasterChains` (`MainAudioGraph.swift`, lines 82–146) already uses `engine.connect(_:to:[AVAudioConnectionPoint]:fromBus:format:)` to fan `preMasterMixer` output into multiple parallel A/B master chains. This proves that AVAudioEngine fan-out is usable in the project's threading model. However, this fan-out is on the **output** side of `preMasterMixer` — it splits the already-summed stereo mix. A send tap needs to branch individual **track** outputs before they reach `preMasterMixer`, which is a different point in the graph.

### Track Output Nodes

- `AudioInstrumentHost` (`Sources/Audio/AudioInstrumentHost.swift`, line 462): connects `outputMixer → preMasterMixer`.
- `SamplePlaybackEngine` (`Sources/Audio/SamplePlaybackEngine.swift`, lines 421–422): connects `trackMixer → SamplerFilterNode → preMasterMixer`.

Neither host exposes a parameter to redirect output to a different destination node. The wiring is hardcoded.

### No Send or Auxiliary Bus Concept

A search for `Send`, `Aux`, `Return`, `Parallel` across all Swift sources returns no audio-domain results. The term `send` appears only in `MIDIClient.send(_:to:)` (MIDI packet dispatch) and `MIDIClientSendTests` (MIDI tests). There is no `SendBusState`, `SendBusHost`, `SendMixerNode`, or equivalent.

### Document Model

`StepSequenceTrack` (`Sources/Document/StepSequenceTrack.swift`):

- `mix: TrackMixSettings` contains `level`, `pan`, `isMuted`. No send-amount fields.
- `macros: [TrackMacroBinding]` — per-track AU macro bindings, not mix sends.
- No `sendA: Double`, `sendB: Double`, or `sends: [SendAmount]` field.

`Project` (`Sources/Document/Project.swift`):

- `masterBus: MasterBusState` — the only bus in the model.
- No `sendBuses`, `sendA`, `sendB`, or `auxiliaryBuses` property.

`ProjectDelta` (`Sources/Document/ProjectDelta.swift`):

- `trackMixChanged(trackID:mix:)` — carries only `TrackMixSettings` (level, pan, muted). No delta case for send-amount changes.
- No delta case for send-bus state changes.

`MasterBusInsert` / `MasterBusInsertKind` (`Sources/Document/MasterBus.swift`, lines 698–748):

- The only insert type in the codebase. Supports `nativeFilter`, `nativeBitcrusher`, `auEffect`.
- Tightly named `MasterBus*`; not parameterised for use on an arbitrary bus.

### Mixer UI

`MixerChannelStrip` (`Sources/UI/MixerView.swift`, lines 54–244):

- Shows: track name, destination label, level fader, pan slider, mute button, step/pitch counts.
- No send-A or send-B knob section. No placeholder or comment indicating future sends placement.

`MixerWorkspaceView` (`Sources/UI/Mixer/MixerWorkspaceView.swift`):

- Contains a "Voice Routes" placeholder panel for per-voice bus treatment — relevant to routing, not specifically to sends.

---

## 2. Per-Story Gap Analysis

### Story 1 — Route a track to Send A or Send B (per-track send-amount knob)

| Dimension | Today |
|---|---|
| Model | `StepSequenceTrack` has no `sendA` / `sendB` amount field. `TrackMixSettings` has no send fields. |
| Engine | `AudioInstrumentHost` and `SamplePlaybackEngine` connect each track's output node to `preMasterMixer` only. No secondary gain node or alternative destination exists per track. |
| Persistence | No send-amount fields in `StepSequenceTrack.encode(to:)`. `ProjectDelta` has no send-changed case. |
| UI | `MixerChannelStrip` has no send-amount control. |
| Model gap | Add `sendA: Double` and `sendB: Double` (both default `0`) to `TrackMixSettings` (or a new nested `TrackSendSettings`). Update `TrackMixSettings.Codable` with `decodeIfPresent` fallback to `0`. Add `trackSendChanged` case to `ProjectDelta`. |
| Engine gap | Each track host needs a `sendGainMixerA` / `sendGainMixerB` `AVAudioMixerNode` placed in parallel with the dry path, connecting to a new per-send-bus `AVAudioMixerNode`. Setting `outputVolume` on these gain nodes is the only real-time-safe way to change send amount (no graph rewire needed for level changes, unlike routing). |
| UI gap | Two send-amount knobs (or faders) per track strip in `MixerChannelStrip`. |

### Story 2 — Add insert effects to a send bus

| Dimension | Today |
|---|---|
| Model | No `SendBusState` or insert list for Send A/B exists. `MasterBusInsert` types exist but are named for the master bus specifically. |
| Engine | No `SendBusHost` or equivalent. `MasterBusHost` manages master-only chains via `installMasterChains`; it is not parameterisable for a separate bus node. |
| UI | Insert chain editor exists in `ScenesWorkspaceView` but is coupled to `MasterBusScene`/`MasterBusState`. See busses inspection for detail on the lack of a generic insert-chain component. |
| Model gap | New type: `SendBusState` (id, name, `inserts: [MasterBusInsert]` or a renamed generic type). Two fixed instances on `Project` (`sendBusA`, `sendBusB`). |
| Engine gap | New `SendBusHost` (analogous to `MasterBusHost`) per send bus, owning the AVAudioNode chain between the send return mixer and `finalOutputMixer`. |
| UI gap | Send bus panel in the mixer showing insert chain, analogous to the master chain editor. Cannot reuse the master chain editor without extraction — same concern as noted for mixer busses. |

### Story 3 — Hear send bus output in the mix (automatic return to master)

| Dimension | Today |
|---|---|
| Model | No send bus model exists. No concept of automatic return to master. |
| Engine | No return mixer node exists. The send bus output would need to connect to `finalOutputMixer` (or to `preMasterMixer` if post-master-chain return is not desired). |
| Architecture concern | Connecting a send return **after** `preMasterMixer` but **before** the master insert chain means the send return signal bypasses any master-bus compression or EQ — which is typical DAW behaviour. Connecting to `preMasterMixer` instead routes the wet signal through the master chain, which is also valid. The choice is not obvious; it should be a spec decision. Connecting the send return back to `preMasterMixer` is simpler (one node already exists), but the loop-avoidance guarantee relies on the send tap coming from a track-level node, not from `preMasterMixer` itself. |
| Loop-avoidance | AVAudioEngine does not allow cycles. Since the send tap is a new gain node inserted **between** the track output and `preMasterMixer`, not from `preMasterMixer` itself, there is no cycle. The send mixer → send chain → return mixer → `finalOutputMixer` (or `preMasterMixer`) path is acyclic. |
| Model gap | `SendBusState` needs a `connectsToMaster: Bool` flag (always `true` initially; this is the automatic return). |
| Engine gap | `SendBusHost` must attach its return mixer to `finalOutputMixer` (preferred) or `preMasterMixer` at graph build time. No dynamic rewire needed for the return path unless the user changes it. |
| UI gap | None beyond visual indication that the return is active (e.g. a label in the send bus panel). |

### Story 4 — Per-track persisted send levels

| Dimension | Today |
|---|---|
| Model | No send-amount fields in `StepSequenceTrack` or `TrackMixSettings`. |
| Persistence | `StepSequenceTrack.init(from:)` uses `decodeIfPresent` for several fields — the pattern for safe additive migration is established (lines 125–144). Adding `sendA` and `sendB` with `decodeIfPresent(_:forKey:) ?? 0` is a standard zero-cost migration. |
| Persistence gap | Add CodingKey cases for `sendA` and `sendB`. Encode both. Decode with `decodeIfPresent` fallback to `0`. |
| Engine gap | `EngineController` must propagate send-amount changes to the send gain nodes when a `trackSendChanged` delta is received — analogous to how `trackMixChanged` drives `setTrackMix`. |

### Story 5 — Pre/post-fader tap (stretch goal)

| Dimension | Today |
|---|---|
| Model | No pre/post-fader toggle exists anywhere. |
| Engine | Post-fader tap is naturally achieved by placing the send gain node after the track's `outputMixer` (which applies the channel fader level). Pre-fader tap requires branching **before** the track fader, i.e. directly from the instrument or raw voice output. The `AudioInstrumentHost` graph is: `instrument → outputMixer → preMasterMixer`. A pre-fader tap would branch from `instrument` (or the raw voice output in `SamplePlaybackEngine`). |
| Engine gap | If pre-fader is added, the send gain node must be inserted at a different point in the chain per-track depending on the toggle state. This requires graph rewiring (engine stop/restart) when the toggle changes — it cannot be achieved with `outputVolume` alone. |
| Model gap | `TrackMixSettings` would need a `sendAIsPreFader: Bool` and `sendBIsPreFader: Bool` (both default `false`). |
| UI gap | Per-send pre/post toggle in the track strip. |
| Recommendation | Defer pre/post to a follow-on iteration. The graph rewire complexity is disproportionate to the stretch-goal priority. Document as out of scope for v1. |

---

## 3. Architecture Constraints Specific to Sends

### Parallel Tap Without Dry-Path Disruption

The send gain node must be a new `AVAudioMixerNode` connected **in parallel** from the track's post-fader output node, not inserted in-series between the track output and `preMasterMixer`. The dry signal must continue to flow unmodified to `preMasterMixer`. AVAudioEngine supports multi-output fan-out using `engine.connect(_:to:[AVAudioConnectionPoint]:fromBus:format:)` — this is already used in `installMasterChains` for the A/B master branches (line 138). The same mechanism can fan a track's `outputMixer` output to both `preMasterMixer` (dry) and `sendGainMixerA`/`sendGainMixerB` (wet). Rewiring to install this fan-out requires an engine stop/restart, but it only needs to happen once when the send infrastructure is first created, not every time the send amount changes.

### Send Amount as Parameter, Not Graph Change

Once the send gain nodes are in place, adjusting `sendGainMixerA.outputVolume` is a real-time-safe parameter change — no graph mutation required. This is the same pattern used for channel fader/pan changes today (`setTrackMix` in `SamplePlaybackEngine`, line 365).

### Return Path and Loop Avoidance

Connecting the send return to `finalOutputMixer` (before `engine.mainMixerNode`, after the master chain) avoids re-entering the master insert chain while still reaching the output. Connecting it to `preMasterMixer` would route the wet signal through the master insert chain, which may or may not be desirable — this must be a spec decision. Either way, the path is acyclic because the tap originates from a track-level node, never from `preMasterMixer` or `finalOutputMixer`.

### Gain Compensation

Sending part of a track's signal to a send bus does not reduce the dry signal level — the fan-out copies the full signal; it does not split it. No gain compensation on the dry path is needed. The send amount knob controls how much signal reaches the send bus, independent of the dry fader.

### Two Fixed Send Buses

The user stories assume Send A and Send B are always present; no dynamic creation/removal is needed. This simplifies lifecycle: two `SendBusHost` instances can be created once at session start and torn down at session end, analogous to `MasterBusHost`.

### Graph Rewire Sequence for Send Infrastructure

Installing send infrastructure for a track follows the same stop/reconnect/restart pattern as `installMasterChains`. The rewire must happen on the main thread with engine coordination (see busses inspection). Because Send A and Send B are always present, the rewire can be done eagerly at session start for all tracks rather than lazily per-track-routing-change.

---

## 4. Test Coverage Gaps

### Covered today (relevant to sends)

- `MainAudioGraphTests` — multi-output fan-out via `AVAudioConnectionPoint` (A/B master branches), chain node order, gain clamping.
- `SamplePlaybackEngineFilterWiringTests` — confirms per-track mixer→filter→preMasterMixer topology.
- `MasterBusHostTests` — insert chain rebuild, AU caching.

### Not covered (gaps for send feature)

- No test for a track-level fan-out: single track outputMixer connecting to both `preMasterMixer` and a send gain mixer simultaneously.
- No test verifying that adjusting `sendGainMixer.outputVolume` does not alter signal level at `preMasterMixer` (dry-path independence).
- No test for `SendBusHost` insert chain construction or teardown.
- No test for the return mixer connection to `finalOutputMixer`.
- No test for `TrackMixSettings` codable round-trip with `sendA`/`sendB` fields.
- No test for `StepSequenceTrack` decode from a legacy document (missing `sendA`/`sendB`) yielding default `0` values.
- No test for `ProjectDelta.trackSendChanged` propagation through `EngineController`.

---

## 5. Summary — What Exists and What Does Not

| Capability | Exists? | Location |
|---|---|---|
| Send A / Send B bus concept | No | — |
| SendBusState model type | No | — |
| SendBusHost (engine layer) | No | — |
| Per-track send-amount field (`sendA`, `sendB`) | No | — |
| Send amount persisted in `StepSequenceTrack` | No | — |
| `ProjectDelta` case for send-amount changes | No | — |
| Track-level fan-out node (send tap) | No | — |
| Send return mixer → output routing | No | — |
| Send bus insert chain (model) | No | — |
| Send bus insert chain (engine) | No | — |
| Send bus insert chain UI | No | — |
| Send-amount knob in MixerChannelStrip | No | — |
| Pre/post-fader toggle | No | — |
| AVAudioEngine multi-output fan-out capability | Yes (master A/B) | `MainAudioGraph.swift` line 138 |
| MasterBusInsert type (reusable for send inserts) | Yes (master-only name) | `MasterBus.swift` line 698 |
| TrackMixSettings (needs send fields added) | Yes (no sends) | `TrackMixSettings.swift` |
| decodeIfPresent migration pattern | Yes | `StepSequenceTrack.swift` line 125 |
