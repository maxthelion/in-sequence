---
feature: note-repeat
created: 2026-06-06
status: ready-for-implementation-handoff
sources:
  - README.md
  - docs/roadmap/note-repeat/spec.md
  - docs/roadmap/note-repeat/architecture.md
  - docs/roadmap/note-repeat/open-questions.md
  - docs/roadmap/note-repeat/user-stories.md
  - docs/roadmap/note-repeat/existing-state.md
  - docs/roadmap/note-repeat/ux-review.md
next_artifact: docs/roadmap/note-repeat/implementation-handoff.md
---

# Note Repeat Implementation Plan

## Purpose

This plan translates the accepted Note Repeat v1 architecture and spec into a
builder-facing implementation sequence. The feature is a track-local live
performance override: the performer holds Repeat from the perform surface, the
engine captures the current quantized step's resolved clip-backed output,
replays that captured material at the track's stored interval, and releases
back to normal transport-aligned playback without mutating phrase or document
performance state.

The plan is intentionally engine-first. Builders should prove command ingress,
runtime state, current-step capture, intra-step scheduling, and cleanup safety
before treating the perform-surface control as complete.

This plan does not promote a build loop and does not replace a later
`implementation-handoff.md`.

## Settled V1 Contract

Builders should preserve these accepted decisions from architecture and spec:

- Repeat is momentary press/hold in v1; latch and hybrid tap/hold behavior are
  deferred.
- Repeat active state is engine playback runtime state, not phrase, clip,
  scene, track source, undoable, redoable, or persisted document state.
- UI sends command-shaped ingress equivalent to
  `engageNoteRepeat(trackID:)` and `releaseNoteRepeat(trackID:)`.
- Commands cross into the engine through the existing thread-safe command queue
  or state-lock pattern.
- Engage captures the resolved/prepared output for the current quantized step
  when the engine applies the command.
- Captured material reflects already-decided clip-backed playback, including
  fill/main lane selection, probability resolution, velocity, gate length, and
  note length.
- Repeats replay captured material and do not re-roll probability, search
  nearby steps, or pull stale rolling history.
- Empty-step capture captures silence and schedules no retriggers.
- Intervals are stored per track with exactly `1/16`, `1/32`, and `1/64`;
  missing or invalid persisted values recover to `1/16`.
- Engage snapshots the stored interval; stored interval edits apply on the next
  engagement, not mid-repeat.
- Main sequencer cadence remains one callback per 1/16 step. Note Repeat must
  not raise global `TickClock` resolution in v1.
- Intra-step repeat scheduling is engine-owned and anchored to the current
  1/16 step tick.
- Clip-backed tracks are supported. Generator-backed or otherwise unsupported
  tracks are disabled or unavailable and command ingress for them is a safe
  no-op.
- Release, rapid re-engage, transport stop, source change, track deletion,
  project close, and playback session rebuild all use the same idempotent
  cleanup contract.

## Implementation Sequence

### 1. Reconfirm Current Seams And Build A Narrow Test Harness

Before editing broadly, verify the current code still matches the accepted
`existing-state.md` map:

- `TracksMatrixView` and `TrackMatrixCard` own the tracks perform page.
- Fill is phrase-authored through the `"fill-flag"` layer and is not a runtime
  precedent for Repeat state.
- `EngineController.prepareTick`, `resolvedStepNotes`, `Executor.tick`, and
  `dispatchTick` form the normal step playback and output path.
- `TickClock` still fires once per 1/16 step.
- `RollingCaptureBuffer` remains history/capture-to-clip precedent only, not a
  proven current-step exact Repeat source.
- `MidiOut.flushPendingNoteOffs(now:)` and engine-level flush paths are still
  available for stuck-note cleanup.
- `StepSequenceTrack` remains the likely persisted home for a per-track repeat
  interval setting.

Create the smallest focused engine test harness needed to drive a track through
engage, one or more ticks, release, and cleanup without relying on SwiftUI. If
existing seams make this difficult, introduce narrowly scoped test helpers near
the playback runtime rather than testing timing through the full app surface
first.

Exit evidence:

- A short switch/seam audit in the build evidence naming any integration points
  that moved since `existing-state.md`.
- Initial focused tests that can submit repeat commands and observe runtime
  state or scheduled repeat output deterministically.

### 2. Add Interval Model And Persistence

Add the v1 repeat interval as a stable per-track setting.

Work:

- Define an enum-like `NoteRepeatInterval` with values for `1/16`, `1/32`,
  and `1/64`.
- Persist the interval on the track or established per-track layer settings
  model selected by the build architecture.
- Decode older documents with missing values as `1/16`.
- Recover missing, removed, or invalid encoded values to `1/16` without
  blocking project load.
- Mark the document dirty only when the stored setting changes.
- Ensure engage and release commands do not dirty the document by themselves.

Verification:

- Codable round-trip for all three v1 values.
- Old-project decode with no interval field.
- Invalid or unknown value recovery to `1/16`.
- Dirty-state tests proving stored interval edits dirty normally, while
  engage/release without a stored setting edit do not.

### 3. Introduce Engine-Owned Repeat Runtime And Command Ingress

