# North-Star vs Implementation Audit — 2026-04-21

## Summary

The implementation has landed the foundational architecture (app scaffold, core engine with 3 block types, macro coordinator + phrase model with layers/cells, track/group structure, MIDI routing, and generator kinds). Critical gaps remain in: step annotations and parameter locks (spec defines rich per-step data; code has minimal ClipNote structure), Takes (entirely absent), Fill presets (no FillPreset struct or capture/playback), template-generator kind, chord-generator as a source block, most transform blocks (force-to-scale, quantise-to-chord, note-repeat, step-order, interpret, density-gate, etc.), audio-side infrastructure (alt-bus, crossfader, insert FX), and Perform view. The two-layer model (song + phrase grid with layers) is correctly implemented at the data level; runtime execution is partial (macro rows exist but transforms are missing). Routes are implemented with tag filtering but only three destination types exist (voicing, trackInput, midi, chordContext); no voice-route tag → destination fan-out yet.

## 🟡 Partial (ordered by severity)

### Step Annotations and Parameter Locks
- **Spec says** (§566–591): Stored clips carry rich per-step data including play-prob, conditionals (1ST/PRE/NEI/A:B/X%), vel-jitter, pitch-jitter, timing-jitter, and `locks: { "block-id.param-name" → value }`. Locks are per-step overrides for any block parameter marked lockable. Ratcheting is locked via `locks["note-repeat.gate-prob"]`.
- **Code has**: `ClipNote` struct (pitch, startStep, lengthSteps, velocity) with no annotations. `ClipContent` enum has `stepSequence(stepPattern, pitches)` and `pianoRoll(notes: [ClipNote])` but no annotation fields.
- **Gap**: No per-step annotation data model. No parameter-lock map. No jitter fields, conditionals, or play-prob. Clip editor cannot edit locks. No runtime codepath to apply locks to blocks at tick time.
- **Plan covering this**: Not explicitly called out; fits under Plan 6 (step annotations) which is `Status: <STATUS_PREFIX> TBD` and not started.

### Transform Blocks — Pipeline Incomplete
- **Spec says** (§775–787): Core transform blocks are listed: `force-to-scale`, `quantise-to-chord` (consumes chord-stream), `randomise`, `accumulate`, `grab-from`, `transpose-by-stream`, `note-repeat` (ratchet), `step-order`, `interpret`, `voice-split/merge`, `density-gate`, `tap-prev`. These are "the actual mechanism" for connecting streams and applying macro control.
- **Code has**: `BlockRegistry` registers 3 kinds: `note-generator`, `midi-out`, `chord-context-sink`. No transform blocks exist. Only `NoteGenerator` produces notes; no downstream transforms.
- **Gap**: 12 core transform blocks are missing. Pipeline is a straight line (generator → sink), not a DAG. Macro rows are authored but only the generator itself reads them (via `interpret` params baked into generator config); no separate `interpret` block exists. `quantise-to-chord` doesn't exist, so the chord-context sink is orphaned. No `note-repeat` means ratcheting is not implementable. Per-track interpretation maps exist in theory (voice presets) but have no runtime execution path.
- **Plan covering this**: None explicitly listed; architecture-level gap. Transforms were implied to land in Plan 1 (core engine) but only the note generator and sinks were shipped.

### Takes (Captured Time-Varying Macros)
- **Spec says** (§616–628): Takes are N-bar recorded sequences of macro-row changes, fill activations, and XY-pad moves. Captured from Perform view, stored in library, replayable anywhere. Composition modes: relative (offsets) or absolute (replacement values). Composable and reusable across phrases.
- **Code has**: Zero presence. No `Take` struct, no capture mechanic, no playback scheduler, no library storage.
- **Gap**: Takes are entirely unimplemented. The Perform pad grid (which would trigger takes) does not exist. Capture button is absent. Library view exists but has no Takes tab.
- **Plan covering this**: Plan 8 (Perform layer) and Plan 7 (Fills) are both not started. Takes depend on Perform infrastructure.

