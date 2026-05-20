# Structural Review — 2026-05-20

Qualitative pass over the 10 biggest Swift source files. Looks at abstractions and domain fit, not metrics. Skips test files.

## Scope

| # | File | Lines | Verdict |
|---|------|------:|---------|
| 1 | `Sources/Engine/EngineController.swift` | 1693 | God object — split into 5 |
| 2 | `Sources/App/SequencerDocumentSession+Mutations.swift` | 970 | Leaky abstraction — cascade leaks to callers |
| 3 | `Sources/UI/TrackSource/Clip/ClipContentPreview.swift` | 963 | Needs split — five editors in one |
| 4 | `Sources/UI/TrackDestinationEditor.swift` | 948 | God view — preset polling + AU window polling |
| 5 | `Sources/UI/Mixer/ScenesWorkspaceView.swift` | 940 | Primitive obsession + binding explosion |
| 6 | `Sources/UI/TrackSource/TrackSourceEditorView.swift` | 908 | Leaky — views reach into store |
| 7 | `Sources/UI/TracksMatrixView.swift` | 900 | Packing problem — split into 4 files |
| 8 | `Sources/UI/Slicer/SliceTrackWorkspaceView.swift` | 834 | Needs split — parallel-arrays anti-pattern |
| 9 | `Sources/Document/MasterBus.swift` | 824 | Mostly healthy — one tagged union to fix |
| 10 | `Sources/Document/GeneratedSourceEvaluator.swift` | 716 | Switch-on-tag overload |

## Progress

Implementation passes now landed on `main`:

- `f919040 refactor(engine): extract clip capture service` — moved rolling capture out of `EngineController`.
- `19301bd refactor(document): add address helpers for phrase timeline` — added `PatternSlotAddress`, `PhraseCellAddress`, and `PhrasePlayhead`.
- `44e3081 refactor(slicer): model slice trigger steps explicitly` — introduced `SliceTriggerStep` / `SliceTriggerSteps` and moved the slicer workspace onto the typed step model while preserving legacy Codable storage.
- `fa6dcd4 refactor(session): centralize project writeback cascade` — added `writeBackProjectStructure(...)` and replaced several duplicated Project → store cascades.
- `304ce07 refactor(engine): isolate tick state buffer` — introduced `TickStateBuffer` for playback snapshot, prepared tick, generated evaluation state, tick mirror, and capture state.
- `d7691f0 refactor(engine): collect track runtime registry` — introduced `TrackRuntimeRegistry` for the parallel per-track runtime tables and sink identity state.
- `5b0303a refactor(document): simplify macro and pitch targets` — introduced `AUParameterReference` and centralized pitch context construction in `GeneratedSourceEvaluator`.
- `ce61374 fix(engine): serialize document model apply` — made broad document-model application single-flight after the full suite exposed concurrent audio-graph apply deadlock risk.

Still open:

- `EngineController` still needs the router/dispatch pipeline, transport lifecycle, and AU readiness/preset facade extractions.
- `writeBackProjectStructure(...)` is a useful central helper, but not yet a full `ProjectMutation` / store diff abstraction.
- `MasterSceneMacroTarget` still encodes as the legacy enum shape for compatibility; the AU parameter pack is now represented internally but the target is not fully polymorphic.
- `GeneratedSourceEvaluator` still owns generator evaluation and pitch-stage adaptation; the pitch context duplication is reduced, not fully split into strategy objects.
- The large SwiftUI files still need file-level splitting after the runtime/domain ownership is steadier.

## File-by-file

### 1. `EngineController.swift` (1693) — god object

Carries at least seven separable responsibilities:

