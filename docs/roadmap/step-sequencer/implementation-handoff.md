# Step Sequencer — Implementation Handoff

## Authoritative Context

| Artifact | When to open it |
|---|---|
| [spec.md](spec.md) | Primary build reference. Defines data shapes, interaction semantics, write paths, track-type coverage, acceptance criteria, and non-goals. All product decisions are locked here. |
| [plan.md](plan.md) | Phase sequence and per-task details with file names, shape definitions, tests to write, and sequencing constraints. Read this first when starting each phase. |
| [architecture.md](architecture.md) | Invariants and guardrails the implementation must preserve. Written before the final UX direction was confirmed; Section 4d (Layer Tab Row Transform) carries a "requires revision" note — treat `ux-review.md` and `spec.md` as authoritative where they differ. |
| [architecture-review.md](architecture-review.md) | Accepted verdict. Covers approved guardrails, missed or under-specified items, and the five open questions the spec must resolve. All five are resolved in `spec.md`. |
| [ux-review.md](ux-review.md) | Accepted verdict. Variant D (Rotary Layer Row) is the selected direction. Contains the head-to-head comparison with Variant C and the open questions that were resolved during the architecture and spec passes. |
| [prototypes/variant-d-rotary-layer-row.html](prototypes/variant-d-rotary-layer-row.html) | Selected prototype. Use for layout and interaction reference. The rotary row, in-cell drag, batch action bar, and four-state cell are all live in this prototype. |
| [prototypes/variant-c-in-cell-drag.html](prototypes/variant-c-in-cell-drag.html) | Variant C. The in-cell drag bar and four-state cell visual conventions originated here and carry forward into Variant D. Use as a secondary reference for cell rendering. |
| [existing-state.md](existing-state.md) | What exists today: the four distinct cell types, their gaps versus the user stories, architecture constraints, and which tests already exist. Read before starting Phase 0. |

---

## Goal

The Step Sequencer feature replaces four structurally distinct step-cell
primitives (`StepGridCell`, `MacroLaneCell`, `SliceStepStrip` cell, `GridEditor`
column) with a single `UnifiedStepCell` primitive that works across all track
types (note grid, slicer, chord generator) and all layer modes (toggle, value
bar, slice label, chord label). It adds multi-step selection, a rotary layer row
that transforms the layer tab strip when steps are selected, and a batch action
bar with Clear, Copy, and Paste. No document model changes are required.
`StepSelectionModel`, `StepClipboard`, and `StepGridCoordinator` are all
transient runtime state and must never appear in any `Codable` type.

---

## Chosen UX Direction

**Variant D — Rotary Layer Row.**

When no steps are selected, the step grid looks and behaves as it does today
(unified cell primitive, layer tabs at top). Right-click (macOS) or long-press
(≥ 400 ms, touch) adds a step to the selection and shows an amber border on that
cell. When any step is selected, the layer tab row transforms into a row of SVG
arc-dial rotary controls — one per editable layer — labeled "STEP EDIT". Turning
a rotary writes an absolute value to all selected steps simultaneously in a
single batch `session.mutateClip` closure.

For single-step value editing (the fast path), the cell itself remains the
editing surface: value layers show a vertical drag bar inside the cell. The
rotary row is the multi-step editing path; both paths are always available when
steps are selected.

The batch action bar (Clear / Copy / Paste) sits below the grid and is hidden
(not collapsed) when no steps are selected, so the grid never shifts.

See `ux-review.md` for the full head-to-head comparison with Variant C and
`spec.md` Sections 4 and 6 for the complete interaction contract.

---

## Guardrails and Invariants

These are hard constraints from `architecture.md` and `architecture-review.md`.
The implementation must preserve all of them.

### Project-Wide Guardrails

**1. No transient state in the document.**
`StepSelectionModel`, `StepClipboard`, and `StepGridCoordinator` must never
conform to `Codable` and must never be referenced by any `Codable` type
(`ClipContent`, `ClipPoolEntry`, `StepSequenceTrack`, `SequencerDocument`).
Recommended guard: add a compile-time assertion or test that confirms these types
do not conform to `Codable`.

