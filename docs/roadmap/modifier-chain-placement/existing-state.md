# Modifier Chain Placement — Existing State

Inspected: 2026-04-29

---

## Model

### Source reference

`SourceRef` (`Sources/Document/TrackSourceCatalog.swift`, lines 303–441) is the per-pattern-slot value that records:

- `mode: TrackSourceMode` — `.clip` or `.generator`
- `clipID: UUID?` — optional; `nil` means the slot has no clip assigned yet
- `generatorID: UUID?` — optional; the source generator when `mode == .generator`
- `modifierGeneratorID: UUID?` — optional; the post-source modifier generator
- `modifierBypassed: Bool`

`isEmpty` is computed from mode + the relevant ID being nil (line 344). This is the correct semantic for "empty slot."

### Pool entries

Both `ClipPoolEntry` and `GeneratorPoolEntry` live on `Project` as arrays (`clipPool`, `generatorPool`). They are shared across all tracks in the project — they are not owned per-track.

`GeneratorKind.supportsModifierStage` controls which generators can appear in the modifier position (line 65). `monoGenerator` and `polyGenerator` return `true`; `progressionChordGenerator` and `sliceGenerator` return `false`.

### Track-to-source relationship

Each track has a `TrackPatternBank` with eight `TrackPatternSlot` entries, each holding its own `SourceRef`. Source assignment is therefore per-pattern-slot, not per-track.

### Mutations available on `Project+TrackSources.swift`

| Mutation | What it does |
|---|---|
| `attachNewGenerator(to:)` | Creates a new pool entry and writes it into all slots of the track's bank |
| `removeAttachedGenerator(from:)` | Clears `attachedGeneratorID` and resets all slots to `.clip` mode |
| `switchAttachedGenerator(to:for:)` | Replaces the generator ID on all slots |
| `setPatternClipID(_:for:slotIndex:)` | Assigns a specific clip to one slot |
| `setPatternSourceRef(_:for:slotIndex:)` | Full SourceRef write for one slot |
| `setPatternModifierGeneratorID(_:bypassed:for:slotIndex:)` | Sets or clears modifier on one slot |
| `setPatternModifierBypassed(_:for:slotIndex:)` | Toggles modifier bypass on one slot |
| `ensureClipForCurrentPattern(trackID:)` | Auto-creates a blank clip if the slot has no clipID |
| `ensureCompatibleClip(for:)` | Ensures at least one clip of the right track type exists in the pool |

**Gap:** there is no `removeClipSource` mutation — a dedicated operation to clear `clipID` from a slot and return it to an explicitly empty state. The existing `removeGeneratorSource()` in the UI layer achieves clip-mode restoration by calling `ensureClipForCurrentPattern` (which creates a clip if none exists) and switching mode back to `.clip`. There is no path that leaves a slot in `.clip` mode with `clipID == nil` deliberately exposed to the user.

---

## Engine

`TrackSourceProgram` (`Sources/Engine/TrackSourceProgram.swift`) and `SequencerSnapshotCompiler` consume `SourceRef` at snapshot time. The engine correctly handles a nil `clipID` (it falls back to a silent buffer). No engine changes are required.

---

## UI

### Current layout

`TrackWorkspaceView` (`Sources/UI/Track/TrackWorkspaceView.swift`) renders:

- A top header with the track name
- `TrackSourceEditorView` (left column, flexible width)
- A `destinationColumn` (right column, fixed 320 pt)

### TrackSourceEditorView (`Sources/UI/TrackSource/TrackSourceEditorView.swift`)

This is the primary surface for the feature request. Current structure:

1. **Pattern panel** — `TrackPatternSlotPalette` (slot buttons 1–8) plus a `Picker` segmented control for "Source" / "Modifiers" tabs. This segmented picker is the closest thing to the requested "tab" affordance, but it is not visually tied to a specific slot; it applies globally to the selected slot.