- Transport lifecycle (`start`/`stop`/`shutdown`/`processTick`, 212–310, 766–776)
- Pipeline construction (`buildPipeline`, `pipelineShape`, 1038–1103)
- Output sink management for AU instruments, samples, slicers, MIDI (`syncAudioOutputs`, `syncMidiOutputs`, `syncSampleMixers`, 1303–1435) — three parallel sub-systems each living as raw dictionaries (`audioOutputsByTrackID`, `routeMidiOutputs`, `liveSampleTrackIDs`, `audioTrackRuntimes`)
- Per-tick note resolution (`resolvedStepNotes`, 1438–1515) — calling into `GeneratedSourceEvaluator`. Essentially a tick-time sequencer.
- Routing fan-out (`flushRoutedEvents`, `flushRoutedNotes`, `flushConcreteDestination`, 1105–1251)
- MIDI panic / note-off bookkeeping (`flushDetachedMIDINoteOffs`, 1553–1597)
- Rolling capture buffer for clip history (`RollingCaptureBuffer` nested struct, `saveRollingCapture`, 12–67, 607–634) — pure domain logic
- Master-bus performance overlay state + AU window plumbing (113, 468–528)
- Preset loading and AU state-blob persistence (`loadPreset`, `presetReadout`, `writeStateBlob`, 376–605)

God functions:
- `prepareTick` (179 lines, 778–955) — generator evaluation, capture-buffer maintenance, executor invocation, transport-string formatting, host triggering, sample dispatch, slicer dispatch, route input building, routed-event flushing.
- `syncAudioOutputs` (82 lines) — reconciles three parallel dictionaries by hand.
- `apply(deltas:documentModel:)` (66 lines) — giant switch where most cases fall through to `applyBroadSync`.

Missing concepts:
- `TrackRuntimeRegistry` (or `TrackSinkTable`) — the four parallel dicts keyed by `UUID` (`audioOutputsByTrackID`, `audioOutputKeysByTrackID`, `lastDestinationByOutputKey`, `audioTrackRuntimes`) plus `midiOutBlocksByTrackID` plus `generatorIDsByTrackID` want a single typed table per track.
- `ClipCaptureService` — `RollingCaptureBuffer` and its filtering on track-removal (339, 1095) is a self-contained subsystem.
- `Router`/`DispatchPipeline` owning `routedNoteEvents`, `routedChords`, `routedMIDINotes`, `routeDispatchNow` (127–131). The dispatcher protocol conformance is already there; just hoist the state.
- `TickStateBuffer` for the lock-protected blob. `withStateLock` (1673–1677) appears 30+ times.

Primitive obsession: `BlockID` is just `String`. Generator IDs formed by `"gen-\(uuid)"` / `"out-\(uuid)"` string concatenation (1528–1534). Strongly type these.

### 2. `SequencerDocumentSession+Mutations.swift` (970) — leaky abstraction

A `+Mutations` extension over 900 lines is a naming smell. The file mixes:

- Generic typed mutators (`mutateClip`, `mutateTrack`, `mutateGenerator`, `mutatePhrase`, `mutatePatternBank`, 82–146, 393–403, 513–523)
- Composite project-round-trip mutations (`setSlicerDestination`, `setEditedDestination`, `appendTrack`, `addDrumGroup`, 170–186, 673–732, 888–932)
- 24 specific master-bus passthroughs (264–388)
- Pattern/macro orchestration (`applySlicerAnalysis`, `assignAUMacroToSlot`, `applyMacroDiff`, 195–238, 558–636)

The project round-trip pattern is duplicated 12+ times:

```swift
var p = store.exportToProject()
p.mutateSomething()
s.replaceTracks(p.tracks)
s.replaceTrackGroups(p.trackGroups)
s.setLayers(p.layers)
s.replacePhrases(...)
s.writeBackChangedClips(from: p)
```

This is the leaky abstraction — every caller is expected to know which sub-collections to write back. `writeBackChangedClips` (964–969) is a post-hoc per-field reconciliation that proves the point.

God function: `applyMacroDiff` (599–636) interleaves search-by-source-tag, descriptor construction, layer/phrase/clip sync. The descriptor construction (619–626) is duplicated verbatim in `TrackDestinationEditor.assignMacro` (902–909) and `TrackSourceEditorView.assignMacro` (439–447).

