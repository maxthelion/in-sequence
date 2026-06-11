---
feature: track-fill-toggle
status: ready-for-build-loop-promotion
stage: implementation-handoff
updated: 2026-06-04
sources:
  - README.md
  - docs/roadmap/track-fill-toggle/prototype-approval.md
  - docs/roadmap/track-fill-toggle/open-questions.md
  - docs/roadmap/track-fill-toggle/architecture.md
  - docs/roadmap/track-fill-toggle/spec.md
  - docs/roadmap/track-fill-toggle/plan.md
---

# Track Fill Toggle Implementation Handoff

## Purpose

This handoff packages the accepted Track Fill Toggle v1 PM artifacts into
builder-ready scope. It should be used to open a future build loop, but it does
not itself promote a build loop or route implementation.

Track Fill Toggle lets a producer temporarily audition the fill variation of
the selected clip-backed track from the track editor header. The feature
supports the README performance-modification intent: quick, bounded musical
experiments that can be heard while playing and discarded without silently
changing authored phrase or clip state.

## Build-Loop Boundary

A future build loop should implement the full v1 preview workflow end to end:

- A track-editor header fill-preview control following the accepted
  `prototypes/01-header-toggle.html` direction.
- Runtime-only selected-track preview state owned outside `Project`, `Phrase`,
  `Clip`, and track source document models.
- Playback shadowing of compiled phrase fill after snapshot resolution and
  before clip-backed step evaluation.
- Selected/open clip-backed track scope only.
- No phrase `"fill-flag"` mutation, document dirtying, undo/redo entry,
  persistence, export, or project reload restoration from preview alone.
- Reset on track switch, editor close/disappear, track deletion, source change
  away from clip-backed, and document/session close.
- Generator-backed or otherwise unsupported tracks disabled/unavailable in v1
  with adjacent explanatory copy.
- Built-surface evidence for header placement, active/inactive/disabled states,
  reset lifecycle, current-track-only scope, and unchanged phrase/dirty-state
  indicators.

Do not broaden the build into generator-backed fill behavior, global fill
preview, drum-group-wide fill preview, normal/fill lane redesign, phrase
automation, persisted preview state, or song-mode authoring.

## Authoritative Context

| Artifact | Builder Use |
|---|---|
| `spec.md` | Primary behavior contract, acceptance criteria, edge cases, and verification requirements. |
| `plan.md` | Implementation and verification sequence for the build loop. |
| `architecture.md` | Runtime ownership, engine shadow point, reset lifecycle, and mutation guardrails. |
| `prototype-approval.md` | Accepted header-toggle UX basis and rejected lane-toolbar comparison. |
| `open-questions.md` | Resolved v1 product decisions and residual non-blocking acceptance notes. |
| `prototypes/01-header-toggle.html` | Accepted prototype reference for placement and state model. |
| `prototypes/02-lane-toolbar-toggle.html` | Rejected comparison only; do not use as implementation lead. |

## Exact First Implementation Slice

The first slice should confirm current code integration points and add the
runtime state plus playback shadow in the smallest verifiable path.

Before UI work, verify that the current code still matches the accepted
architecture map:

- `TrackSourceEditorView` or its local view model owns the track editor header
  and `Source` / `Modifiers` controls.
- Phrase compilation owns persistent `"fill-flag"` layer values.
- `PlaybackSnapshot.resolvedStep` exposes compiled `fillEnabled`.
- `EngineController` passes the resolved fill value into the clip-backed
  `GeneratedSourceEvaluator.resolveClipStep(...)` path.
- Generator-backed playback does not consume `fillEnabled`.

Then add runtime preview state equivalent to one optional active track id and
thread an engine-readable snapshot into clip-backed playback:

```swift
let effectiveFillEnabled =
    resolved.fillEnabled || fillPreviewState.activeTrackID == track.id
```

The effective value should be computed after phrase snapshot resolution and
before clip step evaluation. It must not change phrase compilation, compiled
buffers, clip lane data, or generator evaluation.

## UI Contract

The v1 control belongs in the track editor header beside the existing editor
mode controls. It must not be placed in the normal/fill lane authoring toolbar.

For a selected clip-backed track:

- show the control enabled;
- default it to inactive when the editor opens or track selection changes;
- make active and inactive states visually distinct;
- toggle through runtime preview commands only;
- keep nearby status/helper copy focused on what is being heard for the current
  track.

