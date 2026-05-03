# Existing State

## Summary

The codebase already has two strong halves of this feature, but they do not meet in the middle yet.

- The phrase system already supports phrase-owned values with `single`, `bars`, `steps`, and `curve` modes, and it compiles those values into playback-time buffers.
- The scene system already supports a project-wide A/B scene selection plus a live crossfader in the Scenes workspace.

What is missing is the bridge between them: there is no phrase-owned scene state, no scene-aware phrase matrix mode, no phrase value type for scene references, and no playback/compiler path that can drive master-bus scene selection from phrase progression.

## Existing Support

### Phrase data model and timing

- `Project` already persists both `phrases` and a global `masterBus` side by side, but they are independent top-level domains: `[[code:Sources/Document/Project.swift:16]]`, `[[code:Sources/Document/Project.swift:20]]`.
- `PhraseModel` already stores phrase-local timing and authored cell data through `lengthBars`, `stepsPerBar`, and `cells`: `[[code:Sources/Document/PhraseModel.swift:6]]`, `[[code:Sources/Document/PhraseModel.swift:8]]`.
- Phrase cells already support multiple authoring modes:
  - one value for the whole phrase via `.single`
  - one value per bar via `.bars`
  - one value per step via `.steps`
  - scalar automation via `.curve`
  References: `[[code:Sources/Document/PhraseModel.swift:365]]`, `[[code:Sources/Document/PhraseModel.swift:387]]`.
- Phrase resolution already understands per-bar and per-step playback lookup through `resolvedValue(for:trackID:stepIndex:)`: `[[code:Sources/Document/PhraseModel.swift:82]]`.

This is the strongest existing foundation for story 2 and story 3. The app already knows how to store phrase-wide and per-bar authored values; it just only does so for track-layer data today.

### Phrase matrix UI

- `PhraseWorkspaceView` is the current phrase editor and presents a single `"Phrase Matrix"` surface: `[[code:Sources/UI/PhraseWorkspaceView.swift:68]]`.
- The workspace is built around a selected phrase layer, not around multiple phrase modes. The top bar cycles through layers and pages tracks, but there is no `Tracks / Scenes` mode switch anywhere in the view state or layout: `[[code:Sources/UI/PhraseWorkspaceView.swift:8]]`, `[[code:Sources/UI/PhraseWorkspaceView.swift:113]]`.
- The current matrix is track-first:
  - rows are phrases
  - visible columns are tracks
  - the active interpretation comes from `selectedLayer`
  References: `[[code:Sources/UI/PhraseWorkspaceView.swift:18]]`, `[[code:Sources/UI/PhraseWorkspaceView.swift:24]]`, `[[code:Sources/UI/PhraseWorkspaceView.swift:256]]`.
- Phrase cell editing already routes through `setPhraseCell` and phrase selection changes, so there is an established mutation path for phrase-owned authored state: `[[code:Sources/UI/PhraseWorkspaceView.swift:225]]`, `[[code:Sources/App/SequencerDocumentSession+Mutations.swift:466]]`.

### Current phrase-layer types

- Built-in phrase layers today are all track-oriented: pattern, mute, and macro-style scalar/boolean values like volume, transpose, fill, and swing: `[[code:Sources/Document/PhraseModel.swift:227]]`.
- The only built-in indexed choice is the pattern layer (`.patternIndex`): `[[code:Sources/Document/PhraseModel.swift:229]]`, `[[code:Sources/Document/PhraseModel.swift:347]]`.
- `PhraseLayerTarget` has cases for pattern selection, mute, macro rows, block params, voice-route overrides, and per-track macro params. It has no case for scene A, scene B, or phrase-owned crossfader behavior: `[[code:Sources/Document/PhraseModel.swift:347]]`.
- `PhraseCellValue` only supports `.bool`, `.scalar`, and `.index`: `[[code:Sources/Document/PhraseModel.swift:419]]`.

This means the phrase engine can already represent a crossfader-like scalar, but it cannot represent a stable scene reference without introducing either a new value type or a new normalization strategy for scene identity.

### Playback compilation

- Phrase-authored data is compiled into `PhrasePlaybackBuffer`, which currently carries exactly four track-scoped outputs:
  - `patternSlotIndex`
  - `mute`
  - `fillEnabled`
  - `macroValues`
  References: `[[code:Sources/Engine/PhrasePlaybackBuffer.swift:3]]`, `[[code:Sources/Engine/PhrasePlaybackBuffer.swift:10]]`.
- `SequencerSnapshotCompiler.compilePhraseBuffer` resolves phrase state only into those four outputs: `[[code:Sources/Engine/SequencerSnapshotCompiler.swift:291]]`, `[[code:Sources/Engine/SequencerSnapshotCompiler.swift:317]]`, `[[code:Sources/Engine/SequencerSnapshotCompiler.swift:334]]`, `[[code:Sources/Engine/SequencerSnapshotCompiler.swift:343]]`, `[[code:Sources/Engine/SequencerSnapshotCompiler.swift:352]]`.
- The live store also treats `masterBus` as a separate resident field from phrases and phrase order: `[[code:Sources/Engine/LiveSequencerStore.swift:107]]`, `[[code:Sources/Engine/LiveSequencerStore.swift:116]]`, `[[code:Sources/Engine/LiveSequencerStore.swift:131]]`.

