# Mixer Busses — Existing State

Inspected 2026-04-29. Read scope: document model, audio graph, engine controller, mixer UI.

---

## 1. Current Architecture

### Audio Graph Topology

`MainAudioGraph` (`Sources/Audio/MainAudioGraph.swift`) owns:

- `preMasterMixer: AVAudioMixerNode` — single summing point that every track output connects to
- `finalOutputMixer: AVAudioMixerNode` — sits between preMasterMixer and `engine.mainMixerNode`
- A dynamically-built master insert chain (managed by `MasterBusHost`) between `preMasterMixer` and `finalOutputMixer`

The complete signal path today is:

```
[track outputMixer] ──┐
[track outputMixer] ──┤
[sample mixer/filter] ┤
                      ↓
              preMasterMixer
                      ↓
         [MasterBus insert chain]   (zero or more nodes, A/B branched)
                      ↓
           finalOutputMixer
                      ↓
         engine.mainMixerNode
```

There is **no intermediate bus node** between tracks and `preMasterMixer`. Every track connects directly to `preMasterMixer`. No intermediate group summing mixer exists in the graph.

### How Tracks Connect

`AudioInstrumentHost` (`Sources/Audio/AudioInstrumentHost.swift`, lines 458–465):

```swift
let mixer = self.outputMixer ?? AVAudioMixerNode()
// ...
self.audioGraph.connect(mixer, to: self.audioGraph.preMasterMixer)
self.audioGraph.connect(nextInstrument, to: mixer)
```

`SamplePlaybackEngine` (`Sources/Audio/SamplePlaybackEngine.swift`, lines 421–422):

```swift
audioGraph.connect(mixer, to: filter.avNode)
audioGraph.connect(filter.avNode, to: audioGraph.preMasterMixer)
```

Both paths terminate at `preMasterMixer` with no routing abstraction.

### Document Model

`Project` (`Sources/Document/Project.swift`, `Sources/Document/Project+Codable.swift`):

- `tracks: [StepSequenceTrack]` — each track carries `mix: TrackMixSettings` (level, pan, isMuted) and a `destination: Destination` pointing to an AU instrument or sampler
- `trackGroups: [TrackGroup]` — a drum-kit grouping concept (shared MIDI destination, note mapping, mute, solo). **Not an audio bus.** `TrackGroup` has no fader, no insert chain, no audio-level concept.
- `masterBus: MasterBusState` — a single master bus with scene-based insert chains, A/B crossfade, and macro bindings. No `buses: [MixerBus]` collection exists.

`StepSequenceTrack` (`Sources/Document/StepSequenceTrack.swift`):

- Has no `busID` or output-routing field. Routing is fully implicit: all tracks sum to master.

### Master Bus Insert Chain

`MasterBusState` / `MasterBusScene` / `MasterBusInsert` (`Sources/Document/MasterBus.swift`):

- Well-developed model: insert list, per-insert enable/disable, wet-dry, native filter, native bitcrusher, and AU effect kinds
- `MasterBusHost` manages AVAudioNode graph construction, AU caching, and parameter application
- `MasterBusInsert` is a **master-only type** — it is not generic/shared with any track-level insert type

`TrackMixSettings` (`Sources/Document/TrackMixSettings.swift`):

- Contains only level, pan, isMuted. No inserts, no bus send field.

### TrackGroup (Not a Bus)

`TrackGroup` (`Sources/Document/TrackGroup.swift`):

- Groups tracks for shared MIDI destination and drum note mapping
- Has `mute` and `solo` booleans but they are MIDI-playback controls, not audio-mixer controls
- No fader, no pan, no insert chain
- Not connected to the audio graph in any way

### Mixer UI

`MixerView` (`Sources/UI/MixerView.swift`):

- Renders one `MixerChannelStrip` per track
- Each strip shows: name, destination label, fader (level), pan slider, mute button
- No bus section, no "Add Bus" button, no routing selector at strip bottom
- No solo button exists anywhere in the track strip

`MixerWorkspaceView` (`Sources/UI/Mixer/MixerWorkspaceView.swift`):

- Wraps `MixerView` in a `StudioPanel` labelled "Track strips active now"
- Contains a second placeholder panel called "Voice Routes" with `StudioPlaceholderTile` items for "Tagged Voices" and "Per-Voice Treatment (Mute, bus, FX, and gain)" — this is an explicit placeholder acknowledging the bus gap