### Fill Presets
- **Spec says** (§603–614): Fill presets are named static overlays of macro-row adjustments (e.g., `intensity: 0.2, density: 0.2`). Applied instantaneously when activated, live (hold/latch) or scheduled. Each track interprets them via its own interpretation map.
- **Code has**: A `FillFlag` layer is defined targeting `.macroRow("fill-flag")`. No `FillPreset` struct, no preset library, no activation mechanic, no Perform view to hold/latch them.
- **Gap**: Fill presets cannot be authored, stored, or triggered. The `fill-flag` layer is a boolean switch but has no associated preset payloads. Live performance capture (Perform view, hold/latch triggering) does not exist.
- **Plan covering this**: Plan 7 (Fills) and Plan 8 (Perform layer) not started.

### Template-Generator Kind
- **Spec says** (§761): `template-generator` is a kind that resolves to a pre-authored clip with annotations. Params are template knobs (swing, density-scale, pitch-transpose, …). Internally expands to one-shot clip playback with annotations honored.
- **Code has**: `GeneratorKind` enum has only `monoGenerator`, `polyGenerator`, `sliceGenerator`. No `templateGenerator`. Code mentions "template" as a template for initializing new tracks (default clip content), not as a generator kind.
- **Gap**: No template-generator kind exists. Library-loaded pre-composed material cannot be instantiated as a generator source.
- **Plan covering this**: Not called out explicitly. Implicit in Plan 1 (core engine) and Plan 7 (Fills / library integration) but neither shipped templates-as-generators.

### Chord-Generator as Source Block
- **Spec says** (§759, §453–463): A "chord-generator" is a `poly-generator` instance with `step = manual([true])` and `randomInChord` pitch algo. Chord-gen is a pipeline source (block) that reads abstract macro rows and emits a `chord-stream` to the `chord-context` sink. Multiple pitch algos can stack; chord-gen stacks `randomInChord`.
- **Code has**: `ChordContextSink` exists (receives chord input). `poly-generator` exists in generator kinds. Stacking multiple pitch algos is possible. But no block named "chord-generator" and no chord-emitting block in the registry beyond the data-model support.
- **Gap**: Chord generation is possible via poly-generator params, but is not exposed as a first-class block or preset in the block palette. Chord authoring (per-bar progression editor) does not exist. The pipeline architecture assumes chord-gen as a source block; the runtime must infer it from a poly-generator instance, which is not transparent.
- **Plan covering this**: Plan 4 (Chord layer) is marked `Status: [COMPLETED 2026-04-20]`. Verify completion status and implementation fidelity.

### Interpret Transform Block / Macro Row Integration
- **Spec says** (§434–450): `interpret` is a transform block that reads an abstract macro row (intensity, density, etc.) and maps it to a local parameter. Each track's pipeline includes N interpret blocks fanning abstract rows to local params. Different tracks with the same generator type use different interpretation configs (voice presets). Interpretation configs are savable as voice presets.
- **Code has**: Macro rows are authored and stored (intensity, density, register, variance, brightness, etc.). Voice presets exist as a concept but are not fully wired. `PhraseLayerTarget.macroRow("name")` exists. `NoteGenerator` has `GeneratorParams` but no explicit interpretation pipeline. Macro values are not routed through separate interpret blocks.
- **Gap**: No `interpret` block exists. Macro rows are authored and stored but do not flow through the pipeline as first-class transforms. Interpretation happens implicitly inside `NoteGenerator` by reading macro values at tick time, not via composable blocks. Voice presets (e.g., `bass-default`, `lead-default`) are not shipped or applied at runtime. The architecture calls for blocks; the code uses hardcoded logic in the generator.
- **Plan covering this**: Implicit in Plan 1 (core engine) and Plan 5 (macro coordinator); not explicitly as a block-development plan.

