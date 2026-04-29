# Step Sequencer — Existing State

Inspected on 2026-04-29.

---

## 1. Model Layer

### StepSequenceTrack (`Sources/Document/StepSequenceTrack.swift`)

The primary per-track model. Relevant fields:

- `stepPattern: [Bool]` — on/off bitmask for each step.
- `stepAccents: [Bool]` — a second bitmask used for the "accented" state (triggers a velocity boost or fill path).
- `velocity: Int` and `gateLength: Int` — track-global, not per-step.
- `macros: [TrackMacroBinding]` — up to 8 AU macro bindings per track.

There is **no per-step selection flag** anywhere on this struct. The three-state cycle (off → on → accented) is implemented as `cycleStep(at:)` (line 91). Clear-accents and accent-downbeats helpers exist but operate on the whole track, not on a selection.

### ClipContent (`Sources/Document/ClipContent.swift`)

The richer per-clip step model used by the note-grid and slice-trigger paths:

- `.noteGrid(lengthSteps:, steps: [ClipStep])` — each `ClipStep` contains a `main: ClipLane?` and `fill: ClipLane?`. A `ClipLane` holds `chance: Double` and `notes: [ClipStepNote]` (pitch, velocity, lengthSteps).
- `.sliceTriggers(stepPattern:, sliceIndexes:, stepModes:, stepParameters:)` — parallel arrays; `SliceTriggerStepParameters` carries per-step gain, pitch, startTrim, endTrim, pan, filter, attackMs, releaseMs, reverse, choke.
- `MacroLane` — a per-clip, per-binding array of `Double?` override values parallel to the clip's step count (line 434). A `nil` entry defers to the phrase-layer default.

Per-step values exist at the clip level for: velocity, chance, slice index, slice mode, and per-step macro overrides. There is no per-step selection state anywhere in the persistence model.

### PhraseModel / PhraseLayerDefinition (`Sources/Document/PhraseModel.swift`)

Operates at a coarser granularity (phrase × track × layer). `PhraseCell` can be `.steps([PhraseCellValue])` which gives one value per step in the phrase, but this is for phrase-scoped layers (pattern, mute, volume-like macros), not individual clip step on/off.

`PhraseLayerValueType` maps to three editor kinds:
- `.boolean` → `toggleBoolean`
- `.scalar` → `continuousScalar`
- `.patternIndex` → `indexedChoice`

This trinity directly maps to the three control types described in Story 6 (toggle, value bar, option picker). The model type-system already classifies layers correctly; the gap is entirely presentation-side.

---

## 2. Engine / Playback

`LiveSequencerStore+Accessors.swift` exposes `transportTickIndex` via `EngineController`. Views derive the playing step index by computing `tickIndex % stepCount`. This is the only runtime "playing" signal visible to the UI.

There is no engine-side concept of "selected step" or "batch pending edit."

---

## 3. UI Structure — Three Active Step Cell Types

### 3a. StepGridCell inside StepGridView
`Sources/UI/StepGridView.swift`

The general-purpose cell used in the clip editor for `.noteGrid` trigger and `.sliceTriggers` content:

- State: `StepVisualState` — three values: `.off`, `.on`, `.accented` (line 5).
- Playing indicator: a separate green border overlay keyed on `isPlaying: Bool` (line 90–92).
- Selection state: **none**. The cell has no selected visual state.
- Interaction: single tap → `action()`. Context menu and accessibility action → `inspectAction?()` (double-tap equivalent, called "Inspect Step").
- Value display: symbol (`circle`, `circle.fill`, `bolt.fill`) and an edge-glow capsule. No numeric value is shown inside the cell; value is implicit in the `accented` state.
- Layer awareness: **none**. The caller converts the clip model to `[StepVisualState]` before passing to `StepGridView`. The grid knows nothing about layers.

Used by `ClipContentPreview` (lines 141, 235) in two contexts:
  - `.sliceTriggers` path: plain toggle, stepPattern → on/off (line 141).
  - `.noteGrid` trigger layer: on/off + accented from ClipLane presence (line 235).

### 3b. MacroLaneCell inside ClipMacroLaneEditor
`Sources/UI/Track/ClipMacroLaneEditor.swift` (line 196)

A distinct small cell (28×28 pt) used in the macro lane rows below the clip editor:

- Shows a numeric override value or a muted fallback.
- Tap → opens a `ScalarCellScrubber` sheet (slider, no inline editing).
- Long press → clears the override (sets to `nil`).
- No playing state, no selection state, no boolean/option-picker variants.
- This is a **separate primitive** from `StepGridCell`; it does not share any visual language with it.

