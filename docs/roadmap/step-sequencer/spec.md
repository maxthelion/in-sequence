---
feature: step-sequencer
created: 2026-04-30
status: draft
based_on:
  - docs/roadmap/step-sequencer/user-stories.md
  - docs/roadmap/step-sequencer/existing-state.md
  - docs/roadmap/step-sequencer/ux-review.md
  - docs/roadmap/step-sequencer/architecture.md
  - docs/roadmap/step-sequencer/architecture-review.md
  - docs/roadmap/step-sequencer/prototypes/variant-d-rotary-layer-row.html
  - docs/roadmap/step-sequencer/prototypes/variant-c-in-cell-drag.html
---

# Step Sequencer — Specification

## Overview

This feature replaces the four structurally distinct step-cell primitives
(`StepGridCell`, `MacroLaneCell`, `SliceStepStrip` cell, `GridEditor` column)
with a single `UnifiedStepCell` primitive that supports all track types and all
interaction modes: toggle, in-cell value drag, multi-step selection, rotary-row
batch editing, and copy/paste. The selected UX direction is **Variant D —
Rotary Layer Row**: when steps are selected, the layer-tab row transforms into
a row of arc-dial rotary controls, one per editable layer, that write to all
selected steps simultaneously in a single batch mutation.

---

## 1. Product Direction Summary

The five failing areas identified in `existing-state.md` map to five product
requirements:

| Existing gap | Requirement |
|---|---|
| No shared cell primitive | A single `UnifiedStepCell` used across all step-grid contexts |
| No combined four-state rendering | Each cell shows active, playing, selected, and value simultaneously |
| Right-click opens a sheet, not inline selection | Right-click / long-press selects a step; no sheet opens |
| No multi-step selection or batch write | Selection model + single-closure batch writes |
| No batch action bar | Batch action bar with clear, copy, paste |

The layer tab row transforms (Variant D) is the additional innovation: when any
steps are selected the layer tabs become rotary arc-dials, making multi-step
layer editing directly discoverable.

---

## 2. Data and Runtime Shapes

### 2a. `StepSelectionModel`

```
StepSelectionModel (value type or @Observable class)
  clipID: ClipID
  selectedStepIndexes: Set<Int>
```

