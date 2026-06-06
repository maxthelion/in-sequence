---
feature: note-repeat
created: 2026-06-06
status: accepted-builder-facing
sources:
  - docs/roadmap/note-repeat/open-questions.md
  - docs/roadmap/note-repeat/existing-state.md
  - docs/roadmap/note-repeat/user-stories.md
  - docs/roadmap/note-repeat/ux-review.md
---

# Note Repeat Accepted Architecture

This is accepted PM architecture for the next spec pass. It fixes the
builder-facing direction for timing, state ownership, capture, safety,
persistence, source scope, and v1 product defaults without making the lane ready
for build promotion yet.

Spec, plan, handoff, and build-loop promotion remain downstream artifacts.

## V1 Shape

Note Repeat v1 should be a live, track-local runtime override:

1. The performer engages Repeat on a track from the perform surface.
2. The engine captures the current quantized step's resolved note output.
3. The engine retriggers that captured material at the track's configured
   interval.
4. The performer releases Repeat.
5. The engine cancels repeat scheduling, flushes repeated notes safely, and
   rejoins normal playback at the live transport position.

The feature must not be implemented as phrase-cell authoring. It is a temporary
performance modification that can be discarded by release, transport stop, or
runtime lifecycle cleanup.

Accepted v1 product defaults:

- Repeat is momentary press/hold; latch is deferred.
- Clip-backed tracks are the supported source scope.
- Generator-backed tracks show an unavailable/disabled Repeat state in v1.
- Capturing an empty step captures silence and schedules no retriggers.
- Interval changes apply to the next engagement, not the active repeat.
- Interval setup may remain in track layer settings outside perform mode.

## UI To Engine Command Flow

The perform UI should send command-shaped repeat actions for a track. It should
not bind the active Repeat button directly to document storage or phrase layer
state.

Accepted command contract:

- `engageNoteRepeat(trackID:)` captures the current quantized step and starts
  repeat scheduling for that track;
- `releaseNoteRepeat(trackID:)` stops repeat scheduling and clears active
  runtime state for that track;
- any future latch/toggle behavior should be view-model policy on top of those
  same engage/release commands.

Commands from SwiftUI must cross into the engine through the existing
thread-safe command queue or state-lock pattern. Playback callbacks must read
an engine-safe snapshot, not SwiftUI state.

The spec should treat `engageNoteRepeat(trackID:)` and
`releaseNoteRepeat(trackID:)` as the accepted command boundary. Direct mutation
of document phrase/layer data from the perform button is out of scope.

## Runtime State

Active repeat state belongs to the playback session / engine runtime layer,
outside the document model. The state owner is the engine playback runtime, with
`EngineController` or its existing playback-session equivalent responsible for
receiving UI commands, creating/clearing active state, and exposing only
engine-safe snapshots to playback callbacks.

The state shape should be equivalent to:

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

The implementation may use local naming and output event types, but the
contract is binding:

- active repeat state is not persisted;
- active repeat state is not undoable or redoable;
- engaging or releasing Repeat does not mark the document dirty by itself;
- each active track owns its own captured material and scheduled repeat events;
- state clears when the track/source/transport/session lifecycle invalidates it.

## Capture Point

Capture should happen from the current step's resolved/prepared playback output,
after normal phrase and source evaluation have already decided what notes would
play, and before repeat scheduling reuses that material.

For clip-backed tracks, that means captured material reflects the actual main
or fill lane output, probabilities already resolved for that step, and the
current transport position. Repeats must replay the captured output, not
re-roll probability on every retrigger.

The rolling capture buffer is precedent but should not be assumed to be the
primary Note Repeat source unless a later architecture pass proves it is
current-step exact and release-safe.

The accepted capture contract is current-step exact: engaging Repeat captures
the resolved output for the quantized step active at the engage command's engine
application point. It does not search adjacent steps, pull stale history, or
capture future generated material.

## Sub-Step Scheduling

