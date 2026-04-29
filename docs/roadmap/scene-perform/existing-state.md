# Scene Perform — Existing State

Inspected: 2026-04-29

---

## 1. Model Layer

### MasterBusState (`Sources/Document/MasterBus.swift`)

`MasterBusState` is the persisted document model for the master bus.

| Concept | Where | Notes |
|---|---|---|
| Scene list | `MasterBusState.scenes: [MasterBusScene]` (line 4) | Minimum 2 scenes enforced by `normalize()` (line 155) |
| Active scene | `MasterBusState.activeSceneID: UUID` (line 6) | Points into `scenes[]`; used by the Browse/Edit view |
| A/B slot assignment | `MasterBusState.abSelection: MasterBusABSelection?` (line 7) | `sceneAID`, `sceneBID`, `crossfader: Double` (0…1, clamped). Always present after `normalize()` |
| Crossfader value | `MasterBusABSelection.crossfader: Double` (line 685) | Persisted to document. Range 0…1 |
| Macro slots | `MasterBusScene.macroBindings: [MasterSceneMacroBinding]` (line 281) | Max 8 slots (`MasterSceneMacroBinding.slotCount = 8`, line 372) |
| Macro targets | `MasterSceneMacroTarget` enum (line 411) | Covers outputGain, insertWetDry, filterCutoff, filterResonance, bitcrusherRate, bitcrusherDrive, auParameter |

`MasterBusABSelection` initialises `crossfader` to `0` (full Scene A) by default (line 687). Normalisation on the state ensures the AB selection always references two real scenes that are distinct.

### MasterBusPerformanceOverlayState (`Sources/Document/MasterBus.swift`, line 631)

A non-persisted, in-memory layer that sits on top of `MasterBusState`:

- `sceneMacroOverrides: [UUID: [UUID: Double]]` — per-scene, per-macro knob overrides
- `crossfaderOverride: Double?` — live crossfader position that shadows the persisted crossfader value

`applyingPerformanceOverlay(_:)` (line 203) merges the overlay into a copy of the state for audio rendering. The original `MasterBusState` is not mutated during live performance, only when the user explicitly saves.

---

## 2. Engine / Audio Layer

### EngineController (`Sources/Engine/EngineController.swift`)

`EngineController` is a non-isolated `RouterDispatcher` subclass annotated `@Observable` (line 5). All UI-observed properties publish on the main thread. The controller owns `masterBusPerformanceOverlay` as a `private(set) var` (line 113).

Key perform-mode methods:

| Method | Behaviour |
|---|---|
| `setLiveMasterCrossfader(_:)` (line 486) | Writes to overlay; forwards immediately to `MasterBusHost.setLiveCrossfaderOverride(_:)`. No debounce or smoothing. |
| `clearLiveMasterCrossfader()` (line 492) | Clears the crossfader override; restores the persisted value for audio. |
| `setMasterSceneMacroOverride(sceneID:macroID:value:)` (line 475) | Writes to overlay; forwards to host immediately. |
| `clearMasterSceneMacroOverrides(sceneID:)` (line 481) | Revert path for per-slot macro knobs. |
| `clearMasterBusPerformanceOverlay()` (line 497) | Clears all overrides (used when re-assigning A/B slots). |

### MasterBusHost (`Sources/Audio/MasterBusHost.swift`)

Runs under `NSLock` for thread safety (line 22). Crossfader values are converted to equal-power gains using cosine law:

```
a = cos(crossfader × π/2)
b = sin(crossfader × π/2)
```

(`equalPowerGains(crossfader:)`, line 188). Branch gain is updated on every `setLiveCrossfaderOverride(_:)` call (line 129), which calls `refreshAudioGraphForPerformanceChange()`. There is no audio-side smoothing (no ramp, no parameter automation scheduling). Value is applied sample-frame–accurately on the next buffer boundary only.

---

## 3. Persistence / Session Layer