- `selectedStepIndexes` uses step index within the clip (0-based, bounded by
  the clip's step count). It is not a step index within a phrase or pattern.
- `Set<Int>` is used to avoid indexing assumptions and to support non-contiguous
  multi-step selection directly.
- This type carries no persisted state. It is transient UI state and must never
  appear in `ClipContent`, `ClipPoolEntry`, `StepSequenceTrack`, or any
  `Codable` type.

#### Lifetime Rules

`StepSelectionModel` is cleared (selection set emptied and the model
reinitialised) on each of the following events:

| Event | Clears selection? | Notes |
|---|---|---|
| User navigates away from the clip-editing context | Yes | "Navigate away" means the clip editor hosting this clip is no longer the frontmost active clip editor in the workspace |
| Active track changes | Yes | Switching to a different track's workspace discards the prior selection |
| Active clip changes within the same track | Yes | Selecting a different clip in the clip pool for the same track discards the prior selection |
| Active layer tab changes | No | Switching between Steps / Velocity / Chance / Macro retains the selection; the rotary row updates to reflect the new active layer |
| Document closes | Yes | All transient state is discarded on document close |
| Escape key pressed (macOS) | Yes | Explicit deselect gesture |
| Tap / click on empty grid area (no cell) | Yes | Clicking on the grid background outside any cell clears selection |

Switching the active layer does not clear selection so that the user can select
steps on the trigger layer and immediately switch to velocity layer to see the
value bars for those steps before dragging.

#### Owner

`StepSelectionModel` is owned by `StepGridCoordinator`, which is in turn owned
by the **track workspace view model** for the track whose clip editor is active.
The track workspace view model is a stable `@Observable` reference type with a
lifetime tied to the track workspace session, not to any individual SwiftUI
view's `@State`. This prevents selection loss on view recreation during
navigation.

Specifically: the coordinator must NOT be created as `@State var` on any view.
It must be injected as a dependency (via SwiftUI environment or initializer
parameter) from the track workspace view model.

### 2b. `StepClipboard`

```
StepClipboard (value type)
  sourceClipID: ClipID
  steps: [Int: StepClipboardEntry]   // keyed by source step index (0-based)

StepClipboardEntry
  active: Bool
  velocity: Double?        // nil = not present in source layer; 0.0–1.0 normalized
  chance: Double?          // nil = not present; 0.0–1.0 normalized
  macroOverrides: [Int: Double?]  // keyed by TrackMacroBinding index; nil = clear override
  sliceIndex: Int?         // for slicer tracks; nil = not a slicer clip
  sliceMode: Int?          // for slicer tracks; mirrors stepModes encoding
```

- `StepClipboard` is session-scoped transient state. It is not persisted to disk.
- It carries all data layers (all-layers scope — see Section 4c).
- Owned by `StepGridCoordinator`. It survives layer tab changes and active-clip
  changes within the same session so that cross-clip paste is possible.
- It does NOT survive document close or app termination.

### 2c. `StepGridCoordinator`

```
StepGridCoordinator (@Observable class)
  Owns: StepSelectionModel
  Owns: StepClipboard
  Reads: ClipID (active clip), ClipEditorMode (active layer tab)
  Reads: session reference (for mutateClip dispatch)

  Responsibilities:
  - Convert track-type-specific model data to StepCellContent per step per active layer
  - Handle onTap / onDrag callbacks from cells; dispatch to session.mutateClip
  - Expose isSelectionActive: Bool (= !selectedStepIndexes.isEmpty)
  - Expose shouldShowRotaryRow: Bool (= isSelectionActive && activeLayer has value layers)
  - Expose shouldShowBatchActionBar: Bool (= isSelectionActive)
  - Compute MacroLane write-index from active layer's TrackMacroBinding (see Section 5b)
```

`StepGridCoordinator` does not own clip data or the session. It receives these
as constructor dependencies. It is created once per clip-editing context and
replaced when the track workspace view model is replaced.

In-progress drag state (the gesture's accumulated delta during a mousedown /
touchmove sequence) is local to the gesture recognizer or the cell's gesture
handler. It is never materialized as a named object on the coordinator or any
model type.

---

## 3. Unified Step Cell Primitive

### 3a. `UnifiedStepCell` Parameters

| Parameter | Type | Purpose |
|---|---|---|
| `visualState` | `StepVisualState` | Existing enum: `.off` / `.on` / `.accented` — unchanged |
| `isPlaying` | `Bool` | Green border overlay; driven by `tickIndex % stepCount == stepIndex` |
| `isSelected` | `Bool` | Amber border overlay; driven by `StepSelectionModel.selectedStepIndexes` |
| `content` | `StepCellContent` | Track-type-aware content variant (see 3b) |
| `onTap` | `() -> Void` | Toggle active state (trigger layer) or cycle option (option layers) |
| `onDrag` | `((Double) -> Void)?` | Nil for toggle/option layers; called with normalized 0–1 delta on drag |
| `onSelect` | `() -> Void` | Called when right-click (macOS) or long-press (touch) is received |

`isPlaying` and `isSelected` are separate parameters, not folded into
`StepVisualState`. This preserves backward compatibility with all existing
`StepVisualState` callers.

`StepVisualState` is not modified by this feature.

### 3b. `StepCellContent`

```swift
enum StepCellContent {
    case toggle
    case valueBar(fraction: Double)
    case sliceLabel(index: Int, label: String)
    case chordLabel(name: String)
    case optionLabel(text: String)
}
```

- `.toggle`: trigger layer — dot on/off visual only; no draggable element.
- `.valueBar(fraction:)`: velocity or chance layers — proportional vertical fill
  bar inside the cell. Accepts vertical drag via `onDrag`.
- `.sliceLabel(index:, label:)`: slicer track trigger layer — compact slice
  segment label. Cycles on `onTap`.
- `.chordLabel(name:)`: chord-generator track — chord name or degree stub.
  Cycles on `onTap`. See Section 7 for chord model constraints.
- `.optionLabel(text:)`: generic fallback for any indexed-choice layer.

The caller (coordinator) is responsible for the conversion. `UnifiedStepCell`
has no knowledge of track types.

### 3c. Cell Geometry and Fixed Frame

`UnifiedStepCell` maintains a fixed frame regardless of the active
`StepCellContent` variant. Layer switches do not change cell geometry or break
spatial alignment. This directly fixes the `StepGridView` ↔ `GridEditor` swap
identified in `existing-state.md` Story 6 gap.

### 3d. Four-State Visual Composition

All four states (active, playing, selected, value) must be visible simultaneously
on a single cell:

| State | Visual expression |
|---|---|
| Active (`.on` / `.accented`) | Filled background; symbol or bar present |
| Inactive (`.off`) | Unfilled background; dim symbol |
| Playing | Green 1pt border inset overlay |
| Selected | Amber 2pt border overlay |
| Playing + Selected | Green inset shadow + amber border (compound, distinguishable) |
| Value (fraction) | Vertical fill bar height within cell; visible on value layers regardless of active state |

### 3e. Batch Action Bar Visibility

The batch action bar is positioned below the step grid. It is hidden using
`opacity(0)` combined with `allowsHitTesting(false)` when `shouldShowBatchActionBar`
is false. It is NOT removed from the view hierarchy and NOT collapsed to zero
height. This preserves layout and prevents the grid from shifting when the bar
appears or disappears.

The bar contains three actions: **Clear**, **Copy**, **Paste**.

---

## 4. Interaction Semantics

### 4a. Single-Step Toggle (Trigger Layer)

Left-click / tap on a `UnifiedStepCell` with `content == .toggle` calls `onTap`,
which maps to the existing `cycleStep(at:)` path. The three-state cycle
(`.off` → `.on` → `.accented`) is preserved.

If the tapped cell is part of an active selection (i.e., `isSelected == true`),
the toggle applies to all selected steps in a single `session.mutateClip` closure
(see Section 5a). If the tapped cell is not selected, the toggle applies only to
that cell and does not affect selection.

### 4b. In-Cell Value Drag (Single Step, Value Layers)

On value layers (velocity, chance, scalar macro), `onDrag` is non-nil. A vertical
drag gesture calls `onDrag` with a normalized 0–1 value representing the absolute
target value (not a delta). The gesture starts on mousedown / touchstart over the
cell.

Tap-vs-drag disambiguation: a drag displacement of fewer than 4 pt from the
initial touch point is interpreted as a tap. At 4 pt or more, the drag path
activates and no `onTap` is fired.

If the dragged cell is part of an active selection, the drag applies the value to
all selected steps in a single `session.mutateClip` closure. If the cell is not
selected, the drag applies only to that cell.

### 4c. Option Layer Cycle (Single Step, Option Layers)

On option layers (`.sliceLabel`, `.chordLabel`, `.optionLabel`), left-click / tap
calls `onTap` to cycle through the available options. Cycling wraps at the end of
the available index range.

If the tapped cell is part of an active selection, the cycle target index is
applied to all selected steps in a single mutation closure.

### 4d. Step Selection Gesture

**macOS:** Right-click on any step cell adds that step to
`StepSelectionModel.selectedStepIndexes`. A second right-click on an already-
selected step removes it from the selection (toggle select).

**Touch:** Long-press (threshold: ≥ 400 ms) on any step cell adds it to the
selection. Same toggle behavior on second long-press.

The selection gesture is **additive (multi-select mode)**. Selecting a new step
does not deselect previously selected steps. To deselect all, the user must use
the Escape key, click on empty grid space, or tap the "Clear Selection" button in
the batch action bar when it is present.

Left-click / tap on a non-selected step does NOT clear the selection — it toggles
that step's active state and leaves the selection unchanged. This allows
interleaving individual toggles with a maintained selection.

### 4e. Rotary Row — Trigger Layer Behavior

**Resolved decision:** When steps are selected and the active layer is `trigger`,
the rotary row shows the **velocity and chance layer rotaries unconditionally**,
even though the active tab is `trigger`. Rationale: the most common use case for
selecting steps on the trigger layer is to immediately edit their velocity or
chance, and hiding all rotaries forces an extra layer-tab click before the user
can reach the rotary controls. The active-layer highlight (amber border on the
rotary control for the active tab) is suppressed when the active layer is trigger;
no rotary has the active-layer highlight in this state.

If neither velocity nor chance layers exist on the track (e.g., a slicer track
without those layers enabled), the rotary row shows the available editable layers.
If there are no editable layers at all, the rotary row shows a "No editable layers"
text label and does not transform the tab row into rotary controls.

### 4f. Rotary Row — Semantics (Absolute vs Relative)

**Resolved decision:** The rotary row uses **absolute value semantics**. When
multiple steps with different values are selected and a rotary is turned, the
dragged value is applied as an absolute value to all selected steps simultaneously.
The rotary arc initializes to the value of the **first** (lowest-index) selected
step when the selection changes.

Rationale: absolute semantics are the simpler, more predictable behavior and match
the prototype assumption. Relative delta semantics introduce edge cases (values
below 0 or above 1) that require clamping logic and add implementation complexity
for an interaction pattern that is already non-trivial. Absolute semantics can
always be the implementation baseline; relative semantics can be added as a
modifier (e.g., hold a modifier key) in a future iteration.

### 4g. Rotary Row — All Layers Simultaneously

**Resolved decision:** The rotary row shows **all editable layers for the track
simultaneously**, not only the currently active layer. This is the Variant D
behavior. "Editable layers" are all non-trigger, non-stub layers on the track
(velocity, chance, all enabled macro bindings, slicer mode, chord index).

The active layer's rotary control carries an amber border highlight to orient the
user. This is consistent with the active tab highlight on the plain tab row.

Stub (disabled) layers do not appear in the rotary row.

### 4h. Rotary Row — Overflow at High Layer Counts

**Resolved decision:** The rotary row supports up to **four editable layers**
simultaneously without overflow handling. At five or more editable layers, the
rotary row switches to a horizontally scrollable container. There is no collapse
or "more layers" affordance for this feature's scope — horizontal scroll is
sufficient at the common track macro count (0–3 bindings plus velocity and
chance = max 5 layers). A scroll indicator is shown when the container is
scrollable.

The minimum rotary control width is 56 pt (matching the prototype). At four
rotaries in an 860 pt shell the row is comfortably within bounds.

---

## 5. Write Paths

### 5a. Batch Mutation — All Per-Step Writes

All multi-step mutations (velocity, chance, macro override, active state, option
cycle) for a selection of N steps must be written in a single
`session.mutateClip` closure. The coordinator computes target values for all
selected steps before opening the closure:

```
coordinator receives onTap/onDrag for step(s) to affect
  → compute target value(s) for all affected indexes
  → session.mutateClip(id: clipID) { clip in
       for index in affectedIndexes { clip.write(value, at: index) }
     }
```

N separate sequential `mutateClip` calls are NOT permitted for a batch edit.
This is required by the 16 ms tap-to-invalidation budget established in
`StepGridTapLatencyTests`.

Actor isolation: any `StepSelectionModel` or `StepClipboard` reference captured
in a `mutateClip` closure must either be `Sendable` or the values must be copied
(e.g., `let indexes = selectedStepIndexes`) before the closure is formed. The
closure must not capture the coordinator itself.

### 5b. Macro Override Write Path

**Resolved decision:** Turning the macro rotary in the rotary row writes to
`ClipContent.MacroLane` overrides (per-step, per-clip) through
`session.mutateClip`. It does NOT write to `PhraseCell.steps` phrase-level values.

Rationale: the rotary row appears inside the clip editor, operating on selected
steps within a specific clip. The editing context is per-clip. `ClipContent.MacroLane`
is the correct storage layer for this context. `PhraseCell.steps` operates at
phrase granularity and is a different editing surface (the phrase workspace).
Writing to phrase-level values from the clip editor step grid would cross the
editing-surface boundary and would require a different mutation API
(`session.mutatePhrase`, not `session.mutateClip`).

#### MacroLane Index Mapping

The coordinator must resolve the `TrackMacroBinding` index for the target macro
layer before writing. The mapping is:

```
activeLayerTab → resolves to → TrackMacroBinding at index N
                              → writes to ClipContent.MacroLane[N][stepIndex]
```

The coordinator reads the track's `macros: [TrackMacroBinding]` array and uses
the array index (0-based, stable order) as the `MacroLane` index key. It does
NOT use an implicit layer-order derived from the UI tab position. If the
tab-order and the macro-binding order diverge (which `existing-state.md` confirms
can happen), the coordinator must use the `TrackMacroBinding` index, not the tab
position.

### 5c. Copy/Paste Scope — All Layers

**Resolved decision:** Copy captures all data layers for each selected step.
Paste writes all captured layers.

Rationale: `user-stories.md` Assumptions section states "Copy and paste operate
on the step data for all currently visible/edited layers within the selection,
not just the active layer." The `StepClipboardEntry` structure reflects this:
it carries `velocity`, `chance`, `macroOverrides`, `sliceIndex`, and `sliceMode`
for every copied step. An implementer may add an active-layer-only filter as a
future modifier, but the default behavior is all-layers.

Paste semantics: paste writes to the same step indexes as the source selection
(index-preserving). If any target index is out of bounds for the destination clip
(e.g., the destination clip is shorter than the source), that step is skipped
silently.

Cross-clip paste: `StepClipboard` survives active-clip changes within the same
session, enabling copy from clip A and paste into clip B of the same track.
Cross-track paste is out of scope for this feature.

---

## 6. Layer Tab Row Transition

### 6a. State Machine

The layer tab row has two visual modes:

| Mode | Condition | Content |
|---|---|---|
| Tab mode | `selectedStepIndexes.isEmpty` | Existing tab strip, one tab per layer |
| Rotary mode | `!selectedStepIndexes.isEmpty && hasEditableLayers` | "STEP EDIT" label + one rotary arc-dial per editable layer |

The transition between modes is immediate (no animation required for this
feature's scope, though a cross-fade may be added without spec change).

### 6b. Rotary Arc-Dial

Each rotary in rotary mode shows:

- An SVG arc proportional to the layer's value (0 = empty arc, 1 = full arc)
- A layer name label below the dial
- A numeric value display inline with the dial (0–127 for velocity, 0–100% for
  chance and macro scalar layers, 1–N for option layers)
- Amber highlight border when the rotary corresponds to the active layer tab

Dragging the arc-dial vertically (up = increase, down = decrease) writes the
new absolute value to all selected steps via a single `session.mutateClip`
closure. Drag sensitivity: 80 pt vertical displacement maps to the full value
range (0 to 1 normalized). This matches the prototype default and should be
validated during implementation.

For slicer and chord/option layers: the rotary snaps to integer index values.
The arc fills proportionally (index / max_index).

---

## 7. Track-Type Coverage and Constraints

### 7a. Note Grid Track

| Layer | Cell Content | Rotary in Rotary Row |
|---|---|---|
| Trigger (Steps) | `.toggle` — dot on/off | Not shown (see 4e) |
| Velocity | `.valueBar(fraction:)` — vertical fill bar | Yes — arc 0–127 |
| Chance | `.valueBar(fraction:)` — vertical fill bar | Yes — arc 0–100% |
| Macro (enabled) | `.valueBar(fraction:)` — fill bar | Yes — arc 0–100% (normalized) |
| Macro (stubbed/disabled) | Not shown | Not shown |

### 7b. Slicer Track

| Layer | Cell Content | Rotary in Rotary Row |
|---|---|---|
| Trigger | `.sliceLabel(index:, label:)` | Not shown |
| Velocity | `.valueBar(fraction:)` — was disabled stub; this feature enables it | Yes |
| Chance | `.valueBar(fraction:)` — was disabled stub; this feature enables it | Yes |

`existing-state.md` confirms Velocity and Chance layer tabs on `SliceStepStrip`
are disabled stubs (`isEnabled: false`). This feature enables them as part of
the unified cell work.

### 7c. Chord Generator Track

| Layer | Cell Content | Rotary in Rotary Row |
|---|---|---|
| Trigger | `.chordLabel(name:)` — chord name/degree | Not shown |
| Macro (if any) | `.valueBar(fraction:)` | Yes |

**Chord model constraint:** Chord identity per step is not available as a named
abstraction in `ClipContent.noteGrid`. Chord data is stored as raw notes (pitch +
velocity arrays per step). For this feature's scope, the `chordLabel` cell variant
is **permanently stubbed**: the coordinator passes the step's first note's pitch
class as a label (e.g., "C", "F#") or a Roman numeral degree if scale context is
available, without requiring a full chord-abstraction model.

This stub is acceptable for the feature's launch scope. A future feature that
adds a chord-generator abstraction layer to the model would provide the mapping
to proper chord names; the coordinator's `StepCellContent` conversion would then
call that new path. No changes to `UnifiedStepCell` are required.

**Chord dot legibility:** At 40 pt cell width, seven 5 pt dots across the cell
face is tight. The spec decision: **show chord name label only** (the `.chordLabel`
text case) at any cell width. The dot representation shown in the prototype is
deferred until the chord model provides a stable chord identity, at which point
the dot array could be added as an optional sub-layer without changing the cell
primitive.

---

## 8. Existing Code Constraints for the Implementation Loop

These are carry-forwards from `architecture.md` Section 6 and `architecture-review.md`:

| Constraint | Required action |
|---|---|
| `StepGridCell` is `private` inside `StepGridView.swift` | Must be made `internal` or migrated in the same file before `UnifiedStepCell` can reuse its visual conventions |
| `StepVisualState` has three cases; all callers must remain unbroken | `isSelected` is a separate parameter on `UnifiedStepCell`, not a new enum case |
| `session.mutateClip` is actor-isolated | Batch closures must copy transient state (e.g., `let indexes = selectedStepIndexes`) before the closure; do not capture coordinator |
| Existing views not in this feature's scope must NOT be forced to migrate | Only views directly modified to implement user stories need to use `UnifiedStepCell`; `SliceTrackWorkspaceView`, `ClipMacroLaneEditor`, and `ClipContentPreview` contexts not touched by a user story may stay on their existing cell types |
| `SliceStepStrip` velocity/chance stubs enabled | `isEnabled: false` guards on those tabs must be removed and connected to the new unified cell path |
| `MacroLane` indexing by `TrackMacroBinding` index | Never index by implicit tab order; always by the array index of `TrackMacroBinding` in `StepSequenceTrack.macros` |

---

## 9. Non-Goals

The following are explicitly out of scope for this feature:

- **Phrase-level step editing.** Writing to `PhraseCell.steps` from the step
  grid is not in scope. The rotary row writes to clip-level `MacroLane` only.
- **Cross-track paste.** `StepClipboard` does not support pasting to a different
  track's clip.
- **Touch path specification.** The touch selection gesture (long-press) is
  named in this spec but the expanded-drag-zone concept from Variant C's
  annotation is deferred. The implementation loop should implement long-press
  selection only; the expanded drag zone is a future enhancement.
- **Relative delta rotary mode.** Absolute value semantics only; relative delta
  with modifier key is a future enhancement.
- **Chord-generator model refactor.** The `chordLabel` cell variant uses a pitch-
  class stub. Full chord identity requires a separate feature.
- **Full migration of all existing step-cell call sites to `UnifiedStepCell`.**
  Only views in this feature's user story scope are migrated.
- **Animation of layer row transition.** The tab → rotary row transition is
  immediate for this feature.
- **Copy/paste with offset.** Paste writes to the same step indexes as the
  source. Offset / relative paste is not in scope.

---

## 10. Acceptance Criteria

Traced to user stories:

### Story 1 — Unified Step Cell Primitive

- AC-1.1: A `UnifiedStepCell` type exists and is used in at least the clip
  editor (note-grid trigger), clip editor (velocity), clip editor (chance), and
  the slicer track workspace step strip.
- AC-1.2: Tapping any step cell in any of those views uses the same tap-to-
  toggle interaction pattern (no secondary panel opens).
- AC-1.3: Dragging on a value layer cell in any of those views produces an
  in-cell value change without opening a sheet.

### Story 2 — Step State Legibility

- AC-2.1: A step that is simultaneously `.on`, playing, and selected renders
  with a filled background (active), green border (playing), and amber border
  (selected) without visual ambiguity.
- AC-2.2: A step that is `.off` and selected renders with the amber border and
  an unfilled background; active state is distinguishable from selected state.
- AC-2.3: On a velocity layer, the value bar is visible inside the cell for both
  active and inactive steps.

### Story 3 — Right-Click Step Selection and Layer Editing

- AC-3.1: Right-clicking a step on macOS adds it to `selectedStepIndexes` and
  the cell shows the amber selection border.
- AC-3.2: When any step is selected and the active layer is not trigger, the
  layer tab row shows rotary arc-dial controls.
- AC-3.3: When any step is selected and the active layer is trigger, the rotary
  row shows velocity and chance rotaries (per 4e decision).
- AC-3.4: The batch action bar becomes visible when at least one step is selected.

### Story 4 — Multi-Step Selection

- AC-4.1: Right-clicking a second step adds it to the existing selection (does
  not replace it). Both cells show the amber selection border.
- AC-4.2: Dragging a rotary arc-dial while N steps are selected applies the
  dragged value to all N selected steps. Stepping through the clip data after
  the drag confirms all N steps were written.
- AC-4.3: The mutation for N-step batch write is a single `session.mutateClip`
  closure, not N closures. `StepGridTapLatencyTests` continue to pass after the
  feature is implemented.
- AC-4.4: Pressing Escape clears the selection. All amber borders disappear and
  the rotary row reverts to plain tab row.

### Story 5 — Contextual Batch Action Bar

- AC-5.1: The batch action bar is positioned below the step grid at all times.
  When no steps are selected, it is invisible and non-interactive (zero opacity,
  hitTest disabled). No layout shift occurs when it appears or disappears.
- AC-5.2: "Clear" in the batch action bar sets `visualState` to `.off` for all
  selected steps in a single mutation closure and clears the selection.
- AC-5.3: "Copy" writes all selected steps' data (all layers) into
  `StepClipboard`. The clipboard is confirmed populated by a subsequent paste.
- AC-5.4: "Paste" reads `StepClipboard.steps` and writes each entry's data to
  the same-indexed step in the active clip in a single mutation closure.

### Story 6 — Layer-Driven Cell Control Type

- AC-6.1: Switching the active layer from Steps to Velocity changes every step
  cell from `.toggle` to `.valueBar(fraction:)` without changing cell geometry
  or step positions.
- AC-6.2: Switching back from Velocity to Steps restores `.toggle` cells. The
  velocity values are unchanged (confirmed by switching to Velocity again).
- AC-6.3: Switching to a macro layer (if the track has macro bindings) renders
  each step cell as `.valueBar(fraction:)` using the per-step `MacroLane`
  override value (or a default/global value if the override is nil).

---

## 11. Test Expectations

The implementation loop must provide tests for:

| Area | Test expectation |
|---|---|
| `StepSelectionModel` lifetime | Unit test: selection is cleared when clipID changes; selection is NOT cleared when layer tab changes |
| Multi-step batch write | Unit test: applying a value to a 4-step selection produces exactly one `mutateClip` call with all 4 indexes written |
| 16 ms budget | `StepGridTapLatencyTests` continue to pass on the reference project (8 tracks, 4 patterns, 32-step clips, 4 phrases) |
| Copy/paste round-trip | Unit test: copy N steps, paste to same clip, confirm velocity/chance/macroOverride values are preserved per step |
| MacroLane index mapping | Unit test: coordinator writes to `MacroLane[bindingIndex]`, not to an implicit tab position index |
| Selection clear events | Unit test: Escape press, background tap, and active-clip change each clear selection |
| Layer row mode switch | Snapshot / UI test: when `selectedStepIndexes` is non-empty, the layer row renders rotary controls; when empty, it renders tabs |
| Batch action bar no-layout-shift | UI test: grid frame is identical before and after selection state changes |

`StepGridView` and `StepGridCell` rendering tests (currently absent per
`existing-state.md`) should be added for any views modified by this feature.
`SliceStepStrip` selection behavior tests should be added when that view is
migrated to `UnifiedStepCell`.

---

## 12. Open Questions

The following items remain open and are flagged for user input or deferral to
the implementation loop.

### OQ-1: Touch Drag Sensitivity

The rotary row drag sensitivity (80 pt = full range) was not validated on touch.
On touch, fine-grained precision (e.g., velocity 64 vs 66) may require a
different sensitivity or a fine-tune modifier. This should be validated during
implementation with touch testing. It is not a spec-level blocker but is flagged
here so the implementation loop plans for it.

### OQ-2: Selection Persistence Across Layer Tab Changes

The spec says switching the active layer does NOT clear selection (see 2a
lifetime rules). If this is not the desired behavior (e.g., if the user expects
selection to feel "per-layer"), this decision should be revisited before
implementation begins. The rationale for the current decision: selecting steps
on the trigger layer to then edit their velocity is a common pattern and forcing
a re-selection after every layer switch would break that flow.

### OQ-3: Paste Destination Index Conflict

When steps are selected and the user pastes, the paste target indexes are the
same as the source. If the user wants to paste to a different offset (e.g.,
copy steps 0–3 and paste them at steps 8–11), there is no mechanism in this
spec. This is an acknowledged gap; offset paste is a non-goal (Section 9) but
should be tracked as a future enhancement.
