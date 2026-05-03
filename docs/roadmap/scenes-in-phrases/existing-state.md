# Scenes In Phrases — Existing State

Inspected: 2026-05-03

---

## 1. Current Model Split

The codebase already has two strong but separate authored-state systems:

- **Phrase-authored track state** lives in `Project.phrases` as `PhraseModel` plus `PhraseLayerDefinition` cells. This is what the Phrase Matrix edits today. See [[code:Sources/Document/Project.swift:4]], [[code:Sources/Document/PhraseModel.swift:3]], and [[wiki:document-model]].
- **Scene/crossfader state** lives in `Project.masterBus` as `MasterBusState`, `MasterBusScene`, and `MasterBusABSelection`. This is what Scene Perform edits today. See [[code:Sources/Document/MasterBus.swift:3]] and [[wiki:information-architecture-ux]].

Those systems do **not** currently join anywhere. A phrase does not point at scene A/B slots, and the master bus does not carry phrase-scoped automation.

### PhraseModel

`PhraseModel` stores:

- `id`
- `name`
- `lengthBars`
- `stepsPerBar`
- `cells: [PhraseCellAssignment]`

Each cell is keyed by `(trackID, layerID)`. The built-in layer set is track-oriented:

- pattern
- mute
- volume
- transpose
- intensity
- density
- tension
- register
- variance
- brightness
- fill
- swing

There is no built-in layer for:

- scene A selection
- scene B selection
- crossfader mode
- phrase-level scene summary

See [[code:Sources/Document/PhraseModel.swift:3]] and [[code:Sources/Document/PhraseModel.swift:122]].

### MasterBusState

`MasterBusState` already models the live scene system:

- `scenes: [MasterBusScene]`
- `activeSceneID`
- `abSelection: MasterBusABSelection?`

`MasterBusABSelection` stores:

- `sceneAID: UUID`
- `sceneBID: UUID`
- `crossfader: Double` in `0...1`

This is persisted, normalized, and round-tripped in the document, but it is **global project state**, not phrase-owned state. See [[code:Sources/Document/MasterBus.swift:3]] and [[code:Sources/Document/MasterBus.swift:685]].

### Important data-model consequence

The phrase system can already store **scalar values per bar** (`PhraseCell.bars`) and resolve them deterministically across playback steps. That shape fits Story 3's bar-by-bar crossfader curve. But the scene system identifies scenes by **UUID**, and phrase cells currently only encode `bool`, `scalar`, or `index`-style values. There is no existing phrase-layer target that can point at `MasterBusScene.id`.

This means:

- per-bar crossfader values are structurally close to the existing phrase model;
- phrase-owned scene A/B selection is **not** close to an existing layer target and would need new modeling.

---

## 2. Playback And Runtime Reality

### PlaybackSnapshot only carries phrase/track playback data

`PlaybackSnapshot` contains:

- `selectedPhraseID`
- track order and programs
- clip buffers
- `phraseBuffersByID`

It does **not** include:

- `MasterBusState`
- scene A/B IDs per phrase
- crossfader mode per phrase
- any phrase-triggered master-bus event stream

See [[code:Sources/Engine/PlaybackSnapshot.swift:10]].

### SequencerSnapshotCompiler compiles phrase data, not scene data

`SequencerSnapshotCompiler` compiles `PhrasePlaybackBuffer` by resolving track-oriented phrase layers into:

- pattern slot index
- mute
- fill
- macro values

No part of compilation reads `Project.masterBus` or writes master-bus automation into the snapshot. See [[code:Sources/Engine/SequencerSnapshotCompiler.swift:12]] and [[code:Sources/Engine/PhrasePlaybackBuffer.swift:3]].

### Master bus updates travel on a separate path

`SequencerDocumentSession` treats phrase edits and master-bus edits as different mutation families:

- `setPhraseCell(...)` mutates a phrase and republishes playback snapshot data.
- `setMasterABMode(...)` and `setMasterCrossfader(...)` mutate `MasterBusState` and dispatch a scoped runtime master-bus update.