The `.fullEngineApply` annotations sprinkled in comments (13, 671, 686, 697, 778, …) leak the impact model through every call site — it should be derivable from what changed.

Missing concepts:
- `MacroDescriptorFactory` (or a `TrackMacroDescriptor.init(from: AUParameterDescriptor)`) to kill the three duplications.
- `ProjectMutation` value type or builder that owns the cascade so callers don't have to remember which sub-arrays to write back, or a single `store.applyProjectDiff(_:)`.

### 3. `ClipContentPreview.swift` (963) — needs split

`body` switches on `ClipContent` (135) and then `noteGridEditor` (188 lines) switches again on `selectedMode` × `selectedLayer` (233–294). Four parallel `GridEditor`/`StepGridView` invocations all take `visibleIndices`/`pageStart`/`lengthSteps` — page-pagination duplicated four times.

Missing concepts:
- `ClipPage` (`{ pageIndex, pageStart, pageEnd, visibleIndices }`) — recomputation appears in every editor branch (190–195).
- `ClipStepWriter` / `ClipLaneMutation` — `updatingLaneVelocities`/`updatingLaneChances`/`togglingStep` (808–885) all do the same "find existing lane → mutate or create → write back" loop.

The slice-trigger editor (138–174, 734–785) should be its own view.

Healthier shape: `ClipContentPreview` (dispatcher) + `NoteGridEditorView` + `SliceTriggersEditorView` + `MacroLaneEditorView` + `ClipStepInspectorSheet`.

### 4. `TrackDestinationEditor.swift` (948) — god view

Switching on `editedDestination` (127) to pick six editor variants is fine in isolation, but each branch's implementation lives in the same struct, alongside cross-cutting concerns (preset browser, macro picker, MIDI port/channel/transpose, AU window opening, AU state-blob writing).

Concrete issues:
- `requestPresetReadout` (516–559) is a preset-loading retry state machine with global generation counter, recursive polling, DispatchQueue hopping, and Task hop — has no business in a view. It's a service.
- `prepareAndOpenCurrentAudioUnitWindow` (827–846) polls the engine 20 times waiting for an AU to materialize. The engine should provide an "await AU ready" API.
- Three parallel `Binding` constructions for MIDI port/channel/noteOffset (743–772) read through `editedDestination.midiPort` and write through `session.setEditedMIDIPort/...`. A `MIDIDestinationBinding` would collapse them.
- Descriptor-construction duplication (901–909) — see (2).

Missing concept: `PresetBrowserCoordinator` owning `presetReadoutState`, `presetReadoutGeneration`, retry loop, prepare/load — currently spread across `requestPresetReadout`, `refreshPresetReadout`, `stepPreset`, `makePresetBrowserViewModel`, `presetReadoutRefreshKey`.

### 5. `ScenesWorkspaceView.swift` (940) — primitive obsession + binding explosion

The binding factory pattern is out of control. `filterModeBinding`, `filterCutoffBinding`, `filterResonanceBinding`, `bitDepthBinding`, `bitRateBinding`, `bitDriveBinding` (763–845) each follow the same 10-line shape: open the insert kind, pattern-match-with-`var`, mutate the settings struct, re-wrap. Six near-identical functions plus matching `settingsForFilter`/`settingsForBitcrusher` readers (847–859).

Wants a per-kind editor view (`MasterFilterInsertEditor`, `MasterBitcrusherInsertEditor`) that takes `Binding<MasterFilterSettings>` / `Binding<MasterBitcrusherSettings>` directly. `MasterBusInsertKind` already separates them; the UI refuses to lean on that polymorphism.

Switch cascades on type tags (636–676 `kindEditor`, 929–938 `iconName`, 895–911 `macroTargets`) all re-derive things from `insert.kind`. A `MasterBusInsertEditing` protocol or `MasterBusInsertKind` extension would fold these.

Also contains an entire macro-target-picker sheet (535–632) which is three nested sub-views.

### 6. `TrackSourceEditorView.swift` (908) — leaky abstraction

