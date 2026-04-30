---
feature: step-sequencer
created: 2026-04-30
---

# Step Sequencer Plan

## Status

PM plan — ready for build queue. No production code has been written.

---

## Overview

The Step Sequencer feature introduces a `UnifiedStepCell` primitive, a
`StepGridCoordinator` view model, a `StepSelectionModel`, and a `StepClipboard`
— all transient, never persisted — to replace the four structurally distinct
step-cell primitives with a single coherent editing surface. The selected UX
direction is Variant D (rotary layer row): when steps are selected, the layer
tab row transforms into a row of arc-dial rotary controls that write to all
selected steps in a single batch mutation.

The plan runs in three phases: Phase 0 (read-only verification of live
codebase assumptions), Phase 1 (core model and coordinator), and Phase 2
(UI surfaces and tests). No document model changes are required.
`StepSelectionModel` and `StepClipboard` are transient runtime state and must
never appear in any `Codable` type.

---

## Phase 0 — Pre-Build Verification (read-only)

Phase 0 is a read-and-confirm pass. No production code is written. Its purpose
is to validate the spec's stated assumptions against the live codebase so the
implementer is not surprised mid-build.

---

### 0-A. Confirm `StepSelectionModel` Does Not Already Exist

**What it is.** The spec defines `StepSelectionModel` as a new type. Confirm no
equivalent type exists under a different name before introducing a duplicate.

**Files to read.**

- `Sources/` — search for any type carrying both a `clipID` field and a step
  index set or array; search for `selectedStep`, `stepSelection`, or
  `SelectionModel` in type names.
- `Sources/Document/ClipContent.swift`, `ClipPoolEntry.swift`,
  `StepSequenceTrack.swift` — confirm no selection field is present in any
  `Codable` type (this would be a spec violation if found).

**Exit criteria.**

- Implementer records: "no equivalent type found" or "found `<TypeName>` at
  `<path>`, use or rename instead of adding a duplicate."
- Confirm `StepSelectionModel` fields (`clipID`, `selectedStepIndexes: Set<Int>`)
  are not already present in any persisted type.

---

### 0-B. Confirm `ClipContent.MacroLane` Mutation API

**What it is.** The spec (Section 5b) says macro-layer writes go through
`ClipContent.MacroLane` overrides via `session.mutateClip`. Confirm the API
shape and indexing convention before the coordinator is built.

**Files to read.**

- `Sources/Document/ClipContent.swift` — locate `MacroLane` type (or the
  field on `ClipContent` that stores per-step, per-macro override values).
  Confirm it is indexed by `TrackMacroBinding` array index (0-based), not by
  a layer-position integer or a UUID.
- `Sources/Session/SequencerDocumentSession.swift` (or equivalent) — locate
  `mutateClip` and confirm its closure signature receives a mutable `ClipContent`
  or `ClipPoolEntry`. Confirm whether the closure runs synchronously or on an
  actor.

**Exit criteria.**

- Implementer records the exact field name, indexing key type, and whether
  overrides are stored as `[Int: Double?]`, `[Int: Double]`, or another shape.
- Implementer records the `mutateClip` closure signature and actor isolation
  context so the coordinator's batch writes are shaped correctly.
- If `MacroLane` does not exist or uses a different indexing key, record the
  finding and flag it as a spec deviation requiring a PM note before
  implementation proceeds.

---

### 0-C. Confirm `session.mutateClip` Closure Shape and Actor Isolation

**What it is.** The spec (Section 5a) requires all batch writes to be a single
`session.mutateClip` closure. Confirm the closure shape and whether transient
state captured in it must be copied before the closure forms (the `Sendable`
constraint noted in spec Section 5a).

**Files to read.**

- `Sources/Session/SequencerDocumentSession.swift` (or equivalent) — read the
  `mutateClip` declaration. Note whether it is `async`, uses an `@MainActor`
  closure, or requires a `@Sendable` closure parameter.
- `Tests/SequencerAITests/StepGridTapLatencyTests.swift` — confirm this file
  exists and understand the reference project size (8 tracks, 4 patterns,
  32-step clips, 4 phrases) and the 16 ms budget assertion. Record the test
  method name so the implementation loop knows exactly which test must still
  pass.

**Exit criteria.**

- Implementer records the exact `mutateClip` signature.
- Implementer records whether `@Sendable` is required, so the `let indexes =
  selectedStepIndexes` copy-before-closure pattern is written correctly from
  the start.
- Implementer confirms `StepGridTapLatencyTests` exists and is currently
  passing (or records that it is absent and must be located under a different
  name).

---

### 0-D. Confirm `UnifiedStepCell` Location and `StepGridCell` Access Level