### SequencerDocumentSession+Mutations (`Sources/App/SequencerDocumentSession+Mutations.swift`)

Persist path for crossfader: `session.setMasterCrossfader(_:)` (line 360) writes the crossfader value into the persisted `MasterBusABSelection` via `mutateMasterBus`. This is triggered only when the user taps "Save Blend".

Persist path for A/B slot assignment: `session.setMasterABMode(_:)` (line 354) replaces the whole `MasterBusABSelection`.

Persist path for macro overrides saved back to scene: `session.saveMasterScenePerformanceOverrides(_:to:)` (line 346) iterates the overlay dictionary and calls `setMacroValue` for each entry.

Document flush is debounced; the store is updated immediately but the `SeqAIDocument` (and thus disk) only receives changes after the debounce timer fires or `flushToDocument()` is called explicitly.

---

## 4. Existing UI Structure

### ScenesWorkspaceMode (`Sources/UI/Mixer/ScenesWorkspaceMode.swift`)

A two-case `CaseIterable` enum: `.browseEdit` and `.perform`. Displayed as a segmented picker in the scene header (line 127 of `ScenesWorkspaceView.swift`). Default is `.browseEdit`.

### ScenesWorkspaceView (`Sources/UI/Mixer/ScenesWorkspaceView.swift`)

Top-level view. The `body` switches on `mode` (line 69):

- `.browseEdit` → scene browser grid or scene editor
- `.perform` → `performView` (defined in the extension)

Header and mode picker are hidden when `selectedSceneID != nil` (line 65), i.e. when the scene editor is open — this means entering the scene editor from Browse/Edit hides the Perform toggle while the editor is visible.

### ScenesWorkspaceView+Perform.swift — `performView`

Current layout (lines 5–26):

```
VStack {
    crossfader(selection)         // full-width HStack
    ViewThatFits(.horizontal) {
        HStack { Slot A | Slot B } // side-by-side if wide enough
        VStack { Slot A; Slot B }  // stacked if narrow
    }
}
```

**The crossfader row is fully above the two scene cards.** The crossfader spans the full pane width as a SwiftUI `Slider` with "A" label on the left and "B" label on the right. The percentage readout, Reset button, and Save Blend button are appended in the same `HStack` to the right of the slider.

**The `crossfader` function** (lines 28–72):

- `Slider` range: `0...1` (line 39), maps directly to the overlay's `crossfaderOverride`
- Reset button: calls `engineController.clearLiveMasterCrossfader()`. Disabled when `crossfaderOverride == nil` (i.e. when no live drag has been performed). This means Reset restores only the overlay to the persisted value; it does not snap to the nearest full end (0 or 1) as story 4 requires — it simply removes the live override.
- Save Blend button: calls `session.setMasterCrossfader(value)` then clears the overlay. No confirmation dialog.

**The `performSlot` function** (lines 74–135):

- Displays title ("Slot A" / "Slot B"), scene name, a "MODIFIED" badge when macro overrides are active, a grid picker button to swap the scene, eight macro slot knobs in a horizontal scroll view, and Revert / Save to Scene buttons.
- There is no visual distinction between the currently live/active scene and the off-side scene. Both cards are rendered with identical background, border, and label styles (same amber accent for both titles, same `subtleFill` background).
- Macro knobs are rendered via `MacroSlotKnob` in a `ScrollView(.horizontal)` — they do not all fit on screen for narrow layouts without scrolling.

**Scene slot picker** (lines 179–288): a sheet presenting a grid of existing scenes with checkmark-selected state. Assigning a scene calls `clearMasterBusPerformanceOverlay()` first, clearing any live overrides.

---

## 5. Story-by-Story Gap Analysis

### Story 1 — Hard-switch between scenes

**Model support:** `session.setMasterABMode(_:)` can set a crossfader of 0 or 1 explicitly; `session.setMasterCrossfader(_:)` can snap to 0 or 1 as well. The model fully supports a crossfader at a hard end.