`ScenesWorkspaceView` (`Sources/UI/Mixer/ScenesWorkspaceView.swift`, `ScenesWorkspaceView+AUEffects.swift`):

- Full insert-chain editing UI exists — but it is **master-bus-specific**, not generic
- Renders a scene browser (grid of scene cards), an insert list, and per-insert editors (filter, bitcrusher, AU effect)
- Uses `MasterBusInsert`, `MasterBusScene`, and `MasterBusState` types throughout
- No abstraction layer that could be dropped in under a bus strip without refactoring

---

## 2. Per-Story Gap Analysis

### Story 1: Create a new bus

| Dimension | Today |
|---|---|
| Model | No `MixerBus` or equivalent type exists. `Project` has no bus list. |
| Engine | No bus audio node; no bus host lifecycle. |
| Persistence | No `buses` key in `Project+Codable.swift`. Migration from pre-bus documents would be trivial (decode absent key as empty array). |
| UI | No "Add Bus" button or bus section in `MixerWorkspaceView`. The placeholder panel is the only acknowledgement. |
| Model gap | New type needed: `MixerBus` (id, name, colour, mix settings, insert list). New collection on `Project`. |
| UI gap | New bus section in mixer, "Add Bus" action, bus strip component. |

### Story 2: Route a track's output to a bus

| Dimension | Today |
|---|---|
| Model | `StepSequenceTrack` has no `outputBusID` field. Routing is hardwired to master. |
| Engine | `AudioInstrumentHost` and `SamplePlaybackEngine` connect directly to `preMasterMixer`. No routing table. |
| Persistence | No per-track bus routing is serialised. |
| UI | No output routing selector in the track strip. `destinationLabel` in `MixerView` shows instrument kind only, not audio routing. |
| Model gap | Add `outputBusID: UUID?` (nil = master) to `StepSequenceTrack`. |
| Engine gap | `AudioInstrumentHost.init` and `SamplePlaybackEngine` need a `targetMixerNode` parameter so they can connect to a bus node rather than `preMasterMixer`. Engine must respond to `outputBusID` changes by rewiring. |
| UI gap | Per-strip output selector (Picker or menu). |

**Architecture constraint — real-time safe graph mutation:** Graph rewiring requires stopping/restarting the AVAudioEngine (see `MainAudioGraph.installMasterChains` which stops the engine during rebuild). Changing a track's bus must follow the same stop/reconnect/restart pattern currently used for master chain changes. This must happen on the main thread with engine coordination.

### Story 3: Bus fader, pan, mute, solo

| Dimension | Today |
|---|---|
| Model | `TrackMixSettings` (level, pan, isMuted) exists for tracks. No equivalent bus mix type — closest is `MasterBusScene.outputGain` (gain only, no pan, no solo). |
| Engine | Per-track mix applied via `outputMixer.outputVolume / .pan`. No bus-level mixer node exists. |
| UI | `MixerChannelStrip` fader and pan controls exist for tracks. No solo button anywhere today. |
| Model gap | Bus needs fader + pan + mute + solo. Could reuse or extend `TrackMixSettings` (which lacks solo). A new `BusMixSettings` or extension of `TrackMixSettings` with `isSoloed` is required. |
| Engine gap | Each bus needs its own `AVAudioMixerNode` in the graph, with `outputVolume` and `pan` driven by bus mix state. Solo logic must mute all non-soloed buses (and potentially tracks routed directly to master). |
| UI gap | Bus strip with fader, pan, mute, solo — analogous to `MixerChannelStrip`. |

### Story 4: Insert plugins on a bus

| Dimension | Today |
|---|---|
| Model | `MasterBusInsert` and `MasterBusInsertKind` are master-bus-specific types. Track strips have per-track AU macros (`TrackMacroBinding`) but no insert chain. |
| Engine | `MasterBusHost` builds insert chains for the master. No generic "insert chain host" abstraction exists. |
| UI | Insert chain editor exists in `ScenesWorkspaceView` but is deeply coupled to `MasterBusScene` and `MasterBusState`. |
| Model gap | Inserts on a bus need either: (a) the same `MasterBusInsert`/`MasterBusInsertKind` types reused on a new `MixerBus` model, or (b) a renamed generic type. Option (a) is the lower-cost path and the user-story assumption is consistent with it. |
| Engine gap | A `BusHost` (analogous to `MasterBusHost`) is needed per bus instance to manage its insert chain nodes. Alternatively `MasterBusHost` could be generalised, but its current interface is tightly master-specific. |
| UI gap | The insert chain editing view from `ScenesWorkspaceView` is **not extracted** into a reusable component. It cannot be embedded in a bus strip without extraction and parametrisation. This is a larger refactoring than the user-story assumption implies — the assumption ("reuse the same insert-chain UI") is technically optimistic. |