**2. Playback snapshots and buffers are untouched.**
`ClipBuffer`, `PlaybackSnapshot`, `PhrasePlaybackBuffer`, and
`SequencerSnapshotCompiler` are not modified by this feature. All per-step writes
go through `session.mutateClip`; the snapshot invalidation path already handles
this.

**3. Batch writes are a single `session.mutateClip` closure.**
Applying any value change (toggle, drag, rotary, clear, paste) to N selected
steps must be a single `mutateClip` closure — not N sequential closures. This is
required by the 16 ms tap-to-invalidation budget measured in
`StepGridTapLatencyTests`. N separate closures are not permitted.

**4. No broad rewrites of existing cell types.**
`StepGridCell`, `MacroLaneCell`, `SliceStepStrip` cells, and `GridEditor` columns
stay in place. Only the views directly modified to implement the user stories are
migrated to `UnifiedStepCell`. Forcing full migration of all call sites within
this feature's scope would turn a focused improvement into a broad rewrite.

### Feature-Specific Guardrails

**5. `StepSelectionModel` is transient-only.**
`clipID: ClipID` and `selectedStepIndexes: Set<Int>` — that is all. No encoding,
no archiving. The type is cleared (not persisted) when the user navigates away
from the clip-editing context, changes tracks, changes the active clip, closes
the document, presses Escape, or taps on the empty grid area. Switching the
active layer tab does NOT clear selection (spec Section 2a lifetime rules).

**6. `StepClipboard` is transient-only.**
`sourceClipID: ClipID` and `steps: [Int: StepClipboardEntry]` — transient,
session-scoped. Not persisted. Survives active-clip changes within the same
session (enabling cross-clip paste). Discarded on document close. Not persisted.

**7. `StepGridCoordinator` must not be owned by any view's `@State`.**
The coordinator is owned by the track workspace view model — a stable
`@Observable` reference type with a lifetime tied to the track workspace session.
If the coordinator is created as `@State var` on a SwiftUI view, selection state
will be lost on view recreation. It must be injected via environment or
initializer parameter from the workspace view model (spec Section 2c).

**8. Actor isolation — copy before closure.**
`session.mutateClip` is actor-isolated. Any `StepSelectionModel` or
`StepClipboard` reference captured in a `mutateClip` closure must be copied to a
local `let` before the closure is formed (e.g., `let indexes =
selectedStepIndexes`). The coordinator itself must not be captured. Phase 0-C
confirms the exact closure signature.

**9. `MacroLane` writes must use `TrackMacroBinding` array index.**
The coordinator maps a macro layer tab to its `MacroLane` index by reading
`StepSequenceTrack.macros: [TrackMacroBinding]` and using the 0-based array
index. It must NOT derive the index from tab position — `existing-state.md`
confirms that tab order and binding array order can diverge.

**10. `StepVisualState` is not modified.**
The existing `.off` / `.on` / `.accented` enum and all its callers remain
unbroken. `isSelected` is a separate `Bool` parameter on `UnifiedStepCell`, not
a fourth enum case.

**11. Batch action bar is hidden, not collapsed.**
When no steps are selected, the batch action bar is hidden via `opacity(0)` +
`allowsHitTesting(false)`. It is NOT removed from the view hierarchy and NOT
collapsed to zero height. This prevents the grid layout from shifting when the
bar appears or disappears (spec Section 3e, AC-5.1).

---

## Sequencing and Phases

### Phase 0 — Pre-Build Verification (read-only, no code written)

Five read-only tasks. All five can be done in a single sitting with no
dependencies on each other. Findings gate Phase 1.

**0-A. Confirm `StepSelectionModel` does not already exist.**
Search `Sources/` for any type with a `clipID` field and a step-index set or
array; search for `selectedStep`, `stepSelection`, `SelectionModel` in type
names. Confirm `ClipContent.swift`, `ClipPoolEntry.swift`, and
`StepSequenceTrack.swift` contain no selection fields in `Codable` types.
Record: "no equivalent type found" or "found `<TypeName>` at `<path>`."