Add runtime-only active repeat state owned by the playback session /
`EngineController` equivalent and keyed by track id.

The state should remain equivalent to:

```swift
struct ActiveNoteRepeat {
    var trackID: TrackID
    var capturedStepIndex: Int
    var capturedEvents: [GeneratedNote]
    var interval: NoteRepeatInterval
    var startedAtTickIndex: Int
    var scheduledRepeatEvents: [ScheduledRepeatEvent]
}
```

Local type names may differ, but the ownership contract is binding.

Work:

- Add command APIs equivalent to `engageNoteRepeat(trackID:)` and
  `releaseNoteRepeat(trackID:)`.
- Route SwiftUI/view-model commands through the existing command queue or
  state-lock pattern.
- Ensure playback callbacks read an engine-safe snapshot and never consult
  SwiftUI view state.
- Key active state per track so multiple tracks can repeat independently if
  the UI exposes multiple supported controls.
- Make unsupported, missing, deleted, or invalid track commands safe no-ops.
- Make release idempotent for inactive tracks.

Verification:

- Command tests for engage, release, duplicate release, invalid track, and
  unsupported source.
- Runtime isolation tests proving active state for one track does not cancel or
  corrupt another active track.
- Non-mutation tests proving active runtime state is not persisted, undoable,
  redoable, or written into phrase/clip/scene data.

### 4. Implement Current-Step Capture

Capture from the resolved/prepared output for the current quantized step at the
engine command application point.

Work:

- Hook capture after phrase and source evaluation have resolved the current
  step, including fill/main lane choice and probability decisions.
- Capture clip-backed note material with the values normal playback would use:
  pitch, velocity, gate length, note length, and any local event fields already
  represented by the playback note type.
- Store the captured step index and captured events only in active runtime
  state.
- Capture empty steps as silence, with an active repeat state that schedules no
  note retriggers.
- Avoid using the rolling history buffer as the primary source unless the build
  proves it is current-step exact and cleanup-safe.

Verification:

- Tests for capture on a populated clip step.
- Tests proving fill/main lane choice and probability are captured once and not
  re-evaluated per retrigger.
- Empty-step capture test proving no retriggers are scheduled and release still
  cleans up normally.
- Regression test proving engage does not search adjacent steps, capture future
  generated output, or read stale rolling history.

### 5. Add Intra-Step Repeat Scheduling Without TickClock Resolution Changes

Add an engine-owned scheduler invoked from the existing step/tick playback
path. Keep the main sequencer step counter and `TickClock` semantics unchanged.

Work:

- On each 1/16 step callback, read active repeat state and schedule repeat
  events anchored to that step's tick time.
- Map intervals to v1 trigger counts on the 1/16 grid:
  - `1/16`: one trigger per step;
  - `1/32`: two triggers per step;
  - `1/64`: four triggers per step.
- Dispatch repeat output through the same MIDI/audio/AU paths normal playback
  uses.
- Record scheduled repeat events and output cleanup obligations by track.
- Do not advance the main step counter for intra-step retriggers.
- Do not introduce detached SwiftUI timers or globally increase
  `TickClock` resolution for v1.

Verification:

- Deterministic scheduler tests for `1/16`, `1/32`, and `1/64` trigger counts.
- Timing evidence that sub-step events are anchored to the current step tick.
- Regression tests proving the main step counter advances once per 1/16 step
  and unrelated non-repeat tracks keep normal output timing.
- Existing `TickClock` and step-indexing tests still pass without semantic
  changes.

### 6. Implement Release, Rapid Re-Engage, And Lifecycle Cleanup

Centralize cleanup in one idempotent contract and call it from every release or
invalidation path.

Cleanup must:

- cancel pending sub-step repeat events for affected tracks;
- flush pending MIDI note-offs created by repeated notes;
- perform equivalent cleanup for audio, sample, and AU output paths;
- clear active repeat runtime state;
- resume normal playback from the live transport position.

Call the same cleanup contract for:

- explicit release;
- rapid re-engage before the new capture;
- transport stop;
- source change away from supported clip-backed output;
- owning track deletion;
- project close;
- playback session rebuild.

Verification:

- Release-inside-step test with no stuck notes and no post-release repeat
  events.
- Release-at-step-boundary test proving no doubled normal output and no dropped
  unrelated track output.
- Rapid release/re-engage test proving stale scheduled events do not double the
  new capture.
- Transport-stop test clearing active state and pending repeat output for all
  active tracks.
- Track deletion/source-change tests clearing only affected repeat state.
- Project close/session rebuild tests proving no retained runtime state affects
  the next session.

### 7. Wire Unsupported-State Semantics

Make unsupported behavior explicit in both engine and UI before final polish.

Work:

- Detect v1-supported clip-backed tracks at the same domain seam the engine
  uses for capture.
- Treat generator-backed tracks and other unsupported sources as unavailable in
  v1.
- Ensure command ingress for unsupported sources is a safe no-op.
- If a track becomes unsupported while Repeat is active, run cleanup and leave
  the UI inactive.
- Decode missing or invalid interval storage to the default before UI or engine
  code reads it.