### 3c. SliceStepStrip cells
`Sources/UI/Slicer/SliceTrackEditingControls.swift` (line 33)

Used exclusively inside `SliceTrackWorkspaceView` for the `.sliceTriggers` step strip:

- State: `.off` or `.on(sliceIndex:, mode:)` — shows a slice label and run-mode label.
- Playing indicator: green border overlay (same mechanism as `StepGridCell`).
- Selection indicator: amber border when `selectedStepIndex == absoluteIndex` (line 81). This is a **single-step selection** — not multi-step.
- Interaction: tap → `onTap(absoluteIndex)`. No right-click or context menu.
- Layer awareness: **none** — caller owns layer switching; there are separate `ClipEditorMode` buttons (Steps / Velocity / Chance) rendered outside the cell.

### 3d. GridEditor
`Sources/UI/TrackSource/Generator/GridEditor.swift`

A bar-chart style step editor used for velocity and chance layers (and macro lane rows) inside `ClipContentPreview`. Each column is a height-proportional bar plus a step number label:

- No playing state.
- No selection state.
- Interaction: tap → cycles through `allowedValues`. Long press → `onLongPress?` (clear). Context menu offers "Inspect Step" and "Clear Step".
- Value is shown as bar height, not an inline number.

---

## 4. Views Containing a Step Sequencer

| View | File | Primitive Used | Layer Selection |
|---|---|---|---|
| Clip Editor (note grid, trigger) | `ClipContentPreview.swift` | `StepGridView` | External tab strip (`ClipEditorMode`) |
| Clip Editor (note grid, velocity) | `ClipContentPreview.swift` | `GridEditor` | Same external tab strip |
| Clip Editor (note grid, chance) | `ClipContentPreview.swift` | `GridEditor` | Same external tab strip |
| Clip Editor (note grid, macro) | `ClipContentPreview.swift` | `GridEditor` | Same external tab strip |
| Clip Editor (slice triggers, fallback) | `ClipContentPreview.swift` | `StepGridView` | n/a |
| Slice Track workspace | `SliceTrackWorkspaceView.swift` | `SliceStepStrip` | External layer buttons |
| Macro lane rows | `ClipMacroLaneEditor.swift` | `MacroLaneCell` | n/a (always scalar) |

The `TrackWorkspaceView` (non-slice) does not render a step grid at all — it delegates to `TrackSourceEditorView` which in turn renders `ClipContentPreview`. The phrase matrix (`PhraseWorkspaceView`) does not show individual step cells; it shows one cell per (phrase × track × layer) summary.

---

## 5. Divergence from User Stories

### Story 1 — Unified Step Cell Primitive

**Gap: presentation-side.**

Three visually and structurally different cell types exist: `StepGridCell`, `MacroLaneCell`, and `SliceStepStrip` cells. `GridEditor` is a fourth distinct component. They do not share a common struct or visual language. A musician moving between the clip editor trigger view and the clip editor velocity view sees completely different cell shapes (rounded tile vs. bar chart).

### Story 2 — Step State Legibility (playing / selected / active / value)

**Gap: presentation-side and model-side.**

- Playing: supported in `StepGridCell` and `SliceStepStrip` via a green border. **Not** present in `GridEditor` or `MacroLaneCell`.
- Selected: supported only in `SliceStepStrip` (single step, amber border). Not present in `StepGridCell` or `GridEditor` at all.
- Active (on/off): supported in `StepGridCell` (fill color + symbol) and `SliceStepStrip` (fill color). Not shown in `GridEditor` (bar height encodes value, not on/off).
- Value: shown as bar height in `GridEditor` only. `StepGridCell` shows on/accented but no numeric value. Combining all four states simultaneously into a single cell is not implemented anywhere.

### Story 3 — Right-Click Step Selection and Layer Editing

**Gap: workflow and presentation-side.**

`StepGridCell` exposes a `.contextMenu` with a single "Inspect Step" action (line 126) which triggers an `inspectAction` callback. This opens `ClipStepInspectorSheet` — a sheet that edits one step's notes in isolation. It does not select the step or reveal macro/layer cells above it. There is no "selected" visual state on `StepGridCell`.

### Story 4 — Multi-Step Selection

**Gap: model-side and presentation-side.**

No multi-step selection state exists anywhere in the model or session layer. `SliceStepStrip` tracks a single `selectedStepIndex: Int`. No multi-select gesture, no selection set, no batch write path.