**0-B. Confirm `ClipContent.MacroLane` mutation API.**
Read `Sources/Document/ClipContent.swift` — locate `MacroLane` and confirm it is
indexed by `TrackMacroBinding` array index (0-based). Read
`SequencerDocumentSession.swift` — locate `mutateClip` and record its closure
signature and actor isolation. If `MacroLane` uses a different indexing key,
record as a spec deviation and flag before proceeding.

**0-C. Confirm `session.mutateClip` closure shape and actor isolation.**
Read the `mutateClip` declaration — note whether `@Sendable` is required. Read
`Tests/SequencerAITests/Performance/StepGridTapLatencyTests.swift` — confirm the
file exists and is currently passing; record the test method names and the
reference project size (8 tracks, 4 patterns, 32-step clips, 4 phrases).

**0-D. Confirm `UnifiedStepCell` location and `StepGridCell` access level.**
Read `Sources/UI/StepGridView.swift` (or the file containing `StepGridCell`) —
record whether `StepGridCell` is `private`, `fileprivate`, or `internal`. Record
the file where `StepVisualState` lives and confirm it is `internal` or wider.
Determine whether `UnifiedStepCell` should be placed in the same file or a new
file under `Sources/StepGrid/`.

**0-E. Confirm `SliceStepStrip` velocity/chance stub location.**
Read `Sources/UI/Slicer/SliceTrackEditingControls.swift` (or the file containing
the slicer step editor) — locate the `isEnabled: false` guards on the velocity
and chance layer tab entries. Record the exact lines to change.

---

### Phase 1 — Core Model and Coordinator

Introduces `StepSelectionModel`, `StepClipboard`, `StepCellContent`, and
`StepGridCoordinator`. No UI views are modified. Phase 1 may begin after Phase 0
findings are recorded.

**1-A. Introduce `StepSelectionModel`** — new file
`Sources/StepGrid/StepSelectionModel.swift` (directory confirmed by Phase 0-D).

```swift
struct StepSelectionModel {   // or @Observable class if shared mutation needed
    var clipID: ClipID
    var selectedStepIndexes: Set<Int> = []
}
```

Tests: selection cleared when clipID changes; NOT cleared when layer mode
changes; non-contiguous index set accepted. Type must not conform to `Codable`.

**1-B. Introduce `StepClipboard`** — new file
`Sources/StepGrid/StepClipboard.swift`.

```swift
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
    var steps: [Int: StepClipboardEntry]
}
```

Tests: copy N steps produces N entries with all layer fields populated. Type must
not conform to `Codable`.

**1-C. Introduce `StepGridCoordinator`** — new file
`Sources/StepGrid/StepGridCoordinator.swift`. Owns `StepSelectionModel` and
`StepClipboard`. Responsibilities (full list in spec Section 2c and plan task
1-C): convert model data to `StepCellContent` per step per active layer, dispatch
`onTap`/`onDrag` as single-closure batch writes, expose `isSelectionActive`,
`shouldShowRotaryRow`, `shouldShowBatchActionBar`, enforce selection-clear events,
resolve `TrackMacroBinding` index for macro writes.

Owner: track workspace view model (a stable `@Observable`). Must NOT be
instantiated as `@State` on any view.

Copy-before-closure rule: `let indexes = selectedStepIndexes` before every
`mutateClip` closure (per guardrail 8).

Tests: single-step `onTap` calls `mutateClip` exactly once; 4-step selection
`onTap` calls `mutateClip` exactly once mutating all 4; `onDrag` for 4-step
selection applies same absolute value to all 4; coordinator writes to
`MacroLane[bindingIndex]` not implicit tab position; `isSelectionActive` and
`shouldShowRotaryRow` derived correctly.

Run `StepGridTapLatencyTests` after 1-C. Do not advance to Phase 2 if they fail.

**1-D. Introduce `StepCellContent`** — new file (colocated with `UnifiedStepCell`
or as a separate file; confirmed by Phase 0-D).

```swift
enum StepCellContent {
    case toggle
    case valueBar(fraction: Double)
    case sliceLabel(index: Int, label: String)
    case chordLabel(name: String)
    case optionLabel(text: String)
}
```

No standalone tests needed; coverage comes from coordinator conversion tests
in 1-C.

---