So phrase changes already trigger a snapshot/compiler path, but that path does not emit any scene-related playback intent.

### Existing scene system

- `MasterBusState` already persists the project-wide scene library plus a global A/B selection with one persisted crossfader value: `[[code:Sources/Document/MasterBus.swift:3]]`, `[[code:Sources/Document/MasterBus.swift:6]]`, `[[code:Sources/Document/MasterBus.swift:682]]`.
- `MasterBusPerformanceOverlayState` already adds a non-persisted live `crossfaderOverride` on top of authored state: `[[code:Sources/Document/MasterBus.swift:631]]`.
- `ScenesWorkspaceView` already has a dedicated scene workspace with `browseEdit` and `perform` modes, completely separate from the phrase workspace: `[[code:Sources/UI/Mixer/ScenesWorkspaceView.swift:32]]`, `[[code:Sources/UI/Mixer/ScenesWorkspaceView.swift:69]]`.
- The current perform UI already exposes:
  - slot A / slot B selection
  - a live crossfader
  - scene macro overrides
  References: `[[code:Sources/UI/Mixer/ScenesWorkspaceView+Perform.swift:5]]`, `[[code:Sources/UI/Mixer/ScenesWorkspaceView+Perform.swift:28]]`, `[[code:Sources/UI/Mixer/ScenesWorkspaceView+Perform.swift:74]]`.

This is important for scope: the product already distinguishes live scene performance from phrase authoring. `Scenes In Phrases` should reuse the same scene concept, but it should not collapse phrase authoring into the existing perform pane.

## Divergence From Target UX

### 1. No `Tracks / Scenes` phrase-matrix mode

- The current phrase workspace exposes only one matrix concept, driven by selected layer and track paging: `[[code:Sources/UI/PhraseWorkspaceView.swift:113]]`.
- There is no state for a second phrase-matrix mode and no three-column layout for `A / crossfader / B`.

### 2. No phrase-owned scene A / scene B assignments

- Phrase state today is stored per `(trackID, layerID)` cell assignment: `[[code:Sources/Document/PhraseModel.swift:359]]`.
- There is no phrase-scoped field for `sceneAID` or `sceneBID`, and no `PhraseLayerTarget` that points at master-bus scene slots: `[[code:Sources/Document/PhraseModel.swift:347]]`.
- The only existing A/B slot assignment lives globally on `MasterBusABSelection`, not on each phrase: `[[code:Sources/Document/MasterBus.swift:682]]`.

### 3. No phrase-authored crossfader stream

- A static or per-bar crossfader could conceptually fit the existing scalar phrase-cell machinery, but there is currently no layer target that would make such a scalar mean "master-bus crossfader for this phrase": `[[code:Sources/Document/PhraseModel.swift:319]]`, `[[code:Sources/Document/PhraseModel.swift:347]]`.
- The only current crossfader write paths are live/global scene APIs in the scene workspace or session master-bus mutations: `[[code:Sources/UI/Mixer/ScenesWorkspaceView+Perform.swift:35]]`, `[[code:Sources/App/SequencerDocumentSession+Mutations.swift:243]]`, `[[code:Sources/App/SequencerDocumentSession+Mutations.swift:354]]`.

### 4. No playback path from phrase progression into master-bus scenes

- Phrase compilation produces track playback buffers only; nothing in `PhrasePlaybackBuffer` or `SequencerSnapshotCompiler` describes scene-slot changes or phrase-authored crossfader playback: `[[code:Sources/Engine/PhrasePlaybackBuffer.swift:3]]`, `[[code:Sources/Engine/SequencerSnapshotCompiler.swift:291]]`.
- `selectedPhraseID` exists, but switching or advancing phrases currently affects phrase buffer lookup, not scene A/B selection on the master bus: `[[code:Sources/Engine/SequencerSnapshotCompiler.swift:25]]`, `[[code:Sources/Engine/LiveSequencerStore.swift:138]]`.

### 5. No phrase-row summary for scene intent

- Current phrase previews and tests focus on pattern, mute, and scalar track-layer renderings: `[[code:Tests/SequencerAITests/PhraseCellPreviewTests.swift:19]]`, `[[code:Tests/SequencerAITests/PhraseCellPreviewTests.swift:28]]`, `[[code:Tests/SequencerAITests/PhraseCellPreviewTests.swift:42]]`, `[[code:Tests/SequencerAITests/PhraseCellPreviewTests.swift:81]]`.
- There is no existing row preview language for "Scene A / blend / Scene B" in the phrase matrix.

## Model And Architecture Gaps

### Scene identity does not fit the current phrase value model

