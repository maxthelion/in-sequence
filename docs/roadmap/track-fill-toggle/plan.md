# Track Fill Toggle Plan

- accepted: 2026-06-04
- status: accepted builder-facing implementation plan for v1
- source artifacts: `prototype-approval.md`, `open-questions.md`,
  `architecture.md`, `spec.md`, `existing-state.md`, `ux-review.md`
- scope: transient fill preview for the selected/open clip-backed track
- not included: `implementation-handoff.md`

## Build Goal

Implement a track-editor header control that lets a producer temporarily
audition fill playback for the selected clip-backed track without mutating
phrase data, dirtying the document, or forcing fill onto sibling tracks.

The build should preserve the accepted v1 model:

- fill preview is runtime session state, not a phrase `"fill-flag"` edit;
- the selected/open track is the only track forced into fill preview;
- generator-backed tracks are disabled/unavailable for v1;
- switching tracks, closing the editor, deleting the track, changing the source
  away from clip-backed, or closing the document clears preview;
- mid-playback toggles become audible by the next eligible clip step without a
  transport restart.

## Implementation Sequence

### 1. Confirm Current Integration Points

Before editing, verify the current code still matches the accepted
`existing-state.md` map:

- `TrackSourceEditorView` owns the track editor header and `Source` /
  `Modifiers` controls;
- `PhraseLayerDefinition` and phrase compilation own the persistent
  `"fill-flag"` layer;
- `PlaybackSnapshot.resolvedStep` exposes compiled `fillEnabled`;
- `EngineController` passes `resolved.fillEnabled` into the clip-backed
  `GeneratedSourceEvaluator.resolveClipStep(...)` path;
- generator-backed playback does not consume `fillEnabled`.

If code has moved, preserve the same architectural boundary: runtime preview
state must sit after snapshot resolution and before clip step evaluation, never
inside phrase, clip, or project mutation models.

### 2. Add Runtime Preview State

Add a runtime-only selected-track fill-preview state to the active document
session or equivalent live playback-session layer.

The state shape should remain equivalent to one optional active track id:

```swift
struct TrackFillPreviewState: Equatable {
    var activeTrackID: TrackID?
}
```

Expose command-style APIs equivalent to:

```swift
setFillPreviewEnabled(_ enabled: Bool, for trackID: TrackID)
clearFillPreview(reason: FillPreviewResetReason)
fillPreviewStatePublisher
```

The commands must:

- update runtime/session state only;
- avoid `setPhraseCell(...)` and equivalent document mutation paths;
- avoid undo/redo registration;
- avoid project serialization;
- publish UI-observable state for the selected track;
- provide the engine with a playback-safe read snapshot.

### 3. Shadow Effective Fill In Playback

Thread the runtime preview snapshot into the engine path that evaluates
clip-backed sources.

For each resolved track playback step, compute effective fill as:

```swift
let effectiveFillEnabled =
    resolved.fillEnabled || fillPreviewState.activeTrackID == track.id
```

Pass `effectiveFillEnabled` into the existing clip-backed
`resolveClipStep(...)` branch. Do not change phrase compilation, compiled
buffers, layer snapshots, clip lane data, or generator evaluation.

The preview must be sampled often enough that toggling during playback affects
the next eligible clip step. A transport restart, phrase restart, or manual
snapshot rebuild must not be required.

### 4. Add The Track Editor Header Control

Add the v1 fill-preview control to the track editor header beside the existing
track-editor mode controls, following `prototypes/01-header-toggle.html`.

For clip-backed selected tracks:

- show the control enabled;
- default to inactive when the editor opens or track selection changes;
- show distinct active and inactive states;
- toggle via the runtime preview command API;
- keep nearby status/helper copy focused on what the user is hearing for the
  current track only.

For generator-backed or unsupported selected tracks:

- show the control disabled or unavailable;
- keep a short explanation adjacent to the disabled control;
- make clear that fill preview applies to clip-backed tracks only in v1.

Do not place the primary control in the normal/fill lane authoring toolbar, and
do not bind it to phrase layer state.

### 5. Wire Reset Lifecycle