There is no existing mutation that says "when playback enters phrase X, recall these scene slots and this crossfader state." See [[code:Sources/App/SequencerDocumentSession+Mutations.swift:354]] and [[code:Sources/App/SequencerDocumentSession+Mutations.swift:360]].

### Scene Perform overlay is intentionally live and non-persisted

`EngineController` owns `masterBusPerformanceOverlay`, which carries:

- per-scene macro overrides
- `crossfaderOverride`

This overlay is meant for live performance gestures. It shadows the authored document state until the user explicitly saves. See [[code:Sources/Engine/EngineController.swift:476]] and [[code:Sources/Document/MasterBus.swift:631]].

That is the opposite of this roadmap item's goal. Stories 1 to 3 want phrase-authored, repeatable recall. The current perform overlay is transient and user-driven.

### Existing phrase playback awareness stops at UI highlighting

`PhraseWorkspaceView` and `LiveWorkspaceView` already derive a `playbackPhraseIndex` by walking phrase bar lengths against `engineController.transportTickIndex`. That logic is used to understand which phrase is currently playing, but it does not trigger any master-bus state transition. See [[code:Sources/UI/PhraseWorkspaceView.swift:36]] and [[code:Sources/UI/LiveWorkspaceView.swift:46]].

---

## 3. Current UI Structure

### Phrase Matrix is track/layer editing only

`PhraseWorkspaceView` is a single matrix:

- phrase rows
- track columns
- one selected layer at a time
- track pagination

The top bar lets the user cycle layers and track pages. There is no mode toggle for `Tracks` versus `Scenes`, and no phrase-row summary for scene A / crossfader / scene B. See [[code:Sources/UI/PhraseWorkspaceView.swift:3]] and [[wiki:information-architecture-ux]].

### Scenes are edited in a separate workspace

`ScenesWorkspaceView` has its own segmented mode switch:

- `.browseEdit`
- `.perform`

Scene slot assignment and the crossfader live there, not in the phrase matrix. `ScenesWorkspaceView+Perform.swift` renders:

- a global crossfader
- Slot A scene card
- Slot B scene card
- slot-picker sheets that directly rewrite `MasterBusABSelection`

See [[code:Sources/UI/Mixer/ScenesWorkspaceView.swift:26]] and [[code:Sources/UI/Mixer/ScenesWorkspaceView+Perform.swift:3]].

### Information architecture already treats these as different homes

The UX guidance in [[wiki:information-architecture-ux]] is explicit:

- Phrase Matrix owns phrase rows, track columns, and phrase-level authoring.
- Scene Perform owns scene A/B selection and crossfader state.

This roadmap item is therefore not a small view tweak. It intentionally asks those two homes to meet at a new boundary: phrase-authored scene behavior inside the phrase workspace.

---

## 4. Story-By-Story Gap Analysis

### Story 1 — Assign scene slots per phrase

**What exists**

- Global A/B slots already exist in `MasterBusABSelection`.
- Scene library and slot pickers already exist in `ScenesWorkspaceView`.

**What is missing**

- No phrase field stores scene A or scene B.
- No phrase layer target can reference a scene UUID.
- No phrase row shows or edits scene assignments.

**Gap type:** model + UI + runtime wiring.

### Story 2 — Set one crossfader value for a full phrase

**What exists**

- A persisted crossfader value already exists as `MasterBusABSelection.crossfader`.
- Phrase cells already support a single scalar value for an entire phrase.

**What is missing**

- The crossfader value is global, not phrase-owned.
- No phrase layer targets the master-bus crossfader.
- Playback does not recall a phrase-authored crossfader on phrase entry.

**Gap type:** mainly model ownership + runtime wiring.

### Story 3 — Author per-bar scene blend changes

**What exists**

- `PhraseModel.resolvedValue(...)` already supports `.bars` values, indexed by `stepsPerBar`.
- Phrase timing (`lengthBars`, `stepsPerBar`) already gives the right bar-alignment primitive.

**What is missing**

- No scene-crossfader phrase layer exists.
- No runtime path applies bar-by-bar crossfader changes to the master bus as transport advances.
- No UI surface in the phrase matrix shows a per-bar scene-automation cell.

**Gap type:** runtime + UI, with partial model reuse available.

### Story 4 — Toggle the phrase view between Tracks and Scenes

