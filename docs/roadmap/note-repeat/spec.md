---
feature: note-repeat
created: 2026-06-06
status: spec-ready-for-plan
sources:
  - docs/roadmap/note-repeat/architecture.md
  - docs/roadmap/note-repeat/open-questions.md
  - docs/roadmap/note-repeat/user-stories.md
  - docs/roadmap/note-repeat/existing-state.md
  - docs/roadmap/note-repeat/ux-review.md
---

# Note Repeat Spec

## Product Shape

Note Repeat v1 is a track-local live performance override. From the track
perform surface, the performer holds Repeat for a supported track. The engine
captures the resolved note output for the current quantized step, retriggers
that captured material at the track's configured interval, and returns to normal
transport-aligned playback when the performer releases Repeat.

Repeat is runtime state, not phrase authoring. Engaging or releasing Repeat
must not write phrase cells, clips, selected layers, scenes, or any other
document performance data.

## Accepted V1 Defaults

- Repeat is momentary press/hold; latch-on-tap is deferred.
- Clip-backed tracks are supported.
- Generator-backed tracks are disabled or unavailable.
- Capturing an empty step captures silence and schedules no retriggers.
- Interval changes apply on the next engagement, not while Repeat is active.
- Interval setup may remain outside perform mode in track layer settings.

## In Scope

- Track-local Repeat control on the perform surface for supported tracks.
- Engine commands equivalent to `engageNoteRepeat(trackID:)` and
  `releaseNoteRepeat(trackID:)`.
- Engine-owned active repeat runtime state keyed by track id.
- Current-step capture from resolved/prepared clip-backed output.
- Per-track repeat interval storage for `1/16`, `1/32`, and `1/64`.
- Intra-step repeat scheduling anchored to the existing 1/16 step callback.
- Release and lifecycle cleanup for active repeat state and pending output.
- Regression coverage for timing, persistence, capture, unsupported states, and
  stuck-note safety.

## Out Of Scope

- Latch or hybrid tap/hold behavior.
- Generator-backed repeat capture.
- Phrase-step, bar-level, or automated repeat interval changes.
- Mid-engagement interval changes.
- Global `TickClock` resolution changes.
- Detached UI timers for repeat scheduling.
- Phrase-cell authoring or capture-to-clip behavior.

## Acceptance Criteria

### Interaction

AC-I1: The track perform surface exposes a Repeat control per track where v1
Repeat is supported. The control is visually associated with its track and does
not depend on the currently selected phrase layer.

AC-I2: Pressing or holding Repeat for a supported clip-backed track sends an
engine command equivalent to `engageNoteRepeat(trackID:)` for that track.
Releasing the control sends `releaseNoteRepeat(trackID:)`.

AC-I3: Repeat active feedback identifies the repeating track and the interval
snapshot being used. If the UI displays captured-step feedback, it must reflect
the captured step index owned by engine runtime state, not a guessed UI value.

AC-I4: Engaging or releasing Repeat does not mutate phrase cells, selected
layer values, clips, scenes, track source data, or undo/redo history.

AC-I5: If multiple supported tracks can expose Repeat controls at the same
time, each active track repeats independently. Releasing one track does not
cancel active repeat state for another track.

### Current-Step Capture

AC-C1: Engage captures the resolved/prepared output for the current quantized
step at the point the engine applies the engage command.

AC-C2: Captured material reflects normal phrase and source evaluation for that
step, including fill/main lane selection, probability resolution, clip-backed
step content, velocity, gate length, and note length values already decided for
playback.

AC-C3: Repeated retriggers replay the captured material. They do not re-run
probability, search adjacent steps, pull stale rolling history, or capture
future generated output.

AC-C4: Engaging Repeat on an empty step captures silence. While active, the
engine schedules no note retriggers for that captured empty step, and release
still performs the normal cleanup path.

AC-C5: The captured step index and captured events are stored only in active
engine runtime state. They are not encoded into the document and are not
undoable.

### Engine Scheduling

AC-S1: Note Repeat scheduling is owned by the engine playback runtime and is
invoked from the existing step/tick playback path.

AC-S2: The main sequencer step cadence remains one callback per 1/16 step in
v1. Implementing Note Repeat must not require raising global `TickClock`
resolution.

AC-S3: Repeat intervals map to intra-step trigger counts on the 1/16 grid:
`1/16` schedules one trigger per step, `1/32` schedules two triggers per step,
and `1/64` schedules four triggers per step.

