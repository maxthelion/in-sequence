# Master Bus Scenes and End-of-Chain Inserts

**Status:** Implementation branch `codex/master-bus-scenes`; shared graph and native DSP wiring are now implemented.

Implemented in this branch:

- persisted master bus scenes and inserts;
- dirty live draft and Save Scene / Save As behavior;
- scoped session/store mutations that avoid playback snapshot replacement;
- engine-facing `MasterBusHost` state application and A/B equal-power gains;
- shared `MainAudioGraph` ownership for internal AU instrument and sample paths;
- native master filter and lo-fi/bitcrusher DSP insertion on the shared audio graph;
- asynchronous AU effect insertion that bypasses while the AU is unavailable or still loading;
- mixer-accessible End of Chain page with Filter, Bitcrusher, AU Effect insert choices, scene swap, and A/B controls.

Still to wire in a follow-up:

- AU effect editor windows and live full-state capture;
- custom true bit-depth/sample-rate reduction DSP if the current AVFoundation lo-fi processor is not enough.

## Summary

Add master bus scenes: named end-of-chain effect chains that can be applied to the main audio output, saved from edits, swapped live, and optionally paired in an A/B mode with a virtual crossfader.

The current code has per-track AU instrument hosting and sample playback, but those paths own separate audio engines. A real master bus must process all internal audio through one shared output graph before it reaches hardware. This plan therefore has two parts:

- introduce a shared main audio graph with a master end-of-chain host;
- add persisted master bus scenes, UI, and mutations on top of that graph.

MIDI-only tracks are unaffected except where they route into internal AU/sample audio paths.

## Goals

- Route all internal audio output through a single master bus.
- Support a scene as an ordered list of end-of-chain insert effects.
- Support native packaged inserts, initially filter and bitcrusher or lo-fi, plus AU effects.
- Make the end-of-chain page accessible from the mixer.
- Let users edit the live chain, detect dirty edits, and save the edited chain as a scene.
- Let users select a different scene and swap it for the current one.
- Add A/B mode where two scenes run in parallel and mix to main out through a virtual crossfader.
- Persist scenes and AU effect state in the document.

## Non-Goals

- No per-track insert chains in this plan.
- No sends or sidechain routing in this plan.
- No automation or phrase locks for scene parameters in V1.
- No capture of crossfader moves into phrases in V1.
- No external hardware input processing in V1.

## Domain Model

Add document-level master bus state:

```swift
struct MasterBusState: Codable, Equatable, Sendable {
    var scenes: [MasterBusScene]
    var activeSceneID: UUID
    var abSelection: MasterBusABSelection?
}

struct MasterBusScene: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var inserts: [MasterBusInsert]
    var outputGain: Double
}

struct MasterBusABSelection: Codable, Equatable, Sendable {
    var sceneAID: UUID
    var sceneBID: UUID
    var crossfader: Double
}

struct MasterBusInsert: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var isEnabled: Bool
    var wetDry: Double
    var kind: MasterBusInsertKind
}
```

Insert kinds:

```swift
enum MasterBusInsertKind: Codable, Equatable, Sendable {
    case nativeFilter(MasterFilterSettings)
    case nativeBitcrusher(MasterBitcrusherSettings)
    case auEffect(componentID: AudioComponentID, stateBlob: Data?)
}
```

Add `masterBus: MasterBusState` to `Project`, with decode defaults for existing documents:

- one default scene named `Clean`;
- no inserts;
- active scene set to `Clean`;
- no A/B selection.

Crossfader position can be persisted with the project in V1. If later live performance needs a runtime-only fader, move just `crossfader` into a performance overlay while keeping selected A/B scene IDs persisted.

## Audio Graph

Introduce a shared `MainAudioGraph` in `Sources/Audio/`.

Responsibilities:

- own the process-local `AVAudioEngine` for internal audio;
- expose per-track input mixers for AU instruments and sample playback;
- expose a pre-master mixer that receives all internal audio;
- own a `MasterBusHost` that connects pre-master audio to hardware output;
- provide thread-safe reconfiguration methods for insert-chain changes.

Required refactors:

- `AudioInstrumentHost` should stop owning its own `AVAudioEngine`; it should attach AU instruments to `MainAudioGraph` and route each track into a per-track mixer.
- `SamplePlaybackEngine` should stop owning its own output engine; it should attach voices, preview, per-track mixers, and filters to `MainAudioGraph`.
- `EngineController` should own or receive one `MainAudioGraph` and pass it to audio sinks.

The target graph shape:

```text
track AU instruments -> track mixers -> pre-master mixer
sample voices        -> track mixers -> pre-master mixer
preview/audition     -> preview mixer -> pre-master mixer
pre-master mixer     -> master bus host -> engine output
```

This must happen before master scenes ship. Without it, a master scene cannot reliably process every audible internal path.

## Master Bus Host

Add `MasterBusHost`, owned by `MainAudioGraph`.

Single-scene mode:

```text
pre-master mixer -> insert 1 -> insert 2 -> ... -> final output mixer -> mainMixerNode/output
```

A/B mode:

```text
                        -> scene A insert chain -> scene A gain -
pre-master mixer fanout                                      -> final output mixer -> output
                        -> scene B insert chain -> scene B gain -
```

Use equal-power crossfade gains:

```swift
let clamped = min(max(crossfader, 0), 1)
let gainA = cos(clamped * .pi / 2)
let gainB = sin(clamped * .pi / 2)
```

Scene changes should rebuild only the master insert graph, not playback snapshots. Reconfiguration should be serialized on the audio graph queue and should stop or bypass affected nodes safely enough to avoid stuck output or crashes. Click-free graph morphing can be a later polish pass.

## Insert Processors

Define a small host-facing abstraction:

```swift
protocol MasterInsertProcessor: AnyObject {
    var avNode: AVAudioNode { get }
    func apply(_ insert: MasterBusInsert)
    func captureState() throws -> MasterBusInsert
    func shutdown()
}
```

Native inserts:

- `nativeFilter`: backed by `AVAudioUnitEQ` or an equivalent filter node.
- `nativeBitcrusher`: backed by a bundled/native processor if available. If no robust built-in processor exists, V1 may ship this as `nativeLoFi` backed by a distortion/downsample effect and keep a true bit-depth reducer for a follow-up AUv3/native DSP task.

AU effects:

- add an `AudioEffectChoice` and `AudioEffectChoiceCache`, separate from `AudioInstrumentChoiceCache`;
- scan `kAudioUnitType_Effect` and likely `kAudioUnitType_MusicEffect`;
- instantiate effects with the existing `AUAudioUnitFactory` machinery, generalized beyond instruments;
- persist AU effect `fullState` with `FullStateCoder`;
- expose AU editor windows through a generalized `AUWindowHost` path.

Effect AU loading must be asynchronous. Until a plug-in is ready, the chain should bypass that insert rather than blocking the UI or audio graph indefinitely.

## Session and Mutation Flow

Add LiveSequencerStore state for `masterBus` and document mutations through `SequencerDocumentSession`.

Suggested session APIs:

```swift
func setActiveMasterScene(_ sceneID: UUID)
func setMasterBusDraft(_ scene: MasterBusScene)
func saveMasterBusDraft(as name: String)
func updateMasterBusInsert(_ insertID: UUID, edit: (inout MasterBusInsert) -> Void)
func reorderMasterBusInserts(_ ids: [UUID])
func setMasterABMode(_ selection: MasterBusABSelection?)
func setMasterCrossfader(_ value: Double)
```

Add `ProjectDelta.masterBusChanged` and a corresponding live mutation impact that updates the audio graph without compiling or installing a playback snapshot.

Dirty edit behavior:

- the end-of-chain page edits a live draft derived from the active scene;
- any edit applies immediately to `MasterBusHost`;
- the page compares the live draft to the saved scene and marks it dirty;
- `Save Scene` writes the draft back to the active scene or saves a new named scene;
- selecting a new scene swaps the live draft to that scene and applies it immediately.

If the current draft is dirty and the user selects another scene, V1 should keep the interaction explicit: show Save, Revert, and Switch Without Saving actions rather than silently discarding edits.

## Mixer UI

Replace the existing `Main / Alt Bus` placeholder in `MixerWorkspaceView` with an entry point to an End of Chain page.

End of Chain page:

- header with current scene name and dirty status;
- `Save Scene` button, enabled when the draft differs from the saved scene;
- scene selector button for swapping the current scene;
- insert chain list with enable/bypass, reorder, remove, and wet/dry controls;
- `Add Insert` menu with Filter, Bitcrusher/Lo-Fi, and AU Effect;
- selected insert editor panel for native parameters or AU editor/preset actions;
- A/B mode toggle;
- Scene A and Scene B selectors when A/B mode is active;
- virtual crossfader control between A and B;
- visible output level or gain control for the active scene or final output.

The page should be work-surface UI, not a landing page. It should be dense enough for repeated mixer use and should avoid explaining itself with instructional copy.

## Scene Swap Behavior

Single-scene mode:

1. User opens scene selector.
2. User chooses a scene.
3. Session sets `activeSceneID`.
4. Live draft becomes the chosen scene.
5. `MasterBusHost` rebuilds the active chain.

A/B mode:

1. User selects Scene A and Scene B.
2. `MasterBusHost` keeps two independent chains alive.
3. Crossfader changes update only scene chain output gains.
4. Editing a selected scene updates that side's chain immediately.
5. Disabling A/B mode returns to the active single scene, preferably Scene A unless the UI explicitly chooses otherwise.

## Persistence and Migration

- Extend `Project.CodingKeys` to include `masterBus`.
- Decode old projects with the default `Clean` scene.
- Keep `MasterBusScene` IDs stable so A/B selections survive save/reopen.
- Store AU effect state blobs exactly like AU instrument state blobs.
- Add normalization that removes A/B selections referencing deleted scenes.
- Add a bounded policy for missing AU effects: preserve the insert and state blob, mark it unavailable in UI, and bypass it in audio.

## Test Plan

Document tests:

- old project JSON decodes with default `Clean` scene;
- scene IDs survive encode/decode;
- AU effect state blobs round trip;
- deleting a scene normalizes invalid active and A/B references;
- scene dirty comparison ignores transient UI-only data.

Audio graph tests:

- all internal audio sinks route through `MainAudioGraph` into pre-master;
- single-scene chain connects inserts in order;
- bypassed inserts are skipped or muted according to the processor contract;
- A/B crossfader applies equal-power gains;
- scene swap replaces master inserts without changing playback snapshot.

Controller/session tests:

- master scene edits update `LiveSequencerStore` and document state through session APIs;
- master scene edits do not recompile or replace `PlaybackSnapshot`;
- crossfader movement does not advance phrase state or queue MIDI events;
- missing AU effect inserts remain persisted and bypassed.

UI/helper tests:

- mixer exposes End of Chain entry point;
- Save Scene is enabled only when draft differs from saved scene;
- selecting a scene applies the new draft;
- A/B mode exposes two scene selectors and crossfader;
- Add Insert routes native filter, bitcrusher/lo-fi, and AU effect choices to session APIs.

## Implementation Steps

1. Add `MasterBusState`, `MasterBusScene`, `MasterBusInsert`, and settings models.
2. Add document coding, defaults, normalization, and tests.
3. Introduce `MainAudioGraph` with existing audio paths still behaviorally equivalent.
4. Refactor AU instrument and sample playback sinks to attach to the shared graph.
5. Add `MasterBusHost` and native filter insert support.
6. Add AU effect discovery, instantiation, editor access, and state capture.
7. Add bitcrusher or lo-fi native insert after validating the implementation path.
8. Add session/store mutations and scoped engine graph updates.
9. Replace mixer placeholder with End of Chain page entry.
10. Build End of Chain page, scene selector, insert list, Save Scene, and A/B controls.
11. Add full document, graph, controller, and UI tests.

## Risks

- The shared graph refactor is the hard part. It changes audio ownership and must be done carefully before scene UI lands.
- AU effects differ from AU instruments. Do not reuse instrument-only assumptions such as `AVAudioUnitMIDIInstrument` casts.
- Some AU effects may not expose reliable editor or preset behavior. Preserve state and bypass safely on load failure.
- Rebuilding insert chains while audio is running can click. V1 should prioritize correctness and no stuck output; smoother transitions can follow.
- Scene state can become large if many AU full-state blobs are saved. Keep the model simple, but watch document size in tests.