**Concern:** The user-story assumption that inserts "reuse the existing track insert-chain component" is incorrect — there is no generic track insert-chain component. The master insert chain UI exists but is not shared or parameterised. Creating bus inserts will require either (a) extracting the master chain editor into a generic component or (b) duplicating it for buses. This must be flagged to the implementation loop.

### Story 5: Name and identify buses

| Dimension | Today |
|---|---|
| Model | No `MixerBus.name` field exists because the type does not exist. |
| Persistence | Not serialised. |
| UI | No inline rename interaction for bus strips. The pattern does exist for `MasterBusScene` names inside `ScenesWorkspaceView`. |
| Model gap | `MixerBus` needs `name: String` and `color: String`. Standard normalisation (trim, non-empty) can follow `TrackGroup` or `MasterBusScene` patterns. |
| UI gap | Inline rename gesture on bus strip header. Name must propagate to track routing selector. |

---

## 3. Architecture Constraints

### Actor Isolation / Threading

- `MainAudioGraph` methods dispatch to the main actor (`@MainActor` or `DispatchQueue.main.sync`)
- `AudioInstrumentHost` uses a private serial queue; mixing calls into the graph must go via `performOnMain`
- Adding a bus node and rewiring tracks must happen on the main thread. The engine must be stopped and restarted (same pattern as `installMasterChains`). This is already handled for master chain changes but is not exposed as a generic API.

### Real-Time Safe DSP Graph Mutation

- AVAudioEngine requires stopping before topology changes (connect/disconnect). `MixerWorkspaceView` must not trigger graph rewiring during audio processing without coordinating with `EngineController`.
- Changing a track's output bus is a structural change, not a parameter change — it cannot be done with a simple `outputVolume` update.

### Persistence Migration

- `Project+Codable.swift` uses `decodeIfPresent` for all optional collections. Adding a `buses` key with `decodeIfPresent([MixerBus].self, forKey: .buses) ?? []` is a safe additive migration — existing documents decode with empty bus list (all tracks route to master).
- `StepSequenceTrack` needs `outputBusID: UUID?` added with `decodeIfPresent` fallback to `nil` (master).

### Solo Logic Complexity

- Solo on a bus implies muting all other buses and potentially all tracks that route directly to master. The current engine has no cross-bus solo coordination. This is a non-trivial state machine addition to `EngineController`.

---

## 4. Test Coverage Gaps

### Covered today

- `MainAudioGraphTests` — master chain topology, branch gains, preMasterMixer connection points
- `MasterBusHostTests` — insert chain rebuild, AU effect caching, performance overlays
- `MasterBusStateTests` — state mutation, normalisation, codable round-trips
- `TrackGroupTests` — codable round-trips for `TrackGroup`

### Not covered (gaps for bus feature)

- No test for intermediate bus node insertion between track output and `preMasterMixer`
- No test for track output re-routing (changing `outputBusID` triggers graph rewire)
- No test for bus fader/pan/mute applied to a bus mixer node
- No test for solo exclusivity across buses
- No test for bus insert chain construction (would need a new host type analogous to `MasterBusHostTests`)
- No test for `Project` codable round-trip with a `buses` collection
- No test for `StepSequenceTrack` round-trip with `outputBusID`
- No test for bus name persistence and propagation to routing selector labels

---

## 5. Summary of What Does and Does Not Exist

| Capability | Exists? | Location |
|---|---|---|
| Master insert chain model | Yes | `MasterBus.swift` |
| Master insert chain host | Yes | `MasterBusHost.swift` |
| Master insert chain UI | Yes (master-only) | `ScenesWorkspaceView.swift` |
| Generic / reusable insert chain component | No | — |
| TrackGroup (MIDI grouping) | Yes (not an audio bus) | `TrackGroup.swift` |
| Bus concept in Project model | No | — |
| Track output routing field | No | — |
| Intermediate bus node in audio graph | No | — |
| Bus mixer UI section | No | — |
| Track output selector in strip | No | — |
| Solo button (anywhere) | No | — |
| Bus host lifecycle | No | — |
| Bus persistence | No | — |
| "Add Bus" button | No | — |