**UX gap:** No hard-switch affordance exists. There is no tap target on either scene card that commits the crossfader to that scene's end. The only way to switch fully is to drag the slider to its end or replace the scene via the slot picker (which preserves the current crossfader position). This is a **UX-only gap** — no model change required.

### Story 2 — Blend live with a repositioned crossfader

**Model support:** Full. The overlay's `crossfaderOverride` and `setLiveMasterCrossfader` work correctly end-to-end.

**UX gap:** The crossfader is a full-pane-width `Slider` sitting above the two cards, not between them. The travel distance is the maximum possible. This is a **UX/layout-only gap** — the `crossfader` function in `ScenesWorkspaceView+Perform.swift` needs a structural rewrite to place it between the two slot views.

### Story 3 — Cue the off-side scene before committing

**Model support:** The off-side scene card is fully visible and shows current macro slot values (including live overrides via `resolvedMacroValue`). Changes to either card's macro knobs are independent per scene. No model gap.

**UX gap:** There is no visual indicator distinguishing the live/active scene from the off-side scene. Both cards have identical visual treatment. A performer cannot tell at a glance which side is currently dominant (i.e. where the crossfader sits closest to). This is a **UX-only gap**.

Open question: "active/live" in perform mode is ambiguous — the crossfader is continuous, so there is no hard binary. The indicator should probably reflect whichever end the crossfader is nearest to, or show the blend percentage as a fill on the card border.

### Story 4 — Recover from an accidental partial blend

**Model support:** Exists. `clearLiveMasterCrossfader()` removes the crossfader override and returns to the persisted value. The semantics differ from the story: Reset restores the persisted crossfader position, not necessarily the nearest hard end.

**UX gap (partial model gap):** The story asks Reset to snap to the nearest full-scene end (0 or 1). The current Reset removes the live override entirely, snapping back to whatever value was last saved to the document. If the saved value was 0.3 (a prior partial blend that was saved), Reset would return to 0.3 rather than the nearest end. Additionally, the Reset and Save Blend buttons sit at the far right of the crossfader row — far from where the fader knob typically rests mid-drag. The new layout places the fader between the cards, which naturally brings Reset and Save Blend closer by proximity.

A small model addition may be needed: the Reset action would need to determine the nearest endpoint (0 or 1) at the time of invocation. This logic does not exist today.

### Story 5 — Save a live blend as a new scene state

**Model support:** `session.setMasterCrossfader(value)` + `clearLiveMasterCrossfader()` saves the blend position. The macro overrides for each slot can also be saved individually via `saveMasterScenePerformanceOverrides`.

**UX gap:** Save Blend has no confirmation dialog. An accidental tap overwrites the persisted crossfader position with no undo affordance visible in the perform pane. Additionally, Save Blend is currently at the far right end of the crossfader row.

Note: the current Save Blend only saves the fader position to `abSelection.crossfader`. It does not package macro overrides into a new named scene. If the user wants to make a blended parameter state reproducible as a standalone scene, they must use "Save to Scene" on each slot card independently. The user story says "stores the current blended macro values into the designated scene slot", which matches the existing per-slot "Save to Scene" button, not the crossfader-only "Save Blend". These are two separate operations today.

### Story 6 — Read both scenes at a glance

**Model support:** Complete. All eight macro slots are available per scene.

**UX gap:** Macro knobs are in a `ScrollView(.horizontal)` — at the default pane width, not all eight are visible without scrolling. The "ViewThatFits" fallback stacks the two cards vertically on narrow layouts, which may require scrolling to see both. The proposed three-column layout (Scene A | Fader | Scene B) places all scene information in a single horizontal row, but this depends on each card being narrow enough to show all 8 knobs without a scroll view or on the knob area being scrollable independently. This is a **UX/layout gap**.

---

## 6. Architecture Constraints