2. **Source tab** (`sourceTab`, line 210) — branches on `selectedSourceMode`:

   - **`.clip` branch:** Renders the inline clip editor (`ClipContentPreview`) plus a `StudioPanel` titled "Clip Source" that contains an explanatory body text and a single button: **"Switch To Generator Source"**. No remove-clip button; no empty-slot state.

   - **`.generator` branch with a generator selected:** Renders a `StudioPanel` titled "Generator Source" with two action buttons: **"Choose Different Generator"** and **"Remove Generator Source"**. Removing calls `removeGeneratorSource()`, which calls `ensureClipForCurrentPattern` then flips mode to `.clip`.

   - **`.generator` branch with no generator:** Renders a "Select Generator" button.

3. **Modifiers tab** (`modifiersTab`, line 284) — branches on whether `modifierGeneratorID` is set:

   - **With modifier:** Shows "Choose Different Modifier", "Bypass"/"Enable", and "Remove Modifier" buttons.
   - **Without modifier:** Shows "Add Modifier" button (hidden if `compatibleModifierGenerators` is empty).

### GeneratorSelectionSheet (private, within TrackSourceEditorView)

A `.sheet` that presents a scrollable list of compatible `GeneratorPoolEntry` values. It is reused for both source and modifier selection. It is a full-screen-height modal, dismissable by a Cancel button.

### GeneratorAttachmentControl (`Sources/UI/TrackSource/GeneratorAttachmentControl.swift`)

A standalone component that renders an attached-generator name + "Choose" / "Remove" affordance, or an "Add Generator" button when nothing is attached. This component is not currently used inside `TrackSourceEditorView` — its usage is elsewhere (likely the older `TrackWorkspaceView` for slice tracks or the slicer).

### TrackPatternSlotPalette (`Sources/UI/TrackSource/TrackPatternSlotPalette.swift`)

Each slot button shows a number and a small colored dot. When `bypassState` is `.applicable`, a badge overlaid on each slot shows "C" (clip/bypassed) or "G" (generator) and can be tapped to toggle. Inside `TrackSourceEditorView`, the palette is called with `bypassState: .notApplicable`, so the badge is never shown there. The bypass per-slot toggle is only active in another context (the Scenes workspace).

---

## Gap Analysis: Story vs. Existing State

### Story 1 — Remove a clip source and replace it with a generator

**Gap — UX.** When a slot is in `.clip` mode, the UI shows "Switch To Generator Source" as the only action, immediately launching the generator picker. There is no "remove" affordance that first empties the slot. The desired flow (remove → empty slot → plus button → generator as first option) does not exist.

**Gap — UX.** The generator picker is only triggered by the "Switch To Generator Source" button; there is no path that presents a plus button in an empty-slot state.

**Model note.** The model supports an empty `.clip` slot (`clipID == nil`). A `removeClipSource` mutation that sets `clipID = nil` and leaves `mode = .clip` would be needed. The `SourceRef.isEmpty` computed property already handles this case correctly.

### Story 2 — Four-option source picker (new blank clip / from pool / new blank generator / select generator)

**Gap — UX and model.** No four-option picker exists. The only picker is `GeneratorSelectionSheet`, which lists existing generator pool entries. There is no:

- "Add new blank clip" action in source context
- "Select clip from pool" picker — **confirmed absent.** No component in `Sources/UI/` browses or selects from `clipPool` for the purpose of assigning a clip to a pattern slot. `compatibleClips(for:)` exists on `Project` but is never surfaced in any picker UI.
- "New blank generator" shortcut (a one-tap variant of "Switch To Generator Source" that skips selection and creates a default generator)
- "Select generator" is approximated by the existing `GeneratorSelectionSheet` but is only accessible via "Switch To Generator Source", not via a plus button on an empty slot.

**Open question from user-stories.md resolved:** No in-context library picker for clips exists. `LibraryWorkspaceView` is a placeholder with stub tiles only (`Sources/UI/Library/LibraryWorkspaceView.swift`). The "select clip from pool" and "select generator" options that require a browsing surface will need a new in-context picker component.