### Phase 2 — UI Surfaces and Tests

Begins after Phase 1 is complete and coordinator unit tests pass.

**2-A. Introduce `UnifiedStepCell`** — new file
`Sources/StepGrid/UnifiedStepCell.swift`.

Parameters: `visualState: StepVisualState`, `isPlaying: Bool`, `isSelected: Bool`,
`content: StepCellContent`, `onTap: () -> Void`, `onDrag: ((Double) -> Void)?`,
`onSelect: () -> Void`.

Fixed frame regardless of `StepCellContent` variant. Tap-vs-drag disambiguation
at 4 pt displacement threshold. Selection gesture: right-click (macOS) / long-
press ≥ 400 ms (touch) — toggle select.

Four-state visual composition (spec Section 3d): active = filled background,
inactive = unfilled, playing = green 1pt inset border, selected = amber 2pt
border, playing+selected = green inset shadow + amber border, value = vertical
fill bar height regardless of active state.

Snapshot tests: four-state compound state renders without ambiguity; `.off` +
selected shows amber border; `.toggle` and `.valueBar(fraction: 0.5)` have
identical frame dimensions.

2-A must complete before 2-B through 2-F.

**2-B. Migrate clip editor (trigger and value layers) to `UnifiedStepCell`.**
Wire `StepGridView.swift` to use `StepGridCoordinator` as the data source. If
`StepGridCell` is `private` (Phase 0-D finding), make it `internal` in the same
file. Wire velocity/chance layers in `ClipMacroLaneEditor.swift` (or equivalent)
to `UnifiedStepCell` via the coordinator's `.valueBar(fraction:)` conversion.

UI tests: layer switch Steps→Velocity changes cell content type without changing
geometry; Velocity→Steps restores `.toggle` with values unchanged.

**2-C. Enable `SliceStepStrip` velocity and chance layers.**
Remove `isEnabled: false` guards identified in Phase 0-E. Wire to coordinator's
`.valueBar(fraction:)` conversion. Tests: coordinator returns `.valueBar` for a
slicer clip step on velocity layer; selection + batch bar visible on slicer strip.

**2-D. Layer tab row transform (rotary row).**
When `coordinator.shouldShowRotaryRow` is `true`, the layer tab row transforms to
a row of arc-dial rotary controls (spec Section 6). State machine: tab mode when
`selectedStepIndexes.isEmpty`; rotary mode when non-empty and `hasEditableLayers`.
Transition is immediate (no animation required).

Trigger-layer behavior (spec 4e): when active layer is trigger and steps are
selected, show velocity and chance rotaries unconditionally. If none exist, show
"No editable layers" text.

Rotary semantics: absolute value (spec 4f). Arc initializes to lowest-index
selected step value. Drag sensitivity: 80 pt = full range. Overflow: up to four
layers fixed row; five or more layers horizontal scroll with scroll indicator;
minimum rotary width 56 pt.

Snapshot/UI tests: rotary row renders when selection active + non-trigger layer;
velocity/chance rotaries render when selection active + trigger layer; plain tabs
render when selection empty.

**2-E. Batch action bar.**
Positioned below step grid. Hidden via `opacity(0)` + `allowsHitTesting(false)`
when `shouldShowBatchActionBar == false`. Never removed from view hierarchy.

Actions: Clear (sets all selected steps `.off` in one closure; clears selection),
Copy (all-layers write to `StepClipboard`), Paste (writes `StepClipboard.steps`
to same-indexed steps in active clip in one closure; out-of-bounds steps skipped
silently).

Tests: grid frame identical before and after selection state changes; Clear,
Copy, and Paste round-trip unit tests.

**2-F. Selection lifetime wiring and Escape / background tap.**
Wire clip-switch notification from track workspace view model to coordinator.
Wire Escape key handler and background tap gesture in the step grid host view to
`coordinator.clearSelection()`. Tests: `clearSelection()` empties indexes; clipID
change clears selection; layer tab change does NOT clear selection.

