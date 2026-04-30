---
feature: scene-perform
created: 2026-04-30
---

# Scene Perform Plan

## Status

PM plan — ready for build queue. No production code has been written.

---

## Overview

Scene Perform is a narrow, UI-only refactor of `ScenesWorkspaceView+Perform.swift`. The engine, audio host, document model, and session mutation layers are untouched. The plan runs in two phases: a preparatory verification pass (Phase 0) and the single-file UI build (Phase 1). There are no model migrations, no new persistence fields, and no prerequisite roadmap items.

---

## Phases

### Phase 0 — Pre-Build Verification (one-day pass)

Phase 0 is a read-and-confirm task. No production code is written in this phase. Its sole purpose is to verify two points against the live codebase before coding starts, so the implementer is not surprised mid-build.

---

#### 0-A. Confirm `effectiveCrossfader` Does Not Already Exist

**What it is.** The spec prescribes a computed property `effectiveCrossfader` on `EngineController` (see spec §Engine Call Surface and architecture-review.md). Before adding it, confirm it does not already exist under a different name or location.

**Files to read.**

- `Sources/Engine/EngineController.swift` — search for `crossfader` and `abSelection` references.
- `Sources/Document/MasterBus.swift` — `applyingPerformanceOverlay(_:)` at line 203 already implements the merge logic implicitly; confirm whether it is exposed as a `Double` anywhere.

**Tasks.**

1. Read `EngineController.swift` and confirm no existing property merges `crossfaderOverride` and `abSelection.crossfader` as a plain `Double`.
2. If one exists, note its name and location so the view can use it directly without adding a duplicate.
3. Write up the finding (one sentence in a build-time note or inline comment).

**Acceptance signals.**

- The implementer knows whether to add the property or consume an existing one before touching the view.

---

#### 0-B. Confirm `performView` Entry Point and `ViewThatFits` Location

**What it is.** The spec removes the `ViewThatFits` fallback from `performView`. Confirm the exact location and scope of that wrapper before cutting it.

**Files to read.**

- `Sources/UI/Mixer/ScenesWorkspaceView+Perform.swift` — identify the `ViewThatFits` call site, the `crossfader` sub-function, and the `performSlot` sub-function and their current signatures.

**Tasks.**

1. Read the current `performView` body and confirm the `ViewThatFits(.horizontal)` wrapper and its fallback branch.
2. Confirm the current signatures of `crossfader(...)` and `performSlot(...)` so the rename/restructure is clearly scoped.
3. Write up the finding (one sentence each).

**Acceptance signals.**

- Implementer can identify exactly which lines to remove and which signatures change before opening an editor.

---

### Phase 1 — UI Build

Phase 1 begins after Phase 0 findings are recorded. It is a single-file change to `ScenesWorkspaceView+Perform.swift`. The tasks below are ordered by dependency; within a task, subtasks may proceed in any order.

No new files are created. No other source files are modified.

---

#### 1-A. Add `effectiveCrossfader` to `EngineController`

**What it is.** A pure computed property that merges the live overlay with the persisted baseline:

```
var effectiveCrossfader: Double {
    masterBusPerformanceOverlay.crossfaderOverride ?? abSelection.crossfader
}
```

**File.** `Sources/Engine/EngineController.swift`.

**Tasks.**

1. Add the computed property (if Phase 0-A confirms it does not already exist).
2. Write unit tests:
   - when `crossfaderOverride` is `nil`, `effectiveCrossfader` returns `abSelection.crossfader`;
   - when `crossfaderOverride` is set, `effectiveCrossfader` returns that value regardless of `abSelection.crossfader`.

**Artifacts touched.**

- `Sources/Engine/EngineController.swift`
- `Tests/SequencerAITests/Engine/EngineControllerTests.swift` (or whichever test file covers `EngineController`)

**Acceptance signals.**

- Both unit tests pass.
- The property is not shadowed or re-derived anywhere in the view layer.

---

#### 1-B. Restructure `performView` to Three-Column Layout

**What it is.** Replace the current `VStack { crossfader; ViewThatFits { ... } }` body with an `HStack(spacing: 0)` containing three columns:

```
HStack(spacing: 0) {
    performSlot(.a, ...)   // .frame(maxWidth: .infinity)
    crossfaderColumn(...)  // .frame(width: ~120)
    performSlot(.b, ...)   // .frame(maxWidth: .infinity)
}
```

**File.** `Sources/UI/Mixer/ScenesWorkspaceView+Perform.swift`.

**Tasks.**

1. Remove the `ViewThatFits(.horizontal)` wrapper and its vertical-stack fallback branch.
2. Rename the existing `crossfader(...)` function to `crossfaderColumn(...)` (or create a new one and remove the old one).
3. Wire `effectiveCrossfader` from `EngineController` as the single read path for the slider binding, the blend readout, and the indicator logic.
4. The `HStack` layout is unconditional. No adaptive/compact fallback is introduced.

