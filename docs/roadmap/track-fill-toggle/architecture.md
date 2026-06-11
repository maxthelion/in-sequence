# Track Fill Toggle Architecture

- accepted: 2026-06-04
- status: accepted PM architecture for v1 builder-facing handoff
- source artifacts: `prototype-approval.md`, `open-questions.md`,
  `existing-state.md`, `ux-review.md`
- scope: transient selected-track fill preview for clip-backed tracks only

## Architecture Decision

Track Fill Toggle v1 is a runtime-only playback preview owned outside the
project document model.

The feature must add a live, track-scoped fill-preview override that shadows the
compiled phrase `fillEnabled` value for the selected/open clip-backed track
before clip step evaluation. It must not write the phrase `"fill-flag"` layer,
must not mark the document dirty by itself, and must clear when the user leaves
the selected-track editing context.

The accepted UI basis is the track editor header control from
`prototypes/01-header-toggle.html`. Architecture must preserve that mental
model: this is a temporary audition state, not lane authoring and not phrase
automation.

## Existing Runtime Flow

The current phrase-owned fill path remains the base truth:

1. Phrase compilation resolves the `"fill-flag"` layer into
   `TrackPhrasePlaybackBuffer.fillEnabled`.
2. `PlaybackSnapshot.resolvedStep` returns a `ResolvedTrackPlaybackStep` with
   the compiled `fillEnabled` boolean for a track and phrase step.
3. `EngineController` passes that value to
   `GeneratedSourceEvaluator.resolveClipStep(...)` for clip-backed sources.
4. `GeneratedSourceEvaluator` chooses `step.fill` instead of `step.main` when
   effective fill is enabled and the authored fill lane fires.

The new preview override belongs between steps 2 and 3. It shadows the resolved
value only for the current playback evaluation of the selected track. It does
not change phrase compilation, phrase snapshots, clip content, or project
storage.

## Runtime Override Ownership

Introduce one runtime fill-preview state owned by the active document session or
equivalent live playback-session layer, not by the `Project`, `Phrase`,
`Clip`, or track source models.

The logical state shape for v1 should be equivalent to:

```swift
struct TrackFillPreviewState: Equatable {
    var activeTrackID: TrackID?
}
```

This state is intentionally an optional selected track id rather than a global
boolean. That prevents a preview-on value from following selection to another
track and makes per-track isolation explicit.

The session-facing API should be command-shaped rather than document-mutation
shaped:

```swift
setFillPreviewEnabled(_ enabled: Bool, for trackID: TrackID)
clearFillPreview(reason: FillPreviewResetReason)
fillPreviewStatePublisher
```

Naming can follow local conventions, but the contract is binding:

- setters update runtime preview state only;
- setters do not call phrase cell mutation APIs such as `setPhraseCell(...)`;
- setters do not register undo operations;
- setters do not serialize anything into the project document;
- the engine sees an audio-safe/read-only snapshot of the current override.

If the implementation keeps a UI-observable session state and a separate
engine-readable copy, the session state is the owner and the engine copy is a
derived runtime snapshot. The derived copy must be updated when preview changes
and must be safe for the playback thread to read without consulting SwiftUI
view state.

## Playback Shadow Point

At playback evaluation time, the engine must compute an effective fill value
for each track:

```swift
let effectiveFillEnabled =
    resolved.fillEnabled || fillPreviewState.activeTrackID == track.id
```

That effective value, not the raw compiled phrase value, is passed into the
clip-backed `resolveClipStep(...)` path.

The shadow point must be after phrase snapshot resolution and before clip step
evaluation. That gives the preview immediate audible effect without rebuilding
or mutating phrase data. Mid-playback toggles should become audible by the next
eligible clip step evaluation, with no transport restart required.

The override must be ignored for non-clip-backed sources. It must not add fill
semantics to generator-backed tracks in v1.

## UI Observation Contract

`TrackSourceEditorView` or its local view model observes the runtime preview
state and derives the visible header-control state from the current selected
track:

```swift
let isPreviewActive =
    fillPreviewState.activeTrackID == selectedTrack.id && selectedTrack.isClipBacked
```

The view must not bind the control to phrase layer data. Tapping the control
must call the runtime preview command API, not any project or phrase mutation
API.

The disabled generator-backed state is also derived from source type, not from
phrase data:

- clip-backed selected track: control is enabled and can toggle preview;
- generator-backed selected track: control is disabled/unavailable;
- disabled copy stays adjacent to the control and explains that fill preview is
  available for clip-backed tracks only in v1.

UI status text can describe what the user is hearing, but it must not imply
that the phrase or clip lane has been edited.

## Reset Lifecycle

Preview state is scoped to the currently open selected-track editor context.
The runtime owner must clear `activeTrackID` in these cases:

- selected track changes;
- track editor closes or disappears;
- selected track is deleted;
- selected track source changes away from a clip-backed source;
- project/document session closes.

Track switch reset should happen before the newly selected track renders as
preview-active. The newly selected track always starts with preview off even if
the previous track had preview on.

Editor-close reset is required even when playback continues. Reopening the
editor must show preview off and must not continue forcing fill for the
previously edited track.

## Mutation And Dirty-State Guardrails

Preview is not document state.

Implementation must preserve these guardrails:

- toggling preview does not mutate the phrase `"fill-flag"` layer;
- toggling preview does not mutate clip steps, normal/fill lanes, pattern slots,
  track source settings, or phrase cells;
- toggling preview alone does not mark the document dirty;
- preview state is not persisted, exported, undoable, redoable, or restored from
  the project file;
- preview state does not participate in phrase compilation;
- phrase-authored fill remains the base behavior when preview is off.

The architecture intentionally avoids reusing existing live controls that call
`setPhraseCell(...)`, because those controls author phrase data and would
violate the transient preview requirement.

## Per-Track Isolation

Only one selected/open track can be forced into fill preview for v1.

When preview is active for track A:

- track A evaluates clip steps with effective fill enabled;
- sibling tracks keep their own compiled phrase `fillEnabled` values;
- drum-group siblings are not forced into fill;
- selecting track B clears the override instead of transferring it;
- enabling preview on track B requires an explicit user action after selection.

Phrase-authored fill can still enable fill on any track according to the
compiled phrase. The preview override only adds a selected-track runtime force;
it does not disable phrase-authored fill elsewhere.

## Generator-Backed Disabled Behavior

Generator-backed tracks are out of v1 runtime scope.

The UI must present the fill preview control as disabled or unavailable for
generator-backed tracks, with nearby explanatory copy. The engine must not fake
fill output for generator-backed sources and must not route preview state into
generator evaluation.

If a clip-backed track with preview on changes to a generator-backed source,
the runtime owner clears preview state as part of the source-change lifecycle.

Future generator fill support would require a separate architecture decision
because current generator playback does not consume `fillEnabled` in the same
way clip playback does.

## Builder-Facing Verification Implications

The later spec and plan should turn these architecture constraints into tests
and manual checks:

- engine-level check that preview shadows compiled `fillEnabled` before
  `resolveClipStep(...)` for the selected clip-backed track;
- regression check that phrase `"fill-flag"` cells are unchanged after preview
  toggles;
- dirty-state check that preview toggles alone do not mark the document
  modified;
- UI/view-model check that track switch and editor close clear preview;
- isolation check that sibling tracks, including drum-group siblings, keep
  their compiled fill behavior;
- disabled-state check for generator-backed tracks with adjacent explanation.

## Remaining Dependencies

This architecture closes the runtime ownership and shadowing gap for v1. The
lane still needs accepted `spec.md`, `plan.md`, and
`implementation-handoff.md` before build-loop promotion.
