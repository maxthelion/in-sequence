# Step Sequencer — Architecture

Written: 2026-04-29
Based on: `user-stories.md`, `existing-state.md`, `ux-review.md`

---

## Status

Superseded as an advancement gate: `ux-review.md` now has `verdict: needs-rework`
and `redirect_to: build-prototypes`, so this architecture should be treated as
advisory input until Variant C and Variant D prototypes are built and reviewed.

Architecture is written before Variant C and Variant D prototypes are reviewed.
The model-layer design described here is stable regardless of which UX variant wins, because both
variants share the same underlying data requirements. The one section that may need revision after
the UX decision is "Layer Tab Row Transform" under Section 4.

---

## 1. Design Constraints Carried Forward

The following findings from `existing-state.md` and `ux-review.md` constrain every architectural
decision below.

1. **16 ms tap-to-invalidation budget.** `StepGridTapLatencyTests` measures this on a reference
   project (8 tracks, 4 patterns, 32-step clips, 4 phrases). Any batch write to multiple steps
   must fit inside a single `session.mutateClip` closure — not N sequential mutations.

2. **No per-step selection in the persistence model.** Selection is transient UI state. It must
   live in a view model or session layer, not in `ClipContent` or `StepSequenceTrack`.

3. **`MacroLane` overrides live on `ClipPoolEntry`.** Per-step macro edits go through
   `session.mutateClip`, not through `StepSequenceTrack`.

4. **`StepVisualState` is consumed by all callers.** Adding a fourth case would break every call
   site. Selection must remain a separate boolean parameter on the cell, mirroring the existing
   `SliceStepStrip` pattern.

5. **`StepGridCell` is private inside `StepGridView.swift`.** Any new unified cell type either
   refactors this file or introduces a new cell type alongside it. The architecture recommends a
   new shared type; see Section 3.

6. **Phrase-layer vs clip-layer storage.** The `PhraseCell.steps([PhraseCellValue])` path and the
   `ClipContent.noteGrid` path are separate storage layers for separate concerns. Step-on/off and
   per-step velocity/chance are clip-level data. Phrase-level data (mute, volume-like macros) is a
   different editing surface. The unified cell primitive addresses the clip-level layer only.

---

## 2. Model Changes Required

### 2a. Per-Step Selection State — NOT in the persistence model

Selection is a volatile editing concern. It must not persist to disk.

**Location:** A new `StepSelectionModel` value type (or an `@Observable` class) owned by whichever
coordinator or view model hosts the step grid for a given track context. It holds:

```
StepSelectionModel
  clipID: ClipID
  selectedStepIndexes: Set<Int>
```

This is shared across all step-cell views within the same clip editing context. It is discarded
when the user navigates away from that clip.

No changes to `ClipContent`, `ClipPoolEntry`, or `StepSequenceTrack`.

### 2b. Batch Write Path

All per-step value mutations (velocity, chance, macro override) for a selection of N steps must
be written in a single `session.mutateClip` closure. The coordinator or action handler computes
the target values for all selected steps upfront, then passes a single closure:

```
session.mutateClip(id: clipID) { clip in
    for index in selectedIndexes {
        // apply write to clip at index
    }
}
```

This satisfies the 16 ms budget constraint and avoids N observer notifications.

### 2c. Clipboard Model for Copy/Paste — NOT in the persistence model

Step copy/paste is a transient session-scoped clipboard. It is not stored on disk.

```
StepClipboard
  sourceClipID: ClipID
  steps: [Int: StepClipboardEntry]   // keyed by source step index

StepClipboardEntry
  active: Bool
  velocity: Double?          // nil = no value in source
  chance: Double?
  macroOverrides: [Int: Double?]   // keyed by macro binding index
  sliceIndex: Int?           // for slicer tracks
```

Open question from `user-stories.md`: does paste write all layers or only the active layer?
This determines whether `StepClipboardEntry` carries all layers (as above) or only the active one.
Architecture supports all-layers as the default; active-layer-only is a filtered subset of the
same structure. This must be resolved in the spec before implementation.

### 2d. No Chord-Generator Step Model Yet

The `ux-review.md` identifies that chord-generator steps need to show chord identity, but chord
data is not present in `ClipContent.noteGrid` as a chord abstraction — only as raw notes. This is
a model gap. The architecture for the chord-generator cell representation is deferred until:

- The chord-generator track type is sufficiently specified, OR
- A stub static cell state is accepted for the prototypes (see UX review recommendation).

This gap must be surfaced in `spec.md` as a known constraint on the track-type-aware cell work.

---

## 3. Unified Step Cell Primitive

### 3a. New `UnifiedStepCell` type

The existing cell types (`StepGridCell`, `MacroLaneCell`, `SliceStepStrip` cell, `GridEditor`
column) remain in place. The unified primitive is introduced as a new SwiftUI view, initially used
for new or refactored grid surfaces. Existing views migrate to it incrementally.

`UnifiedStepCell` accepts:

| Parameter | Type | Purpose |
|---|---|---|
| `visualState` | `StepVisualState` | off / on / accented (existing enum, unchanged) |
| `isPlaying` | `Bool` | green border overlay |
| `isSelected` | `Bool` | amber border overlay |
| `content` | `StepCellContent` | see 3b |
| `onTap` | `() -> Void` | toggle active state |
| `onDrag` | `((Double) -> Void)?` | nil for toggle layers; called with normalized 0–1 on drag |

`isPlaying` and `isSelected` are separate parameters, not folded into `StepVisualState`, to
preserve backward compatibility with all existing `StepVisualState` consumers.

### 3b. `StepCellContent` — Track-Type-Aware Variation

```
enum StepCellContent {
    case toggle                           // note-grid trigger layer: dot on/off
    case valueBar(fraction: Double)       // velocity or chance: proportional bar, draggable
    case sliceLabel(index: Int, label: String)  // slicer: compact slice label
    case chordLabel(name: String)         // chord-generator: chord name or degree stub
    case optionLabel(text: String)        // generic indexed-choice layer fallback
}
```

The caller (coordinator or parent view) is responsible for converting its track-type-specific
data to the appropriate `StepCellContent` case before passing to `UnifiedStepCell`. The cell
itself has no knowledge of track types; it renders what it is given.

This separation means:
- Adding a new track type requires only a new calling convention (a new content conversion), not
  a change to the cell primitive itself.
- The `chordLabel` case can be stubbed with static data in prototypes until the chord model is
  defined.

### 3c. Layer-Driven Content Switching

The active layer determines which `StepCellContent` variant is passed to each cell. The content
switch happens at the coordinator/parent level, not inside the cell. When the active layer changes,
every cell re-renders with a new `StepCellContent`; cell geometry and grid alignment are preserved
because `UnifiedStepCell` maintains a fixed frame regardless of content variant.

This is the structural fix for the existing `StepGridView` ↔ `GridEditor` swap, which changes
cell geometry when the layer changes and breaks spatial alignment (identified in `existing-state.md`
Story 6 gap).

---

## 4. Interaction Model

Both UX variants (C and D) share the same interaction primitives for the base case. The
architecture supports both without requiring a fork in the model or cell types.

### 4a. Left-Click / Tap — Toggle

`onTap` on a `UnifiedStepCell` toggles `visualState` between `.off` and `.on` (or `.off` /
`.on` / `.accented` for tracks that use the accent cycle). This maps directly to the existing
`cycleStep(at:)` path.

### 4b. Drag on Value Layers (Variant C core, Variant D also uses this)

When `content` is `.valueBar(fraction:)`, the cell accepts a vertical drag gesture. The drag
delta is converted to a normalized 0–1 delta and passed to `onDrag`. The coordinator converts
this to the appropriate clip-level write (velocity, chance, or macro override).

The drag gesture and the tap gesture must be distinguished. Architecture recommendation: a drag
of fewer than 4 pt is interpreted as a tap; a drag of 4 pt or more triggers the drag path. This
threshold should be validated in the Variant C prototype.

### 4c. Right-Click / Long-Press — Select Step

Right-click (macOS) or long-press (touch) adds the tapped step to `StepSelectionModel.selectedStepIndexes`.
Multiple steps can be added by right-clicking/long-pressing additional steps.
Tapping any non-selected step clears the selection (configurable; see open question below).

The selection gesture must not conflict with the drag gesture. On macOS, right-click and drag
are separate input paths. On touch, long-press-to-select followed by a separate drag on the
selected cell is the expected sequence.

### 4d. Layer Tab Row Transform (Variant D specific)