Two private methods reach right through the session abstraction into raw `store`/`Project`:
- `select(generator:, for:)` (464–506) — for `.modifier`, opens `session.batch`, exports the project, ensures a clip, manually filters new clips, syncs pattern banks. Same cascade `+Mutations` is supposed to own.
- `removeGeneratorSource` (517–540) — identical pattern.

Both should be single session calls (e.g. `session.setModifierGenerator(...)`, `session.removeGeneratorSource(...)`).

`ClipHistoryCaptureSheet` (568–775) is an unrelated feature crammed in — should be its own file. Missing concept: `ClipHistoryCapture` (`lengthSteps`, `destinationSlotIndex`, `selectedSlotIndex`) as a feature unit.

### 7. `TracksMatrixView.swift` (900) — packing problem, decent shape

Three substantial structs in one file: `TracksMatrixView` (top), `TrackMatrixCard` (cell), `CreateTrackSheet` and `AddSliceTrackSheet` (modals). Each is sensibly scoped; split into four files.

`performPrimaryAction` (386–444) is a 58-line switch over `PhraseCell` cases that all do the same thing — compute a cycled value at the current bar/step, build a new cell, write back via `setPhraseCell`. Five cases, four identical-shape branches. Missing method on `PhraseCell` itself: `func cycledAtPosition(_ position: PhrasePosition, layer: PhraseLayerDefinition) -> PhraseCell`. Five lines instead of 58.

`playbackPhraseIndex` (89–112) — `PhraseTimeline` concept, duplicated in `SliceTrackWorkspaceView.resolvedPatternIndex` and `TrackSourceEditorView.resolvedPatternIndex`.

`Color(hex:)` extension at 886 — likely defined at least twice elsewhere.

### 8. `SliceTrackWorkspaceView.swift` (834) — parallel-arrays anti-pattern

Mixes waveform editor scaffolding, auto-detect controls, pattern-slot palette, step editor, sample-player parameters, routes list. The `SliceTriggerParts` shadow-struct (444–462) signals that `ClipContent.sliceTriggers` is hard to work with — four parallel arrays kept in sync by `synced(_:stepCount:fallback:)` (670–675).

Missing concept: `SliceTriggerSteps` (or per-step `SliceTriggerStep { isOn, sliceIndex, mode, parameters }`) replacing the four-array shape. Every mutator (`toggleStep`, `assignSliceIndex`, `assignStepMode`, `assignStepParameters`, `resizeClip`, 605–656) re-synchronizes them.

Analysis state (`analysisDraft`, `analysisMode`, `analysisSensitivity`, `analysisBars`, `analysisMessage`) is a coherent sub-state that wants its own observable (`SliceAnalysisDraft`).

`resolvedPatternIndex` (821–833) is duplicated verbatim with `TrackSourceEditorView.resolvedPatternIndex` (542–555).

### 9. `MasterBus.swift` (824) — mostly healthy, one tagged union to fix

The structures (`MasterBusState`, `MasterBusScene`, `MasterSceneMacroBinding`, `MasterSceneMacroTarget`, `MasterBusPerformanceOverlayState`, `MasterBusInsert`, `MasterBusInsertKind`, `MasterFilterSettings`, `MasterBitcrusherSettings`, `MasterBusABSelection`) belong in their own files — packing problem, not abstraction problem.

The real smell: `MasterSceneMacroTarget` (411–629) is a giant tagged union with parallel switches — `valueRange`, `authoredDefaultValue`, `storesAuthoredValue`, `isValid(in:)`, `targetsInsert(_:)`, `remappedInsertIDs(_:)`, `read(from:)`, `write(_:to:)`, `label(in:)` — nine methods each switching over six cases (218 lines of switch). The `.auParameter` case has eight associated values inline (418–427); every method re-destructures them.

Missing concepts:
- `AUParameterReference { insertID, address, identifier, displayName, range, defaultValue, unit }` — collapses the inline associated-value pack.
- `MacroTarget` protocol (with `valueRange`, `read`, `write`, `label`) — one type per target, removes the 9-way switches.

