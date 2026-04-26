# Engine Boundary and Large-File Refactor Plan

**Parent context:** `wiki/pages/project-layout.md`, `wiki/pages/code-review-checklist.md`, and the current oversized files audit.
**Status:** Not started. Tag `v0.0.NN-engine-boundary-refactor` at completion.

## Summary

The project already has the right top-level responsibility boundaries:

- `Sources/Engine/` owns sequencing runtime, transport, snapshot tick preparation, routing, and dispatch.
- `Sources/Audio/` owns `AVAudioEngine`, AU hosting, sample playback, filters, and mixer nodes.
- `Sources/UI/` owns SwiftUI rendering and user interaction.
- `Sources/App/` composes the per-document `SequencerDocumentSession`, live store, runtime, and flush lifecycle.

The problem is not that `Engine/` should be a new top-level directory separate from audio and UI. It already is. The problem is that several files now violate the file-per-responsibility rule, and a few UI surfaces reach through `EngineController` into low-level runtime/AU details.

This refactor must preserve the recent live-store architecture: clips, pattern banks, phrase buffers, generated-source state, macro lanes, and playback snapshots are kept resident in performant authored/runtime shapes. `Project` is a persistence/export DTO, not the normal UI read path and not the playback hot path.

This plan does a behaviour-preserving cleanup in two layers:

1. Split oversized files into small, named responsibility files without changing public behaviour.
2. Tighten the UI/runtime boundary so views issue user-intent commands through the session or small view models instead of directly driving AU host preparation, preset loading, parameter readout, or sample-engine details.

No feature work lands in this plan.

## Current Findings

### Oversized files

Files over or near the project cap:

- `Sources/Engine/EngineController.swift` — 1518 lines
- `Sources/Document/PhraseModel.swift` — 1088 lines
- `Tests/SequencerAITests/Engine/EngineControllerTests.swift` — 1035 lines
- `Sources/UI/TrackDestinationEditor.swift` — 897 lines
- `Sources/UI/TrackSource/Clip/ClipContentPreview.swift` — 703 lines
- `Sources/Document/GeneratedSourceEvaluator.swift` — 694 lines
- `Sources/App/SequencerDocumentSession+Mutations.swift` — 691 lines
- `Sources/Audio/AudioInstrumentHost.swift` — 642 lines

### Boundary concerns

Mostly clean:

- `UI` reads transport status and sends transport commands (`start`, `stop`, BPM, mode). This is acceptable app-facing controller use.
- `App` owns the document session and per-document engine construction. This is the right composition boundary.
- `Engine` depends on audio through `TrackPlaybackSink` / `SamplePlaybackSink` protocol seams, which is the right shape.

Needs cleanup:

- `TrackDestinationEditor` calls `engineController.prepareAudioUnit`, `presetReadout`, `loadPreset`, `currentAudioUnit`, `audioInstrumentHost(for:)`, and passes `sampleEngineSink` to a child view. That is UI driving AU host/runtime details.
- `TrackSourceEditorView` calls `audioInstrumentHost(for:)?.parameterReadout()` for macro assignment.
- `SamplerDestinationWidget` accepts a `SamplePlaybackSink`, giving UI a direct audio runtime handle.
- `EngineController` exposes concrete `AudioInstrumentHost` through `audioInstrumentHost(for:)`, which pierces the protocol abstraction.

The target is not "UI cannot mention EngineController." The target is "UI should not know how AU hosting, preset loading, parameter-tree reads, or sample runtime commands are performed."

Performance intent to preserve:

- UI editing surfaces should keep reading resident `LiveSequencerStore` fields or `SessionSnapshotPublisher`, not `session.project` or `store.exportToProject()`.
- Clip edits should stay narrow: mutate one clip, publish the correct `SnapshotChange`, and avoid whole-project export unless the operation is structural and explicitly documented.
- Tick preparation should continue reading `PlaybackSnapshot` buffers and snapshot-carried tracks, not `currentDocumentModel` or live `Project` traversal.
- Splitting files must not move pure runtime helpers into places that require broader imports or force value conversions.

## Guardrails