The accepted v1 scheduling direction is to preserve the existing main
`TickClock` step cadence and add repeat-specific intra-step event scheduling
owned by the engine playback runtime.

The main sequencer should continue to advance once per 1/16 step. When Repeat
is active, the engine schedules captured note events inside the current step at
the selected interval:

| Interval | Relative behavior on a 1/16 grid |
| --- | --- |
| 1/16 | one trigger per step |
| 1/32 | two triggers per step |
| 1/64 | four triggers per step |

This direction intentionally avoids raising global clock resolution for v1.
Global high-resolution ticks would require auditing every step-indexed playback
path and could turn Note Repeat into a broad sequencer rewrite.

The concrete scheduler hook for spec is an engine-owned repeat scheduler invoked
from the existing step/tick playback path. On each 1/16 step callback, the
scheduler reads active repeat state, creates repeat events at offsets anchored
to that step's tick time, dispatches them through the existing note/audio output
paths, and records any pending note-off or cleanup work by track. The scheduler
may be implemented as an `EngineController` helper or another local playback
runtime primitive, but it must not be a detached UI timer and must not change
the global `TickClock` resolution in v1.

## Release And Safety

Release must be explicit and conservative:

- cancel pending sub-step events for the released track;
- flush pending MIDI note-offs created by repeated notes;
- perform equivalent cleanup for audio/sample/AU dispatch paths;
- clear active repeat runtime state;
- resume normal playback from the live transport position.

Rapid re-engage must run the same cleanup before capturing again. Lifecycle
cleanup uses the same release contract when transport stops, the source changes,
the owning track is deleted, the project closes, or the playback session is
rebuilt. Cleanup must be idempotent so duplicate release/lifecycle calls cannot
leave stuck notes or crash.

The spec must include regression coverage for stuck notes, doubled notes,
release within a step, release at a step boundary, rapid re-engage, transport
stop while Repeat is active, track deletion/source change while active, and
project/session close while active.

## Interval Storage

The track's repeat interval should be a stable per-track layer setting for v1.

Use an enum-like document value with exactly the accepted initial divisions:

- `1/16`;
- `1/32`;
- `1/64`.

Existing projects must decode with a default value, recommended as `1/16`.
The active interval should be snapshotted when Repeat engages. Stored interval
changes then apply to the next engagement unless a product decision explicitly
requires live interval changes while repeating.

Do not add phrase-step interval automation in v1 unless product direction
changes. The current accepted evidence supports setup in track layer settings,
not live per-step repeat-rate authoring.

The accepted persistence contract is: a missing stored interval decodes to
`1/16`, encoded projects preserve only the enum-like v1 values, and changing
the stored interval marks the document dirty only as a normal layer-setting
edit, not as a perform-button engage/release side effect.

## Source Scope

Initial v1 supports clip-backed track output first.

Generator-backed tracks should be disabled or unavailable for Note Repeat until
generator capture semantics are intentionally designed. This keeps v1 aligned
with existing Fill precedent and avoids pretending that generator output has
the same deterministic step material as clips.

If later product direction requires generator support in v1, architecture must
define whether Repeat captures the generator's already-prepared output, a
stable seed/result pair, or another explicit generated-event representation.

## Product Defaults Accepted

The architecture accepts the conservative defaults from
`open-questions.md` for v1:

- Repeat is momentary press/hold in v1; latch is deferred.
- Generator-backed tracks are disabled in v1.
- Empty-step capture captures silence and does not snap to another step.
- Interval changes apply on next engagement, not mid-repeat.
- Interval setup may remain outside perform mode for v1.

No product-owner lock is required before spec unless a later PM pass changes
one of these defaults.

## Builder-Readiness Status

This accepted architecture does not make the lane builder-ready.

Before build-loop promotion, the lane still needs:

- `spec.md` with interaction, scheduling, persistence, lifecycle, and safety
  acceptance criteria;
- `plan.md`;
- `implementation-handoff.md`.