### Story 3 — Visual clarity: source and modifier as labelled slots

**Partial coverage.** A segmented "Source / Modifiers" picker already exists inside the Pattern panel. It is labelled and functional. However:

- The current UI does not visually communicate whether the slot is clip-driven or generator-driven at a glance before switching to a tab. The slot palette dots give color cues but no type label.
- The slot-level type label ("Clip" vs "Generator") is only visible once the source tab is open. The user must already be on the source tab to see the `StudioPanel` title ("Clip Source" or "Generator Source").
- The design requested by the notes is "source and modifier slots are tabs" with a "well/holder" for the item — this implies a more persistent visual container, not just a segmented picker that swaps panel content.

### Story 4 — Symmetrical add/remove on modifiers

**Partial coverage.** The modifiers tab has Add / Remove / Bypass buttons, which is close to the requested model. However:

- The modifier slot does not visually match the source slot layout (one is a full panel, the other is a segmented tab body). The requested parity means both should have the same slot-well visual metaphor.
- There is no "plus button" affordance in the modifier tab when empty — the Add Modifier button is a text button, not a consistent plus-button that mirrors a hypothetical source slot plus button.

### Story 5 — Clip-to-generator swap in two or three taps without screen navigation

**Gap.** Current minimum tap count to switch from clip to generator: tap "Switch To Generator Source" → tap a generator in the sheet → sheet auto-closes. That is two taps but requires knowing that "Switch To Generator Source" is the correct action. The text label is not a prominent plus or swap icon. If the generator pool is empty, the button is hidden entirely, making the path zero-tap but also completely inaccessible.

The new blank generator shortcut (one tap from an empty slot) does not exist at all.

---

## Architecture Constraints

- Generator pool entries are project-global and shared across all tracks; the picker must filter by `compatibleGenerators(for:)` / `compatibleModifierGenerators(for:)`.
- Clip pool entries are also project-global; `compatibleClips(for:)` already provides the right filtered list for a picker.
- The source mode is per-pattern-slot, not per-track. UI mutations must target the selected slot index.
- `attachNewGenerator` and `removeAttachedGenerator` operate across all slots of a bank (bank-level). `setPatternSourceRef` operates on individual slots. The new UI should use slot-level mutations to avoid unintended cross-slot side effects.

---

## Test Coverage

Well-covered by existing tests:

- `ProjectAttachNewGeneratorTests`, `ProjectRemoveAttachedGeneratorTests`, `ProjectSwitchAttachedGeneratorTests` — bank-level generator attachment mutations
- `ProjectSetPatternClipIDTests`, `ProjectEnsureClipForCurrentPatternTests` — clip assignment and auto-creation
- `SourceRefNormalizationTests` — normalization across pool changes
- `ProjectTrackSourceCatalogTests` — compatible clip/generator filtering logic

**Missing tests:**

- No test for a `removeClipSource` mutation (setting `clipID = nil` on a slot while keeping `mode = .clip`)
- No UI-level test covering the source tab's action buttons or state transitions
- No test for the four-option picker flow (does not exist yet)

---

## Summary

| Area | Status |
|---|---|
| Model support for clip and generator sources | Exists and complete |
| Model support for modifier generator per slot | Exists and complete |
| Remove-clip mutation (explicit nil clipID on slot) | Missing |
| Source/Modifiers tab segmented control | Exists but is not slot-well metaphor |
| Generator picker (GeneratorSelectionSheet) | Exists but is generator-only and not triggered from empty-slot plus |
| Clip pool picker (select clip from pool) | Does not exist |
| Four-option source picker | Does not exist |
| Plus-button affordance on empty slot | Does not exist |
| Library / browse surface for clips | Placeholder only (LibraryWorkspaceView) |
| Modifier add/remove/bypass actions | Exists, partial parity with source slot |
| Tests for new UI flows | Not yet written |
