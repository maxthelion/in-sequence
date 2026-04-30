# Note Repeat — Existing State

## Summary

Note Repeat has zero existing implementation. No toggle, no per-track repeat state, no sub-step scheduling primitive. The findings below map the architecture a build loop must extend.

---

## 1. Perform Page UI

### What exists

The tracks perform page is `TracksMatrixView` (`Sources/UI/TracksMatrixView.swift`). It has a `TracksWorkspaceMode` enum with `.edit` and `.perform` cases. In perform mode, tapping a `TrackMatrixCard` calls `performPrimaryAction(trackID:)` which **cycles the current layer's phrase-cell value** for that track at the live transport position.

There is no per-track momentary toggle row. There is no Fill button on the perform page; fill is a phrase-layer value (`"fill-flag"` boolean layer, `PhraseLayerTarget.macroRow("fill-flag")`). To see the fill layer, a performer selects the "Fill" layer in the layer picker on `TracksMatrixView` and then taps track cards to cycle the boolean on/off.

The Scenes perform page (`ScenesWorkspaceView+Perform.swift`) is for scene A/B crossfading and macro knobs — it is unrelated to per-track fill or repeat.

### Gap vs. user story 1

There is no dedicated per-track button strip alongside a Fill toggle. A Note Repeat toggle needs a new UI component: a persistent button row that appears on the perform page (either on `TracksMatrixView` or on a new perform-specific panel) showing both a Fill button and a Note Repeat button per track, operable independently of which phrase layer is currently selected.

---

## 2. Fill — How It Actually Works Today

### Model

Fill is a built-in `PhraseLayerDefinition` with `id = "fill-flag"`, `valueType = .boolean`, and `target = .macroRow("fill-flag")` (`Sources/Document/PhraseModel.swift`, line 239). Each track's per-step fill state lives in the phrase grid, compiled into `PhrasePlaybackBuffer.TrackPhrasePlaybackBuffer.fillEnabled: [Bool]` (`Sources/Engine/PhrasePlaybackBuffer.swift`, line 6). At tick time, `PlaybackSnapshot.resolvedStep` reads the precompiled `fillEnabled[normalizedIndex]` and passes it into `GeneratedSourceEvaluator.resolveClipStep(for:stepIndex:fillEnabled:rng:)` (`Sources/Document/GeneratedSourceEvaluator.swift`, line 303).

### Engine use of fillEnabled

`resolveClipStep` uses `fillEnabled` to choose between a clip step's `.fill` lane and its `.main` lane (`Sources/Document/GeneratedSourceEvaluator.swift`, lines 315–320). If fill is enabled and the clip step has a fill lane that fires by chance, the fill lane's notes are used instead of the main lane.

Fill for generator-backed sources is **not** applied at all: `resolvedStepNotes` in `EngineController` only passes `resolved.fillEnabled` into the clip branch, not the generator branch (`Sources/Engine/EngineController.swift`, line 1493). Generator steps ignore fill.

### No live/runtime fill override

There is no `setLiveFill(trackID:)` or equivalent. The only way to activate fill for a track today is to author the `"fill-flag"` boolean layer in the phrase. There is no mechanism to override fill at runtime without writing a phrase-cell mutation. The `MasterBusPerformanceOverlayState` handles scene-level macro overrides but nothing track-level runtime.

**This means the perform-page "fill toggle" described in the notes does not exist yet.** Fill is purely a phrase-authored value, not a live momentary control.

---

## 3. Clock and Intra-Step Scheduling

### TickClock resolution

`TickClock` fires one tick per sequencer step (`Sources/Engine/TickClock.swift`). The interval is:

```
seconds = 60.0 / bpm / stepsPerBar * beatsPerBar
```

With `stepsPerBar = 16` and `beatsPerBar = 4`, each tick equals one 1/16th note. The clock fires `DispatchSourceTimer` callbacks at that fixed interval. **There is no subdivision within a tick.**

### Executor tick resolution

`Executor.tick(now:preparedNotesByBlockID:)` is called once per `TickClock` tick (`Sources/Engine/Executor.swift`). Each call processes one step. `NoteGenerator.tick(context:)` reads `context.tickIndex % stepPattern.count` to determine the current step, and `MidiOut.tick(context:)` schedules note-offs at `context.tickIndex + event.length` — both operate at step granularity.

### Conclusion on sub-step scheduling

**Sub-step scheduling does not exist.** There is no mechanism to fire multiple note events within a single clock tick, no fractional tick index, no secondary timer, and no subdivision queue. Implementing repeat/32 or repeat/64 (which would need to fire 2 or 4 retriggers respectively within a single 1/16 step) requires one of:

- Running `TickClock` at a higher resolution (e.g. 64 steps per bar), with the main sequencer advancing every N ticks. This is the lowest-friction approach but changes `EngineController`'s existing 1-tick = 1-step invariant everywhere.
- Adding a secondary intra-step timer that fires independently of `TickClock` only when a track has sub-step note repeat active.
- Changing `Executor.tick` to accept a subdivision parameter and dispatching multiple note events from within a single clock tick.