### Routes — Voice-Route Fan-Out and Voice-Split/Merge
- **Spec says** (§467–483): Drum pipeline ends in a `voice-route` sink that maps `voice-tag` to destination(s). Each tag maps to a **list** of destinations; every destination receives the event. Drum view surfaces "+ destination" per tag for layering (e.g., kick → sub-bus + external-gate-trigger).
- **Code has**: `Route` struct with `RouteDestination` enum: `.voicing(trackID)`, `.trackInput(trackID, tag)`, `.midi(port, channel, noteOffset)`, `.chordContext(broadcastTag)`. Routes support `RouteFilter.voiceTag(tag)` to filter events by tag. No list-per-tag; each route is a single source → destination. No `.midi` can route to multiple channel outputs, no `.voicing` fanout.
- **Gap**: Routes are 1:1 (one source filter to one destination). The spec's tag → [destinations] model is not implemented. Multiple routes with the same source tag and filter would work, but the UI does not surface "+ destination" per tag; it surfaces "+ route" as a separate row. Voice-split/merge blocks do not exist, so complex multi-destination routing requires manual route creation.
- **Plan covering this**: Plan 5 (Tracks + groups, v0.0.6-midi-routing) marked completed. Current implementation covers basic routing but not the multi-destination fan-out per tag.

### Chord-Lane Routable / Destination Override
- **Spec says** (§372, §461): Chord-context is a sink that broadcasts chord. Tracks subscribe to it with consumption modes (ignore / scale-root / chord-pool / transpose). `voiceRouteOverride` is a layer target that per-phrase overrides the drum voice-route destination for a named tag (e.g., "kick → alternate slice on break phrase").
- **Code has**: `Route` destination includes `.chordContext(broadcastTag)`, so chord-context can be routed. No per-phrase route override layer target exists. `PhraseLayerTarget` has `.voiceRouteOverride(String)` defined but no code applies it at runtime.
- **Gap**: Chord-context routing exists at the data level. Per-phrase route override is defined but not implemented (no layer evaluates it, no runtime applies it). Chord consumption modes (ignore/scale-root/chord-pool/transpose) are not exposed in code or UI.
- **Plan covering this**: Implicit in Plan 4 (Chord layer, marked completed) and Plan 5 (routing, marked completed).

### PitchAlgo `markov` — Incomplete
- **Spec says** (§730): `markov` pitch algo with styleID, leap, color params. StyleProfileID picks a pre-baked weight profile (vocal / balanced / jazz). Leap and color are macro-controllable overlays.
- **Code has**: `PitchAlgo.markov(root, scale, styleID, leap, color)` exists in enum. `StyleProfileID` enum exists with three cases: `vocal`, `balanced`, `jazz`. Markov chains are not implemented in the runtime (see Transform block gap above). The generator does not compute Markov transitions; a generic `randomInScale` is used.
- **Gap**: Markov pitch-algo is defined but not implemented in the generator runtime. It falls back to random or manual selection. The leap and color params are stored but not used.
- **Plan covering this**: Plan 3 (generator-algos, v0.0.3-generator-algos, marked completed 2026-04-19). Verify markov implementation fidelity in code.

### Destination `.inheritGroup` and `sharedDestination` Resolution
- **Spec says** (§45–47, §185–227): `Destination.inheritGroup` routes a track's notes through its group's `sharedDestination`. At tick time, `effectiveDestination()` resolves `.inheritGroup` to the group's shared destination + note offset. Drum tracks with a shared AU use this to map kick→36, snare→38, hat→42, etc.
- **Code has**: `Destination` enum has `.inheritGroup` case. `Project+Destinations.swift` provides routing helpers. But `effectiveDestination()` logic is not present in the search results.
- **Gap**: The resolve-at-tick-time logic may exist but is not clearly exposed. No evidence that note-offset mappings are applied. Drum group setup (sharedDestination + noteMapping) may not flow through to the engine at tick time.
- **Plan covering this**: Plan 5 (Tracks + groups) marked completed; Plan 5 (MIDI routing, v0.0.6-midi-routing) marked completed. Verify runtime integration.