- Behaviour-preserving refactor only. No new playback features, no new UI features.
- Keep `Sources/Engine/`, `Sources/Audio/`, and `Sources/UI/` as the top-level boundaries.
- Do not move `AVAudioEngine` or AU host code into `Engine/`.
- Do not move SwiftUI views into `Engine/` or `Audio/`.
- Do not create generic `Utils.swift`, `Helpers.swift`, or `EngineSupport.swift` dumping grounds.
- Prefer extension-file splits before deeper abstractions.
- Preserve resident live-store and incremental snapshot semantics. Do not reintroduce `Project` as a hot UI/runtime model.
- No new `store.exportToProject()` calls in normal UI read paths, clip editing paths, tick preparation, or snapshot-only mutations.
- Any remaining `exportToProject()` use must stay limited to persistence flushes, structural composite mutations, or explicitly documented compatibility paths.
- Each source/test file under `Sources/` and `Tests/` must end under 1000 lines.
- Keep public call sites stable unless a phase explicitly replaces them with a narrower API and tests cover the replacement.
- Run focused tests after each phase; run the full suite before close.

## Desired Architecture

```
Sources/App/
  SequencerDocumentSession.swift
  SequencerDocumentSession+ClipMutations.swift
  SequencerDocumentSession+DestinationMutations.swift
  SequencerDocumentSession+MacroMutations.swift
  SequencerDocumentSession+PatternMutations.swift
  SequencerDocumentSession+PhraseMutations.swift
  SequencerDocumentSession+RouteMutations.swift
  SequencerDocumentSession+TrackMutations.swift
  SequencerRuntimeCommands.swift          # optional, only if UI boundary cleanup needs a named facade

Sources/Engine/
  EngineController.swift                  # init, stored state, app-facing facade
  EngineController+Transport.swift
  EngineController+Apply.swift
  EngineController+Pipeline.swift
  EngineController+TickPreparation.swift
  EngineController+Routing.swift
  EngineController+Outputs.swift
  EngineController+RollingCapture.swift
  EngineDestinationResolver.swift         # optional pure helper, if extraction is cleaner than extension methods

Sources/Document/
  PhraseModel.swift
  PhraseLayerDefinition.swift
  PhraseCell.swift
  PhraseCurveSampler.swift
  TrackPatternBank.swift
  TrackPatternSlot.swift
  TrackSourceMode.swift
  GeneratorKind.swift
  GeneratorPoolEntry.swift
  ClipPoolEntry.swift
  SourceRef.swift

Sources/UI/TrackDestination/
  TrackDestinationEditor.swift
  MIDIDestinationEditor.swift
  AUDestinationEditor.swift
  AUPresetStepperControl.swift
  TrackDestinationRuntimeViewModel.swift  # optional, owns preset readout polling and command closures

Sources/UI/TrackSource/Clip/
  ClipContentPreview.swift
  ClipContentEditModel.swift              # pure clip edit operations
  ClipStepInspectorSheet.swift
  ClipMacroSlotStrip.swift

Tests/SequencerAITests/Engine/
  EngineControllerTransportTests.swift
  EngineControllerApplyTests.swift
  EngineControllerSourceResolutionTests.swift
  EngineControllerDestinationTests.swift
  EngineControllerRoutingTests.swift
  EngineControllerRollingCaptureTests.swift
```

## Task 1 — Split `SequencerDocumentSession+Mutations.swift`

**Goal:** Mechanical split by existing `MARK` sections. No behaviour changes, and no widening of live-store mutations.

Create:

- `SequencerDocumentSession+MutationDispatch.swift`
- `SequencerDocumentSession+ClipMutations.swift`
- `SequencerDocumentSession+PhraseMutations.swift`
- `SequencerDocumentSession+PatternMutations.swift`
- `SequencerDocumentSession+MacroMutations.swift`
- `SequencerDocumentSession+DestinationMutations.swift`
- `SequencerDocumentSession+TrackMutations.swift`
- `SequencerDocumentSession+RouteMutations.swift`

Acceptance:

- All moved methods keep the same signatures.
- No new `exportToProject()` calls are introduced.
- Existing `exportToProject()` calls remain in the same semantic operations they served before the split.
- No call sites change except import/project registration if needed.
- Focused session tests pass.
- Original file is deleted or reduced to no more than a short overview if the compiler requires it.

## Task 2 — Split `PhraseModel.swift`

**Goal:** Move independent document value types into named files.

Create:

- `PhraseLayerDefinition.swift`
- `PhraseCell.swift`
- `PhraseCurveSampler.swift`
- `TrackPatternBank.swift`
- `TrackPatternSlot.swift`
- `TrackSourceMode.swift`
- `GeneratorKind.swift`
- `GeneratorPoolEntry.swift`
- `ClipPoolEntry.swift`
- `SourceRef.swift`

Keep `PhraseModel.swift` focused on `PhraseModel` only.

Acceptance:

- No type or method signatures change.
- Codable compatibility remains unchanged.
- Existing document/model tests pass.
- No source file in `Sources/Document/` exceeds 1000 lines.

## Task 3 — Split `EngineControllerTests.swift`

**Goal:** Make the test suite match runtime responsibility slices before changing `EngineController`.

Create focused test files:

- `EngineControllerTransportTests.swift`
- `EngineControllerApplyTests.swift`
- `EngineControllerSourceResolutionTests.swift`
- `EngineControllerDestinationTests.swift`
- `EngineControllerRoutingTests.swift`
- `EngineControllerRollingCaptureTests.swift`

Move shared fixtures into narrowly named helper files, for example:

- `EngineControllerTestDoubles.swift`
- `EngineControllerFixtureBuilders.swift`

Acceptance:

- Test names and assertions remain intact.
- No test file exceeds 1000 lines.
- Focused engine test suite passes.

## Task 4 — Split `EngineController.swift`

**Goal:** Reduce `EngineController.swift` to the app-facing facade and stored state, then move responsibility clusters into extension files.

Suggested splits:

- `EngineController+Transport.swift`
  - `start`, `stop`, `shutdown`, BPM/mode setters, transport string helper.
- `EngineController+Apply.swift`
  - `apply(documentModel:)`, `apply(playbackSnapshot:)`, delta dispatch, broad sync.
- `EngineController+Pipeline.swift`
  - pipeline shape, block construction, effective destination, audio output key.
- `EngineController+TickPreparation.swift`
  - `processTick`, `prepareTick`, snapshot tick resolution bridge.
- `EngineController+Routing.swift`
  - router dispatch, routed event flushing, MIDI route output management.
- `EngineController+Outputs.swift`
  - MIDI/audio/sample output sync, AU host lookup, preset bridge methods, mix writes.
- `EngineController+RollingCapture.swift`
  - rolling capture buffer types and save/captured clip APIs.

Acceptance:

- No runtime behaviour changes.
- Tick preparation still reads `PlaybackSnapshot` and snapshot-carried tracks, not `currentDocumentModel`.
- Snapshot application and delta dispatch preserve existing invalidation behavior.
- `EngineController.swift` is under 500 lines if practical, and definitely under 1000.
- Every new file has a clear responsibility name.
- `EngineController` tests pass.

## Task 5 — Extract UI Runtime Commands From `TrackDestinationEditor`

**Goal:** Keep `TrackDestinationEditor` rendering user intent, not directly managing AU host preparation, preset polling, state-blob writes, or parameter-tree reads.

This task must not route UI reads back through `Project` export. Runtime command helpers should accept the narrow IDs / descriptors / closures they need and should read resident store state through `SequencerDocumentSession` or `LiveSequencerStore`.

Introduce either:

- session methods such as:
  - `prepareDestinationRuntime(trackID:)`
  - `presetReadout(for:)`
  - `loadPreset(_:for:)`
  - `openAudioUnitWindow(for:)`
  - `parameterReadout(for:)`

or a small app-layer facade:

- `SequencerRuntimeCommands`

The facade may internally call `EngineController`, `AUWindowHost`, and session mutation methods. UI receives closures or a view model.

Acceptance:

- `TrackDestinationEditor` no longer calls:
  - `engineController.audioInstrumentHost(for:)`
  - `engineController.currentAudioUnit(for:)`
  - `engineController.loadPreset`
  - `engineController.presetReadout`
- The AU window open flow still captures and persists state blobs.
- Preset browser and preset stepper behavior remain unchanged.
- Macro slot picker still reads AU parameters through a session/app command, not by reaching into `AudioInstrumentHost`.
- Destination UI keeps reading from `session.store` / specific live-store helpers, not from `session.project` or `store.exportToProject()`.

## Task 6 — Remove Direct Sample Runtime Handle From UI

**Goal:** Stop passing `SamplePlaybackSink` into SwiftUI.

Replace `SamplerDestinationWidget(sampleEngine:)` with intent closures such as:

- `auditionSample(sampleID:settings:trackID:)`
- `setFilterSettings(settings:trackID:)`
- `setDestination(destination:trackID:)`

The implementation can live in `SequencerDocumentSession` or the runtime command facade.

Acceptance:

- `Sources/UI/` no longer references `SamplePlaybackSink`.
- Sampler audition and filter controls still work.
- Filter and sample edits keep using scoped runtime/session mutation paths; they must not fall back to broad document apply unless a destination kind change truly requires it.
- Existing sampler/filter tests pass.

## Task 7 — Extract Pure Clip Editing Helpers

**Goal:** Shrink `ClipContentPreview` and make edit behavior unit-testable.

The helper must operate on `ClipContent` / `ClipStep` values directly. It must not require `Project`, `LiveSequencerStore`, or snapshot compilation.

Create `ClipContentEditModel` or equivalent pure helper for:

- toggle lane at step
- resize note grid
- update lane chances
- update lane velocities
- compute note count / summaries if useful

Move `ClipStepInspectorSheet` and macro-slot strip into separate view files if the file still feels too dense.

Acceptance:

- `ClipContentPreview.swift` drops below 500 lines if practical.
- Pure edit helper has focused tests.
- Step toggles still publish clip-scoped changes through the existing session path.
- Existing step-grid UI behavior remains unchanged.

## Task 8 — Optional Evaluator Split

**Goal:** Only if generator/source work is imminent, split `GeneratedSourceEvaluator` into small pure evaluators.

Potential files:

- `GeneratedSourceEvaluator.swift` — public entry points
- `GeneratedTriggerEvaluator.swift`
- `GeneratedPitchEvaluator.swift`
- `ClipSourceResolver.swift`

Acceptance:

- Existing generator evaluator tests pass.
- No semantic change to seeded outputs.

## Task 9 — Audio Host Light Split

**Goal:** Keep audio-host churn low while extracting clearly pure helpers.

Move parameter descriptor walking to:

- `AUParameterDescriptor+Readout.swift`

Optionally move preset descriptor read/load support if it is still embedded in host code after Task 5.

Acceptance:

- `AudioInstrumentHost` still owns lifecycle, threading, AU instantiation, and note playback.
- Parameter readout tests pass.
- No new UI dependency enters `Audio/`.

## Test Plan

Run after each mechanical phase:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -quiet \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath /tmp/seqai-build \
  test
```

Focused suites to run earlier where possible:

- `SequencerAITests/EngineControllerTests` and split successors
- `SequencerAITests/SequencerDocumentSessionAuthorityTests`
- `SequencerAITests/SessionMacroSlotTests`
- `SequencerAITests/LiveSequencerStoreResidentStateTests`
- `SequencerAITests/UIReadsStoreDirectlyTests`
- `SequencerAITests/StepGridTapLatencyTests`
- `SequencerAITests/IncrementalCompileEquivalenceTests`
- `SequencerAITests/PlaybackInertSelectionTests`
- `SequencerAITests/PresetBrowserSheetViewModelTests`
- sampler/filter focused tests
- clip/grid focused tests

## Manual Smoke

- Open a document, press Play/Stop, change BPM and transport mode.
- Edit a clip step and verify immediate visual/audible response.
- Open an AU destination, browse presets, step presets, and confirm state persists after save/reopen.
- Assign and remove an AU macro slot.
- Switch a track to sampler destination, audition a sample, and adjust filter settings.
- Route a track to MIDI and verify endpoint/channel/note-offset controls still update playback.

## Traceability

| Concern | Task |
|---|---|
| Source/test file cap violations | 1, 2, 3, 4 |
| Engine runtime responsibilities mixed in one file | 4 |
| UI directly reaching into AU host/runtime details | 5 |
| UI directly holding sample engine sink | 6 |
| Clip editing logic buried in SwiftUI view | 7 |
| Live-store resident/performance architecture must not regress | 1, 4, 5, 6, 7 |
| Generated source evaluator density | 8 |
| Audio host mixed with pure parameter traversal | 9 |

## Recommendation

Execute Tasks 1 through 4 first. They are mostly mechanical and reduce review risk for the boundary cleanup.

Then execute Tasks 5 and 6 together as the real architectural cleanup. Those are the phases that answer the boundary question: UI may observe engine state and request user-intent actions, but AU/preset/sample runtime work should be mediated by App/session services rather than view code.