**What it is.** The spec (Section 8) notes that `StepGridCell` is `private`
inside `StepGridView.swift`. Confirm this before deciding where to introduce
`UnifiedStepCell`.

**Files to read.**

- `Sources/UI/StepGrid/StepGridView.swift` (or the file containing
  `StepGridCell`) — confirm the access level of `StepGridCell` and whether it
  is `private`, `fileprivate`, or `internal`.
- Confirm the current location of `StepVisualState` (the enum whose three cases
  must remain unbroken). Record the file and whether it is `public` or
  `internal`.

**Exit criteria.**

- Implementer records whether `StepGridCell` must be made `internal` before
  `UnifiedStepCell` can reference its visual conventions, or whether
  `UnifiedStepCell` should be introduced as a fully independent type in a new
  file.
- Implementer records the file where `StepVisualState` lives, confirming that
  the `isSelected` separate-parameter approach does not require any change to
  that enum.

---

### 0-E. Confirm `SliceStepStrip` Velocity/Chance Stub Location

**What it is.** The spec (Section 7b) says the velocity and chance layer tabs
on `SliceStepStrip` are disabled stubs (`isEnabled: false`). Confirm the exact
guard and file before enabling them.

**Files to read.**

- `Sources/UI/SliceTrack/SliceStepStrip.swift` (or the file containing the
  slicer step editor) — locate the `isEnabled: false` guards on the velocity
  and chance layer tab entries. Record the line numbers or method names.

**Exit criteria.**

- Implementer records exactly which guards must be removed or changed to
  `isEnabled: true` and wired to the new unified cell path.

---

## Phase 1 — Core Model and Coordinator

Phase 1 introduces the two new transient types (`StepSelectionModel`,
`StepClipboard`) and the `StepGridCoordinator`. No UI views are modified in
this phase. The coordinator is wired to its owner but not yet connected to any
view.

Phase 1 may begin after Phase 0 findings are recorded.

---

### 1-A. Introduce `StepSelectionModel`

**What it is.** A new value type (or `@Observable` class if shared mutation is
needed) representing the current selection state for one clip-editing context.

**Shape (from spec Section 2a).**

```swift
// StepSelectionModel.swift  (new file)
struct StepSelectionModel {   // or: @Observable class StepSelectionModel
    var clipID: ClipID
    var selectedStepIndexes: Set<Int> = []
}
```

**Lifetime rules the implementation must enforce (spec Section 2a).**

- Cleared on: navigate away from clip-editing context, active track change,
  active clip change, document close, Escape key, tap on empty grid area.
- NOT cleared on: active layer tab change.

**Files touched.**

- `Sources/StepGrid/StepSelectionModel.swift` (new file — confirm parent
  directory with Phase 0-D finding)

**Tests to add.**

- Unit test: constructing `StepSelectionModel` with clipID A, then updating
  to clipID B, clears `selectedStepIndexes`.
- Unit test: selection is NOT cleared when clipID is unchanged and only a
  layer-mode value changes.
- Unit test: `selectedStepIndexes` accepts non-contiguous indexes (e.g.,
  {0, 3, 7}) without reordering or deduplication error.

**Acceptance signals.**

- `StepSelectionModel` is not `Codable` and is not referenced by any
  `Codable` type.
- The three unit tests above pass.

**Spec traceability.** Section 2a (StepSelectionModel shape and lifetime rules),
AC-3.1, AC-4.1, AC-4.4.

---

### 1-B. Introduce `StepClipboard`

**What it is.** A session-scoped transient type storing copied step data for
all layers. Not persisted.

**Shape (from spec Section 2b).**

```swift
// StepClipboard.swift  (new file)
struct StepClipboardEntry {
    var active: Bool
    var velocity: Double?
    var chance: Double?
    var macroOverrides: [Int: Double?]
    var sliceIndex: Int?
    var sliceMode: Int?
}

struct StepClipboard {
    var sourceClipID: ClipID
    var steps: [Int: StepClipboardEntry]   // keyed by source step index (0-based)
}
```

**Files touched.**

- `Sources/StepGrid/StepClipboard.swift` (new file)

**Tests to add.**

- Unit test: copy N steps produces `steps.count == N` entries with all layer
  fields populated.
- Unit test: clipboard survives an active-clip change (the coordinator holds
  it across clip switches) — this will be exercised more fully in Phase 2, but
  the type's independence from `ClipID` should be confirmed here.

**Acceptance signals.**

- `StepClipboard` is not `Codable`.
- Unit tests pass.

**Spec traceability.** Section 2b (StepClipboard shape), Section 5c
(copy/paste scope, all-layers), AC-5.3, AC-5.4.

---

### 1-C. Introduce `StepGridCoordinator`