### Chord-Generator Output — Per-Step vs Per-Bar Granularity
- **Spec says** (§853): Chord-context is per-step in the data layer. Chord-gen blocks default to "quantise to bar" (one chord per bar) for the clean common case. Per-block toggle off quantise-to-bar for jazz-style mid-bar changes.
- **Code has**: `Chord` stream type exists. No evidence of quantise-to-bar logic or per-block toggle. No chord-generator block (see above).
- **Gap**: Chord-context granularity and quantise-to-bar toggle are not implemented.
- **Plan covering this**: Plan 4 (Chord layer).

### Project Serialisation — Deferred Audio-Side Package Upgrade
- **Spec says** (§797–802): `.seqai` is JSON (Codable) for now. Package upgrade to `.seqaipkg` is deferred to a later phase. State persistence is project-document-scoped; library assets are in `~/Library/Application Support/sequencer-ai/library/`.
- **Code has**: Project is Codable and serialises to JSON. `Project+Codable.swift` handles round-trip. No package format implemented yet.
- **Gap**: None; this is correctly deferred. Format is JSON as specified for MVP.

### Perform View and XY Pad
- **Spec says** (§661): Perform view includes fill-preset pad grid, Take pad grid, XY pad (configurable, default X=intensity Y=tension), punch-in effects (repeat/reverse/loop/step-shuffle), per-track select pads, Capture button.
- **Code has**: No Perform view. A `LiveWorkspaceView` exists but is not documented as Perform. No fill or take pad grids, no XY pad, no capture mechanics.
- **Gap**: Perform view is entirely absent. Live-performance interaction model is not implemented.
- **Plan covering this**: Plan 8 (Perform layer) not started.

### Library View — Takes and Templates
- **Spec says** (§662): Library browser of voice presets, drum templates, fill presets, **Takes**, chord-gen presets, sample slice sets, saved phrases. Preview, tag/search, drag-drop, source flag (bundled vs user).
- **Code has**: `LibraryWorkspaceView` exists. No evidence of Takes, fill presets, or templates as asset types in the library.
- **Gap**: Library is a stub. Takes, fill presets, and template browsing are not implemented.
- **Plan covering this**: Implicit in Plan 8 (Perform layer) and not started separately.

### Mixer View — Alt-Bus, Crossfader, Send A/B, FX Chain
- **Spec says** (§659, §632–637): Mixer has per-track channel strips (vol/pan/mute/solo), bus assignment (main/alt), send-A and send-B, crossfader, per-bus FX chain slots, VU meters, master bus. Alt-bus and crossfader are architectural reservations for MVP.
- **Code has**: `MixerView` exists with basic UI. No send controls, no alt-bus assignment, no crossfader, no FX chain UI, no VU meters, no master bus. Audio engine is MIDI-only in MVP; no audio-side infrastructure.
- **Gap**: Mixer is a stub. Audio-side features (alt-bus, crossfader, FX) are out of MVP scope and correctly deferred. Sends and basic mixer strips are not yet implemented.
- **Plan covering this**: Plan 10 (Audio-side) deferred. Out of MVP scope by design.

### Clip Editor — Parameter Locks UI, Conditionals, Jitter
- **Spec says** (§663): 16-cell step grid per bar; cell state shows trig / p-lock / conditional / probability / slide / ratchet. Hold a step + twist knob → records parameter lock. Inspector "Locks" section lists active locks per step. Sub-grids show velocity / length / delay / micro-timing.
- **Code has**: No clip editor UI in the codebase (or if it exists, not exposed in UI directory listing). Clip content is edited as raw `stepSequence` or `pianoRoll` with no per-step annotation interface.
- **Gap**: No Elektron-style clip editor. Step annotations, locks, and conditionals cannot be edited in the UI.
- **Plan covering this**: Implicit in Plan 6 (step annotations); not started.

### Phrase Variants vs Full Copy Model
- **Spec says** (§855): Phrase variants are full copies; variants are independent after creation. Edits to base do not ripple.
- **Code has**: No phrase variant concept in the `Phrase` struct. Phrase duplication would create independent phrase instances, which matches the full-copy model.
- **Gap**: No gap; the model is simple (phrases are independent). The spec's note about "full copy" is how the code works by default.

