# Mixer Main Out — Existing State

Inspected 2026-04-29.

---

## 1. Audio Engine and Signal Chain

### Topology

`Sources/Audio/MainAudioGraph.swift` (lines 15–33) defines the summing graph:

```
[per-track AudioInstrumentHost / SamplePlaybackEngine nodes]
  → preMasterMixer (AVAudioMixerNode)
    → [per-branch insert nodes]
      → managedMasterGainMixer (AVAudioMixerNode, one per A/B branch)
        → finalOutputMixer (AVAudioMixerNode)
          → engine.mainMixerNode
            → engine.outputNode (hardware output)
```

The insert chains sit between `preMasterMixer` and `finalOutputMixer`. When A/B mode is active, two parallel branch chains run simultaneously and their gain mixers receive equal-power crossfade coefficients.

### Master Scene Gain Field — Stubbed Out

`MasterBusScene` carries an `outputGain: Double` field (MasterBus.swift:280), but `MasterBusScene.normalized()` (MasterBus.swift:301) hard-codes it back to `1` on every normalize call. The field is never read by `MasterBusHost`. There is no independent master output fader that a user can move; the crossfade branch gains (0…1.5 range in the audio graph) are the only per-branch gain control and those are driven entirely by the crossfader position, not by a user fader.

### Insert Effects Infrastructure

`MasterBusHost` (`Sources/Audio/MasterBusHost.swift`) manages scene-scoped insert chains. Three insert kinds are supported: `nativeFilter` (AVAudioUnitEQ), `nativeBitcrusher` (AVAudioUnitDistortion), and `auEffect` (third-party AudioUnit). Inserts are stored in `MasterBusScene.inserts` ([MasterBusInsert]) and are per-scene, not global to the bus. Bypass is per-insert (`isEnabled: Bool`); wet/dry is per-insert (`wetDry: Double`). Reorder is available via `MasterBusState.reorderInserts`.

### Crossfader

`MasterBusABSelection.crossfader` (MasterBus.swift:686) stores the authored value (0…1). `MasterBusHost.setLiveCrossfaderOverride` (MasterBusHost.swift:129) applies a runtime override without writing to the document, driving an equal-power panner `MasterBusHost.equalPowerGains(crossfader:)` (MasterBusHost.swift:188). `EngineController` exposes `masterBusPerformanceOverlay.crossfaderOverride` as an `@Observable` property (EngineController.swift:113).

---

## 2. Document / Persistence Model

`Project.masterBus: MasterBusState` (Project.swift:16) is serialised via Codable. The full round-trip is tested in `MasterBusStateTests` and `SeqAIDocumentTests`. Persistence includes scenes, inserts, AB selection, and crossfader. There is no persisted field for a global master output fader level or a clip indicator latch.

---

## 3. Mixer UI — Current State

`MixerWorkspaceView` (`Sources/UI/Mixer/MixerWorkspaceView.swift`) is a two-panel layout:
- Top panel: `MixerView` — a horizontal scroll of `MixerChannelStrip` cards, one per `StepSequenceTrack`. Each strip has a `VerticalLevelFader`, pan slider, mute, and edit buttons.
- Bottom panel: a placeholder `StudioPlaceholderTile` for "Tagged Voices".

There is **no master out section** anywhere in `MixerWorkspaceView`. The master bus is not rendered in the mixer at all. It lives in a separate workspace section (`WorkspaceSection.scenes` / `ScenesWorkspaceView`).

`ScenesWorkspaceView` (`Sources/UI/Mixer/ScenesWorkspaceView.swift`) hosts scene browse/edit and perform mode, including the crossfader widget (`ScenesWorkspaceView+Perform.swift:28`). Scene A/B badges appear on scene cards. The crossfader widget reads and writes `engineController.masterBusPerformanceOverlay.crossfaderOverride`.

The `WorkspaceSection` enum (WorkspaceSection.swift) has separate `mixer` and `scenes` cases. `WorkspaceDetailView` routes them to different views. There is no combined view that shows track channels alongside the master out.

---

## 4. Metering

There is **no metering infrastructure** anywhere in the codebase. Specifically:

- No `installTap` / `removeTap` call on any AVAudioNode.
- No peak detection, RMS, or dBFS computation anywhere.
- No `@Observable` or `@Published` property carrying meter level data.
- No calibrated dB scale conversion anywhere.
- No clip indicator state (persistent latch or otherwise).
- `ThrottledMixValue` (ThrottledMixControl.swift) is only used for fader drag throttling, not for metering.

The only "level" concept in the project is per-track `TrackMixSettings.level` (a normalized 0…1 ratio), which controls `AVAudioMixerNode.outputVolume` or `AudioInstrumentHost.outputMixer.outputVolume`.

---

## 5. Per-Story Gap Analysis

### Story 1 — Dedicated master-out section in the mixer

**What exists:**
- Master bus model is complete (`MasterBusState`, `MasterBusScene`, `MasterBusABSelection`).
- No master fader property exists that is not either frozen to 1.0 (outputGain) or crossfader-driven (branch gains).

**Gap — UI (presentation-side):**
- The mixer workspace has no master out panel. Adding one requires adding a new column or end-section to `MixerWorkspaceView`, not just a new document field.

**Gap — Model (model-side):**
- `MasterBusScene.outputGain` exists as a persisted field but is zeroed by `normalized()`. A global `MasterBusState.outputGain` (applied independent of scenes) is absent. Whether the intended fader should be scene-independent or per-scene is an open design question for the spec.

**Gap type:** Primarily presentation-side; model needs at least one new non-clobbered field.

---

### Story 2 — Insert effects on the master out channel

**What exists:**
- The model is fully built: `MasterBusInsert`, `MasterBusInsertKind` (native filter, bitcrusher, AU effect), `MasterBusState.addInsert` / `updateInsert` / `removeInsert` / `reorderInserts`. Session mutations exist (SequencerDocumentSession+Mutations.swift lines 297–324). Engine applies the chain in real time (MasterBusHost.swift).
- `ScenesWorkspaceView` already exposes an insert list UI with add, reorder (arrow buttons), enable/disable toggle, and remove. This is per-scene, which aligns with the current architecture.

**Gap — UI (presentation-side):**
- The insert UI exists only in `ScenesWorkspaceView` (`.scenes` workspace section). Story 2 asks for it to be surfaced inside the mixer's master out panel.
- No drag-to-reorder is implemented; only arrow-button reorder (MixerView+Perform gap: up/down buttons exist, swipe-to-reorder does not).

**Gap type:** Presentation-side only. The model and engine are ready; the mixer just needs a view that re-exposes the same scene insert list.

---

### Story 3 — Decibel metering with clip indication

**What exists:**
- Nothing. No metering, no tap, no dB conversion, no clip state.

**Gap — Model (model-side):**
- No `MasterBusMeterState` or equivalent observable.
- No clip latch field in any persistent model.

**Gap — Engine (engine-side):**
- No audio tap is installed on `finalOutputMixer` or `engine.mainMixerNode`.
- No peak detection loop or timer.
- `AVAudioEngine` / `AVAudioMixerNode` do not expose peak levels automatically; an `installTap` on the desired node is required, using a buffer callback on a real-time audio thread.

**Architecture constraint:**
The tap callback fires on a real-time thread. Peak values must be published to the main thread safely (e.g. via an atomic or a main-queue async dispatch), and the UI update rate should be throttled (typically 30–60 Hz via a `CADisplayLink` or `Timer`). Writing to an `@Observable` property from the audio thread without dispatch would be a thread-safety violation. A dedicated `MasterMeterPublisher` or equivalent is needed.

**Gap type:** Entirely new capability, spanning model, engine, and UI. No existing infrastructure can be borrowed.

---

### Story 4 — Scene A/B crossfader in the master out section

**What exists:**
- The crossfader model is complete (`MasterBusABSelection.crossfader`, `MasterBusPerformanceOverlayState.crossfaderOverride`).
- A full crossfader widget exists in `ScenesWorkspaceView+Perform.swift` (lines 28–72). It reads from `engineController.masterBusPerformanceOverlay.crossfaderOverride` and writes via `engineController.setLiveMasterCrossfader(_:)`.
- Scene A/B assignment (which scenes are in the A and B slots) is readable from `masterBus.abSelection` and displayed via slot badges in `ScenesWorkspaceView`.
- `EngineController.masterBusPerformanceOverlay` is `@Observable`; the crossfader widget already reacts to it.