Verification:

- Engine tests for unsupported engage no-op, no document dirtiness, and no
  active runtime state.
- Source-change tests from supported to unsupported while active.
- UI/view-model evidence for disabled, unavailable, or suppressed Repeat
  controls on unsupported tracks with a clear inactive state.

### 8. Build The Perform Surface And Interval Setting UI

Wire the user-facing controls after the runtime contract is testable.

Perform surface:

- Add a Repeat control per supported track on the tracks perform surface,
  visually associated with the track and independent of the currently selected
  phrase layer.
- Use momentary press/hold semantics in v1: press sends engage, release sends
  release.
- Show active feedback for the repeating track and the interval snapshot.
- If captured-step feedback is shown, source it from engine runtime state, not
  a guessed UI step value.
- Keep unsupported source controls disabled, unavailable, or suppressed with a
  clear inactive state.

Interval setting:

- Expose the stored `1/16`, `1/32`, and `1/64` repeat interval in the accepted
  track layer settings area.
- Preserve the accepted v1 rule that interval edits apply on the next Repeat
  engagement.
- Do not add phrase-step automation or mid-engagement interval changes.

Verification:

- UI/view-model tests or manual evidence for supported inactive, active,
  released, and unsupported perform states.
- Evidence that Repeat controls are track-local and not tied to the selected
  phrase layer.
- Evidence that interval setup persists and reloads, and that changing it while
  active does not alter the current runtime snapshot.
- Visual evidence against `prototypes/perform-page-toggle.html` and
  `prototypes/layer-interval-and-substep.html` for the built surface, not only
  prototype screenshots.

### 9. Run Safety And Non-Regression Review

Before declaring the build complete, review the full feature against the spec's
safety and non-mutation criteria.

Required review evidence:

- Engage/release does not mutate phrase cells, selected layer values, clips,
  scenes, track source data, undo/redo history, or persisted project data.
- Normal playback for tracks without active Repeat is unchanged, including
  phrase advancement, fill/main lane evaluation, probability resolution, and
  output timing.
- Multi-track active repeat state is independent where multiple supported
  tracks can be active.
- Sub-step scheduling does not change global `TickClock` resolution or normal
  step indexing.
- No stuck notes or retained scheduled events remain after every cleanup path.

## Verification Sequence

Run verification in this order:

1. Model and persistence tests for interval decode, encode, dirty-state, and
   snapshot semantics.
2. Engine command and runtime-state tests for engage, release, duplicate
   release, unsupported source, invalid track, and multi-track independence.
3. Current-step capture tests for resolved clip-backed output, fill/probability
   capture, empty-step silence, and no stale/future capture source.
4. Scheduler tests proving `1/16`, `1/32`, and `1/64` trigger counts inside one
   1/16 step without main step-counter advancement.
5. Cleanup and safety tests for release inside a step, release at a boundary,
   rapid re-engage, transport stop, track deletion, source change, project
   close, session rebuild, and no stuck notes.
6. UI/view-model tests for perform-surface inactive, active, released,
   unsupported, and interval-setting states.
7. Full project test command normally used by the build loop.
8. Manual or visual evidence of the actual built perform surface and interval
   setting UI.

If the full suite is too slow or blocked in the build worktree, the builder
should record the blocker and still provide the focused engine, persistence,
cleanup, and built-surface evidence that did run.

## Handoff Risks

- Sub-step scheduling is the largest implementation risk. The accepted v1
  plan avoids global `TickClock` resolution changes, so review must verify no
  hidden broad sequencer rewrite landed.
- Current-step capture must be exact at the engine command application point.
  A stale rolling-history capture would miss the product contract.
- Thread discipline matters: SwiftUI state must not be read from playback
  callbacks.
- Release and lifecycle cleanup need one shared contract. Separate ad hoc
  cleanup paths are likely to leave stuck notes or retained scheduled events.
- Empty-step capture should be silent but still active enough to release
  cleanly. Treating it as a failed engage can create ambiguous UI and cleanup
  behavior.
- Interval persistence is document state, but active Repeat state is not.
  Mixing those concerns would create dirty-state, undo, or restore bugs.
- Generator-backed tracks must be explicitly unavailable in v1. Silent partial
  support would make capture semantics unclear.
- The perform-surface prototype implies a Fill-adjacent control, but existing
  Fill is phrase-authored today. Builders should not copy Fill's phrase-cell
  mutation path for Repeat.

## Out Of Scope For This Build

- Latch, hybrid tap/hold, or automatable Repeat behavior.
- Generator-backed repeat capture.
- Phrase-step, bar-level, or scene-level repeat interval automation.
- Mid-engagement interval changes.
- Global `TickClock` resolution changes.
- Detached UI timers for repeat scheduling.
- Phrase-cell authoring, capture-to-clip, or undoable Repeat state.
- Broad redesign of the perform page beyond the controls needed for v1 Repeat.
- Authoring `implementation-handoff.md`; that remains the next PM artifact.

## Promotion Dependency

This plan closes the bounded implementation-sequence gap. The PM lane still
needs accepted `implementation-handoff.md` before it is ready for build-loop
promotion.
