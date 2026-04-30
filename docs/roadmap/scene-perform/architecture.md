---
created: 2026-04-29
sources:
  - Sources/Document/MasterBus.swift
  - Sources/Engine/EngineController.swift
  - Sources/Audio/MasterBusHost.swift
  - Sources/App/SequencerDocumentSession+Mutations.swift
  - Sources/UI/Mixer/ScenesWorkspaceView.swift
  - Sources/UI/Mixer/ScenesWorkspaceView+Perform.swift
  - wiki/pages/architecture-guardrails.md
  - wiki/pages/engine-architecture.md
  - wiki/pages/document-model.md
---

# Scene Perform — Architecture

This document covers in-scope stories only: 1 (hard-switch), 2 (repositioned crossfader), 3 (active-scene indicator / cue), and 6 (macro grid always visible). Stories 4 and 5 are descoped per `ux-review.md` and have no architecture here.

---

## Application Invariants This Feature Must Preserve

1. **Overlay non-persistence.** `MasterBusPerformanceOverlayState` is intentionally not part of the `.seqai` document. Live crossfader movement must continue to write to `crossfaderOverride`, never directly to `MasterBusABSelection.crossfader`. The document is mutated only on explicit user save actions — none of which remain in scope for this feature after the descoping of stories 4 and 5.

2. **`EngineController` as the single owner of the overlay.** Views must never hold crossfader state of their own. The crossfader position lives in `engineController.masterBusPerformanceOverlay.crossfaderOverride`. SwiftUI views read it and call `setLiveMasterCrossfader(_:)` to mutate it; they do not shadow it locally.

3. **Audio thread is not involved in view layout decisions.** The three-column layout is a pure SwiftUI structural change. No audio code changes are required for stories 1, 2, 3, or 6. The crossfader update path (`setLiveMasterCrossfader` → `MasterBusHost.setLiveCrossfaderOverride`) is unchanged.

4. **No new global mutable state.** The active-scene indicator (story 3) must derive from the existing `crossfaderOverride` (or the persisted `crossfader` when no override is active) as a pure computed property. No new stored state should be introduced to track which card is "active" — that is always `crossfader < 0.5` → A dominant, `crossfader > 0.5` → B dominant, `crossfader == 0.5` → neither.

5. **`MasterBusState` document model is not touched.** The only document mutation that was in scope (Save Blend, Reset) has been descoped. The model layer — `MasterBusABSelection`, `MasterBusScene`, `MasterSceneMacroBinding` — is read-only from this feature's perspective.

---

## Data Model Touch Points

### What Is Read (no mutations)

| Model object | Field | Used for |
|---|---|---|
| `MasterBusABSelection` | `sceneAID`, `sceneBID` | Identify which scene is in each slot |
| `MasterBusABSelection` | `crossfader: Double` | Baseline position when no override is active |
| `MasterBusScene` | `name`, `macroBindings` | Card header text, macro slot display |
| `MasterSceneMacroBinding` | `slotIndex`, `value` | Macro slot label and current value in the grid |
| `MasterBusPerformanceOverlayState` | `crossfaderOverride: Double?` | Live crossfader position; drives indicator and readout |
| `MasterBusPerformanceOverlayState` | `sceneMacroOverrides` | Live macro values on either card |

### Effective Crossfader Value

A single computed helper is needed in the view layer (or view model):

```
effectiveCrossfader = crossfaderOverride ?? abSelection.crossfader
```

This already exists implicitly via `applyingPerformanceOverlay(_:)` in `MasterBus.swift` (line 203), but the view needs it as a plain `Double` for the slider binding and the indicator logic. The implementation can expose it as a computed property on `EngineController` or derive it inline in the view — either is acceptable, but it must not create a second source of truth.

### Active-Scene Indicator Derivation

```
isADominant = effectiveCrossfader < 0.5
isBDominant = effectiveCrossfader > 0.5
// exactly 0.5: neither card gets the active treatment
```

This is a pure function of `effectiveCrossfader`. No new state field is needed anywhere.

---

## Engine Integration

### What Changes

Nothing changes in the engine or audio layers. The existing call surface is sufficient:

| Story | Engine call | Already works? |
|---|---|---|
| Hard-switch to A | `setLiveMasterCrossfader(0.0)` | Yes |
| Hard-switch to B | `setLiveMasterCrossfader(1.0)` | Yes |
| Live crossfader drag | `setLiveMasterCrossfader(newValue)` | Yes |
| Macro slot display | Read from overlay via `resolvedMacroValue` | Yes |