**What it is.** An `@Observable` class that owns `StepSelectionModel` and
`StepClipboard`, converts track-type-specific data to `StepCellContent` per
step and per active layer, handles cell callbacks, and exposes derived
visibility flags to the view layer.

**Owner rule (spec Section 2c).** The coordinator MUST be owned by the track
workspace view model (a stable `@Observable` reference type), not by any view's
`@State`. It is injected via SwiftUI environment or initializer parameter.

**Responsibilities.**

- Convert step data to `StepCellContent` for the active layer and track type.
- Handle `onTap` and `onDrag` callbacks; dispatch to `session.mutateClip` as
  a single batch closure for all affected indexes.
- Copy `selectedStepIndexes` to a local `let` before forming any `mutateClip`
  closure (required by the `@Sendable` constraint confirmed in Phase 0-C).
- Expose: `isSelectionActive: Bool`, `shouldShowRotaryRow: Bool`,
  `shouldShowBatchActionBar: Bool`.
- Resolve `TrackMacroBinding` index from the active layer tab using the
  `StepSequenceTrack.macros` array index — never the tab position (spec
  Section 5b, MacroLane Index Mapping).
- Enforce selection-clear events (clip change, track change, Escape, background
  tap).

**Files touched.**

- `Sources/StepGrid/StepGridCoordinator.swift` (new file)
- Track workspace view model file (to add coordinator as a stored property and
  inject it) — specific file to be confirmed from Phase 0-D finding.

**Tests to add.**

- Unit test: `onTap` for a single step calls `session.mutateClip` exactly once
  and the closure mutates only that step's index.
- Unit test: `onTap` for a step in a 4-step selection calls `session.mutateClip`
  exactly once and the closure mutates all 4 indexes.
- Unit test: `onDrag(value:)` for a step in a 4-step selection applies the
  same absolute value to all 4 steps in one closure.
- Unit test: coordinator writes to `MacroLane[bindingIndex]` (the
  `TrackMacroBinding` array index), not to an implicit tab-position index.
- Unit test: `isSelectionActive` is `false` when `selectedStepIndexes` is
  empty; `true` when at least one index is present.
- Unit test: `shouldShowRotaryRow` is `true` when selection is active and at
  least one editable layer exists; `false` when selection is empty.

**Acceptance signals.**

- All unit tests above pass.
- The coordinator does not own a reference to any SwiftUI view type.
- No `mutateClip` call opens more than one closure for a single user action.
- `StepGridTapLatencyTests` continue to pass (confirmed via Phase 0-C finding).

**Spec traceability.** Section 2c (coordinator shape), Section 5a (batch
mutation), Section 5b (MacroLane index mapping), AC-4.2, AC-4.3.

---

### 1-D. Introduce `StepCellContent`

**What it is.** A new enum carrying the track-type-aware rendering variant
for a single step cell. This is a type-only addition; no view is modified in
Phase 1.

**Shape (from spec Section 3b).**

```swift
enum StepCellContent {
    case toggle
    case valueBar(fraction: Double)
    case sliceLabel(index: Int, label: String)
    case chordLabel(name: String)
    case optionLabel(text: String)
}
```

**Files touched.**

- `Sources/StepGrid/StepCellContent.swift` (new file; or colocated with
  `UnifiedStepCell` — confirm with Phase 0-D finding)

**Tests to add.**

- No standalone tests needed for an enum. Coverage comes from coordinator
  conversion tests in 1-C.

**Acceptance signals.**

- The enum compiles. All five cases are reachable from the coordinator's
  conversion logic.

**Spec traceability.** Section 3b.

---

## Phase 2 — UI Surfaces and Tests

Phase 2 begins after Phase 1 is complete and the coordinator has passing unit
tests. It wires the coordinator to views, introduces `UnifiedStepCell`, applies
the layer tab row transform, and enables the disabled slicer velocity/chance
stubs.

---

### 2-A. Introduce `UnifiedStepCell`

**What it is.** A new SwiftUI view that renders a single step cell for any
track type and any layer, given the parameters defined in spec Section 3a.

**Parameters (from spec Section 3a).**

| Parameter | Type |
|---|---|
| `visualState` | `StepVisualState` |
| `isPlaying` | `Bool` |
| `isSelected` | `Bool` |
| `content` | `StepCellContent` |
| `onTap` | `() -> Void` |
| `onDrag` | `((Double) -> Void)?` |
| `onSelect` | `() -> Void` |

**Four-state visual composition rules (spec Section 3d).**

- Active (`.on`/`.accented`): filled background.
- Inactive (`.off`): unfilled background.
- Playing: green 1pt border inset overlay.
- Selected: amber 2pt border overlay.
- Playing + Selected: green inset shadow + amber border (compound).
- Value layer: vertical fill bar height from `fraction`; visible regardless of
  active state.