## 🔴 Not started

### Note-Repeat Block (Ratchet)
- **Spec says** (§782): `note-repeat(count, shape, velocity-shape, gate)` — ratchet. Per-step gate-prob locked via parameter locks. Central to performance.
- **Code has**: Zero implementation.
- **Plan covering this**: Plan 9 (Note-repeat & step-order blocks) not started.

### Step-Order Block
- **Spec says** (§783): `step-order(preset | user-perm)` — deterministic playhead reorder.
- **Code has**: Zero implementation.
- **Plan covering this**: Plan 9 not started.

### Force-to-Scale Block
- **Spec says** (§776): `force-to-scale(scale, root)` — scene-level pitch correction.
- **Code has**: Zero implementation.
- **Plan covering this**: No plan explicitly; implicit in Plan 1 (core engine) but not shipped.

### Quantise-to-Chord Block
- **Spec says** (§777): `quantise-to-chord(mode: scale-root|chord-pool|transpose|ignore)` — consumes `chord-stream`.
- **Code has**: Zero implementation. The modes are not exposed. Blocks don't subscribe to chord-context.
- **Plan covering this**: Plan 4 (Chord layer, marked completed); verify if this block was shipped.

### Randomise Block
- **Spec says** (§778): `randomise(pitch=±N, vel=±M, timing=±T)` — global or tag-filtered.
- **Code has**: Zero implementation.
- **Plan covering this**: Not called out; implicit in Plan 1 but not shipped.

### Accumulate Block
- **Spec says** (§779): `accumulate(+N per bar|step|repeat)` — Cirklon-style.
- **Code has**: Zero implementation.
- **Plan covering this**: Not called out.

### Grab-From Block
- **Spec says** (§780): `grab-from(track, field)` — Cirklon inter-track.
- **Code has**: Zero implementation.
- **Plan covering this**: Not called out.

### Transpose-by-Stream Block
- **Spec says** (§781): `transpose-by-stream(scalar-stream)` — continuous transpose.
- **Code has**: Zero implementation.
- **Plan covering this**: Not called out.

### Voice-Split / Voice-Merge Blocks
- **Spec says** (§785): Separate a tagged note-stream into per-tag sub-streams, or merge them back. Power-user DAG decomposition.
- **Code has**: Zero implementation.
- **Plan covering this**: Not called out.

### Density-Gate Block
- **Spec says** (§786): `density-gate(threshold-stream, tag-filter?)` — probabilistic gate.
- **Code has**: Zero implementation.
- **Plan covering this**: Not called out.

### Tap-Prev Block
- **Spec says** (§787): `tap-prev(stream)` — one-tick-delayed read for feedback-like patterns.
- **Code has**: Zero implementation.
- **Plan covering this**: Not called out; implicit in Plan 1 cycle-policy (resolved with tap-prev as escape hatch) but not shipped.

### Sliced-Loop Tracks (Plan 11)
- **Spec says** (§497–549): Slice loading, slicing analysis, slice-clip source, slice-player, voice-route sink per slice. Pipeline identical to drum tracks (slice = voice-tag).
- **Code has**: `GeneratorKind.sliceGenerator` exists with `StepAlgo × [SliceIndex]`. No audio sample loading, slicing analysis, or slice-player engine.
- **Plan covering this**: Plan 11 (Sliced-loop tracks) not started. Out of MVP scope.

### Freeze / Stamp Workflow (Plan 12)
- **Spec says** (§830–831): Sliding-window capture, in-place pipeline reconfiguration. Commands: freeze → clip captured, pattern slot rewired from generator to clip.
- **Code has**: No freeze UI, no capture mechanism, no in-place rewiring.
- **Plan covering this**: Plan 12 (Freeze / stamp workflow) not started.

