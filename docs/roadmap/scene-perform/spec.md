---
created: 2026-04-29
stories_covered: [1, 2, 3, 6]
stories_descoped: [4, 5]
architecture_approved: true
architecture_review: architecture-review.md
---

# Scene Perform — Spec

## Scope

This spec covers stories 1, 2, 3, and 6 from `user-stories.md`. Stories 4 (Reset to nearest end) and 5 (Save Blend / Save to Scene) are explicitly out of scope and must not be implemented as part of this feature. See the Out-of-Scope section below.

---

## What Changes

The only file that changes in the production codebase is `Sources/UI/Mixer/ScenesWorkspaceView+Perform.swift`.

No model layer, engine, audio host, session mutation, or document serialization changes are required or approved for this feature. The change surface is deliberately narrow: the `performView` function and its two child functions (`crossfader` and `performSlot`) are restructured and trimmed.

---

## Behaviour

### Story 1 — Hard-switch between scenes

Tapping or clicking the scene card header commits the crossfader immediately to that card's hard end:

- Tapping the Scene A card header calls `engineController.setLiveMasterCrossfader(0.0)`.
- Tapping the Scene B card header calls `engineController.setLiveMasterCrossfader(1.0)`.

The call goes through the existing overlay path (`MasterBusPerformanceOverlayState.crossfaderOverride`). No document mutation occurs. The audio update happens at the next buffer boundary (no ramp — see Audio Smoothing note).

The entire card header area is the tap target, not a separate button inside it. The header contains the slot label ("Slot A" / "Slot B") and the scene name. The full bounding rect of the header row is tappable.

### Story 2 — Live crossfader blend

The crossfader is a vertical control that sits in a fixed-width centre column between the two scene cards. Dragging it from end to end covers only the width of that centre column — not the full pane width.

Every drag gesture delta calls `engineController.setLiveMasterCrossfader(newValue)` with a value clamped to `0.0...1.0`. The blend readout (percentage) is derived from `effectiveCrossfader` and is visible at all times within the crossfader column. No Reset or Save Blend control is present in the crossfader column.

### Story 3 — Cue the off-side scene / active-scene indicator

Both scene cards are simultaneously visible in the perform view. The off-side card shows the current macro slot values from the model (and from live macro overrides in `sceneMacroOverrides` if any are active). Inspecting the off-side card does not change the live audio because macro changes in this version directly mutate the original scene — there is no isolation or preview layer (see Out-of-Scope note on Revert).

The active-scene indicator is derived from `effectiveCrossfader`:

- `effectiveCrossfader < 0.5` → Scene A card is dominant (active treatment).
- `effectiveCrossfader > 0.5` → Scene B card is dominant (active treatment).
- `effectiveCrossfader == 0.5` → neither card shows the active treatment.

Active treatment is a full header colour inversion: the dominant card's header background is dark with white text. The non-dominant card's header is rendered in the default style. There is no ambiguous intermediate state — the ternary comparison is the only indicator logic; no additional stored state is introduced.

### Story 6 — Read both scenes at a glance

All eight macro slots (M1–M8) on both scene cards must be visible simultaneously without horizontal scrolling. The macro display uses a 2-column × 4-row fixed grid (`LazyVGrid` with two columns, or equivalent). The `ScrollView(.horizontal)` wrapper that currently contains the macro knobs is removed. Each macro label must not be truncated at typical card widths under the new three-column layout.

---

## Data Model Touch Points

All fields listed here are read-only from this feature's perspective. No field is written to by this feature.

| Model object | Field | Used for |
|---|---|---|
| `MasterBusABSelection` | `sceneAID`, `sceneBID` | Identify which scene occupies each slot |
| `MasterBusABSelection` | `crossfader: Double` | Baseline fader position when no override is active |
| `MasterBusScene` | `name`, `macroBindings` | Card header scene name, macro slot display |
| `MasterSceneMacroBinding` | `slotIndex`, `value` | Macro label and current value in the 2×4 grid |
| `MasterBusPerformanceOverlayState` | `crossfaderOverride: Double?` | Live fader position; drives the indicator and readout |
| `MasterBusPerformanceOverlayState` | `sceneMacroOverrides` | Live macro values displayed on either card |

