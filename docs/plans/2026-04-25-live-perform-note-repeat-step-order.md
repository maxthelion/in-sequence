# Live Perform Note Repeat and Step Order Overlays

**Status:** Proposed. Plan-only branch `codex/live-perform-performance-mechanics-plan`.

## Summary

Implement note repeat and step-order as runtime performance overlays. They sit on top of compiled phrase playback, affect the next prepared tick, and do not mutate `PhraseModel`, `LiveSequencerStore`, clips, pattern banks, or snapshot contents.

Both mechanics operate at the source-note lookup layer:

- phrase position continues normally;
- pattern slot selection continues normally except where note repeat intentionally repeats a captured source clip;
- mute, phrase macro curves, destination routing, and base fill progression continue normally;
- clip note/slice lookup can be transformed at runtime.

This plan assumes the fill overlay branch has either been merged first or its runtime overlay foundation is ported before implementation.

## Goals

- Add note repeat that can hold or latch selected tracks into repeating the currently heard clip source step.
- Add step-order modes that transform selected tracks' clip source step index without editing the phrase or clip.
- Share the same target-selection and clear-live-mods behavior as Fill.
- Keep every performance overlay outside persistence and snapshot compilation.
- Make overlay changes immediate by invalidating prepared tick output without replacing the playback snapshot.

## Non-Goals

- No capture/recording of overlay output into authored material.
- No sub-step ratchet scheduler in V1. V1 note repeat retriggers on sequencer step ticks. Faster ratchets require a separate subdivision scheduler.
- No generator-source note repeat in V1. If a targeted track resolves to a generator source, note repeat is a no-op for that track.
- No phrase or clip step-order authoring UI in V1.

## Shared Runtime Model

Extend `PerformanceOverlayState` rather than adding phrase cells or store fields.

Suggested additions:

```swift
struct PerformanceOverlayState: Equatable, Sendable {
    var fillTrackIDs: Set<UUID>
    var allTracksFill: Bool
    var noteRepeat: PerformanceNoteRepeatState
    var stepOrderByTrackID: [UUID: PerformanceStepOrderMode]

    var isActive: Bool
    func isFillEnabled(for trackID: UUID) -> Bool
    func stepOrderMode(for trackID: UUID) -> PerformanceStepOrderMode
}

struct PerformanceNoteRepeatState: Equatable, Sendable {
    var activeTrackIDs: Set<UUID>
    var capturesByTrackID: [UUID: PerformanceRepeatCapture]
}

struct PerformanceRepeatCapture: Equatable, Sendable {
    let clipID: UUID
    let sourceStepIndex: Int
}

enum PerformanceStepOrderMode: String, CaseIterable, Sendable {
    case forward
    case reverse
    case pingPong
}
```

`forward` is equivalent to no step-order overlay and should not be stored as an active override. Keep the model ready for later `random`, `shuffle`, and custom orders, but do not implement them in V1 unless the UI has a clear deterministic contract.

## Engine Mechanics

Add an engine-local source-step resolution helper used only from the tick path:

```swift
struct PerformanceSourceStep {
    let clipID: UUID
    let sourceStepIndex: Int
}
```

Resolution order:

1. Resolve the normal phrase step from `PlaybackSnapshot`.
2. Resolve the selected program slot for the track.
3. If the slot is a clip, compute the base clip source step from `stepIndex`.
4. Apply step-order overlay to that source step for the target track.
5. Apply note-repeat overlay. If a repeat capture exists, use its captured `clipID` and `sourceStepIndex`; otherwise create the capture from the post-step-order source step on the first active tick.
6. Resolve clip notes/slices from the chosen source step.
7. Apply merged fill state to lane selection.
8. Process modifier generators using the normal phrase `stepIndex`, not the transformed source step.

This ordering means step-order changes what note repeat captures, but an active note repeat remains stable until released or cleared.

## Note Repeat

V1 behavior:

- `setPerformanceNoteRepeat(active: true, trackIDs:)` marks target tracks as repeat-active.
- On the next tick for each active track, the engine captures the currently resolved clip source step after step-order transformation.
- While active, the track retriggers that captured source step on every sequencer tick.
- Releasing or clearing repeat removes captures and returns the track to normal source-step resolution.
- Muting, phrase macro curves, destination routing, and modifier generator timing continue at the live phrase step.
- Fill lane selection is evaluated each tick from the current merged fill state, so Fill can alter a repeated source step immediately.
- If the targeted track resolves to an empty or generator slot, no capture is created and playback continues normally for that track.