**Tap-vs-drag disambiguation (spec Section 4b).** A displacement of fewer than
4 pt from the initial touch point is a tap; 4 pt or more activates the drag
path and suppresses `onTap`.

**Selection gesture (spec Section 4d).**

- macOS: right-click adds the step to `selectedStepIndexes` (toggle select on
  second right-click).
- Touch: long-press ≥ 400 ms adds the step (same toggle behavior).

**Fixed frame rule (spec Section 3c).** Cell geometry is constant regardless
of the active `StepCellContent` variant. Layer switches must not change cell
size or break spatial alignment.

**Files touched.**

- `Sources/StepGrid/UnifiedStepCell.swift` (new file)

**Rendering tests to add.**

- Snapshot / preview test: a cell with `visualState: .on`, `isPlaying: true`,
  `isSelected: true`, `content: .valueBar(fraction: 0.7)` renders with all
  four states simultaneously visible and distinguishable.
- Snapshot test: a cell with `visualState: .off`, `isSelected: true` renders
  with an amber border and an unfilled background.
- Snapshot test: `content: .toggle` and `content: .valueBar(fraction: 0.5)`
  produce cells of identical frame dimensions.

**Acceptance signals.**

- AC-1.2, AC-1.3, AC-2.1, AC-2.2, AC-2.3 all pass.
- The three snapshot/preview tests above pass.

**Spec traceability.** Sections 3a–3d, 4b, 4d; AC-1.2, AC-1.3, AC-2.1,
AC-2.2, AC-2.3, AC-6.1, AC-6.2.

---

### 2-B. Migrate Step Grid (Trigger and Value Layers) to `UnifiedStepCell`

**What it is.** Wire the clip editor's step grid — at minimum the trigger layer
(`StepGridView`) and the velocity/chance value layers — to use `UnifiedStepCell`
via the coordinator. The existing `StepGridCell` type is not deleted in this
feature's scope; the migration is limited to views directly modified by the user
stories.

**Key constraint (spec Section 8).** `StepGridCell` may need to be made
`internal` (from `private`) to allow visual convention reuse. The Phase 0-D
finding governs whether this is necessary or whether `UnifiedStepCell` is fully
independent.

**Files touched.**

- `Sources/UI/StepGrid/StepGridView.swift` — wire `StepGridCoordinator` as
  the data source for cell parameters; replace the trigger-layer cell with
  `UnifiedStepCell`. If `StepGridCell` access level must change, make it
  `internal` in this file.
- `Sources/UI/ClipEditor/ClipMacroLaneEditor.swift` (or equivalent) — wire
  the velocity and chance layer cell rendering to `UnifiedStepCell` via the
  coordinator's `StepCellContent` conversion.

**Tests to add.**

- UI test or snapshot test: switching the active layer from Steps to Velocity
  changes every cell from `.toggle` to `.valueBar(fraction:)` without changing
  cell geometry or step positions (AC-6.1).
- UI test: switching back from Velocity to Steps restores `.toggle` cells;
  velocity values are unchanged (AC-6.2).

**Acceptance signals.**

- AC-1.1 (UnifiedStepCell used in clip editor trigger and velocity layers).
- AC-6.1, AC-6.2.
- `StepGridTapLatencyTests` continue to pass.

**Spec traceability.** Sections 3c, 4a, 4b, 8; AC-1.1, AC-6.1, AC-6.2.

---

### 2-C. Enable `SliceStepStrip` Velocity and Chance Layers

**What it is.** The velocity and chance layer tabs on `SliceStepStrip` are
currently `isEnabled: false` stubs (confirmed by Phase 0-E). This task removes
those guards and connects those layers to `UnifiedStepCell` via the coordinator.

**Files touched.**

- `Sources/UI/SliceTrack/SliceStepStrip.swift` — remove `isEnabled: false`
  guards on velocity and chance layer tab entries; wire to coordinator's
  `StepCellContent` conversion for `.valueBar(fraction:)`.

**Tests to add.**

- Unit test: `StepGridCoordinator` returns `.valueBar(fraction:)` content for
  a slicer clip step on the velocity layer.
- UI test: selecting a step in a slicer step strip shows the amber selection
  border; the batch action bar becomes visible.

**Acceptance signals.**

- AC-1.1 (UnifiedStepCell also used in the slicer track workspace step strip).
- No regression in slicer trigger-layer behavior (`.sliceLabel` cycling still
  works).

**Spec traceability.** Section 7b; AC-1.1, AC-1.2.

---

### 2-D. Layer Tab Row Transform (Rotary Row)

**What it is.** When `StepGridCoordinator.shouldShowRotaryRow` is `true`, the
layer tab row transforms into a row of arc-dial rotary controls (one per
editable layer). On deselection or Escape, it reverts to the plain tab row.