Clear the runtime preview state when the user leaves the selected-track editing
context:

- selected track changes;
- track editor closes or disappears;
- selected track is deleted;
- selected track source changes away from clip-backed;
- project/document session closes.

Track-switch reset must happen before the newly selected track renders as
preview-active. Editor-close reset must stop forcing fill even if playback
continues.

### 6. Preserve Mutation And Dirty-State Guardrails

Add regression coverage around the non-mutation contract while implementing the
feature. Preview toggles must not:

- mutate phrase `"fill-flag"` cells;
- mutate clip steps or lane content;
- mutate track source settings or pattern slots;
- mark the document dirty by themselves;
- create undo or redo entries;
- persist, export, or restore preview state.

Phrase-authored fill remains the base truth. Turning preview off removes only
the runtime force; it must not force phrase-authored fill false.

### 7. Add Focused UI And Engine Tests

Add focused tests at the smallest useful seams:

- runtime state toggles one track id and clears on reset;
- UI/view-model active state derives from selected track plus runtime preview
  state;
- generator-backed tracks derive disabled state and adjacent explanatory copy;
- engine effective-fill calculation shadows compiled `fillEnabled` only for the
  previewed clip-backed track;
- sibling and drum-group sibling tracks keep their compiled fill behavior;
- track switch, editor close/disappear, deletion, and source-change resets all
  clear preview;
- preview does not persist across project reload.

Prefer direct model/session/engine tests for non-UI behavior and one or more
view-level checks for header placement and disabled-state copy.

### 8. Capture Built-Surface Evidence

After implementation, capture actual built-surface evidence rather than relying
on prototype screenshots.

Manual or visual evidence should cover:

- clip-backed selected track with inactive header control;
- active clip-backed preview state with current-track-only copy;
- generator-backed selected track disabled state with adjacent explanation;
- track switch clearing preview;
- editor close clearing preview while playback continues where practical;
- phrase grid cells and dirty-state indicators unchanged by preview toggles.

## Verification Sequence

Run verification in this order:

1. Focused runtime/session tests for preview state commands and reset reasons.
2. Focused engine tests proving effective fill shadows compiled fill after
   snapshot resolution and before clip step evaluation.
3. Regression tests for phrase non-mutation, dirty-state preservation,
   undo/redo absence, and no persistence across reload.
4. Per-track isolation tests, including a drum-group sibling case.
5. UI/view-model tests for enabled, active, inactive, generator-disabled, and
   reset-derived states.
6. Full project test command normally used by the build loop for Swift package
   and app-level coverage.
7. Manual or visual app evidence for the built header control and reset
   lifecycle.

If a full suite is too slow or blocked in the build worktree, the builder
should record the blocker and provide the focused tests plus built-surface
evidence that did run.

## Handoff Risks

- The largest implementation risk is accidentally reusing existing phrase-cell
  mutation paths for a control that must be runtime-only.
- Engine state must be playback-safe; SwiftUI view state must not be read
  directly from the playback thread.
- Header placement has accepted product direction, but discoverability remains
  an acceptance note. Built-surface review should verify the control is visible
  without making it look like lane authoring.
- Generator-backed disabled copy must stay near the disabled control. Hiding
  the reason in distant help text would miss the accepted UX note.
- A phrase that already enables fill must continue to do so when preview is
  off. Preview-off is not a force-main command.
- Reset-on-close is easy to miss because prototypes annotated it rather than
  demonstrating a close/reopen flow.
- Source-change and deletion resets are edge cases likely to need explicit
  tests because they may bypass normal track-selection UI paths.

## Out Of Scope For This Build

- Generator-backed fill support.
- Global or drum-group-wide fill preview.
- Redesigning normal/fill lane authoring.
- Writing phrase `"fill-flag"` cells from the preview control.
- Persisted, exported, undoable, redoable, or automatable preview state.
- Authoring `implementation-handoff.md`; that remains the next PM artifact.

## Promotion Dependency

This plan closes the bounded implementation-sequence gap. The PM lane still
needs accepted `implementation-handoff.md` before it is ready for build-loop
promotion.