When `selectedStepIndexes` is non-empty, the layer tab row transforms. Each layer entry gains an
inline rotary or arc-scrubber control. Turning the control calls the same batch write path
described in Section 2b, writing the new value to all selected steps in a single mutation closure.

The layer tab row transform is controlled by the same `StepSelectionModel` object that drives
cell selection state. When `selectedStepIndexes` becomes empty, the row reverts to plain tabs.

**This section requires revision after Variant D prototype review.** The specific control type
(arc slider, numeric scrubber, miniature dial) affects layout constraints for the layer row,
particularly how many layers can be simultaneously visible. See UX review question 3.

### 4e. Batch Action Bar

The batch action bar appears when `selectedStepIndexes` is non-empty. Actions:

| Action | Behavior |
|---|---|
| Clear | Sets `visualState` to `.off` for all selected steps in a single mutation |
| Copy | Writes current step data for selected steps into `StepClipboard` |
| Paste | Reads `StepClipboard`, writes to steps at the same or target indexes via single mutation |

The bar is hidden (not collapsed to zero height — hidden to avoid layout shift) when no steps
are selected.

---

## 5. View Model / Coordinator Responsibilities

A new coordinator (a SwiftUI `@Observable` class, tentatively `StepGridCoordinator`) is
responsible for:

- Owning `StepSelectionModel` for the current clip context.
- Owning `StepClipboard` for the current session.
- Converting track-type-specific model data to `StepCellContent` per step per active layer.
- Handling `onTap` and `onDrag` callbacks from cells and dispatching to `session.mutateClip`.
- Exposing whether the batch action bar should be visible.
- Exposing whether the layer tab row should show rotary controls (Variant D).

`StepGridCoordinator` does not own the clip data or the session; it receives them as dependencies.
It is instantiated per clip-editing context and discarded when the context closes.

This coordinator pattern prevents selection state from leaking into `@State` on individual views
(the current `SliceStepStrip` approach, which makes cross-view unified selection impossible).

---

## 6. Architecture Constraints on Implementation

These are findings the implementation loop must address; they are not decisions made here.

| Constraint | Finding |
|---|---|
| `StepGridCell` is `private` | Must be made `internal` or replaced in the same file before `UnifiedStepCell` can reuse its visual conventions |
| `StepVisualState` callers | All callers must remain unbroken; `isSelected` is a separate parameter, not a new enum case |
| Actor isolation | `session.mutateClip` is actor-isolated; batch closures must not escape non-Sendable state |
| `MacroLane` indexing | Macro override writes must index by `TrackMacroBinding` index, not by an implicit layer order that may differ between views |
| `SliceStepStrip` Velocity/Chance stubs | These disabled layer tabs (confirmed in `existing-state.md`) represent a known gap; enabling them is in scope for this feature's unified cell work |
| Chord-generator cell | Deferred; chord identity is not in the current step model |

---

## 7. Open Questions Gating Spec

These must be resolved in `spec.md` before implementation begins.

1. **Copy/paste scope:** Does paste write all layers or only the active layer? Determines
   `StepClipboardEntry` structure. (Carried from `user-stories.md` assumption note.)

2. **Phrase-layer vs clip-layer for macro editing:** Story 3 says "macro/layer cells above the
   step column become editable." For the rotary-row (Variant D), does turning the rotary write to
   `ClipContent.MacroLane` overrides (per-step, per-clip), or to `PhraseCell.steps` phrase-level
   values (per-step, per-phrase)? These are different storage paths and cannot be resolved without
   a UX decision on which editing context the rotary represents.

3. **Selection clear-on-tap:** When a step is selected and the user taps a non-selected step,
   does the selection shift to the new step (single-select mode) or extend (multi-select mode)?
   The notes imply multi-select; the interaction design of Variant C/D should make this explicit.

4. **Drag threshold:** The 4 pt tap-vs-drag threshold is an assumption. The Variant C prototype
   should validate or adjust this.

5. **Rotary control type for Variant D:** Arc slider, numeric scrubber, or miniature dial. The
   choice affects how many layers fit in the row simultaneously. Must be resolved after Variant D
   prototype review. (Carried from UX review question 3.)

6. **Chord-generator model gap:** Chord identity per step is not in `ClipContent`. Either the
   chord-generator track type provides a mapping from step index to chord name, or the
   `chordLabel` cell variant is permanently stubbed. Must be resolved before spec covers
   chord-generator track support. (Carried from UX review question 4.)