### Authored-Scalar and Saw-Ramp Generators
- **Spec says** (§763–764): `authored-scalar` (constant or curve) and `saw-ramp` (LFO-style) are generator kinds for macro-row input. `authored-scalar` powers layer evaluation for non-patternIndex layers.
- **Code has**: Neither kind is in `GeneratorKind` enum. Layer cells are authored directly; no generator-source fallback for scalar rows.
- **Gap**: Not implemented. Macro rows are authored as cells, not generated. LFO / ramp sources are not available.
- **Plan covering this**: Not called out; implicit in Plan 2 (macro coordinator) but not shipped.

### MIDI-In Generator / External Pitch Feed
- **Spec says** (§732, §765): `midi-in(port, channel, holdMode)` — external MIDI feed as pitch or step source. Port selection, holdMode (.pool | .latest).
- **Code has**: No MIDI-in generator kind or block. Basic MIDI session exists for device discovery and input, but not wired as a pipeline source.
- **Plan covering this**: Not called out; implicit in core engine but not shipped.

### Clip-Sourced Step Algos
- **Spec says** (§718): `fromClipSteps(clipID)` — use clip's step mask. `fromClipPitches(clipID, pickMode)` — use clip's pitches.
- **Code has**: `StepAlgo.fromClipSteps` case exists. `PitchAlgo.fromClipPitches` case exists. But no runtime codepath reads clips at generation time; generators don't invoke this path.
- **Gap**: The enum cases exist for data storage but are not executed by the note generator. Clip-sourced material would need a `clip-reader` block or special handling in the generator.
- **Plan covering this**: Implicit in Plan 6 (step annotations) but not shipped.

### Bundled Content (Presets, Templates, Fills, Chord Presets)
- **Spec says** (§859): Curated starter kit: ~20 drum templates, 8 voice presets, 6 fill presets, 4 chord-gen presets. Category list committed. Authored in a dedicated content sub-spec late in development.
- **Code has**: No bundled library content. Voice presets exist as a concept but none are shipped. Drum-kit presets are hardcoded (`DrumKitPreset` enum) with 3 examples (kick, snare, hat). No drum templates, fill presets, or chord-gen presets.
- **Gap**: Content is entirely missing. Only basic drum-kit presets exist.
- **Plan covering this**: Not explicitly called out; implicit in library planning and content-production phase, post-MVP.

## ⚫ Superseded / contradicted

### Drum-Kit Generator Kind
- **Spec says** (§50): "there is no `drum-kit` kind in the flat-track model — drum parts are individual `monoMelodic` tracks, each with their own generator (typically `mono-generator(step: euclidean, pitch: manual([constantPitch]))` for a drum voice)."
- **Code has**: `GeneratorKind` enum contains only `monoGenerator`, `polyGenerator`, `sliceGenerator`. No `drumKit` kind.
- **Status**: No contradiction; the spec explicitly rejected drum-kit as a kind. The flat-track model is correctly implemented.

### Track-Type Immutability
- **Spec says** (§148–150): Track type is immutable after creation. "Change the mind" = create new track.
- **Code has**: `StepSequenceTrack.trackType` is not mutable; type is set at creation.
- **Status**: No gap; correctly implemented.

### One Song Per Document
- **Spec says** (§847): One song per `.seqai` document. Multi-song is a future option.
- **Code has**: `Project` has `phrases: [Phrase]` (the song). No multi-song support.
- **Status**: Correct; MVP model is implemented as specified.

## ✅ Landed (brief list, no detail)