`MasterBusState.normalize()` (155–195) — 40 lines doing ID-dedup, fallback construction, AB-selection normalization — extract to test.

### 10. `GeneratedSourceEvaluator.swift` (716) — switch-on-tag overload

A free-floating `enum GeneratedSourceEvaluator { static func ... }` is a naming smell — namespaced bag of static functions that wants to be a type.

Two parallel `evaluateSourceStep` switches: one over `GeneratorParams` (58–154) and one `evaluateStep` over `GeneratedSourcePipeline.content` (156–248). Both walk near-identical cases (`melodic`/`poly`/`progressionChords`/`drum`/`slice`/`template`) producing the same `[GeneratedNote]`. Either the params and pipeline are the same concept and should be unified, or there should be a single `GeneratorContent` type with `evaluate(...)`. As written it's ~200 lines of duplicated structure.

`transformedPitches` (498–635) is a 138-line switch over `PitchAlgo` with seven cases, each constructing a `PitchContext` with five fields. Each branch repeats the same context build with subtle variations. Extract `PitchAlgo` evaluation onto `PitchAlgo` itself or a `PitchAlgoEvaluator` so this function is six lines.

## Cross-cutting findings

These recur across many files and are the highest-leverage refactors.

### A. Missing `AudioUnitHost` service

`EngineController` exposes `prepareAudioUnit`, `currentAudioUnit`, `presetReadout`, `loadPreset`, `audioInstrumentHost` (559–605). `TrackDestinationEditor` implements a polling state machine on top (516–559, 827–846). `ScenesWorkspaceView` does the same dance for master inserts (`prepareMasterAUEffect`, 921; `currentMasterAUEffect`, `masterAUEffectParameterReadout` on EngineController 518–528).

Extract an `AudioUnitHost` that owns readiness, presets, parameter readout, state-blob persistence. Views call `await host.preset(...)` instead of polling.

### B. Missing macro-descriptor factory + unified macro-slot model

`TrackMacroDescriptor(from: AUParameterDescriptor)` is hand-built three times:
- `SequencerDocumentSession+Mutations.swift:618–626`
- `TrackDestinationEditor.swift:901–909`
- `TrackSourceEditorView.swift:439–447`

The `(slotIndex, binding: TrackMacroBinding?)` pair is reified as `AUMacroSlot` in one place and `ClipMacroSlot` in another (`ClipContentPreview.swift:85–90`, `TrackDestinationEditor.swift:460–467`, `TrackSourceEditorView.swift:130–137`). Same data, two types.

One `MacroSlot` type plus one `TrackMacroBinding.descriptor(from:)` initializer kills three duplications.

### C. Project round-trip cascade leaks into views

`var p = store.exportToProject(); mutate(&p); store.replaceTracks(...); store.replaceTrackGroups(...); store.setLayers(...); store.replacePhrases(...); store.writeBackChangedClips(from: p)` appears in `+Mutations.swift` (12+ places) and inside views (`TrackSourceEditorView.swift:483–504, 521–539`).

`SequencerDocumentSession` is supposed to hide store mechanics but doesn't. Solve by making `Project` mutations return a typed diff applicable in one shot, or by giving the store a single `apply(_:Project)` that does the right reconciliation.

### D. Missing address value types

The trio `(trackID, slotIndex, ...)` recurs all over: `setPatternSourceRef(_, for:, slotIndex:)`, `setPatternModifierBypassed(_, for:, slotIndex:)`, `setPatternModifierGeneratorID(_, for:, slotIndex:)`, `ensureClipAndMutate(trackID:)`, `saveRollingCaptureToPatternSlot(trackID:, slotIndex:, lengthSteps:)`.

`(phraseID, layerID, trackID, stepIndex)` recurs across `setPhraseCell`, `editableCell`, `resolvedValue`.