### Effective Crossfader Value

A single computed property `effectiveCrossfader` on `EngineController` exposes the merged value:

```
effectiveCrossfader = crossfaderOverride ?? abSelection.crossfader
```

This is the single read path consumed by the view. The view must not shadow or re-derive this value locally. The view reads `engineController.effectiveCrossfader` wherever the fader position is needed (slider binding, indicator logic, blend readout).

The initial persisted crossfader value is `0.0` (Scene A full), so the indicator correctly shows Scene A as dominant at startup.

---

## View Structure

The change is entirely within `ScenesWorkspaceView+Perform.swift`.

### `performView` — top-level layout

Replace the current `VStack { crossfader; ViewThatFits { ... } }` structure with a three-column `HStack`:

```
HStack(spacing: 0) {
    performSlot(.a, ...)       // .frame(maxWidth: .infinity)
    crossfaderColumn(...)      // .frame(width: ~120)
    performSlot(.b, ...)       // .frame(maxWidth: .infinity)
}
```

The `ViewThatFits` fallback is removed. The three-column layout is unconditional. If a narrow-layout concern arises in future it is addressed as a separate item.

### `crossfaderColumn` — centre column

Contents (top to bottom):

1. "A" label
2. Vertical crossfader control (see Vertical Fader note)
3. Blend readout (percentage derived from `effectiveCrossfader`)
4. "B" label

No Reset button. No Save Blend button. The column is purely a fader and its readout.

The crossfader control is vertical. SwiftUI's `Slider` does not have a native vertical mode. The preferred implementation is a custom drag gesture view that maps vertical drag offset to the `0.0...1.0` range. A rotated `Slider` (`.rotationEffect(.degrees(-90))`) is acceptable if implementation testing shows hit area and accessibility are adequate, but the preferred default per the architecture review is the custom gesture view.

### `performSlot` — scene card

Changes to the existing `performSlot` function:

1. **Card header as hard-switch tap target.** Wrap the header row (slot label + scene name) in a `Button` or apply `.onTapGesture`. The action calls `engineController.setLiveMasterCrossfader(0.0)` for slot A, or `setLiveMasterCrossfader(1.0)` for slot B.

2. **Active-scene indicator.** Apply full header colour inversion to the dominant card. The header background and text colours switch when `isADominant` or `isBDominant` is true. `isADominant = effectiveCrossfader < 0.5`; `isBDominant = effectiveCrossfader > 0.5`. No additional stored state.

3. **Macro grid layout.** Replace the `ScrollView(.horizontal)` containing a flat `HStack` of macro knobs with a `LazyVGrid` (2 columns, 4 rows) or equivalent fixed 2×4 grid. All eight knobs are visible simultaneously. The scroll view is removed from this display path.

4. **Remove the card-actions footer.** The bottom row containing the Modified badge, Revert button, and Save to Scene button is removed entirely. These controls are descoped per `ux-review.md`. If macro values are modified in perform mode they take effect on the original scene directly (current model behaviour); no in-pane recovery action is provided in this feature.

5. **Scene picker stub remains.** The grid picker button that opens the scene picker sheet stays in place. Assigning a new scene via the picker still calls `clearMasterBusPerformanceOverlay()` first, which is the existing correct behaviour.

---

## Engine Call Surface

No changes to `EngineController`, `MasterBusHost`, or `SequencerDocumentSession+Mutations`.

The calls used by this feature already exist and work correctly:

| Action | Call | Already exists |
|---|---|---|
| Hard-switch to A | `engineController.setLiveMasterCrossfader(0.0)` | Yes |
| Hard-switch to B | `engineController.setLiveMasterCrossfader(1.0)` | Yes |
| Live crossfader drag | `engineController.setLiveMasterCrossfader(newValue)` | Yes |
| Read macro slot values | `resolvedMacroValue` via overlay | Yes |

The only new surface is the computed property `effectiveCrossfader` on `EngineController`, which combines `crossfaderOverride` and `abSelection.crossfader`. This is a pure getter with no side effects.

---

## Audio Smoothing Note

Hard-switching (story 1) applies a gain jump at the next audio buffer boundary with no ramp. This will produce an audible step on a typical buffer size. Adding a ramp requires changes in `MasterBusHost` that are outside this feature's scope. The implementation team should flag this as a known limitation and track it as a separate item if audio-quality ramping is required.

---

## Acceptance Criteria

These map directly to the user story "Done when" conditions for stories 1, 2, 3, and 6.

**Story 1 — Hard-switch:**
- A single click or tap on a scene card header snaps the fader to that end (0.0 for A, 1.0 for B).
- The active indicator updates immediately to reflect the new dominant card.
- No navigation away from the perform pane is required.

**Story 2 — Live blend:**
- The crossfader control is visually positioned between the two scene cards.
- Dragging the crossfader from end to end covers only the centre column width, not the full pane.
- The blend percentage readout updates continuously during a drag and is always visible.

**Story 3 — Cue / active indicator:**
- Both scene cards are simultaneously visible in the perform pane without scrolling or switching views.
- The dominant card (as determined by `effectiveCrossfader`) displays the full header colour inversion.
- The non-dominant card is displayed in the default style.
- At exactly 0.5, neither card shows the active treatment.
- Macro slot values on both cards reflect the current state (including any live overrides).

**Story 6 — Read both scenes at a glance:**
- All eight macro slots on both scene cards are visible simultaneously in the perform pane without horizontal scrolling.
- Each macro slot label is not truncated at the operating pane width.
- The Scene A card, crossfader column, and Scene B card all appear side by side in a single unscrolled viewport.

---

## Acceptance Signals (from user-stories.md)

- Moving the crossfader end-to-end requires a short drag (roughly the width of one scene card) rather than a full-pane sweep.
- The active and inactive scene are immediately distinguishable by visual treatment (colour inversion on the header) with no ambiguity.
- Hard-switch, live blend, and cue (inspect off-side card) all work without navigating away from the perform pane.
- The blend readout (percentage) remains visible during a drag.

---

## Out-of-Scope

The following stories and controls are explicitly descoped per `ux-review.md` and the `feedback/20260430-102206-prototypes-feedback.md` feedback. They must not be implemented as part of this feature.

**Story 4 — Reset to nearest end:** raises unresolved questions about where "the last clean state" is stored during a live performance session. Deferred to a future Live Scene Performance roadmap item.

**Story 5 — Save Blend pos. / Save to Scene:** raises questions about document mutation during a live set and about the semantics of saving a blended state. Both the Save Blend pos. button (crossfader position) and the Save to Scene per-card button are deferred to the same future Live Scene Performance item.

**Revert per-card button:** the current model mutates the original scene when macro values are adjusted in perform mode. A revert path requires a snapshot or ephemeral overlay model that is not specified for this feature. Deferred to the future Live Scene Performance item.

**Modified badge:** without a recovery action (Revert or Save to Scene) in this feature, the badge is not needed. Removed.

The crossfader column must not contain Reset or Save Blend controls. The scene card footer (card-actions row) must not contain Revert, Save to Scene, or Modified badge.

---

## Open Questions

None. The architecture review (`architecture-review.md`) resolved all three open architecture questions:

1. `effectiveCrossfader` is exposed as a computed property on `EngineController`.
2. The preferred fader implementation is a custom vertical drag gesture view (rotated `Slider` permitted if testing confirms it is adequate).
3. The full card header is the hard-switch tap target.

The implementation team has no open pre-conditions before starting.