Engine APIs:

```swift
func setPerformanceNoteRepeat(active: Bool, trackIDs: [UUID])
func clearPerformanceNoteRepeat(trackIDs: [UUID])
```

If the event queue has already prepared the upcoming tick, these methods must invalidate prepared tick output without reinstalling the snapshot.

## Step Order

V1 behavior:

- Step order transforms only clip note/slice source-step lookup.
- Phrase step, pattern slot layer, mute layer, fill layer, phrase macro curves, routing, and modifier generator timing continue normally.
- Clip macro overrides should remain tied to the normal phrase step in V1. This matches the "source notes only" performance-overlay contract and avoids surprising macro jumps.

Initial modes:

- `reverse`: source step `length - 1 - (phraseStep % length)`.
- `pingPong`: source steps travel `0, 1, ..., last, last - 1, ..., 1` in a repeating reflected cycle.

Engine APIs:

```swift
func setPerformanceStepOrder(_ mode: PerformanceStepOrderMode, active: Bool, trackIDs: [UUID])
func clearPerformanceStepOrder(trackIDs: [UUID])
```

Passing `.forward` should clear the step-order overlay for those tracks. As with note repeat, changing step order must invalidate prepared tick output without replacing the playback snapshot.

## Live View Behavior

Use the same target-routing model as Fill:

- Add live controls for **Repeat** and **Order** alongside Fill.
- `Select` chooses target tracks/groups.
- If no target selection is active, the live control applies to all tracks.
- Hold/Latch applies to momentary effects such as Fill and Repeat.
- Step order is mode-like: selecting `Reverse` or `Ping Pong` applies that mode to the current target set; selecting `Forward` clears the overlay for that target set.
- `Clear Live Mods` clears Fill, Repeat, Step Order, captures, and target selection.
- Clear overlays on live view disappear and when active playback phrase identity changes.

Once Fill, Repeat, and Order all exist, consider replacing the top-bar-only controls with a Live Mods matrix:

- rows: tracks or groups;
- columns: Fill, Repeat, Order mode;
- route an action either to selected rows or to all rows when none are selected.

That matrix is a UI consolidation follow-up, not a prerequisite for V1 engine correctness.

## Implementation Steps

1. Extend `PerformanceOverlayState` with note-repeat and step-order state.
2. Add `EngineController` overlay APIs and prepared-tick invalidation for overlay changes.
3. Extract source-step resolution inside `EngineController.resolvedStepNotes`.
4. Add step-order mapping for clip sources.
5. Add note-repeat capture and release semantics.
6. Add live view controls using the existing target-selection routing.
7. Update `Clear Live Mods`, live-view disappear cleanup, and playback-phrase-change cleanup.
8. Add engine, authority, and UI/helper tests.

## Test Plan

Engine tests:

- note repeat captures the currently resolved clip source step and repeats it as phrase steps advance;
- releasing note repeat resumes normal clip source-step lookup;
- note repeat affects targeted tracks only;
- note repeat does not capture generator-source slots in V1;
- fill overlay can change the lane used by an active repeated source step;
- reverse maps clip steps correctly for multiple clip lengths;
- ping-pong maps clip steps correctly, including length 1 and length 2;
- step order affects targeted tracks only;
- step order does not alter phrase mute, phrase macro values, or base fill progression;
- note repeat captures the post-step-order source step when both overlays are active.

Authority tests:

- note repeat does not mutate phrase cells;
- step order does not mutate phrase cells;
- neither mechanic advances store revision;
- neither mechanic recompiles or replaces the playback snapshot;
- overlay changes invalidate prepared tick output without snapshot replacement.

UI/helper tests:

- Repeat live action calls overlay APIs, not `setPhraseCell`;
- Order live action calls overlay APIs, not `setPhraseCell`;
- selected targets route actions to a subset;
- empty target selection routes actions to all tracks;
- `Forward` clears step-order overlay for the target set;
- playback phrase change clears active overlays and repeat captures;
- `Clear Live Mods` clears all live overlay state and target selection.

## Risks

- The engine prepares ticks ahead of playback. Overlay setters must invalidate prepared output directly; otherwise a UI action can miss the next audible tick even though no snapshot is recompiled.
- Note repeat can overlap note lengths. Tests should verify note-off behavior so repeated notes do not hang.
- Random or shuffle order is tempting but needs deterministic seeding and a clear UI contract. Keep it out of V1.
- If implementation starts before the fill overlay branch is merged, avoid creating a second overlay system. Port or merge the existing fill overlay foundation first.