AC-S4: Sub-step repeat events are anchored to the current 1/16 step tick time.
They must not advance the main sequencer step counter between intra-step
retrigger events.

AC-S5: Repeat output is dispatched through the existing MIDI/audio/AU output
paths used by normal playback, with output-specific note-off or cleanup
tracking for scheduled repeated events.

AC-S6: UI commands enter the engine through the existing thread-safe command
queue or state-lock pattern. Playback callbacks read an engine-safe snapshot and
do not read SwiftUI view state directly.

### Interval Persistence

AC-P1: Each track has a stored repeat interval setting with exactly the v1
values `1/16`, `1/32`, and `1/64`.

AC-P2: Existing projects that do not encode the interval decode to `1/16`.

AC-P3: Encoded projects preserve the selected v1 interval value across save,
close, reopen, and normal document reload.

AC-P4: Changing the stored repeat interval marks the document dirty only as a
normal track/layer setting edit.

AC-P5: Engage snapshots the stored interval into active runtime state. Later
stored interval edits do not affect an already active repeat; they apply on the
next engagement.

AC-P6: Engage and release do not dirty the document if no stored interval or
other document setting changes.

### Release And Lifecycle Cleanup

AC-L1: Release cancels pending sub-step repeat events for the released track,
flushes pending MIDI note-offs created by repeat playback, performs equivalent
cleanup for audio/sample/AU output paths, and clears that track's active repeat
runtime state.

AC-L2: After release, the track resumes normal playback from the live transport
position. It does not jump back to the captured step and does not restart the
phrase, clip, scene, or transport.

AC-L3: Release is idempotent. Duplicate release commands for the same track do
not crash, leave stuck notes, or corrupt active state for other tracks.

AC-L4: Rapid re-engage for a track first performs the release cleanup contract
for any existing active repeat state, then captures according to the current
engine position and interval snapshot.

AC-L5: Transport stop, source change, owning track deletion, project close, and
playback session rebuild all run the same cleanup contract for affected active
repeat state.

AC-L6: Cleanup can run safely while playback is stopped, while a repeat event is
pending inside the current step, and while the active track has already become
invalid.

### Unsupported States

AC-U1: Generator-backed tracks do not allow active Note Repeat in v1. Their
Repeat control is disabled, unavailable, or suppressed with a clear inactive
state.

AC-U2: Attempting to engage Repeat for an unsupported source through command
ingress is a safe no-op that does not create active repeat state, dirty the
document, or crash.

AC-U3: If a track becomes unsupported while Repeat is active, the engine runs
the release cleanup contract for that track and leaves the UI inactive.

AC-U4: Missing, removed, or invalid stored interval values decode or recover to
the v1 default `1/16` without blocking project load.

### Safety Regressions

AC-R1: Releasing Repeat during a step leaves no stuck MIDI notes and no repeated
audio/sample/AU events scheduled after release.

AC-R2: Releasing Repeat at a step boundary neither doubles the normal step
output nor drops unrelated tracks' output.

AC-R3: Rapid release and re-engage inside the same step cannot produce doubled
notes from stale scheduled repeat events.

AC-R4: Transport stop while Repeat is active clears active state and pending
repeat output for every active track.

AC-R5: Deleting a track or changing its source while Repeat is active clears
only affected repeat state and does not crash playback.

AC-R6: Project close or playback session rebuild while Repeat is active leaves
no retained runtime state that affects the next session.

AC-R7: Normal playback behavior for tracks without active Repeat is unchanged,
including phrase advancement, fill/main lane evaluation, probability resolution,
and output timing.

AC-R8: The accepted v1 feature does not change global sequencer step indexing
or `TickClock` semantics for existing tests and playback paths.

## Required Build Evidence

A future build loop should provide evidence for:

- UI interaction tests or visual evidence for supported, active, released, and
  unsupported perform-surface states.
- Engine unit or integration tests for engage/release command handling,
  current-step capture, interval snapshotting, and independent per-track active
  state.
- Scheduler tests or equivalent deterministic timing evidence for `1/16`,
  `1/32`, and `1/64` trigger counts without main step-counter advancement.
- Persistence tests for default decode, save/reload, document dirty behavior,
  and interval snapshot semantics.
- Lifecycle and safety regression tests covering release inside a step, release
  at a boundary, rapid re-engage, transport stop, track deletion/source change,
  project close/session rebuild, and no stuck notes.

## Readiness

This spec is ready to feed a PM `plan.md` pass. It is not an implementation
handoff and does not promote Note Repeat to a build loop by itself.
