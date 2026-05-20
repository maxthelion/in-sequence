# EngineController Carve-Up Plan

**Status:** Proposed architecture plan. No production extraction in this slice.
**Inputs:** `docs/observations/2026-05-20-structural-review.md`, `wiki/pages/playback-data-path.md`, `wiki/pages/engine-architecture.md`, `wiki/pages/architecture-guardrails.md`, and `Sources/Engine/EngineController.swift`.

## Summary

`EngineController` is currently the app-facing runtime facade and also owns most runtime subsystems directly. The split should preserve the existing tick model:

```
PlaybackSnapshot -> prepareTick -> EventQueue/router state -> dispatchTick -> sinks
```

The goal is not to replace the runtime or introduce new playback behavior. The goal is to move coherent responsibilities behind named owners while keeping `EngineController` as the app-facing composition root.

## Current Responsibilities

`EngineController` currently owns:

- Transport lifecycle: `start`, `stop`, `shutdown`, `setBPM`, `setTransportMode`, `processTick`, clock callbacks, and observable transport status.
- Document/runtime apply: `apply(documentModel:)`, `apply(playbackSnapshot:)`, `apply(deltas:documentModel:)`, broad sync, scoped mix/send/master-bus updates, and current document/snapshot references.
- Tick preparation: layer snapshot resolution, macro application, generated-source evaluation, prepared note injection, sample/slicer enqueueing, router input construction, and transport-position publication.
- Dispatch: `EventQueue` draining, AU/sample/slicer playback, chord-context broadcasts, and destination application before playback.
- Track runtime tables: generator block IDs, MIDI out blocks, audio runtimes, AU/sample output hosts, output keys, destination cache, live sample tracks, effective mutes, and pipeline shape.
- Pipeline construction: default generator/MIDI graph creation, `Executor` lifecycle, route snapshots, mixer/send-bus installation, and sink synchronization.
- Routing fan-out: `MIDIRouter`, routed note/chord buffers, routed MIDI output cache, route dispatch timestamp, and `RouterDispatcher` conformance.
- AU hosting facade: track AU readiness, preset readout/loading, current AU access, AU state blob persistence, and pass-through master AU effect APIs.
- Clip history capture: rolling per-track generated-note buffers and capture-to-clip conversion.
- Tick-thread state: `stateLock`, current layer snapshot, generated-source evaluation states, prepared tick index, tick-thread tick mirror, and snapshot reads/writes.
- MIDI panic and detachment handling: primary MIDI note-off flushing plus routed MIDI cleanup when destinations or routes disappear.

## Proposed Ownership

- **`EngineController`**
  - Remains the app-facing facade and composition root.
  - Owns construction of the collaborators below and exposes stable UI/session commands.
  - Keeps document-facing APIs stable during migration, then delegates internally.

- **`Transport`**
  - Owns `TickClock`, BPM clamping, start/stop/shutdown sequencing, transport mode, and observable transport publication.
  - Coordinates the prepare/dispatch cycle through narrow closures or a small protocol.
  - Does not own `Project`, snapshot compilation, routing tables, or sink registries.

- **`TickStateBuffer`**
  - Owns the lock-protected tick state: current `PlaybackSnapshot`, current `LayerSnapshot`, generated evaluation states, prepared tick index, tick-thread tick mirror, and capture buffer access while capture is still tick-driven.
  - Provides explicit narrow mutations such as `install(snapshot:)`, `invalidatePreparedTick(resetGenerators:)`, `readPrepareInputs()`, and `commitPrepareOutputs(...)`.
  - Makes the threading contract visible before any render-thread work: no broad document reads on the hot path, no hidden `@Observable` writes from the clock thread.

- **`TrackRuntimeRegistry` / `TrackSinkTable`**
  - Owns per-track runtime identity and sink tables: generator block IDs, MIDI out blocks, AU output hosts, output keys, destination cache, audio runtimes, sample-track membership, effective mute sets, and pipeline shape.
  - Owns pipeline-shape comparison, graph rebuild outputs, `syncMidiOutputs`, `syncAudioOutputs`, `syncSampleMixers`, destination application caching, and detached MIDI note-off flushing for primary track outputs.
  - Exposes typed lookups to tick/dispatch code instead of handing around parallel dictionaries.

- **`Router` / `DispatchPipeline`**
  - Owns `MIDIRouter`, `RouterDispatcher` state, routed note/chord/MIDI buffers, routed MIDI output cache, route dispatch timestamp, and `EventQueue` draining/enqueueing policy.
  - Accepts prepared track outputs and a snapshot-backed mute/layer context, then emits concrete dispatch events.
  - Keeps routed AU/sample/slicer/MIDI behavior on scoped runtime paths; it must not read `currentDocumentModel` during routing or dispatch.

