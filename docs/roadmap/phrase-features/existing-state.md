# Phrase Features — Existing State

Inspected 2026-04-29.

## 1. Phrase Data Model

**File:** `Sources/Document/PhraseModel.swift`

`PhraseModel` already carries `lengthBars: Int` and `stepsPerBar: Int`, both enforced >= 1. The model is fully `Codable`, so any new fields added alongside those will persist automatically.

What is absent from the model:

| Story requirement | Current model field | Gap |
|---|---|---|
| Repeat count | Not present | Model gap — no `repeatCount` field |
| Loop toggle (permanent loop) | Not present | Model gap — no `loopEnabled: Bool` or equivalent |
| Phrase-level "advance" vs "loop forever" | Not present | Model gap — currently only a global `TransportMode` |

The `PhraseModel` default creates a phrase named "Phrase A" with `lengthBars: 8`. Bar count is therefore readable and settable today, but there is no UI on the phrase button to change it (see Section 3).

## 2. Engine — Looping, Free Mode, Song Mode

**Files:** `Sources/Engine/TransportMode.swift`, `Sources/Engine/EngineController.swift`

`TransportMode` is a global, two-case enum (`song` / `free`) owned by `EngineController.transportMode`. It is not per-phrase.

- `.free` — "Transport stays on the current phrase." The tick path in `EngineController.prepareTick` wraps the step counter modulo the selected phrase's `stepCount`, so in practice the selected phrase loops forever.
- `.song` — "Transport follows phrase order." The `playbackPhraseIndex` computed property in `TracksMatrixView`, `LiveWorkspaceView`, and `PhraseWorkspaceView` reconstructs which phrase is "currently playing" by summing `lengthBars` across all phrases and wrapping the absolute bar counter. Crucially, the engine tick path itself does **not** advance the active phrase — phrase advancement is computed in the UI for display purposes only. The `EngineController` always plays against `playbackSnapshot.selectedPhraseID`, which is the document's `selectedPhraseID`. There is no engine-side phrase sequencing loop.

Implications for Story 2 (repeat count) and Story 3 (loop toggle):

- The engine currently has no concept of "play this phrase N times then stop/advance". Song-mode phrase ordering is a pure UI calculation that does not feed back into what the engine actually ticks through.
- Implementing repeat count or per-phrase loop toggle will require either (a) teaching the engine to maintain a phrase-advance cursor based on repeat counts, or (b) having the session layer drive `selectedPhraseID` changes on the fly.
- This is an engine architecture gap, not just a model gap.

**Tests:** `Tests/SequencerAITests/Engine/TransportModeTests.swift` — covers only codable roundtrip and label distinctness. No test covers phrase advancement in song mode or loop-boundary behaviour.

## 3. Phrase Button UI — Bar Count, Repeat Count, Loop Toggle

**File:** `Sources/UI/PhraseWorkspaceView.swift` — `PhraseMatrixPhraseCell`

The `PhraseMatrixPhraseCell` struct (lines 446–479) renders each phrase row-header. It shows the phrase name and `"\(phrase.lengthBars) bars"` as a read-only label. There is no stepper, button, or other control for changing `lengthBars` from this cell. There is no repeat-count control and no loop-toggle control.

The phrase-level action menu (`PhraseRowActions`) provides insert-below, duplicate, and remove actions only (lines 377–407).

Gap summary for stories 1–3: the phrase button (row-header cell) exposes bar count as a display value but no edit control. Repeat count and loop toggle have no model backing and no UI.

## 4. Performance Modes — User Story 4 Concern Resolved

**Files:** `Sources/UI/TracksMatrixView.swift`, `Sources/UI/LiveWorkspaceView.swift`, `Sources/UI/Mixer/ScenesWorkspaceMode.swift`, `Sources/UI/Mixer/ScenesWorkspaceView+Perform.swift`

There are **two distinct "perform" modes** in the codebase:

### 4a. Track-matrix perform mode (`TracksWorkspaceMode.perform`)

Declared in `Sources/UI/TracksMatrixView.swift` (lines 1–17). A toggle on the track matrix action bar switches between `.edit` and `.perform`. In perform mode, tapping a track card directly cycles the phrase-cell value for the currently-editing phrase (the `performPrimaryAction` path, lines 386–444). The editing phrase is `editingPhraseID`, which tracks the live playback phrase in song mode.

This is the "performance mode" that User Story 4 refers to. It writes directly into the phrase model — there is no intermediate overlay or "performance scratch pad". Changes made while performing are immediately committed to the phrase. There is therefore no "save back" workflow and no "cancel without saving" path.

Gap summary for Story 4:
- No separate performance-state layer exists. Perform-mode edits go straight into the canonical phrase model via `session.setPhraseCell(...)`.
- No "save back" action is needed today because edits are already saved.
- But there is also no "discard" path — accidental perform-mode edits cannot be undone within the session (undo is not wired).
- The story asks for a staging layer that can be committed or discarded; neither exists.

### 4b. Scenes perform mode (`ScenesWorkspaceMode.perform`)

