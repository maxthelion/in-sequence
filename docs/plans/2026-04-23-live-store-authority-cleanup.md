# Live Store Authority Cleanup

## Summary

The first V2 live-store slice moved the sequencer hot path onto a resident session/store and compiled playback snapshots, but a number of non-clip UI surfaces still mutate `document.project` directly. The next cleanup work should finish the authority cutover for track-level controls so hot UI changes no longer bypass the live runtime owner.

The immediate next step is to move **mixer values** into the live authority path:

- `level`
- `pan`
- `mute`

That includes both the dedicated mixer UI and the inspector’s mixer section.

## Goals

- Mixer and inspector read track mix state from `SequencerDocumentSession` / `session.project`
- Level and pan writes update the live store immediately
- Level and pan continue to use the scoped engine mix path instead of broad engine rebuilds
- Mute writes also go through the live store, even if the first pass still uses a broader engine update path
- No normal mixer editing path mutates `document.project` directly

## Implementation Changes

### 1. Add a session-level mix mutation API

Add a focused mutation method on `SequencerDocumentSession` for track mix edits.

Requirements:

- update the detached live `Project` inside `LiveSequencerStore`
- call the engine’s scoped `setMix(trackID:mix:)` path for live sink updates
- schedule the normal document flush

This should become the standard path for level/pan writes from UI.

### 2. Keep engine mix state coherent

`EngineController.setMix(trackID:mix:)` should update any cached track/runtime mix mirrors that affect live playback decisions, not just the sink objects. That avoids the live store and engine diverging during high-frequency mixer edits.

### 3. Migrate MixerView

Move [MixerView.swift](/Users/maxwilliams/dev/in-sequence/.claude/worktrees/main-recovery-integration/Sources/UI/MixerView.swift) off `$document.project.tracks[index]`.

Requirements:

- read tracks from `session.project`
- use explicit callbacks rather than document bindings for mix edits
- route level/pan writes through the session mix API
- route mute through the live store mutation path
- keep the existing throttled drag behavior

### 4. Migrate InspectorView

Move the mixer section of [InspectorView.swift](/Users/maxwilliams/dev/in-sequence/.claude/worktrees/main-recovery-integration/Sources/UI/InspectorView.swift) onto `session.project`.

Requirements:

- selected track reads from `session.project.selectedTrack`
- level/pan use the same session mix API as mixer
- mute goes through the live store mutation path

It is acceptable in this pass to migrate the other inspector track/generator fields too, so the file stops mixing two authority models.

## Follow-on Cleanup

After mixer authority is done, the next recommended order is:

1. Track selection / add-remove / grouping surfaces
2. Routes editor/list
3. Remaining document-backed inspector/sidebar helpers
4. Cleanup of authority tests and warnings

## Test Plan

- add or extend tests to prove level/pan writes do not require broad `apply(documentModel:)`
- verify mute still affects live playback correctly
- run focused engine mix tests
- run full macOS `xcodebuild test`

## Assumptions

- Mixer authority cleanup is incremental, not a second architecture rewrite
- Level and pan can use scoped live mix updates
- Mute may still use a broader engine path in the first pass if needed for correctness
- `SequencerDocumentSession` remains the one hot-state owner for these edits
