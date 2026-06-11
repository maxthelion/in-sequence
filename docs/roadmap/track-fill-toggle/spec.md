# Track Fill Toggle Spec

- accepted: 2026-06-04
- status: accepted builder-facing behavior spec for v1
- source artifacts: `prototype-approval.md`, `open-questions.md`,
  `architecture.md`, `user-stories.md`, `existing-state.md`, `ux-review.md`
- selected prototype: `prototypes/01-header-toggle.html`
- scope: transient fill preview for the selected/open clip-backed track

## Product Intent

Track Fill Toggle lets a producer audition the fill variation of the track they
are editing without leaving the track editor and without committing phrase data.

The feature exists to support quick, bounded performance-style exploration from
the editor. It must feel like a temporary playback preview of the selected
track, not like phrase automation, clip lane authoring, or a persistent song
mode edit.

## User-Facing Behavior

### Header Control

The v1 control appears in the track editor header beside the existing
track-editor mode controls, following the accepted header-toggle prototype.

For a selected clip-backed track:

- the control is visible and enabled;
- the default state is off;
- clicking the control on forces that selected track to audition its fill lane
  during playback;
- clicking the control off returns the track to its phrase-resolved fill
  behavior;
- the active state is visually distinct from the inactive state;
- nearby status copy describes what the user is hearing for the current track.

The control must not be placed in the normal/fill lane authoring toolbar for v1.
The user should not have to infer that toggling it edits the phrase
`"fill-flag"` layer or changes the selected clip lane.

### Audible Preview

When preview is active for the selected clip-backed track, playback uses an
effective fill value of true for that track before clip step evaluation. The
fill lane is therefore eligible wherever authored fill-lane content and
probability rules allow it.

When preview is inactive, playback follows the compiled phrase state exactly as
it does today. Phrase-authored fill remains the base truth for all tracks.

Toggling preview during playback must become audible by the next eligible clip
step evaluation, with no transport restart, phrase restart, or snapshot rebuild
required from the user.

### Track Scope

Preview applies only to the selected/open track in the track editor.

If preview is active on track A:

- track A evaluates clip steps as if fill is enabled;
- track B keeps its own compiled phrase fill behavior;
- drum-group siblings are not forced into fill;
- selecting track B clears the preview instead of transferring it;
- enabling preview on track B requires a separate user action after selection.

Only one selected/open track can be forced into preview fill in v1.

### Reset Lifecycle

The preview is scoped to the current editor session and must clear when the user
leaves the selected-track editing context.

Preview must reset to off when:

- the selected track changes;
- the track editor closes or disappears;
- the selected track is deleted;
- the selected track changes from a clip-backed source to a generator-backed or
  otherwise unsupported source;
- the project/document session closes.

Track switch reset must happen before the newly selected track renders as
preview-active. Closing the editor while playback continues must stop forcing
fill for the previously edited track.

### Generator-Backed Tracks

Generator-backed tracks are out of v1 scope.

When the selected track is generator-backed:

- the fill preview control is disabled or otherwise unavailable;
- the disabled state is visually clear;
- short explanatory copy appears adjacent to the disabled control;
- the copy says, in product-appropriate wording, that fill preview is available
  for clip-backed tracks only in v1.

The engine must not fake fill behavior for generator-backed tracks, and preview
state must not be routed into generator evaluation.

## Non-Mutation Contract

Fill preview is runtime state only.

Toggling preview must not:

- mutate the phrase `"fill-flag"` layer;
- mutate phrase cells through `setPhraseCell(...)` or equivalent document
  mutation paths;
- mutate clip steps, normal lanes, fill lanes, pattern slots, track source
  settings, or phrase definitions;
- register undo or redo operations;
- mark the document dirty by itself;
- serialize preview state into the project document;
- restore preview state after reopening a project;
- participate in phrase compilation.

Preview may coexist with phrase-authored fill. If a phrase already enables fill
for a track, turning preview off returns to that phrase-authored result rather
than forcing fill false.

## Acceptance Criteria

1. A clip-backed selected track shows an enabled header fill-preview control in
   the track editor.
2. The enabled control defaults to off when the track editor opens or when a
   track is selected.