`setLiveMasterCrossfader` already writes through `crossfaderOverride` to `MasterBusHost.setLiveCrossfaderOverride`, which updates the equal-power branch gains immediately (no smoothing, next buffer boundary only). This is sufficient for the in-scope stories.

### Audio Smoothing Note (Not In Scope)

There is no parameter ramping in `MasterBusHost`. A hard-switch (story 1) calls `setLiveMasterCrossfader(0.0)` or `setLiveMasterCrossfader(1.0)`, which will apply the new gain at the next buffer boundary without a ramp. This produces an audible step on typical buffer sizes. The implementation team should note this; adding a ramp would require changes in `MasterBusHost` that are outside the scope of this layout feature and should be tracked as a separate item.

---

## View Structure

### Proposed View Hierarchy

```
ScenesWorkspaceView+Perform.swift
└── performView  (HStack, 3 columns via a Grid or HStack with fixed centre width)
    ├── performSlot(.a, selection, effectiveCrossfader)   // Scene A card
    ├── crossfaderColumn(selection, effectiveCrossfader)  // centre column
    └── performSlot(.b, selection, effectiveCrossfader)   // Scene B card
```

### Column Layout

The UX review selected a `1fr / ~120px / 1fr` grid. In SwiftUI the natural expression is:

```swift
HStack(spacing: 0) {
    slotView(...)          // .frame(maxWidth: .infinity)
    crossfaderColumn(...)  // .frame(width: 120)
    slotView(...)          // .frame(maxWidth: .infinity)
}
```

A `Grid` with `GridRow` is equally valid but adds complexity for three columns of fixed/flexible mix. The `HStack` approach is simpler and follows existing patterns in `ScenesWorkspaceView`.

### `crossfaderColumn` Contents

Per `ux-review.md` recommended direction:

- "A" label at top, "B" label at bottom (or reversed to match fader direction)
- `Slider` with vertical axis or a custom drag gesture on a vertical track
- Blend readout (percentage) below or beside the slider
- No Reset, no Save Blend (descoped)

The slider should be vertical to match the physical metaphor of the fader sitting between two cards. SwiftUI's `Slider` does not support vertical orientation natively; the implementation team will need to rotate a horizontal slider with `.rotationEffect(.degrees(-90))` or build a custom drag gesture view. This is an implementation detail — the architecture does not mandate which approach, but the PM record should note the constraint so the implementation team is not surprised.

### `performSlot` Changes

The existing `performSlot` function requires these changes:

1. **Remove the card-actions footer** (Revert, Save to Scene, Modified badge) — descoped per `ux-review.md`. The footer currently lives at the bottom of the slot card; it is removed entirely.

2. **Add active-scene visual treatment** — a full header colour inversion (dark background, white text) when the card is dominant (story 3). The header is the clickable hard-switch target (story 1).

3. **Hard-switch tap target** — the card header area (containing the slot label and scene name) should be wrapped in a `Button` or `.onTapGesture` that calls `setLiveMasterCrossfader(0.0)` for slot A or `setLiveMasterCrossfader(1.0)` for slot B.

4. **Macro grid layout** — change from `ScrollView(.horizontal)` wrapping a flat `HStack` of knobs to a `LazyVGrid` with 2 columns × 4 rows. This removes the scroll view from the macro display path and makes all 8 knobs visible simultaneously (story 6). The 2×4 layout is preferred per `ux-review.md` because it fits full macro labels without truncation.

### Removal of `ViewThatFits` Fallback

The current `performView` uses `ViewThatFits(.horizontal)` to fall back to a vertical stack at narrow widths. With the new three-column layout where the fader sits between the cards, the vertical fallback is less useful — a stacked layout would no longer have the fader adjacent to both cards. The implementation team should remove the `ViewThatFits` wrapper and use the three-column `HStack` unconditionally. If a narrow-layout concern arises later, it can be addressed as a separate item.

---

## Key Trade-Offs and Decisions for Review

### 1. Effective Crossfader Exposure Point

**Decision required:** Should `effectiveCrossfader` be a computed property on `EngineController` (exposed as `@Observable`-published state) or computed inline in the view from `crossfaderOverride` and `abSelection.crossfader`?