Declared in `Sources/UI/Mixer/ScenesWorkspaceMode.swift`. This is a live-override mode for master-bus scene macros and the A/B crossfader. It does have a staging overlay (`EngineController.masterBusPerformanceOverlay`) and explicit "Save to Scene" / "Revert" actions. This is the correct pattern Story 4 wants for phrases, but it does not exist at the phrase layer.

The user-stories assumption that "performance modes exist and this feature adds save-back" is partially correct: the pattern exists in the scenes layer but not at the phrase layer, where perform mode writes through immediately.

## 5. Track-Page Navigation Arrows

**File:** `Sources/UI/PhraseWorkspaceView.swift` (lines 113–183)

The phrase workspace already has track-page navigation. Left/right arrows are rendered inside `layerBar` as `trackPageButton(...)` calls (lines 172–182). The current placement is at the **right side of the layer bar** (after a `Spacer()`), not at the top-left and top-right corners of the matrix header row.

Occupancy hint: when `trackPage >= trackPageCount - 1` the right arrow is `isEnabled: false` and dimmed; the left arrow is disabled when `trackPage == 0`. There is no positive indicator that content exists on the adjacent page — disabled appearance is the only hint, which is a passive signal. No explicit "N tracks on next page" badge or arrow variant exists.

The `TracksMatrixView` (the separate track-grid view) has no page navigation at all — all tracks are shown in a `LazyVGrid` without paging.

Gap summary for Story 5:
- Arrows exist in `PhraseWorkspaceView` but are positioned in the layer-selector bar, not at the matrix corners.
- Occupancy is communicated only by enabling/disabling the arrow, not by a positive visual (e.g. a dot, count badge, or brighter active style).
- No "tracks on next page" count or indicator.

## 6. Layer Selector Width Stability

**File:** `Sources/UI/PhraseWorkspaceView.swift` (lines 127–155), `Sources/UI/TracksMatrixView.swift` (lines 236–292)

In `PhraseWorkspaceView.layerBar`, the layer-name pill is built with:
```
HStack { Text(selectedLayer.name...) + Rectangle() + Text(layerSubtitle...) + Text(index...) }
.padding(.horizontal, 14)
.padding(.vertical, 10)
.background(..., in: RoundedRectangle(...))
```

No fixed width is set on this `HStack` or its container — it sizes to its content. Layer names vary in length ("Pattern" vs "Transpose" vs "Variance") and `layerSubtitle` also varies ("pattern slot" vs "track mute" vs "intensity"). Switching layers will change the pill width, which may cause the surrounding `HStack` (and the `Spacer()` to its right) to relayout.

In `TracksMatrixView.layerControl`, the inner `VStack` has `.frame(width: 190, alignment: .leading)` (line 272), which fixes the text container width. However the outer `HStack` (the entire layer control group including the two chevron buttons) is not fixed-width — only the text block is. The chevron buttons are fixed 30×30 each. The net container will be approximately fixed at 190 + two 30-pt chevrons + spacing, but any minor text overflow or truncation change still affects layout if `minimumScaleFactor` kicks in.

Gap summary for Story 6:
- `PhraseWorkspaceView` layer bar: no fixed width — shifts with layer name length.
- `TracksMatrixView` layer control: partial fix (text block is 190 pt wide) but the assembly is not anchored to the grid column start.
- Neither selector is explicitly aligned to the grid column positions.

## 7. Architecture Constraints

- **Engine phrase sequencing is UI-driven, not engine-driven.** The `EngineController` tick path always uses `selectedPhraseID` from the playback snapshot. Song-mode phrase cycling is computed in the UI by three views (`TracksMatrixView`, `LiveWorkspaceView`, `PhraseWorkspaceView`) using duplicate logic. Adding repeat-count or loop-toggle behaviour would require either (a) centralising phrase-advance logic in the session or engine layer, or (b) duplicating the new logic across all three views. Centralisation is the correct approach but is a non-trivial refactor.
- **No per-phrase playback override cursor exists.** There is no `phraseRepeatIndex` or `phraseCursor` in the engine or session state.
- **Perform-mode phrase edits are not staged.** Writing a staging layer for phrase perform mode would need a new in-memory overlay structure analogous to `MasterBusPerformanceOverlayState`.

## 8. Test Coverage

| Area | Coverage | Gap |
|---|---|---|
| `TransportMode` codable / labels | `TransportModeTests.swift` | No test for song-mode phrase advancement |
| `PhraseModel` bar count / step count | Covered via `SequencerSnapshotCompilerSemanticsTests` indirectly | No test for `repeatCount` (field doesn't exist) |
| Perform-mode cell mutation | `LiveWorkspaceViewTests.swift` exists | Coverage of discard/stage workflow: none (feature doesn't exist) |
| Layer selector width | None | No snapshot or layout test |
| Track-page navigation arrows | None | No test |

## Summary of Gaps by Story

| Story | Gap type | Severity |
|---|---|---|
| 1. Bar count control on phrase button | UX only (model field exists, no edit control) | Medium |
| 2. Repeat count | Model + engine + UX | High |
| 3. Loop toggle | Model + engine + UX; replaces global `TransportMode.free` | High |
| 4. Perform save-back | UX architecture (staging layer, discard path) | High |
| 5. Page arrows at matrix corners | UX repositioning + occupancy hint | Medium |
| 6. Fixed-width layer selector | UX layout fix | Low |