The current phrase value model is numeric/boolean only: `[[code:Sources/Document/PhraseModel.swift:419]]`. That is enough for:

- crossfader amount as a scalar
- mode toggles as booleans
- pattern-slot indexes as small integers

It is not enough for durable scene references, because scenes are identified by `UUID` in `MasterBusState`, not by stable dense indexes: `[[code:Sources/Document/MasterBus.swift:4]]`, `[[code:Sources/Document/MasterBus.swift:36]]`.

That leaves an architectural choice for later PM/spec work:

- add a new phrase value kind for scene references, or
- introduce a scene-index layer with explicit normalization and migration rules when scenes are added, removed, or reordered.

### Phrase state is track-scoped, but scene assignment is phrase-scoped

`PhraseCellAssignment` is keyed by `(trackID, layerID)`: `[[code:Sources/Document/PhraseModel.swift:359]]`. The requested scene mode is different:

- scene A and scene B belong to the phrase row as a whole
- they are not track-specific values

That mismatch means the current storage shape is awkward for `Scenes In Phrases`. Reusing the existing phrase cell table as-is would force fake track ownership for data that is conceptually phrase-global.

### Phrase playback buffers are track-oriented only

`TrackPhrasePlaybackBuffer` currently models only per-track pattern/mute/fill/macro outputs: `[[code:Sources/Engine/PhrasePlaybackBuffer.swift:3]]`.

If this feature wants authored scenes to affect playback automatically, the playback layer needs a new phrase-global representation for:

- selected scene A
- selected scene B
- authored crossfader behavior

without conflating those with track playback state.

### The existing live scene overlay is runtime-only

`MasterBusPerformanceOverlayState.crossfaderOverride` is explicitly ephemeral live state: `[[code:Sources/Document/MasterBus.swift:631]]`. It is useful for live Scene Perform, but it is the wrong authority for authored phrase data because:

- it is not persisted as part of phrases
- it is not keyed by phrase
- it is cleared as a live overlay, not recalled as a phrase program

So the current live-scene implementation is reusable as UX precedent, not as the data model for phrase-authored scenes.

## Test Coverage

## Existing coverage

- Phrase-cell preview tests cover boolean, scalar, and pattern-index rendering behavior only: `[[code:Tests/SequencerAITests/PhraseCellPreviewTests.swift:19]]`, `[[code:Tests/SequencerAITests/PhraseCellPreviewTests.swift:56]]`, `[[code:Tests/SequencerAITests/PhraseCellPreviewTests.swift:81]]`.
- Incremental compiler tests verify that phrase-layer changes round-trip through the current phrase buffer model: `[[code:Tests/SequencerAITests/Engine/IncrementalCompileEquivalenceTests.swift:36]]`.
- Incremental selection tests verify that changing `selectedPhraseID` can reuse existing phrase buffers, which confirms the current system treats phrase selection as pointer-switching rather than as scene-program recompilation: `[[code:Tests/SequencerAITests/Engine/IncrementalCompileEquivalenceTests.swift:101]]`.
- Hot-path isolation tests verify that phrase-layer edits publish snapshots without broad engine reapply: `[[code:Tests/SequencerAITests/Engine/EngineHotPathIsolationTests.swift:87]]`.
- Master-bus tests already cover A/B normalization and crossfader behavior separately from phrase playback: `[[code:Tests/SequencerAITests/Document/MasterBusStateTests.swift:163]]`, `[[code:Tests/SequencerAITests/Audio/MasterBusHostTests.swift:82]]`.

## Missing coverage

- No tests cover phrase-owned scene references.
- No tests cover phrase-authored crossfader playback over bars.
- No tests cover a phrase workspace mode switch between track editing and scene editing.
- No tests cover any interaction between phrase progression and master-bus scene state.
- No tests cover how scene references should behave when scenes are deleted, duplicated, or reordered.

## Prototype And Spec Implications

The next roadmap stages should treat this feature as a join between two existing systems, not as a greenfield invention.

Prototype work should answer:

- how the phrase matrix switches between `Tracks` and `Scenes` without confusing the user about which data they are editing
- how a phrase row shows scene identity compactly when scene names vary in length
- whether the crossfader column in scene mode should support only whole-phrase and per-bar authoring in v1, even though the core phrase model also supports per-step and curve modes for scalars

Architecture/spec work should answer:

- whether phrase-authored scene A/B values are stored as UUID references or normalized scene indexes
- whether phrase-authored scene data lives in the existing phrase cell system or in a separate phrase-global scene payload
- how playback applies authored scene changes at phrase boundaries without fighting the live Scene Perform overlay

## Bottom Line

The codebase is ready for this feature at the UX and planning level, but not yet at the data-contract level.

- The phrase editor already knows how to author values over phrase time.
- The scene system already knows how to store and perform A/B scenes.
- The missing work is the integration contract that says how a phrase owns scene A, scene B, and crossfader behavior, and how that authored state flows into playback and the matrix UI.