**State machine (spec Section 6a).**

| Mode | Condition |
|---|---|
| Tab mode | `selectedStepIndexes.isEmpty` |
| Rotary mode | `!selectedStepIndexes.isEmpty && hasEditableLayers` |

**Trigger layer behavior (spec Section 4e).** When the active layer is trigger
and steps are selected, the rotary row shows velocity and chance rotaries
unconditionally. If neither exists, show "No editable layers" text label.

**Rotary arc-dial per control (spec Section 6b).**

- SVG arc proportional to value (0 = empty, 1 = full).
- Layer name label below dial.
- Numeric value display inline (0–127 for velocity; 0–100% for chance/macro;
  1–N for option layers).
- Amber highlight border when the rotary corresponds to the active layer tab.
- Vertical drag: 80 pt = full range (0–1 normalized). Absolute value semantics.
- Rotary arc initializes to the value of the lowest-index selected step when
  selection changes.

**Overflow handling (spec Section 4h).** Up to four editable layers: fixed
row. Five or more: horizontally scrollable container with scroll indicator.
Minimum rotary width: 56 pt.

**Transition.** Immediate (no animation required for this scope).

**Files touched.**

- The layer tab row view file (to be identified from the track workspace view
  hierarchy; name to be confirmed from Phase 0 inspection).
- `Sources/StepGrid/StepGridCoordinator.swift` — the coordinator's
  `shouldShowRotaryRow` and editable-layer enumeration logic.

**Tests to add.**

- Snapshot / UI test: when `selectedStepIndexes` is non-empty and the active
  layer is not trigger, the layer row renders rotary controls (AC-3.2).
- Snapshot / UI test: when `selectedStepIndexes` is non-empty and the active
  layer is trigger, the layer row renders velocity and chance rotaries (AC-3.3).
- Snapshot / UI test: when `selectedStepIndexes` is empty, the layer row
  renders plain tabs.
- Unit test: coordinator returns `shouldShowRotaryRow == false` when selection
  is active but all layers are stubs (no editable layers).

**Acceptance signals.**

- AC-3.2, AC-3.3, AC-3.4, AC-4.2.
- Rotary row is horizontally scrollable when the track has five or more editable
  layers.

**Spec traceability.** Sections 4e, 4f, 4g, 4h, 6a, 6b; AC-3.2, AC-3.3,
AC-4.2.

---

### 2-E. Batch Action Bar

**What it is.** A bar below the step grid with three actions: Clear, Copy,
Paste. Visible when `shouldShowBatchActionBar` is `true`; hidden (not
collapsed) when `false`.

**Visibility rule (spec Section 3e).** Hidden via `opacity(0)` combined with
`allowsHitTesting(false)`. Must NOT be removed from the view hierarchy or
collapsed to zero height. No layout shift when it appears or disappears.

**Action semantics (spec Sections 4, 5c).**

- **Clear:** sets `visualState` to `.off` for all selected steps in one
  `mutateClip` closure; then clears `selectedStepIndexes`.
- **Copy:** writes all selected steps' data (all layers, all fields in
  `StepClipboardEntry`) into `StepClipboard`. Does not mutate clip data.
- **Paste:** reads `StepClipboard.steps` and writes each entry to the same
  step index in the active clip in one `mutateClip` closure. Steps whose
  target index is out of bounds are silently skipped.

**Files touched.**

- The step grid host view file (to be confirmed from Phase 0 findings).
- `Sources/StepGrid/StepGridCoordinator.swift` — Clear, Copy, Paste action
  handlers.

**Tests to add.**

- UI test: grid frame is identical before and after `shouldShowBatchActionBar`
  changes from `false` to `true` (AC-5.1, no layout shift).
- Unit test: Clear sets all selected steps' active state to `.off` in one
  `mutateClip` closure and empties `selectedStepIndexes` (AC-5.2).
- Unit test: Copy populates `StepClipboard.steps` with entries for all
  selected indexes, all layers populated (AC-5.3).
- Unit test: Paste after copy round-trip confirms velocity, chance, and
  macroOverride values are preserved per step (AC-5.4).

**Acceptance signals.**

- AC-5.1, AC-5.2, AC-5.3, AC-5.4.
- No layout shift test fails.

**Spec traceability.** Sections 3e, 5c; AC-5.1–AC-5.4.

---

### 2-F. Selection Lifetime Wiring and Escape / Background Tap

**What it is.** Connect the selection-clear events defined in spec Section 2a
to the coordinator. The coordinator already owns `StepSelectionModel`; this
task wires the external events that must trigger a clear.

**Events to wire.**