None of these approaches are present. This is the key architecture risk identified in the user stories.

---

## 4. Per-Layer Config Storage

### What exists

`StepSequenceTrack` stores no repeat-interval field (`Sources/Document/StepSequenceTrack.swift`). The model has `pitches`, `stepPattern`, `stepAccents`, `velocity`, `gateLength`, `macros`, and `filter` — no repeat-related property.

`PhraseLayerDefinition.defaultSet` does not include a "repeat-interval" layer.

### Gap vs. user story 3

A `repeatInterval` property (or equivalent per-layer config) needs to be added to `StepSequenceTrack` or to a new per-track layer structure. The simplest model is an enum stored on `StepSequenceTrack`: `.off`, `.sixteenth`, `.thirtySecond`, `.sixtyFourth`. The phrase-layer system (`PhraseLayerDefinition`) could also model this as a new indexed-choice layer if per-bar or per-step variation is desired, but the user story specifies "layer settings" which aligns with a single per-track value, not a per-step grid.

The built-in phrase layer at `id = "fill-flag"` serves as a direct design analogy: a boolean layer toggled per-track-per-step. A repeat-interval value could be a scalar or index layer similarly.

---

## 5. Note Capture and Note-Out Path

### Capture mechanism

`EngineController.RollingCaptureBuffer` accumulates per-track generated notes step by step (`Sources/Engine/EngineController.swift`, lines 12–67). It stores the most recent 64 steps of `GeneratedNote` values. This is used for the "capture to clip" feature, not for live repeat. However, it is the closest analogue to "capturing the step at engage time."

### Note-out path

The tick path for note output is:
1. `EngineController.prepareTick` calls `resolvedStepNotes` per track.
2. Results are placed in `preparedNotesByBlockID`.
3. `Executor.tick` is called; each `NoteGenerator.tick` returns the prepared notes.
4. Outputs flow to `MidiOut.tick` or to the audio sample/AU dispatch in `EngineController.dispatchTick`.

A note-repeat hook would need to intercept step 1 or 2: when note repeat is active for a track, replace the call to `resolvedStepNotes` with a return of the captured step's notes, and issue them at the appropriate sub-step intervals.

### Stuck-note safety

`MidiOut.flushPendingNoteOffs(now:)` and `flushAllPendingMIDINoteOffs(now:)` exist (`Sources/Engine/Blocks/MidiOut.swift`, line 90; `Sources/Engine/EngineController.swift`, line 1545). These must be called on repeat disengage to prevent stuck notes. The audio path (`TrackPlaybackSink`) also needs equivalent handling.

---

## 6. Architecture Constraints

- `TickClock` fires at 1-tick-per-step. **Sub-step intervals cannot be implemented without either changing this resolution or adding a parallel timer.**
- `EngineController.prepareTick` and `dispatchTick` run on the clock callback queue (not main thread). Live state toggled from the UI (main thread) must be passed through a thread-safe mechanism — the existing `CommandQueue` or `withStateLock` pattern.
- Fill state is compiled into `PhrasePlaybackBuffer` ahead of time and is not a runtime observable flag. A note-repeat "active" flag by contrast needs to be a live runtime value not compiled from the phrase, because it is toggled momentarily during playback.
- `StepSequenceTrack` is `Codable`. Adding a `repeatInterval` field requires a `decodeIfPresent` migration path (the same pattern used for `macros` and `filter`).

---

## 7. Relevant Tests

- `TickClockTests` (`Tests/.../Engine/TickClockTests.swift`) — covers interval accuracy and BPM changes; has no sub-step or fill-related coverage.
- `GeneratedSourceEvaluatorTests` — tests `resolveClipStep` with `fillEnabled: true/false` (line 203 and lines 223, 252, 258).
- `SequencerSnapshotCompilerSemanticsTests` — compiles fill layer into `PhrasePlaybackBuffer`; confirms the `"fill-flag"` layer target.
- No tests exist for: live fill runtime override, note capture on engage, sub-step scheduling, repeat-interval persistence.

---

## 8. Divergence Summary

| Story | Gap |
|-------|-----|
| 1 — Note Repeat toggle on perform page | No per-track toggle strip on TracksMatrixView; fill itself is not a runtime toggle |
| 2 — Capture step and loop until released | `RollingCaptureBuffer` exists but is not wired to any live-repeat path; no engage/disengage API |
| 3 — Per-layer repeat interval config | No `repeatInterval` field on `StepSequenceTrack`; no phrase layer or UI for it |
| 4 — Sub-step intervals within a step | No intra-step scheduling; `TickClock` fires at 1/16 only; fundamental engine change required |

The sub-step scheduling gap (story 4) is the highest-risk item and should be the first open architecture question resolved in the spec.