- **`ClipCaptureService`**
  - Owns rolling capture buffers and conversion to `ClipContent`.
  - Exposes `append(trackID:stepIndex:notes:)`, `capturedClipContent(trackID:lengthSteps:)`, `saveRollingCapture(...)`, and `removeMissingTracks(_:)`.
  - Remains transient runtime state until the user explicitly saves captured output into the document.

- **`AudioUnitHost`**
  - Owns AU readiness, preset browser preparation, preset readout/loading, parameter readout, state blob capture, and current AU access for both track instruments and master inserts.
  - Presents async/readiness-oriented APIs to UI/session code so views do not poll `EngineController`.
  - Lives at the engine/audio boundary through protocols; do not move concrete `AVAudioEngine` graph ownership into `Sources/Engine/`.

## Performance-Time Guardrail

Live playback and live state paths must remain scoped runtime updates:

- Tick preparation reads `PlaybackSnapshot`, `LayerSnapshot`, generated evaluation state, capture buffers, and sink registries. It must not walk or replace `Project`.
- Playback, transport, routing, AU readiness, capture, macro/mix gestures, and tick preparation must not route through export/import, broad `Project` replacement, or broad `EngineController.apply(documentModel:)` calls.
- Structural edits may still use broader document apply paths when occasional and document-shaped. Repeated performance gestures must use existing scoped paths such as `apply(playbackSnapshot:)`, `setMix`, `setMixerBusMix`, `apply(sendBus:)`, `apply(masterBus:)`, snapshot invalidation, or collaborator-specific narrow updates.
- Any extraction that touches the tick path must prove that `prepareTick` still iterates snapshot-carried tracks and that routing/dispatch still use snapshot-backed destination and mute context.

## Migration Order

1. **Extract `ClipCaptureService`.**
   - Move `RollingCaptureStep`, `RollingCaptureBuffer`, capture append/read/save, and track-removal filtering into one runtime service.
   - Keep calls from `prepareTick`, `capturedClipContent`, `saveRollingCapture`, `apply(documentModel:)`, and `buildPipeline` behaviorally identical.

2. **Introduce `TickStateBuffer` without moving sink logic.**
   - Centralize `stateLock` access and the lock-protected tick fields.
   - Replace repeated `withStateLock` blobs with named read/commit operations.
   - Keep `EngineController` responsible for collaborators until the state contract is explicit.

3. **Introduce `TrackRuntimeRegistry` / `TrackSinkTable`.**
   - Move the parallel per-track dictionaries into typed records.
   - Migrate pipeline build results, audio/MIDI/sample sync, output-key destination caching, mute state, and primary MIDI note-off cleanup behind the registry.

4. **Extract `Router` / `DispatchPipeline`.**
   - Move routed buffers, `RouterDispatcher` conformance, route MIDI output cache, routed-event flushing, and event queue draining.
   - Keep `EngineController.processTick` as the high-level coordinator until transport is extracted.

5. **Extract `Transport`.**
   - Move clock lifecycle, BPM command enqueueing, transport mode, process-tick bootstrapping, and main-thread observable publication.
   - `EngineController` should delegate start/stop/shutdown and expose the same public API.

6. **Extract `AudioUnitHost` facade.**
   - Move track AU preset/readout/current-unit APIs and master AU pass-throughs behind a readiness API.
   - Update UI/session call sites only after the runtime ownership split is stable.

## Test And Verification Strategy

- Before each extraction, add characterization tests for the moved responsibility when coverage is missing.
- Run focused engine tests after each slice, then the full test suite before any larger branch handoff.
- For tick-path slices, cover:
  - `apply(playbackSnapshot:)` invalidates prepared tick and clears generated state without broad document apply.
  - Mix, bus, send, master-overlay, AU readiness, and route changes stay on scoped runtime paths.
  - Generated notes, capture content, routed AU/MIDI/chord events, sample triggers, and slicer triggers match pre-extraction behavior.
  - Removed tracks/destinations flush pending MIDI note-offs and release sink state.
- Add explicit tests around the collaborator API boundary, not just the final controller facade, so later moves do not reintroduce parallel dictionaries or document reads.
- Verify no extraction adds new `store.exportToProject()` or broad `EngineController.apply(documentModel:)` call sites for repeated performance gestures.

## First Safe Extraction Slice

Extract `ClipCaptureService` first.

Why this is low risk:

- It is self-contained domain logic already isolated as nested capture structs plus three controller touchpoints: append during tick preparation, read/save through capture APIs, and prune buffers when track IDs change.
- It has no AU, MIDI, routing, graph, or clock ownership.
- It preserves the live-path shape: tick preparation still appends scoped generated notes to a transient runtime buffer, and document mutation still happens only when the user saves captured output.
- It can be reviewed as one small file plus call-site delegation, with focused tests for append replacement within a step, max-length trimming, empty capture, explicit length padding, track removal, and save-to-slot behavior.

Do not schedule broader extraction work until this plan receives architecture review.