**What exists**

- Phrase Matrix already has a strong row/column scaffold.
- ScenesWorkspace already has scene-specific controls and terminology.

**What is missing**

- No `Tracks | Scenes` toggle in `PhraseWorkspaceView`.
- No alternate scene-oriented column set.
- No shared component between the two workspaces for scene slot display or crossfader summaries.

**Gap type:** UI / information architecture.

### Story 5 — Read scene intent quickly from the phrase row

**What exists**

- Scene names are available from `MasterBusScene.name`.
- Crossfader values are already rendered in Scene Perform as a percentage.

**What is missing**

- Phrase rows have no scene summary at all.
- Adjacent phrase comparison is only possible for track-layer cells today.
- There is no compact representation for "static value" versus "per-bar automation" in the phrase matrix.

**Gap type:** UI, plus a small representation/model contract for automation mode.

---

## 5. Architecture Constraints

### 1. Phrase layers currently target track playback, not master-bus state

The phrase compiler writes per-track playback buffers. A scene-in-phrases feature either needs:

- new phrase-layer targets that can drive master-bus state, or
- a parallel phrase-owned scene structure outside the existing layer system.

Reusing the current phrase layer pipeline for crossfader values is plausible. Reusing it for scene UUID selection is much less straightforward.

### 2. Scene IDs are UUID-based, not stable ordinal slots

`MasterBusScene` identity is `UUID`. That is good for persistence, but it means any phrase-authored scene reference must decide whether it stores:

- the actual scene UUIDs, or
- a transient positional index into the current scene list

The current codebase strongly favors UUID identity. A position-based shortcut would be fragile when scenes are duplicated, removed, or reordered later.

### 3. Phrase entry has no existing "recall master bus state" hook

The transport loop already knows which phrase is playing, but no engine path converts phrase boundaries into master-bus document updates or performance-overlay changes. This hook would need to be introduced carefully so playback truth stays deterministic and UI state does not fork from audio state.

### 4. Live overlay and authored phrase state must stay distinct

The current scene overlay is intentionally ephemeral. Phrase-authored scene recall should not accidentally be implemented by mutating the live overlay and calling it "saved," or by overwriting the global authored A/B state in a way that destroys the user's live Scene Perform context.

---

## 6. Tests And Coverage

### What is covered today

- `MasterBusStateTests` cover scene normalization, A/B selection normalization, and crossfader persistence. See [[code:Tests/SequencerAITests/Document/MasterBusStateTests.swift:4]].
- `SequencerDocumentSessionMasterBusTests` cover scoped master-bus mutations and live overlay save-back. See [[code:Tests/SequencerAITests/App/SequencerDocumentSessionMasterBusTests.swift:6]].
- `MasterBusHostTests` cover equal-power crossfade math and live crossfader override behavior. See [[code:Tests/SequencerAITests/Audio/MasterBusHostTests.swift:5]].
- `SequencerSnapshotCompilerSemanticsTests` and related engine tests cover phrase-buffer semantics for track playback layers. See [[code:Tests/SequencerAITests/Engine/SequencerSnapshotCompilerSemanticsTests.swift:1]].

### What is missing

- No tests for phrase-owned scene A/B assignment.
- No tests for phrase-driven crossfader recall at phrase boundaries.
- No tests for per-bar crossfader automation.
- No tests for a `Tracks | Scenes` mode switch in the phrase workspace.
- No tests for any compact phrase-row scene summary.

---

## 7. Bottom Line

The repo already has:

- a solid phrase timing/value system;
- a solid scene/crossfader model;
- a dedicated scene-perform UI;
- tests for both phrase playback layers and master-bus behavior separately.

What it does **not** have is the bridge between them.

The cheapest reuse path appears to be:

- reuse phrase timing and per-bar scalar machinery for crossfader automation;
- keep scene references UUID-based and add a new phrase-owned scene-assignment model;
- add a new scene-editing mode to `PhraseWorkspaceView` rather than trying to force Scene Perform itself into phrase authoring.

That makes this feature more than a UI pass but less than a brand-new subsystem: the building blocks exist, yet the phrase/scene boundary is currently unimplemented.