| Event | Mechanism |
|---|---|
| Active clip changes | Track workspace view model notifies coordinator on clip switch |
| Active track changes | Track workspace view model replaces coordinator (coordinator has a fresh empty selection) |
| Document closes | Coordinator is discarded with the track workspace view model |
| Escape key (macOS) | Key handler in the step grid host view calls `coordinator.clearSelection()` |
| Tap on empty grid area | Tap gesture on the grid background (outside any cell) calls `coordinator.clearSelection()` |

**Files touched.**

- `Sources/StepGrid/StepGridCoordinator.swift` — add `clearSelection()` method.
- Track workspace view model — wire clip-switch notification.
- Step grid host view — wire Escape key handler and background tap gesture.

**Tests to add.**

- Unit test: calling `coordinator.clearSelection()` empties
  `selectedStepIndexes` (AC-4.4).
- Unit test: updating `coordinator`'s active clipID to a new value via the
  workspace view model clears `selectedStepIndexes`.
- Unit test: layer-tab change does NOT clear `selectedStepIndexes`.

**Acceptance signals.**

- AC-4.4 (Escape clears selection, amber borders disappear, rotary row reverts
  to tab row).
- All three unit tests pass.

**Spec traceability.** Section 2a (lifetime rules); AC-4.4.

---

### 2-G. Macro Layer Cell Support

**What it is.** Wire the macro layer tabs (for tracks with enabled macro
bindings) to `UnifiedStepCell` via the coordinator's `StepCellContent`
conversion. Per-step `MacroLane` override values drive `.valueBar(fraction:)`.

**MacroLane Index Mapping (spec Section 5b).** The coordinator reads
`StepSequenceTrack.macros: [TrackMacroBinding]` and uses the array index
(0-based, stable order) as the `MacroLane` key. It must NOT use the tab
position as the index.

**Files touched.**

- `Sources/StepGrid/StepGridCoordinator.swift` — `StepCellContent` conversion
  for macro layers.
- `Sources/UI/ClipEditor/ClipMacroLaneEditor.swift` (or equivalent) — wire
  macro layer view to `UnifiedStepCell`.

**Tests to add.**

- Unit test: coordinator maps macro layer tab at position N to
  `MacroLane[bindingIndex]` where `bindingIndex` is the `TrackMacroBinding`
  array index, not N (AC-6.3 and spec Section 5b).

**Acceptance signals.**

- AC-6.3 (switching to a macro layer renders `.valueBar(fraction:)` from
  per-step `MacroLane` override values).
- MacroLane index mapping unit test passes.

**Spec traceability.** Section 5b, Section 7a; AC-6.3.

---

### 2-H. Chord Generator Track Cell (Stub)

**What it is.** Wire chord generator track steps to `UnifiedStepCell` with the
`.chordLabel(name:)` content variant. The coordinator stubs the label from the
step's first note's pitch class (e.g., "C", "F#"). No chord-abstraction model
is built.

**Constraint (spec Section 7c).** Show chord name label only. The dot
representation is deferred until a chord model provides stable chord identity.
No changes to `UnifiedStepCell` are required for this task.

**Files touched.**

- `Sources/StepGrid/StepGridCoordinator.swift` — chord generator track
  `StepCellContent` conversion.

**Tests to add.**

- Unit test: coordinator returns `.chordLabel(name:)` for a chord generator
  track step on the trigger layer; the label is a non-empty string derived from
  the step's pitch class.

**Acceptance signals.**

- Chord generator steps render without crashing.
- No chord-abstraction model is introduced.

**Spec traceability.** Section 7c.

---

## Review Gate Between Phase 2 and Handoff

After Phase 2 is complete, the implementation team should self-review against
the acceptance criteria in `spec.md` Section 10 before marking the build
complete. The gate checklist:

- [ ] AC-1.1: `UnifiedStepCell` in use across clip editor (trigger, velocity, chance) and slicer step strip.
- [ ] AC-1.2: Tapping any step cell in any of those views uses tap-to-toggle; no secondary panel opens.
- [ ] AC-1.3: Dragging on a value layer cell produces in-cell value change.
- [ ] AC-2.1–2.3: Four-state rendering; all states simultaneously visible and distinguishable.
- [ ] AC-3.1–3.4: Right-click select; rotary row appears; batch action bar appears.
- [ ] AC-4.1–4.4: Multi-step selection; batch rotary write; single closure; Escape clears.
- [ ] AC-5.1–5.4: Batch action bar no layout shift; Clear; Copy; Paste round-trip.
- [ ] AC-6.1–6.3: Layer switch changes cell content type; geometry preserved; macro layer wired.
- [ ] `StepGridTapLatencyTests` pass.
- [ ] No `StepSelectionModel` or `StepClipboard` field in any `Codable` type.

---

