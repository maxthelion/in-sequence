# Toggle Fill On A Track To Hear It — Existing State

## Summary

The app already has two pieces of fill infrastructure:

1. clip authoring supports separate normal and fill lanes; and
2. playback already knows how to choose the fill lane when the phrase-authored `"fill-flag"` layer resolves true.

What does **not** exist is the user-facing feature described by [[story:1]] and [[story:3]]: there is no track-editor toggle, no transient runtime fill override, and no track-scoped live preview state that can shadow the phrase without mutating it.

---

## 1. Track Editor UI

### What exists

The track editor is `TrackSourceEditorView` (`[[code:Sources/UI/TrackSource/TrackSourceEditorView.swift:35]]`). Its top-level controls are the pattern-slot palette plus the `Source` / `Modifiers` segmented picker (`[[code:Sources/UI/TrackSource/TrackSourceEditorView.swift:154]]`). There is no fill-preview button, no local transport-affecting toggle, and no per-track playback override state in this view.

For clip-backed sources, the embedded clip editor already supports **authoring** both normal and fill note lanes. `ClipContentPreview` has a `ClipEditorLane` enum with `.main` and `.fill` and uses it to edit either `step.main` or `step.fill` (`[[code:Sources/UI/TrackSource/Clip/ClipContentPreview.swift:3]]`, `[[code:Sources/UI/TrackSource/Clip/ClipContentPreview.swift:36]]`, `[[code:Sources/UI/TrackSource/Clip/ClipContentPreview.swift:45]]`). Its summary text also distinguishes "Normal lane" from "Fill lane" (`[[code:Sources/UI/TrackSource/Clip/ClipContentPreview.swift:787]]`).

### Gap vs. the roadmap item

The track editor can edit fill content, but it cannot tell the engine "audition the fill lane for this track right now." The missing feature is not lane authoring; it is **playback-state control** inside the editor.

---

## 2. Fill Model And Phrase Ownership

### What exists

Fill is currently a built-in phrase layer, not an editor-local flag. `PhraseLayerDefinition.defaultSet(for:)` defines `"fill-flag"` as a boolean layer targeting `.macroRow("fill-flag")` (`[[code:Sources/Document/PhraseModel.swift:227]]`).

That layer resolves into `TrackPhrasePlaybackBuffer.fillEnabled: [Bool]` during phrase compilation (`[[code:Sources/Engine/PhrasePlaybackBuffer.swift:3]]`, `[[code:Sources/Engine/SequencerSnapshotCompiler.swift:291]]`). The compiler reads the `"fill-flag"` layer per track and per phrase step and emits a boolean array into the playback buffer (`[[code:Sources/Engine/SequencerSnapshotCompiler.swift:300]]`, `[[code:Sources/Engine/SequencerSnapshotCompiler.swift:343]]`).

### Consequence

Today, fill ownership lives with the selected phrase. The runtime receives an already-resolved `fillEnabled` boolean for each track step. There is no separate notion of "editor preview fill state" in the document or engine model.

---

## 3. Playback Path

### What exists

At tick time, `PlaybackSnapshot.resolvedStep` returns `ResolvedTrackPlaybackStep`, which includes the precompiled `fillEnabled` boolean (`[[code:Sources/Engine/PlaybackSnapshot.swift:55]]`, `[[code:Sources/Engine/PlaybackSnapshot.swift:82]]`). The per-phrase `LayerSnapshot` also carries fill-enabled tracks as a derived snapshot, not as an independently mutable live state (`[[code:Sources/Engine/PlaybackSnapshot.swift:90]]`, `[[code:Sources/Engine/LayerSnapshot.swift:3]]`).

For clip-backed sources, `EngineController` passes `resolved.fillEnabled` into `GeneratedSourceEvaluator.resolveClipStep(...)` (`[[code:Sources/Engine/EngineController.swift:1485]]`). `GeneratedSourceEvaluator` then prefers `step.fill` over `step.main` when fill is enabled and the fill lane fires by chance (`[[code:Sources/Document/GeneratedSourceEvaluator.swift:303]]`).