- **On `EngineController`:** Keeps the view thin, testable, and consistent with how other controller state is consumed. Risk: adds public surface area to `EngineController`.
- **Inline in view:** Simpler, but duplicates the merge logic if multiple views need it.

The `EngineController` approach is preferred to avoid logic in views, but this is a judgment call for the implementation team.

### 2. Vertical Slider Implementation

**Decision required:** Rotated `Slider` vs. custom drag gesture view.

- **Rotated `Slider`:** One line of SwiftUI. Known quirk: hit area may not rotate correctly; accessibility may be degraded.
- **Custom `DragGesture` view:** More code, full control over hit area and accessibility, matches the physical crossfader metaphor more closely.

The architecture has no preference; the implementation team should choose based on testing in the actual pane width. The PM record notes both options.

### 3. Hard-Switch Interaction: Header Tap vs. Dedicated Button

**Decision required:** Should the hard-switch target be the entire card header (slot label + scene name area) or a distinct button within the header?

- **Full header as tap target:** Large hit area, natural for stage use, clearly communicated by the active inversion treatment.
- **Distinct button:** Smaller hit area, less ambiguous about what is interactive vs. what is informational.

`ux-review.md` and the primary prototype recommend the full header as the tap target. This is the proposed direction unless the reviewer disagrees.

### 4. Exactly 0.5 Crossfader State

**Decision required:** When `effectiveCrossfader == 0.5`, neither card shows the active treatment. This is the correct behaviour per `ux-review.md`. The implementation team should confirm that the initial state (persisted crossfader at `0.0`) correctly shows card A as dominant, not neither.

The initial `crossfader` in `MasterBusABSelection` is `0.0` (line 687 of `MasterBus.swift`), which means card A is dominant at startup. `0.0 < 0.5` is true, so the indicator works correctly at the default state without any additional initialization.

---

## Architecture Questions That Must Be Answered Before Spec

1. **Vertical fader implementation choice:** rotated `Slider` or custom drag gesture. This affects accessibility and hit-area behaviour and should be decided before the view spec is written.

2. **`effectiveCrossfader` exposure point:** on `EngineController` or inline in the view. Either is acceptable architecturally; the spec should specify which to avoid dual implementations.

3. **Card header hard-switch scope:** confirm the full header (including scene name text) is the intended tap target, not just the slot label. This determines the hit area and the accessibility label.

These three questions are low-risk and can be resolved by the user's architecture review response or deferred to implementation with a documented default.

---

## Existing Tests: No Changes Required

The model and audio tests in `MasterBusStateTests.swift`, `MasterBusHostTests.swift`, and `SequencerDocumentSessionMasterBusTests.swift` are unaffected by this feature. No model mutation, no new overlay semantics, no new session mutations. The implementation team should add:

- A unit test for the `effectiveCrossfader` computed property (overlay present vs. absent).
- A unit test for the `isADominant` / `isBDominant` derivation at 0.0, 0.5, and 1.0.
- No snapshot tests are required by the current test infrastructure; if a SwiftUI preview test harness is introduced later, the new `performView` should be covered.

---

## Sources Inspected

- `Sources/Document/MasterBus.swift` — `MasterBusState`, `MasterBusABSelection`, `MasterBusPerformanceOverlayState`, `applyingPerformanceOverlay(_:)`, `normalize()`
- `Sources/Engine/EngineController.swift` — `setLiveMasterCrossfader`, `clearLiveMasterCrossfader`, `masterBusPerformanceOverlay`
- `Sources/Audio/MasterBusHost.swift` — `setLiveCrossfaderOverride`, `equalPowerGains`, `NSLock` threading contract
- `Sources/App/SequencerDocumentSession+Mutations.swift` — `setMasterCrossfader`, `setMasterABMode`, `saveMasterScenePerformanceOverrides`
- `Sources/UI/Mixer/ScenesWorkspaceView.swift` — mode picker, `performView` entry point, editor-open guard
- `Sources/UI/Mixer/ScenesWorkspaceView+Perform.swift` — `crossfader` function, `performSlot` function, `ViewThatFits` fallback, card-actions footer
- `wiki/pages/architecture-guardrails.md` — document truth vs runtime state, small boundaries, no view-local playback truth
- `wiki/pages/engine-architecture.md` — `EngineController` responsibilities, `@Observable` / threading model
- `wiki/pages/document-model.md` — what the document does and does not contain