## Files and Modules Touched

| File | Phase | Reason |
|---|---|---|
| `Sources/StepGrid/StepSelectionModel.swift` (new) | 1-A | New transient selection type |
| `Sources/StepGrid/StepClipboard.swift` (new) | 1-B | New transient clipboard type |
| `Sources/StepGrid/StepCellContent.swift` (new) | 1-D | New content variant enum |
| `Sources/StepGrid/StepGridCoordinator.swift` (new) | 1-C, 2-D, 2-E, 2-F, 2-G, 2-H | New coordinator: owns selection, clipboard, cell conversion, batch writes |
| Track workspace view model file (TBD from Phase 0) | 1-C | Add coordinator as stored property; inject into step grid |
| `Sources/UI/StepGrid/StepGridView.swift` | 2-B | Wire coordinator; replace trigger-layer cell with `UnifiedStepCell`; access-level fix for `StepGridCell` if needed |
| `Sources/UI/ClipEditor/ClipMacroLaneEditor.swift` (TBD) | 2-B, 2-G | Wire velocity/chance and macro layers to `UnifiedStepCell` |
| `Sources/UI/SliceTrack/SliceStepStrip.swift` | 2-C | Remove `isEnabled: false` stubs; wire slicer layers to `UnifiedStepCell` |
| Layer tab row view file (TBD from Phase 0) | 2-D | Layer tab row transform (tab ↔ rotary mode) |
| Step grid host view file (TBD from Phase 0) | 2-E, 2-F | Batch action bar; Escape key handler; background tap gesture |
| `Sources/StepGrid/UnifiedStepCell.swift` (new) | 2-A | New unified step cell primitive |
| Test files (multiple, TBD) | 1-A through 2-H | Unit and UI tests per task above |

Files marked TBD have their names gated on Phase 0 findings and must be
confirmed before Phase 1 or 2 work on those files begins.

---

## Tests Expected per Phase

| Phase | Test | Type |
|---|---|---|
| 1-A | Selection cleared when clipID changes | Unit |
| 1-A | Selection NOT cleared when layer-mode changes without clipID change | Unit |
| 1-A | Non-contiguous index set accepted | Unit |
| 1-B | Copy N steps produces N entries with all layer fields | Unit |
| 1-C | Single-step `onTap` produces exactly one `mutateClip` closure | Unit |
| 1-C | 4-step selection `onTap` produces exactly one `mutateClip` closure mutating all 4 | Unit |
| 1-C | `onDrag` for 4-step selection applies same absolute value to all 4 in one closure | Unit |
| 1-C | Coordinator writes to `MacroLane[bindingIndex]` not implicit tab position | Unit |
| 1-C | `isSelectionActive` and `shouldShowRotaryRow` derived correctly | Unit |
| 2-A | Four-state cell snapshot: `.on`, playing, selected, `.valueBar(fraction: 0.7)` | Snapshot |
| 2-A | `.off` + selected renders amber border, unfilled background | Snapshot |
| 2-A | `.toggle` and `.valueBar(fraction: 0.5)` have identical frame dimensions | Snapshot |
| 2-B | Layer switch from Steps to Velocity: cells change content, geometry unchanged | UI |
| 2-B | Layer switch Velocity → Steps: `.toggle` restored, velocity values unchanged | UI |
| 2-C | Coordinator returns `.valueBar` for slicer clip step on velocity layer | Unit |
| 2-C | Selection + batch bar visible on slicer step | UI |
| 2-D | Layer row renders rotary controls when selection active, active layer not trigger | Snapshot/UI |
| 2-D | Layer row renders velocity/chance rotaries when selection active, active layer is trigger | Snapshot/UI |
| 2-D | Layer row renders plain tabs when selection empty | Snapshot/UI |
| 2-D | `shouldShowRotaryRow == false` when all layers are stubs | Unit |
| 2-E | Grid frame identical before and after `shouldShowBatchActionBar` changes | UI |
| 2-E | Clear: all selected steps `.off` in one closure; selection emptied | Unit |
| 2-E | Copy: clipboard populated with all-layer data for all selected indexes | Unit |
| 2-E | Paste round-trip: velocity, chance, macroOverride preserved per step | Unit |
| 2-F | `clearSelection()` empties `selectedStepIndexes` | Unit |
| 2-F | Active clipID change clears selection | Unit |
| 2-F | Layer tab change does NOT clear selection | Unit |
| 2-G | MacroLane indexed by `TrackMacroBinding` array index, not tab position | Unit |
| 2-H | Coordinator returns `.chordLabel(name:)` for chord generator trigger step | Unit |

`StepGridTapLatencyTests` (existing) must continue to pass throughout.

---

## Migration and Data Shape Changes