- `EngineController` is not `@MainActor` but publishes `@Observable` state that is consumed on the main thread. Perform-mode mutations (`setLiveMasterCrossfader`) go directly to the `EngineController` instance without routing through `SequencerDocumentSession`. This is by design — the overlay is intentionally non-persisted and mutation-free.
- `MasterBusHost` uses `NSLock` for thread-safe state access and does not use Swift concurrency actors. Crossfader updates from the UI hit the audio graph synchronously within the lock.
- There is no audio-level crossfader smoothing or parameter ramping. Sudden slider jumps will produce audible steps. This is not a model gap but an audio quality concern for the implementation team to address.
- The `MasterBusPerformanceOverlayState` is separate from the document model and is not persisted. It resets on session teardown. This means any live blend state not explicitly saved is lost on app quit, which is the expected behaviour for a live performance tool.
- `ScenesWorkspaceView` hides the mode picker (Browse/Edit | Perform) when the scene editor is open (`selectedSceneID != nil`). This prevents entering Perform mode while a scene is being edited, which is correct but is a quirk worth noting.

---

## 7. Existing Tests

### Model-level tests (`Tests/SequencerAITests/Document/MasterBusStateTests.swift`)

- `test_defaultProject_hasBlankSceneSlots` — AB selection initialised to first two scenes
- `test_invalidABSelection_defaultsToFirstTwoScenes` — normalisation clamps crossfader and resolves missing scene IDs
- `test_removingScenes_keepsTwoABSlots` — minimum scene count enforced
- `test_macroBindingsAreCappedAndCleanedUpWhenInsertIsRemoved` — 8-slot cap and teardown
- `test_sceneOutputGain_isNormalizedToUnityAndNotAMacroTarget` — normalisation guard

### Audio-level tests (`Tests/SequencerAITests/Audio/MasterBusHostTests.swift`)

- `test_equalPowerCrossfadeGains` — verifies cosine-law gains at 0, 0.5, 1
- `test_abModeInstallsTwoSceneBranchesWithEqualPowerGains` — graph topology for A/B mode
- `test_liveCrossfaderOverrideUpdatesBranchGainsWithoutReapply` — overlay does not trigger a full apply
- `test_liveMacroOverrideUpdatesExistingNodeWithoutReapply` — macro override hits AU node directly

### Session integration tests (`Tests/SequencerAITests/App/SequencerDocumentSessionMasterBusTests.swift`)

- `test_liveSceneMacroOverlay_doesNotMutateStoreOrSnapshots`
- `test_savingLiveSceneMacroOverlay_writesBackToScene`

### Missing coverage

- No test for Reset snapping to the nearest hard end (the semantic required by story 4 is not yet implemented, so there is no test to write yet).
- No test for Save Blend confirmation guard (no such guard exists today).
- No test for the "active scene visual indicator" (a UI concern, not directly unit-testable without a snapshot harness — none exists).
- No test for hard-switch (clicking a scene card to snap the fader) — feature does not yet exist.
- No snapshot or SwiftUI preview tests for `ScenesWorkspaceView+Perform.swift` in any form.

---

## 8. Summary: Model Gaps vs UX/Workflow Gaps

| Story | Gap type | Description |
|---|---|---|
| 1. Hard-switch | UX only | No tap-to-commit affordance on scene cards |
| 2. Repositioned fader | UX/layout only | Fader above cards, not between them |
| 3. Cue / live indicator | UX only | No visual distinction between live and off-side scene |
| 4. Reset to nearest end | UX + small model | Reset restores persisted value, not nearest 0/1; nearest-end logic missing |
| 5. Save Blend confirmation | UX only | No confirmation dialog before overwriting |
| 5. Save Blend semantics | Clarification needed | Current Save Blend saves only the fader position; saving a full blended macro state requires per-slot "Save to Scene" — these are two distinct operations |
| 6. Macro slots always visible | UX/layout | Knobs live in a horizontal scroll view; not all visible at once at typical pane widths |