3. Turning the control on makes the selected clip-backed track audition fill
   playback without restarting transport.
4. Turning the control off returns that track to its compiled phrase fill
   behavior.
5. Mid-playback toggles are reflected by the next eligible clip step.
6. Active, inactive, and disabled states are visually distinct.
7. Status or helper copy identifies that preview affects the current track only.
8. Switching to another track clears preview before the new track renders.
9. Closing and reopening the track editor leaves preview off.
10. Deleting the previewed track clears preview.
11. Changing the previewed track to an unsupported source clears preview.
12. Sibling tracks, including drum-group siblings, keep their compiled phrase
    fill behavior while preview is active.
13. Generator-backed tracks present a disabled/unavailable control with nearby
    explanatory copy.
14. Toggling preview leaves phrase `"fill-flag"` cells unchanged.
15. Toggling preview alone does not mark the document dirty.
16. Preview state is not undoable, redoable, persisted, exported, or restored.
17. No product behavior depends on the rejected lane-toolbar prototype.

## Edge Cases

### Phrase Already Enables Fill

If the current phrase already resolves fill enabled for the selected track, the
preview control may still show its own runtime preview state. Turning preview
off must not suppress phrase-authored fill. It only removes the runtime force.

### Preview On While Transport Is Stopped

If the user enables preview while stopped and then starts playback, the selected
clip-backed track should audition fill from the first eligible evaluated clip
step. Stopping transport alone does not need to clear preview unless local
session conventions already clear other editor preview state on stop.

### No Authored Fill Content

If a clip-backed track has no audible fill-lane content at the current step, the
preview can be active without producing a different sound. The UI should still
show active preview because the runtime fill force is on.

### Fill Lane Probability

Existing fill-lane probability and step-selection behavior still applies.
Preview forces effective fill eligibility for the selected clip-backed track; it
does not guarantee that every step produces a fill note if authored clip content
or probability rules say otherwise.

### Track Selection Race

If selection changes while a preview toggle command is in flight, the runtime
state must not leave preview active for a non-selected or stale track. The
selected-track reset rule wins.

### Source Change Race

If a previewed clip-backed track changes source type, preview must clear before
the UI can present a generator-backed track as active or before the engine can
apply preview to an unsupported source.

## Verification Requirements

### Automated Checks

The build should include focused automated coverage for:

- runtime state command toggling for one track id and clearing on reset;
- UI/view-model derivation of active state from selected track plus runtime
  preview state;
- disabled generator-backed control state and adjacent explanatory copy;
- engine effective-fill calculation that shadows compiled `fillEnabled` after
  playback snapshot resolution and before clip step evaluation;
- phrase non-mutation after preview toggles;
- document dirty-state preservation after preview toggles alone;
- per-track isolation, including a sibling/drum-group sibling case;
- reset on track switch;
- reset on editor close/disappear;
- reset on selected track deletion;
- reset on selected track source changing away from clip-backed;
- no persistence or restoration of preview state across project reload.

### Manual Or Visual Checks

Verification should also exercise the built surface:

- open a clip-backed track in the track editor and confirm header placement;
- confirm inactive, active, and generator-disabled states are visually clear;
- confirm disabled generator explanation is adjacent to the disabled control;
- toggle preview while playback is running and confirm audible response without
  transport restart;
- switch tracks and confirm the next selected track renders preview off;
- close the editor while preview is active, keep playback running if possible,
  and confirm fill preview stops;
- confirm phrase grid cells and dirty-state indicators do not change from
  preview toggles.

Visual evidence should prefer the actual built app surface over prototype
screenshots once implementation exists.

## Out Of Scope

- Editing or redesigning the clip normal/fill lane authoring UI.
- Writing phrase `"fill-flag"` layer cells from the preview toggle.
- Global fill preview across all tracks.
- Drum-group-wide fill preview.
- Generator-backed fill support.
- Persisted, exported, undoable, or automatable fill preview state.
- Build-loop implementation sequencing, which belongs in a later `plan.md`.

## Remaining PM Dependencies

This spec closes the accepted behavior contract for v1. The lane still needs
`plan.md` and `implementation-handoff.md` before build-loop promotion.