**2-G. Macro layer cell support.**
Wire enabled macro layer tabs to `UnifiedStepCell` via coordinator's `.valueBar`
conversion. Coordinator uses `StepSequenceTrack.macros` array index as the
`MacroLane` key — never tab position. Test: coordinator maps macro layer tab at
position N to `MacroLane[bindingIndex]` where `bindingIndex` is the array index
of `TrackMacroBinding`, not N.

**2-H. Chord generator track cell (stub).**
Wire chord generator track trigger-layer steps to `.chordLabel(name:)`. The
coordinator stubs the label from the step's first note pitch class (e.g., "C",
"F#"). Guard for empty `noteGrid` steps; return "—" as default. No chord-
abstraction model is built. Test: coordinator returns `.chordLabel(name:)` for a
chord generator trigger step; label is a non-empty string.

---

### Review Gate (after Phase 2)

Self-review against spec.md Section 10 acceptance criteria before marking build
complete. See the full checklist below.

---

## Files and Modules Touched

| File | Phase | Reason |
|---|---|---|
| `Sources/StepGrid/StepSelectionModel.swift` (new) | 1-A | New transient selection type |
| `Sources/StepGrid/StepClipboard.swift` (new) | 1-B | New transient clipboard type |
| `Sources/StepGrid/StepCellContent.swift` (new) | 1-D | New content variant enum |
| `Sources/StepGrid/StepGridCoordinator.swift` (new) | 1-C, 2-D, 2-E, 2-F, 2-G, 2-H | Coordinator: owns selection and clipboard, cell conversion, batch writes |
| `Sources/StepGrid/UnifiedStepCell.swift` (new) | 2-A | New unified step cell primitive |
| Track workspace view model file (TBD from Phase 0-D) | 1-C | Add coordinator as stored property; inject into step grid |
| `Sources/UI/StepGridView.swift` | 2-B | Wire coordinator; replace trigger-layer cell with `UnifiedStepCell`; access-level fix for `StepGridCell` if needed |
| `Sources/UI/Track/ClipMacroLaneEditor.swift` (TBD from Phase 0) | 2-B, 2-G | Wire velocity/chance and macro layers to `UnifiedStepCell` |
| `Sources/UI/Slicer/SliceTrackEditingControls.swift` | 2-C | Remove `isEnabled: false` stubs; wire slicer velocity/chance to `UnifiedStepCell` |
| Layer tab row view file (TBD from Phase 0) | 2-D | Layer tab row transform (tab ↔ rotary mode) |
| Step grid host view file (TBD from Phase 0) | 2-E, 2-F | Batch action bar; Escape key handler; background tap gesture |
| Test files (multiple, TBD per plan.md task) | 1-A through 2-H | Unit and UI tests |

Files marked TBD have names gated on Phase 0 findings. Do not assume file names
for TBD entries; confirm them in Phase 0 before writing code.

---

## Non-Goals and Explicitly Deferred Work

Do not build any of the following as part of this feature:

- **Phrase-level step editing.** The rotary row writes to `ClipContent.MacroLane`
  (per-step, per-clip) only. Writing to `PhraseCell.steps` from the step grid is
  out of scope.
- **Cross-track paste.** `StepClipboard` does not support pasting to a different
  track's clip.
- **Offset paste.** Paste writes to the same step indexes as the source.
  Offset / relative paste is a future enhancement (spec OQ-3).
- **Relative delta rotary mode.** Absolute value semantics only. Modifier-key
  relative delta is a future enhancement.
- **Chord-generator model refactor.** The `.chordLabel` cell variant uses a pitch-
  class stub. Full chord identity requires a separate feature.
- **Full migration of all existing step-cell call sites to `UnifiedStepCell`.**
  Only views directly modified by the user stories in this feature are migrated.
- **Animation of layer row transition.** The tab ↔ rotary row transition is
  immediate. A cross-fade may be added later without a spec change.
- **Expanded drag zone for touch.** Long-press selection is in scope; the
  expanded drag zone concept from Variant C's annotation is a future enhancement.
- **Accessibility beyond basic VoiceOver labelling.** Hardware controller
  mappings, dynamic type scaling, and high-contrast mode are not assessed here.
- **Keyboard navigation for rotary row.** The horizontally scrollable rotary row
  is not required to be keyboard-navigable in this scope.