None. No document fields are added, removed, or renamed. No schema version bump
is needed. `StepSelectionModel`, `StepClipboard`, and `StepGridCoordinator` are
all non-persistent transient types. The spec explicitly requires that these types
never appear in any `Codable` type; the implementation loop should add a
compile-time guard (e.g., a `static func confirmNotCodable()` that will not
compile if the types accidentally conform to `Codable`) or enforce this in tests.

---

## Risks and Dependencies

| Risk | Likelihood | Mitigation |
|---|---|---|
| `session.mutateClip` closure is `@Sendable`; capturing coordinator directly causes a compile error | High | Phase 0-C confirms the signature. Copy `selectedStepIndexes` to `let indexes` before closure formation (spec Section 5a). Document the pattern in coordinator source. |
| `StepGridCell` being `private` prevents visual convention reuse | Medium | Phase 0-D confirms the access level. If `private`, either make it `internal` in the same file (low risk, local change) or write `UnifiedStepCell` as a fully independent view (slightly more duplication, no access-level risk). |
| Layer order diverges from `TrackMacroBinding` array order | Medium | Use `StepSequenceTrack.macros` array index only; never derive from tab position. Unit test in 1-C and 2-G confirms this. |
| `StepGridTapLatencyTests` fail after batch write path is introduced | Medium | Phase 0-C confirms the test exists and is currently passing. After Phase 1-C (coordinator with batch write), run the latency tests before proceeding to Phase 2. |
| Touch drag sensitivity at 80 pt = full range may be too coarse for fine values | Low | Spec OQ-1 flags this. The 80 pt default is the prototype value; it should be validated on touch during 2-A implementation. Adjust the constant if needed; it does not require a spec change. |
| Chord generator steps crash if first note pitch class is absent (empty step) | Low | 2-H must guard for empty `noteGrid` steps and return a default label (e.g., "—"). |
| Horizontal scroll on rotary row is not accessible by keyboard | Low | Flag as a known accessibility gap. A future feature can add keyboard navigation for the rotary row. |

**External dependencies.** None. No other roadmap items are prerequisites.
`session.mutateClip`, `ClipContent.MacroLane`, and `StepSequenceTrack.macros`
all exist today (confirmed by `existing-state.md`). The only gating work is the
Phase 0 read pass.

---

## Sequencing Notes

1. Phase 0 is a read-only pass. All five tasks (0-A through 0-E) can be done
   in a single sitting and have no dependencies on each other.
2. Phase 1 tasks (1-A through 1-D) can proceed in any order once Phase 0 is
   complete. They introduce types only and do not touch UI views.
3. Run `StepGridTapLatencyTests` after Phase 1-C is complete. Do not advance
   to Phase 2 if they fail.
4. Phase 2 tasks have internal dependencies:
   - 2-A (`UnifiedStepCell`) must complete before 2-B, 2-C, 2-D, 2-E, 2-F.
   - 2-B (trigger/value layer wiring) can proceed in parallel with 2-C (slicer)
     once 2-A is done.
   - 2-D (rotary row), 2-E (batch action bar), and 2-F (selection lifetime
     wiring) each depend on the coordinator from Phase 1-C but not on each other.
   - 2-G (macro layer cell) and 2-H (chord cell stub) have no dependencies
     beyond Phase 1-C and 1-D.
5. The review gate runs after all of Phase 2 is complete.

---

## Non-Goals and Explicitly Deferred Work

The following must not be built as part of this plan:

- **Phrase-level step editing.** Writing to `PhraseCell.steps` from the step
  grid is out of scope. The rotary row writes to `ClipContent.MacroLane` only.
- **Cross-track paste.** `StepClipboard` does not support pasting into a
  different track's clip.
- **Offset paste.** Paste writes to the same step indexes as the source.
  Offset / relative paste is a future enhancement (spec OQ-3).
- **Relative delta rotary mode.** Absolute value semantics only; modifier-key
  relative delta is a future enhancement (spec Section 9).
- **Chord-generator model refactor.** `.chordLabel` uses a pitch-class stub.
  Full chord identity requires a separate feature.
- **Full migration of all existing step-cell call sites to `UnifiedStepCell`.**
  Only views that are directly modified by the user stories are migrated in this
  scope.
- **Animation of layer row transition.** The tab → rotary row transition is
  immediate. A cross-fade may be added later without a spec change.
- **Expanded drag zone for touch.** Long-press selection only; the expanded
  drag zone concept from Variant C is a future enhancement.
- **Accessibility beyond basic VoiceOver labelling.** Hardware controller
  mapping, dynamic type scaling, and high-contrast mode are not assessed here.
- **Keyboard navigation for rotary row.** The horizontally scrollable rotary
  row is not required to be keyboard-navigable in this scope.