The behavior is covered by `test_fill_enabled_clip_step_prefers_fill_lane_over_main_lane` (`[[code:Tests/SequencerAITests/Engine/EngineControllerTests.swift:445]]`).

### Gap vs. the roadmap item

This path already answers "how does a clip play its fill lane?" but not "how do I temporarily force that behavior from the editor for one track?" There is no API in this path for a transient override such as `setLiveFill(trackID:)`.

---

## 4. Existing Live Controls Already Mutate Phrase Data

### What exists

The current live/performance surface is `LiveWorkspaceView` (`[[code:Sources/UI/LiveWorkspaceView.swift:3]]`). Its primary interaction path calls `session.setPhraseCell(...)` directly when the user taps a card (`[[code:Sources/UI/LiveWorkspaceView.swift:246]]`, `[[code:Sources/UI/LiveWorkspaceView.swift:253]]`).

`SequencerDocumentSession.setPhraseCell(...)` mutates the selected phrase in the store and publishes a snapshot update (`[[code:Sources/App/SequencerDocumentSession+Mutations.swift:465]]`). The underlying project mutation writes the phrase cell into the document model (`[[code:Sources/Document/Project+Phrases.swift:15]]`).

### Consequence for [[story:3]]

The only existing "toggle fill while running" interaction path is a **persistent phrase edit**, not a transient preview state. Reusing the existing live controls would violate [[story:3]] because it would alter authored phrase data instead of temporarily shadowing it.

---

## 5. Scope Constraints And Edge Cases

### Generator-backed tracks

The fill-aware playback branch is only wired for `.clip` sources in `EngineController` (`[[code:Sources/Engine/EngineController.swift:1485]]`). The generator branch does not receive `fillEnabled` (`[[code:Sources/Engine/EngineController.swift:1470]]`). That matches the assumption already captured in `user-stories.md`: generator-backed tracks currently have no fill-preview semantics.

### Per-track isolation

The compiled fill data is stored per track in `PhrasePlaybackBuffer.trackStates` and surfaced per track in `ResolvedTrackPlaybackStep` (`[[code:Sources/Engine/PhrasePlaybackBuffer.swift:10]]`, `[[code:Sources/Engine/PlaybackSnapshot.swift:55]]`). That means a future runtime override can stay track-scoped, but the current user-facing controls do not expose such an override in the editor.

### Reset-on-close behavior

`TrackSourceEditorView` holds local UI state for tabs and sheets only (`[[code:Sources/UI/TrackSource/TrackSourceEditorView.swift:41]]`). There is no lifecycle-owned fill-preview state to clear when the editor closes or the selected track changes, so [[story:2]] and the acceptance signal about auto-reset both require new state ownership.

---

## 6. Divergence Summary

| Story | Existing state | Gap |
|---|---|---|
| [[story:1]] Preview fill while editing | Fill lane authoring exists; playback can already choose fill for clips | No track-editor control that can force fill playback |
| [[story:2]] Clear active/inactive editor state | No editor-local fill state exists | Need visible local state and reset rules |
| [[story:3]] Preview is transient, not a phrase edit | Existing live interactions call `setPhraseCell(...)` and mutate the phrase | Need a runtime override path separate from phrase data |
| [[story:4]] Scope is the selected track only | Engine model already resolves fill per track | Need UI + runtime state that targets one track without affecting siblings |

## 7. Build-Relevant Conclusion

The smallest coherent implementation direction is:

- keep clip fill authoring exactly as-is;
- add a **runtime-only, track-scoped fill preview override** that shadows compiled `fillEnabled` for playback; and
- surface that override inside `TrackSourceEditorView`.

Without that runtime shadow state, the only available implementation route is phrase mutation, which conflicts directly with [[story:3]].