---

## Open Questions and Risks

The three open questions flagged in spec.md Section 12 are non-blocking and are
carried forward for the implementation loop:

**OQ-1: Touch drag sensitivity.**
The 80 pt = full range drag sensitivity was not validated on touch. Fine-grained
values (e.g., velocity 64 vs 66) may need a different sensitivity constant or a
fine-tune modifier on touch. Validate during Phase 2-A implementation. Adjusting
the constant does not require a spec change.

**OQ-2: Selection persistence across layer tab changes.**
The spec says switching the active layer does NOT clear selection (spec 2a). If
this proves to feel wrong in practice, it can be reversed during Phase 2-F
wiring without a spec change — just update the lifetime rule in both the spec and
the coordinator.

**OQ-3: Paste destination index conflict.**
Paste writes to the same step indexes as the source. There is no offset-paste
path. This is an acknowledged gap; it should be tracked as a future enhancement
request, not worked around in this feature.

**Implementation risks from plan.md:**

| Risk | Likelihood | Mitigation |
|---|---|---|
| `mutateClip` is `@Sendable`; capturing coordinator causes compile error | High | Phase 0-C confirms the signature. Use `let indexes = selectedStepIndexes` before every closure. |
| `StepGridCell` is `private`; visual convention reuse blocked | Medium | Phase 0-D confirms the access level. If `private`, make it `internal` in the same file (local change, no external callers affected). |
| Layer order diverges from `TrackMacroBinding` array order | Medium | Always use `StepSequenceTrack.macros` array index. Unit test in 1-C and 2-G confirms this. |
| `StepGridTapLatencyTests` fail after batch write path is introduced | Medium | Run latency tests after Phase 1-C completes. Do not advance to Phase 2 if they fail. |
| Chord generator empty step crashes on pitch class lookup | Low | Guard for empty `noteGrid` step in 2-H; return "—" as default label. |
| Rotary row horizontal scroll not keyboard-accessible | Low | Known gap; flag as accessibility follow-up. |

---

## Acceptance Criteria Checklist

Condensed from spec.md Section 10. The implementation team self-reviews against
this before marking the build complete.

### Story 1 — Unified Step Cell Primitive
- [ ] AC-1.1: `UnifiedStepCell` is used in at least the clip editor (trigger, velocity, chance layers) and the slicer track workspace step strip.
- [ ] AC-1.2: Tapping any step cell in those views uses tap-to-toggle; no secondary panel or sheet opens.
- [ ] AC-1.3: Dragging on a value layer cell produces an in-cell value change without opening a sheet.

### Story 2 — Step State Legibility
- [ ] AC-2.1: A step that is simultaneously `.on`, playing, and selected renders with filled background (active), green border (playing), and amber border (selected) without visual ambiguity.
- [ ] AC-2.2: A step that is `.off` and selected renders with the amber border and unfilled background; active state is distinguishable from selected state.
- [ ] AC-2.3: On a velocity layer, the value bar is visible inside the cell for both active and inactive steps.

### Story 3 — Right-Click Step Selection and Layer Editing
- [ ] AC-3.1: Right-clicking a step on macOS adds it to `selectedStepIndexes`; the cell shows the amber selection border.
- [ ] AC-3.2: When any step is selected and the active layer is not trigger, the layer tab row shows rotary arc-dial controls.
- [ ] AC-3.3: When any step is selected and the active layer is trigger, the rotary row shows velocity and chance rotaries.
- [ ] AC-3.4: The batch action bar becomes visible when at least one step is selected.

### Story 4 — Multi-Step Selection
- [ ] AC-4.1: Right-clicking a second step adds it to the existing selection (additive, not replacing). Both cells show the amber border.
- [ ] AC-4.2: Dragging a rotary arc-dial while N steps are selected applies the dragged value to all N steps. Step data confirms all N were written.
- [ ] AC-4.3: The N-step batch write is a single `session.mutateClip` closure. `StepGridTapLatencyTests` continue to pass.
- [ ] AC-4.4: Pressing Escape clears the selection. All amber borders disappear and the rotary row reverts to the plain tab row.