Missing: `PatternSlotAddress { trackID, slotIndex }` and `PhraseCellAddress`.

### E. Per-step parallel-arrays anti-pattern

`ClipContent.sliceTriggers(stepPattern: [Bool], sliceIndexes: [Int], stepModes: [SliceTriggerStepMode], stepParameters: [SliceTriggerStepParameters])` — four arrays in lock-step. `SliceTrackWorkspaceView` invents `SliceTriggerParts` and a `synced(_:stepCount:fallback:)` helper used 8 times to enforce the invariant. Replace with `[SliceTriggerStep]`.

Same shape: `(values, visibleIndices, stepCount, lengthSteps)` parameter quartet across `ClipContentPreview.updatingLaneVelocities`/`updatingLaneChances`/`updateMacroLaneValues` (836, 855, 563) — wants a `VisibleStepWindow` type.

### F. Switch-on-enum-tag where polymorphism would fit

- `MasterSceneMacroTarget` — 9 methods × 6 cases = 218 lines of switch in MasterBus.
- `PitchAlgo` — 138-line switch in GeneratedSourceEvaluator.
- `GeneratorParams` — parallel switches in GeneratedSourceEvaluator.
- `Destination` — switches in EngineController, TrackDestinationEditor, MasterBus.
- `MasterBusInsertKind` — 4+ switches in ScenesWorkspaceView.

Strategy cases (`PitchAlgo`, `MasterSceneMacroTarget`) want a protocol with one type per case. Shape-variation cases (`Destination`) at least want centralized switches in one extension instead of every view re-deriving.

### G. Phrase-position math is duplicated

`resolvedPatternIndex(in: phrase, trackID:, stepIndex:)` appears verbatim in `TrackSourceEditorView` (542–555) and `SliceTrackWorkspaceView` (821–833). `playingClipStepIndex` is duplicated likewise (`TrackSourceEditorView.swift:88–104`, `SliceTrackWorkspaceView.swift:510–523`). The `(transportTickIndex, phrase.stepCount, phrase.stepsPerBar, lengthBars)` math recurs in `TracksMatrixView`, `TrackSourceEditorView`, `SliceTrackWorkspaceView`.

Missing: `PhrasePlayhead` (or `PhraseTimeline`) translating engine tick → `(phraseID, barInPhrase, stepInPhrase, patternIndex)`.

### H. Naming smells

`EngineController`, `SequencerDocumentSession+Mutations`. Both signal "we don't have a name for what this does because it does too much."

## Recommended order of attack

Highest ROI first.

1. **Carve up `EngineController`** into `Transport` + `TrackRuntimeRegistry` + `Router` + `ClipCaptureService` + `AudioUnitHost`. Biggest god object by a wide margin; unlocks testability everywhere. Wants a proper plan doc under `docs/plans/` before any code moves.
2. **Fix the project round-trip cascade** (cross-cutting C). Actively breeds bugs every schema change; views are doing it directly which is the clearest sign the abstraction is broken.
3. **Extract `MacroSlot` + `MacroDescriptor.init(from:)`** (cross-cutting B). Small change, kills three duplications and a parallel-type confusion. Good warm-up.
4. **Introduce `PatternSlotAddress` / `PhraseCellAddress` / `PhrasePlayhead`** (cross-cutting D, G). Small types, large readability win.
5. **Replace `ClipContent.sliceTriggers` parallel arrays with `[SliceTriggerStep]`** (cross-cutting E). Localized to slice subsystem; removes the `synced(...)` helper entirely.
6. **Polymorphic `PitchAlgo` and `MasterSceneMacroTarget`** (cross-cutting F). Each removes ~150 lines of switch and makes adding new cases additive.
7. **Split the big UI files** (`ClipContentPreview`, `TrackDestinationEditor`, `ScenesWorkspaceView`, `TracksMatrixView`, `SliceTrackWorkspaceView`). Mostly mechanical once the missing concepts above are extracted.

Steps 3–4 are low-risk and unblock 1–2. Step 1 is the multi-week one.