For a selected generator-backed or unsupported track:

- show the control disabled or unavailable;
- keep the reason adjacent to the disabled control;
- explain that fill preview is available for clip-backed tracks only in v1;
- do not fake fill behavior in generator evaluation.

## Non-Mutation Guardrails

Preview is not document state. The build must prove that toggling preview does
not:

- write phrase `"fill-flag"` cells or call phrase mutation paths such as
  `setPhraseCell(...)`;
- mutate clip steps, normal lanes, fill lanes, pattern slots, track source
  settings, or phrase definitions;
- register undo or redo operations;
- mark the document dirty by itself;
- serialize, export, or restore preview state;
- suppress phrase-authored fill when preview turns off.

Phrase-authored fill remains the base truth. Preview can only add a runtime
force for the selected clip-backed track.

## Required Reset Behavior

Clear runtime preview state when:

- selected track changes;
- track editor closes or disappears;
- selected track is deleted;
- selected track changes away from a clip-backed source;
- project/document session closes.

Track switch reset must happen before the newly selected track renders as
preview-active. Editor-close reset must stop forcing fill even if playback
continues.

## Required Exit Evidence

The build loop is complete only when it leaves compact evidence for:

- runtime/session state commands: enable for one track id, disable, clear by
  reset reason, and no persistence across project reload;
- engine effective-fill shadowing after snapshot resolution and before
  clip-backed step evaluation;
- mid-playback audible response by the next eligible clip step without
  transport restart;
- phrase `"fill-flag"` non-mutation;
- document dirty-state preservation and no undo/redo entry from preview alone;
- sibling-track and drum-group sibling isolation;
- reset on track switch, editor close/disappear, deletion, source change, and
  document close;
- generator-backed disabled/unavailable UI with adjacent explanatory copy;
- actual built-surface evidence for inactive, active, and disabled header
  states;
- visual or manual confirmation that phrase grid cells and dirty-state
  indicators do not change from preview toggles.

If the full suite is too slow or blocked in the build worktree, record the
blocker and provide the focused runtime, engine, mutation, isolation, reset, and
built-surface evidence that did run.

## Acceptance Review Checklist

- Clip-backed selected tracks show an enabled header fill-preview control.
- The control defaults to off when the editor opens and after track changes.
- Turning the control on auditions fill playback for the selected clip-backed
  track without restarting transport.
- Turning the control off returns to compiled phrase fill behavior.
- Phrase-authored fill elsewhere remains unchanged.
- Sibling tracks, including drum-group siblings, are not forced into fill.
- Switching tracks, closing the editor, deleting the track, changing source
  type, or closing the document clears preview.
- Generator-backed tracks show a disabled/unavailable state with adjacent copy.
- Preview toggles do not mutate phrase cells, clip content, source settings, or
  pattern slots.
- Preview toggles alone do not dirty the document, create undo/redo history, or
  persist into saved project files.
- The rejected lane-toolbar prototype does not drive product behavior.

## V1 Exclusions

Do not implement or infer these in v1:

- generator-backed fill support;
- global fill preview;
- drum-group-wide fill preview;
- normal/fill lane authoring redesign;
- phrase `"fill-flag"` writes from the preview toggle;
- persisted, exported, undoable, redoable, or automatable preview state;
- transport, phrase, or snapshot rebuild requirements for ordinary
  mid-playback preview toggles.

## Residual Risks

- The highest implementation risk is accidentally reusing existing phrase-cell
  mutation paths for a control that must be runtime-only.
- Engine preview state must be playback-safe; SwiftUI view state must not be
  consulted directly from the playback thread.
- Header placement is accepted, but discoverability remains an acceptance note.
  Built-surface review should verify the control is visible without reading as
  lane authoring.
- Reset-on-close, deletion, and source-change cleanup are easy to miss because
  they may bypass the normal selection path.
- Generator-disabled explanation must stay adjacent to the disabled control.
  Distant help text is not enough for the accepted UX note.

## Product-Owner Attention

No product-owner decision is needed for build-loop promotion. The accepted
prototype, resolved v1 decisions, architecture, spec, and plan close the
product choices needed for implementation.

## Promotion Read

This lane is builder-ready from the PM artifact perspective after this handoff
package is present. Build-loop promotion remains a project-loop decision and
should wait for PM readiness observation, orientation, and decision evidence to
consume this handoff.