### Story 5 — Contextual Batch Action Bar
- [ ] AC-5.1: The batch action bar is below the step grid at all times. When no steps are selected, it is invisible and non-interactive (zero opacity, hitTest disabled). No layout shift occurs when it appears or disappears.
- [ ] AC-5.2: Clear sets `visualState` to `.off` for all selected steps in one mutation closure and clears the selection.
- [ ] AC-5.3: Copy writes all selected steps' data (all layers) into `StepClipboard`. Confirmed populated by a subsequent paste.
- [ ] AC-5.4: Paste reads `StepClipboard.steps` and writes each entry to the same-indexed step in the active clip in one mutation closure.

### Story 6 — Layer-Driven Cell Control Type
- [ ] AC-6.1: Switching the active layer from Steps to Velocity changes every step cell from `.toggle` to `.valueBar(fraction:)` without changing cell geometry or step positions.
- [ ] AC-6.2: Switching back from Velocity to Steps restores `.toggle` cells. Velocity values are unchanged (confirmed by switching to Velocity again).
- [ ] AC-6.3: Switching to a macro layer (if the track has macro bindings) renders each step cell as `.valueBar(fraction:)` using the per-step `MacroLane` override value (or default/global if the override is `nil`).

### Cross-Cutting
- [ ] `StepGridTapLatencyTests` pass throughout (Phase 1-C gate and final gate).
- [ ] No `StepSelectionModel` or `StepClipboard` field appears in any `Codable` type (confirmed by compile-time guard or test assertion).

---

## Testing Expectations Summary

| Phase | Test | Type |
|---|---|---|
| 1-A | Selection cleared when clipID changes | Unit |
| 1-A | Selection NOT cleared on layer-mode change | Unit |
| 1-A | Non-contiguous index set accepted | Unit |
| 1-B | Copy N steps produces N entries, all layers populated | Unit |
| 1-C | Single-step `onTap` → exactly one `mutateClip` | Unit |
| 1-C | 4-step selection `onTap` → exactly one `mutateClip`, all 4 indexes | Unit |
| 1-C | `onDrag` 4-step selection → same absolute value to all 4, one closure | Unit |
| 1-C | Coordinator writes to `MacroLane[bindingIndex]`, not tab position | Unit |
| 1-C | `isSelectionActive` and `shouldShowRotaryRow` derived correctly | Unit |
| 2-A | Four-state snapshot: `.on`, playing, selected, `.valueBar(0.7)` | Snapshot |
| 2-A | `.off` + selected → amber border, unfilled background | Snapshot |
| 2-A | `.toggle` and `.valueBar(0.5)` have identical frame dimensions | Snapshot |
| 2-B | Steps→Velocity: cell content changes, geometry unchanged | UI |
| 2-B | Velocity→Steps: `.toggle` restored, values unchanged | UI |
| 2-C | Coordinator returns `.valueBar` for slicer clip on velocity layer | Unit |
| 2-C | Selection + batch bar visible on slicer step | UI |
| 2-D | Rotary row when selection active + non-trigger active layer | Snapshot/UI |
| 2-D | Velocity/chance rotaries when selection active + trigger layer | Snapshot/UI |
| 2-D | Plain tabs when selection empty | Snapshot/UI |
| 2-D | `shouldShowRotaryRow == false` when all layers are stubs | Unit |
| 2-E | Grid frame identical before and after `shouldShowBatchActionBar` changes | UI |
| 2-E | Clear: all selected steps `.off` in one closure; selection emptied | Unit |
| 2-E | Copy: clipboard populated with all-layer data for all selected indexes | Unit |
| 2-E | Paste round-trip: velocity, chance, macroOverride preserved per step | Unit |
| 2-F | `clearSelection()` empties `selectedStepIndexes` | Unit |
| 2-F | Active clipID change clears selection | Unit |
| 2-F | Layer tab change does NOT clear selection | Unit |
| 2-G | Macro indexed by `TrackMacroBinding` array index, not tab position | Unit |
| 2-H | Coordinator returns `.chordLabel(name:)` for chord generator trigger step | Unit |
| Existing | `StepGridTapLatencyTests` (all methods) continue to pass | Performance |