**Acceptance signals.**

- The perform pane shows three columns side by side at the operating window width.
- No `ViewThatFits` or fallback branch remains in the perform path.

---

#### 1-C. Build `crossfaderColumn`

**What it is.** The centre column: A label → vertical fader → blend readout → B label. No Reset or Save Blend controls.

**File.** `Sources/UI/Mixer/ScenesWorkspaceView+Perform.swift`.

**Tasks.**

1. Implement a custom vertical drag gesture view that maps vertical drag offset to `0.0...1.0`, clamped. This is the preferred implementation per the architecture review; a rotated `Slider` is acceptable if hit-area and accessibility testing confirm it is adequate.
2. Every drag delta calls `engineController.setLiveMasterCrossfader(newValue)`.
3. The blend readout (percentage, e.g. "37 %") is derived from `engineController.effectiveCrossfader` and is visible at all times.
4. "A" label appears above the fader track; "B" label appears below (matching fader direction: top = 0.0 = A, bottom = 1.0 = B, or inverted if direction testing shows the opposite is more intuitive — the implementation team must test both and pick the one that matches physical fader expectation).
5. The column width is fixed at approximately 120 pt.

**Acceptance signals.**

- Dragging end-to-end covers only the centre column width, not the full pane.
- Blend readout updates continuously during a drag.
- No Reset or Save Blend control is present in the column.

---

#### 1-D. Update `performSlot` — Header Hard-Switch and Active Indicator

**What it is.** Two changes to the slot card header: (a) the full header row becomes the hard-switch tap target; (b) the dominant card's header receives full colour inversion.

**File.** `Sources/UI/Mixer/ScenesWorkspaceView+Perform.swift`.

**Tasks.**

1. Wrap the header row (slot label + scene name) in a `Button` or apply `.onTapGesture`. The action is:
   - Slot A: `engineController.setLiveMasterCrossfader(0.0)`
   - Slot B: `engineController.setLiveMasterCrossfader(1.0)`
2. Derive `isADominant = engineController.effectiveCrossfader < 0.5` and `isBDominant = engineController.effectiveCrossfader > 0.5`. These are local computed bindings in the view; no new stored state is added anywhere.
3. Apply full header colour inversion (dark background, white text) when the card is dominant. The non-dominant card renders in the default style. When `effectiveCrossfader == 0.5` exactly, neither card shows the active treatment.
4. Set appropriate accessibility labels so the hard-switch action and active state are announced by VoiceOver.

**Acceptance signals.**

- Single tap on the card header snaps the fader to that end.
- Active indicator updates immediately after the tap.
- At 0.5, neither card shows the active treatment.
- At startup (persisted crossfader = 0.0), Scene A is correctly shown as dominant.

**Unit tests (indicator derivation).**

Write unit tests for the indicator logic, exercising the three boundary values:

| `effectiveCrossfader` | Expected `isADominant` | Expected `isBDominant` |
|---|---|---|
| `0.0` | `true` | `false` |
| `0.5` | `false` | `false` |
| `1.0` | `false` | `true` |

These can be tested as pure logic (no SwiftUI dependency needed).

---

#### 1-E. Update `performSlot` — Macro Grid Layout

**What it is.** Replace `ScrollView(.horizontal)` wrapping a flat `HStack` of macro knobs with a `LazyVGrid` (2 columns × 4 rows). All eight knobs are visible simultaneously.

**File.** `Sources/UI/Mixer/ScenesWorkspaceView+Perform.swift`.

**Tasks.**

1. Remove the `ScrollView(.horizontal)` from the macro display path.
2. Replace the flat `HStack` with a `LazyVGrid` using two equally-weighted columns.
3. Confirm that all eight macro knob labels (e.g. "M5 Delay Send", "M7 Bit Rate") render without truncation at the card width produced by the `1fr / 120px / 1fr` layout.
4. Verify that macro knobs still read their values via the existing `resolvedMacroValue` path (no data-layer changes).

**Acceptance signals.**

- All eight macro knobs visible simultaneously without horizontal scrolling.
- No macro label is truncated at operating card widths.
- The scroll view is entirely removed from this display path.

---

#### 1-F. Remove Card-Actions Footer

**What it is.** The bottom row containing the Modified badge, Revert button, and Save to Scene button is removed entirely.

**File.** `Sources/UI/Mixer/ScenesWorkspaceView+Perform.swift`.

**Tasks.**

1. Remove the card-actions footer (the entire row, not just individual buttons).
2. Confirm the scene picker stub remains in place (the grid picker button that opens the scene picker sheet is retained). Its existing `clearMasterBusPerformanceOverlay()` call on scene assignment is preserved.

**Acceptance signals.**

- No Revert, Save to Scene, or Modified badge appears in the perform view.
- The scene picker button remains functional.

---

### Review Gate Between Phases 1 and Handoff