**Gap — UI (presentation-side):**
- The crossfader widget lives only in `ScenesWorkspaceView`'s `.perform` mode. Story 4 wants it inline in the mixer's master out section.
- The crossfader widget is defined as `private func crossfader(...)` inside `ScenesWorkspaceView+Perform.swift` (line 28), so it is not directly reusable. Extraction to a standalone `MasterCrossfaderView` or equivalent is needed.

**Gap type:** Presentation-side only. The model and engine state are shared; no new model layer is required. The crossfader widget must be extracted and re-embedded.

---

## 6. Architecture Constraints

- **Actor isolation:** `MainAudioGraph.installMasterChains` and `setMasterBranchGains` both dispatch via `performOnMain` (MainAudioGraph.swift:164), landing on `@MainActor`. Production audio-graph mutations must follow this pattern.
- **Real-time audio thread:** Any metering tap callback runs on a non-main real-time thread. Observable state updates must be dispatched to the main thread explicitly (see `EngineController.publishToMain`, EngineController.swift:163).
- **Bus format:** `preMasterMixer` and `finalOutputMixer` use `nil` format in connections, which lets AVAudioEngine negotiate the native format. A metering tap must match or request a compatible format explicitly.
- **Engine start/stop during graph mutation:** `installMasterChains` stops and restarts the engine (MainAudioGraph.swift:88–145). Any metering tap installed on `finalOutputMixer` must be removed before this stop and reinstalled after restart, or installed on `mainMixerNode` (which persists across graph rebuilds).
- **`outputGain` clobber:** `MasterBusScene.normalized()` resets `outputGain` to 1 unconditionally. A user-controllable master fader either needs its own non-scene field (e.g., `MasterBusState.masterOutputGain`) or the normalization must be changed. Both changes must be made in tandem to avoid silent reset on every engine apply call.
- **Scene-scoped inserts vs. global chain:** Currently, all inserts belong to a scene. A global master insert chain (processed after A/B crossfade) does not exist. Story 2 as written ("the chain processes audio in slot order before the main output") is consistent with the scene-scoped model; the mixer panel would expose the active scene's inserts, not a new global chain.

---

## 7. Existing Test Coverage

| Area | Covered | Not Covered |
|---|---|---|
| `MasterBusState` model mutations | Yes — `MasterBusStateTests` covers addScene, removeScene, insert CRUD, crossfader, normalization, codable round-trip | Master fader field (does not yet exist) |
| `MasterBusHost` audio graph wiring | Yes — `MasterBusHostTests` covers filter node install, bitcrusher, AB gains, crossfade math | Any metering tap |
| `SequencerDocumentSession` master bus mutations | Yes — `SequencerDocumentSessionMasterBusTests` covers session-level insert and macro mutations | Metering publishing |
| Mixer UI | None — `MixerView` has no dedicated test | Master out panel, crossfader widget integration |
| Metering | None | Entire metering subsystem |
| Clip indicator latch | None | Not yet designed |

---

## 8. Open Questions for the Spec

1. **Master fader scope:** Should the master output fader be per-scene (matching the existing `outputGain` field) or global across all scenes (requiring a new `MasterBusState.masterOutputGain`)? The `outputGain` field currently exists but is always normalized to 1.

2. **Insert chain scope in the mixer panel:** Should the mixer's master out panel expose the active scene's inserts (existing model, low implementation cost), or should it expose a new global insert chain that runs after the A/B crossfade (new model, higher cost)?

3. **Metering tap placement:** Should the tap go on `finalOutputMixer` (after per-branch gain mixing, before `mainMixerNode`) or on `engine.mainMixerNode` (which includes any additional AVAudioEngine overhead)? Only the former measures what the user's master chain produces.

4. **Clip indicator reset:** Is "clear on user action" (button press) sufficient, or should the latch also reset automatically after a configurable hold period?

5. **Meter ballistics:** What peak-hold duration and meter fall-off rate are required? These are implementation decisions, but the spec should state the design intent (e.g. IEC 60268-18 Type I peak-hold or simpler).