1. **App scaffold** — SwiftUI app shell, document-based architecture, Xcode project, Swift packages (Plan 0, v0.0.1-scaffold).
2. **Core engine** — Tick loop, pipeline DAG executor, block registry, block protocol, typed streams (notes, scalars, chords), lock-free command queue (Plan 1, v0.0.2-core-engine). Three blocks shipped: `NoteGenerator`, `MidiOut`, `ChordContextSink`.
3. **Generator kinds (data layer)** — `monoGenerator`, `polyGenerator`, `sliceGenerator` in `GeneratorKind` enum. StepAlgo variants: manual, randomWeighted, euclidean, perStepProbability, fromClipSteps (Plan 3, v0.0.3-generator-algos). PitchAlgo variants: manual, randomInScale, randomInChord, intervalProb, markov, fromClipPitches, external.
4. **Macro coordinator + phrase model** — Project-scoped `PhraseLayerDefinition` with value types, targets, defaults. Per-phrase per-track per-layer cells (inheritDefault, single, bars, steps, curve). 12 default layers (Pattern, Mute, Volume, Transpose, Intensity, Density, Tension, Register, Variance, Brightness, FillFlag, Swing). Layer evaluation at tick time. MacroCoordinator ticks and publishes macro-row values (Plan 2, v0.0.15-coordinator-scheduling).
5. **Song model** — Ordered `phrases: [Phrase]` list in project. Song playhead, transport, phrase insertion/reorder/duplicate (Plan 3, v0.0.14-phrase-workspace-split).
6. **Tracks + groups** — Flat `StepSequenceTrack` with immutable `trackType`. `TrackGroup` with `memberIDs`, optional `sharedDestination`, note mapping, mute/solo (Plan 5, v0.0.7-tracks-matrix). Drum-kit presets (hardcoded, 3 examples).
7. **Pattern bank** — 16-slot per-track pattern bank with source mode (generator or clip) and optional name. Per-track owned clips (initial seeded clip per track). Attached generator model (opt-in generator per track, Plan 17, v0.0.17-per-track-owned-clips).
8. **Destinations** — `Destination` enum: `.midi(port, channel, noteOffset)`, `.auInstrument(componentID, stateBlob)`, `.internalSampler(bankID, preset)`, `.none`, `.inheritGroup`. Inheritance resolution logic sketched (Plan 5, v0.0.5-track-destinations, v0.0.6-midi-routing).
9. **MIDI routing** — `Route` struct with `RouteSource` (track or chord-generator), `RouteFilter` (all, voiceTag, noteRange), `RouteDestination` (voicing, trackInput, midi, chordContext). Projects carry `routes: [Route]` (Plan 6, v0.0.6-midi-routing).
10. **ClipContent data model** — Clip variants: stepSequence, pianoRoll, sliceTriggers. `ClipNote` with pitch, startStep, lengthSteps, velocity.
11. **Chord context** — `Chord` stream type, `ChordContextSink` block, chord-stream plumbing in engine (Plan 4, v0.0.15-macro-coordinator, marked as part of chunk 2 of that plan).
12. **Track sources split** — Source editor (generator/clip/MIDI-in) on left, destination editor on right (Plan 13, v0.0.13-ui-org-track-source-split).
13. **Phrase workspace** — Grid view with layers and cells, phrase matrix with track headers, layer selector. Live/phrase mode toggle (Plan 14, v0.0.14-phrase-workspace-split).
14. **Live view** — Real-time matrix editing of phrase cells in current phrase/layer state (Plan 11, v0.0.11-live-view).
15. **Transport** — Playback controls, transport mode (song/free), phrase playhead, tick clock tied to audio render clock (Plan 1, core engine).
16. **Codable serialization** — Project Codable round-trip to JSON. Undo/redo stack (Plan 12, v0.0.12-document-as-project-refactor).
17. **Musical reference data** — Static Scales (19), Chords (16), StyleProfiles (3) in code. No library-scoped customization yet.

---

## Notes for Remediation Priority

1. **Highest impact**: Implement core transform blocks (interpret, quantise-to-chord, note-repeat, force-to-scale, density-gate). These are the bridge between authored macro rows and generator behavior. Without them, abstract macros don't flow through the pipeline.
2. **Blocker for performance workflows**: Take implementation (capture, playback, library storage) requires Perform view and live-mode infrastructure.
3. **Block completeness**: Fill presets and their triggering (Perform view, hold/latch, scheduled). Currently only FillFlag layer exists; no preset payloads.
4. **Spec fidelity**: Parameter locks (per-step data model + clip editor UI + runtime application). Step annotations complete the clip-data model.
5. **Architectural clarity**: Chord-generator as explicit source block (currently merged with poly-generator; needs first-class preset and block palette presence).