After Phase 1 is complete, the implementation team should do a self-review against the acceptance criteria in `spec.md` before marking the build complete. The gate checklist:

- [ ] Hard-switch (story 1): single tap commits fader to 0.0 or 1.0; indicator updates immediately.
- [ ] Live blend (story 2): fader travel confined to centre column; blend readout visible during drag.
- [ ] Cue / active indicator (story 3): both cards visible; dominant card shows header inversion; 0.5 shows neither.
- [ ] Read both scenes (story 6): all eight macros on both cards visible simultaneously; no horizontal scroll.
- [ ] No descoped controls present: no Reset, no Save Blend, no Revert, no Save to Scene, no Modified badge.
- [ ] Audio smoothing limitation documented as a known issue (hard-switch produces buffer-boundary step; no ramp in scope).

---

## Files and Modules Touched

| File | Phase | Reason |
|---|---|---|
| `Sources/Engine/EngineController.swift` | 1-A | Add `effectiveCrossfader` computed property |
| `Sources/UI/Mixer/ScenesWorkspaceView+Perform.swift` | 1-B through 1-F | All view changes |
| `Tests/SequencerAITests/Engine/EngineControllerTests.swift` | 1-A, 1-D | Unit tests for `effectiveCrossfader` and indicator derivation |

No other source files are modified. No document model, audio host, session mutation, or routing files are touched.

---

## Tests Expected per Phase

| Phase | Test | Location |
|---|---|---|
| 1-A | `effectiveCrossfader` returns overlay value when set | `EngineControllerTests.swift` |
| 1-A | `effectiveCrossfader` returns persisted baseline when overlay is nil | `EngineControllerTests.swift` |
| 1-D | `isADominant` and `isBDominant` at 0.0, 0.5, 1.0 | `EngineControllerTests.swift` or inline logic test |

Existing model and audio tests (`MasterBusStateTests.swift`, `MasterBusHostTests.swift`, `SequencerDocumentSessionMasterBusTests.swift`) are unaffected and should continue to pass unmodified.

No snapshot tests are required by the current test infrastructure. If a SwiftUI preview test harness is introduced later, the new `performView` should be covered at that point.

---

## Migration and Data Shape Changes

None. No document fields are added, removed, or renamed. No schema version bump is needed. `MasterBusPerformanceOverlayState` is intentionally non-persistent; its shape is unchanged.

---

## Risks and Dependencies

| Risk | Likelihood | Mitigation |
|---|---|---|
| Rotated `Slider` hit area does not behave correctly | Medium | Default to custom drag gesture view per architecture review; rotated `Slider` is the fallback, not the default. |
| Macro label truncation at narrower-than-expected card width | Low | Verify at operating window width before marking 1-E done; adjust font size or label abbreviation if needed (does not require PM approval for minor cosmetic tuning). |
| Hard-switch produces audible pop (no ramp) | Known | Documented in spec as a known limitation. Do not add a ramp — that requires `MasterBusHost` changes that are out of scope. Track as a separate follow-on item if user reports it as a blocker. |
| Concurrent `EngineController` edits from another in-flight feature | Low | Confirm no other feature is actively touching `EngineController` before merging 1-A. |

**External dependencies.** None. No other roadmap items are prerequisites. The engine call surface (`setLiveMasterCrossfader`, `clearMasterBusPerformanceOverlay`, `resolvedMacroValue`) already exists and works correctly.

---

## Sequencing Notes

1. Phase 0 is a read-only pass. It can be done in a single sitting and has no dependencies.
2. Phase 1-A (`effectiveCrossfader`) should be completed and tested before the view tasks (1-B through 1-F) begin, because the view tasks depend on `engineController.effectiveCrossfader` being available.
3. Phases 1-B through 1-F can proceed in any order after 1-A is done. They all operate on the same file. The recommended order matches the dependency chain: restructure the top-level layout (1-B) before building the column contents (1-C) and slot changes (1-D, 1-E, 1-F).
4. The review gate runs after all of Phase 1 is complete.

---

## Non-Goals and Deferred Work

The following must not be built as part of this plan:

- **Reset to nearest end** (story 4) — deferred to the future Live Scene Performance roadmap item.
- **Save Blend pos. / Save to Scene** (story 5) — deferred to the same future item.
- **Revert per-card** — deferred; requires an ephemeral overlay or snapshot model not specified here.
- **Modified badge** — removed; no recovery action in scope to pair it with.
- **Audio ramp on hard-switch** — requires `MasterBusHost` changes; explicitly out of scope. Document as a known limitation.
- **Narrow-layout or touch fallback** — the three-column layout is unconditional. A narrow-layout adaptation is a separate item if it becomes needed.
- **Accessibility beyond basic labels** — VoiceOver labelling on the hard-switch button and active-state announcement is in scope (task 1-D). Hardware controller mappings, dynamic type scaling, and high-contrast mode support are not assessed here and may be follow-on items.