### Story 5 — Contextual Batch Action Bar

**Gap: workflow and presentation-side.**

No batch action bar exists. Clear, copy, and paste are not implemented at the step level in any view. `StepSequenceTrack` has `clearAccents()` as a track-wide operation but no step-range version. There is no copy-paste infrastructure for step ranges.

### Story 6 — Layer-Driven Cell Control Type

**Gap: presentation-side.**

The model already distinguishes `PhraseLayerValueType` (.boolean / .scalar / .patternIndex) and `ClipEditorMode` (.trigger / .velocity / .probability), and `ClipEditorLayer` (.mode / .macro). The clip editor does switch cell type when the layer tab changes (StepGridView ↔ GridEditor). However:
- The switch is implemented by swapping the entire component (StepGridView vs GridEditor), which changes cell geometry and breaks spatial alignment.
- The macro layer also uses GridEditor (same as velocity/chance), losing the on/off semantic for boolean macros.
- The concept is not implemented in `SliceStepStrip` at all (layer tab exists as a disabled stub for Velocity/Chance, lines 243–245 in `SliceTrackWorkspaceView.swift`).

---

## 6. Architecture Constraints

- `StepGridView` and `StepGridCell` are in the same file and `StepGridCell` is `private`. Any new unified cell type needs to either extend this file or the private struct needs to be made internal/public.
- `StepVisualState` is a flat enum with three cases. Adding "selected" as a fourth state would be a breaking change to all callers. A separate `isSelected: Bool` parameter on the cell (as `SliceStepStrip` does) is the safer path.
- Selection state is view-local `@State` in `SliceTrackWorkspaceView` (`selectedStepIndex: Int`, line 12). To support cross-view unified selection, a selection model would need to live in the session or a dedicated view model, not local `@State`.
- `MacroLane` overrides are stored at the `ClipPoolEntry` level, not at `StepSequenceTrack`. Any batch write to macro overrides for selected steps must operate on `ClipPoolEntry.macroLanes`, going through `session.mutateClip`.
- `SequencerDocumentSession` mutations are actor-isolated. Batch operations (set velocity on N steps) need to be a single mutation closure, not N separate mutations, to stay within the 16ms tap-to-invalidation budget measured in `StepGridTapLatencyTests`.
- The phrase-level `.steps([PhraseCellValue])` mode provides per-step phrase values but at phrase granularity, not clip granularity. Step-level editing in the clip editor and step-level editing in the phrase editor are separate storage layers; unifying the UX requires clarity on which layer a given step edit targets.

---

## 7. Existing Tests

### Directly relevant
- `Tests/SequencerAITests/Performance/StepGridTapLatencyTests.swift` — four tests measuring tap-to-invalidation latency, per-clip isolation, body evaluation count, and absence of `exportToProject` on tap. These establish a 16ms performance budget for step mutations on a reference project (8 tracks, 4 patterns each, 32-step clips, 4 phrases).

### Indirectly relevant
- `Tests/SequencerAITests/Document/ClipContentMacroLaneTests.swift` — MacroLane syncing.
- `Tests/SequencerAITests/Document/ClipContentSliceTriggerModeTests.swift` — slice trigger step mode encoding.
- `Tests/SequencerAITests/Document/StepSequenceTrackFilterDefaultTests.swift` — StepSequenceTrack defaults.
- `Tests/SequencerAITests/UI/ObservationGranularityTests.swift` — dict-level observation tracking (known ceiling for cross-clip invalidation).

### Notable gaps
- No tests for `StepGridView` or `StepGridCell` rendering or interaction.
- No tests for `SliceStepStrip` selection behaviour.
- No tests for `GridEditor` cycling logic beyond what is implicit in integration tests.
- No tests for step-range copy/paste (does not exist yet).
- No tests for multi-step selection state management (does not exist yet).

---

## 8. Open Questions Surface From Inspection

1. The `PhraseCell.steps([PhraseCellValue])` mode and the `ClipContent.noteGrid` step array both have per-step data but for different concerns. Story 3 says "macro/layer cells above the step column become editable" — which storage layer does that write to? Phrase-level `.steps` or clip-level `MacroLane`?
2. `SliceStepStrip` has a Velocity and Chance layer tab that is disabled ("stub, currently `isEnabled: false`"). Is that intentional until this feature, or is it a separate backlog item?
3. Copy/paste semantics for Story 5 are flagged as an open question in user-stories.md: does paste write all layers or only the active layer? The model supports both paths but the answer determines data structure for a clipboard.
