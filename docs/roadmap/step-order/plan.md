---
feature: step-order
created: 2026-06-06
status: ready-for-implementation-handoff
sources:
  - README.md
  - docs/roadmap/step-order/spec.md
  - docs/roadmap/step-order/architecture.md
  - docs/roadmap/step-order/open-questions.md
  - docs/roadmap/step-order/user-stories.md
  - docs/roadmap/step-order/existing-state.md
  - docs/roadmap/step-order/ux-review.md
  - docs/roadmap/step-order/prototypes/step-order-wireframe.html
next_artifact: docs/roadmap/step-order/implementation-handoff.md
---

# Step Order Implementation Plan

## Purpose

This plan translates the accepted Step Order v1 architecture and spec into a
builder-facing implementation sequence. Step Order is a phrase-scoped
playback-order performance override: a named 16-step map is assigned to a
phrase, an enabled phrase resolves output steps through that map at playback
time, and disabling the map restores sequential source-step reads without
rewriting authored material.

The plan is engine-and-model first. Builders should prove persistence,
validation, snapshot compilation, and non-destructive playback resolution
before treating the picker/editor surface as complete.

This plan does not promote a build loop and does not replace a later
`implementation-handoff.md`.

## Settled V1 Contract

Builders should preserve these accepted decisions from architecture and spec:

- Step Order is phrase-only in v1: one assigned map per phrase, applied to all
  playable tracks in that phrase when enabled.
- Maps live in a top-level named project pool with stable IDs, user-visible
  names, and exactly 16 source-step values.
- Map values are constrained to `0...15`.
- Phrases persist an optional map assignment plus saved enabled state.
- Runtime pending toggle state is not persisted, exported, undoable, or
  redoable.
- Toggling while playback is running applies at the next phrase boundary and
  exposes explicit Off, On, Pending On, and Pending Off UI state.
- Toggling while stopped updates the effective saved phrase state immediately.
- Playback remapping is non-destructive and happens after the output
  `stepInPhrase` is known but before source/pattern note data is read.
- Phrase-layer timing remains anchored to the output step in v1.
- Non-16-step phrases, invalid maps, missing maps, and deleted assigned maps do
  not silently modulo or crash; they resolve as unavailable or sequential.
- Per-track, project-wide, layer-level, variable-length, and stacked map
  behavior is deferred.

## Implementation Sequence

### 1. Reconfirm Current Seams And Add Focused Test Fixtures

Before editing broadly, verify the current code still matches the accepted
`existing-state.md` map:

- `EngineController.prepareTick` still computes one phrase-local
  `stepInPhrase` from `upcomingStep`.
- `PlaybackSnapshot.resolvedStep` still normalizes `stepInPhrase` before
  reading per-track source/pattern data.
- `PlaybackSnapshot.layerSnapshot` still reads phrase layers from the original
  output step.
- `SequencerSnapshotCompiler.compilePhraseBuffer` still owns phrase playback
  buffer construction and incremental invalidation.
- `PhrasePlaybackBuffer` and/or `TrackPhrasePlaybackBuffer` remain the right
  homes for immutable engine-safe compiled Step Order data.
- Project save/load still routes through the document-root Codable path and
  phrase models named in `existing-state.md`.

Create the smallest deterministic fixtures needed to prove a phrase with known
source steps can play sequentially, then play through the accepted remap
`[0,1,2,3,3,3,3,3,7,8,9,0,1,2,3,3]`.

Exit evidence:

- A short seam audit in build evidence naming any integration points that moved
  since `existing-state.md`.
- Initial focused tests or fixtures that can observe compiled phrase buffers
  and source-step resolution without depending on SwiftUI.

### 2. Add Project Map Pool And Phrase Assignment Persistence

Add the durable model before engine behavior so invalid and legacy data cases
have a clear source of truth.

Work:

- Add a stable `StepOrderMapID` and `StepOrderMap` equivalent with `id`, `name`,
  and exactly 16 `UInt8` source-step values.
- Add a top-level Step Order map pool to the project/document root.
- Add an optional `StepOrderAssignment` equivalent to each phrase, storing a
  map ID and saved enabled state.
- Decode existing projects to an empty map pool, no assignments, and sequential
  playback.
- Save and load map IDs, names, values, phrase assignment, and saved enabled
  state.
- Ensure map edits, map rename, assignment changes, deleting unused maps, and
  saved enabled-state changes dirty the document through normal edit paths.
- Ensure runtime pending state is not part of the document model, undo stack,
  export, or Codable payload.

Verification:

- Codable round-trip for map pool and phrase assignment.
- Legacy decode with no Step Order fields.
- Dirty-state coverage for durable edits.
- Non-persistence coverage for runtime pending state.

### 3. Enforce Validation And Unsupported-State Recovery

Make 16-step validity a model, UI, decode, and compiler invariant rather than a
late playback guess.

Work:

- Keep production editing constrained to 16 values in `0...15`.
- Reject or safely quarantine wrong-length and out-of-range decoded maps.
- Compile missing, invalid, deleted, unassigned, disabled, and unsupported
  phrase states to sequential playback.
- Prevent assignment or enabling for non-16-step phrases in v1, or surface an
  explicit unavailable state if a saved assignment already exists.
- Block deletion of any map assigned to at least one phrase and expose usage
  count/reason in the picker.
- Avoid hidden modulo behavior for arbitrary phrase lengths.

Verification:

- Tests for wrong-length, out-of-range, missing-map, deleted-map, disabled,
  unassigned, and non-16-step phrase states.
- Tests proving invalid data does not crash project load or enter an active
  compiled map.
- Tests proving assigned-map deletion is blocked in v1.

### 4. Compile Step Order Into Engine-Safe Phrase Buffers

Thread the durable model into immutable playback data before touching the hot
tick path.

Work:

- Resolve each phrase assignment's map ID during snapshot compilation.
- Store `nil` or equivalent for sequential playback.
- Store an immutable 16-entry value for a valid assigned and enabled phrase.
- Preserve phrase-level semantics even if the local storage lands on
  per-track buffers: every playable track in the phrase gets the same active
  map, and no per-track v1 control appears.
- Invalidate the affected phrase buffer when the assigned map ID changes,
  saved enabled state changes, assigned map values change, an assigned map is
  deleted, or a map becomes invalid.
- Keep live document traversal, SwiftUI state access, dynamic validation, and
  map-ID lookup out of the playback tick path.

Verification:

- Compiler tests for enabled, disabled, unassigned, missing, invalid, deleted,
  and unsupported assignments.
- Incremental invalidation tests for assignment, enabled-state, map-value,
  deletion, and invalidation changes.
- Thread-safety/regression coverage that tick resolution reads immutable
  compiled data only.

### 5. Apply Non-Destructive Playback Source-Step Remapping

Insert the actual remap at the accepted playback boundary, after the output
step is known and before source/pattern material is read.

Work:

- Keep the original `stepInPhrase` as the output clock position.
- Compute the source step conceptually as:

  ```swift
  let sourceStep = stepOrderMap?[outputStep] ?? outputStep
  ```

- Use the source step for note/source/pattern playback reads.
- Keep phrase-layer timing, including mute, fill, macro lanes, and phrase
  automation, anchored to the output step.
- Ensure inactive, unavailable, or unsupported Step Order follows the existing
  sequential path.
- Avoid mutating clips, generators, pattern slots, phrase cells, phrase layers,
  scenes, selected phrase state, or transport position.

Verification:

- Playback tests proving the accepted fixture map resolves the first 16 output
  steps to the expected source-step indexes for every playable track in the
  phrase.
- Tests proving disabled Step Order restores sequential playback.
- Regression tests proving phrases/tracks without active Step Order behave as
  they did before.
- Non-mutation tests for clips, generated sources, pattern slots, phrase
  cells, phrase layers, scenes, transport, and unrelated phrases/tracks.

### 6. Add Runtime Pending Toggle State And Commands

Implement live enable/disable behavior as explicit runtime/session state.

Work:

- Add command-style ingress equivalent to requesting Step Order enabled or
  disabled for a phrase.
- While playback is running, record a runtime-only pending request containing
  phrase ID and requested enabled value.
- Keep current playback on the existing effective state until the phrase
  boundary.
- At the phrase boundary, apply the requested value, update the effective
  compiled state through the chosen snapshot/session path, and publish applied
  state so the UI clears pending.
- While stopped, update the effective saved enabled state immediately without
  showing a boundary-pending state.
- Clear or resolve pending requests safely if the assigned map becomes missing,
  deleted, invalid, unassigned, or unsupported before application.

Verification:

- Engine/session tests for Off, On, Pending On, Pending Off, boundary
  application, stopped-toggle behavior, and race ordering near phrase
  boundaries.
- Tests proving pending state is runtime-only, not undoable, not redoable, and
  not persisted.
- Tests proving pending state for one phrase does not corrupt unrelated
  phrases.

### 7. Build The Picker, Editor, Assignment, And Toggle Surface

Implement the accepted wireframe workflow with the spec's closed gaps.

Work:

- Add a named map picker/list with create, rename, edit, assign, usage count,
  and delete-when-unused actions.
- Let the selected named map be assigned to the current phrase from the picker
  without leaving the Step Order workflow.
- Make the active-map control in the editor open the picker or switch the
  current phrase assignment.
- Build the two-row 16-cell editor: select output step, choose source step,
  update the map value, auto-advance, and show a visible wrap/end indication
  after step 15.
- Default new maps to identity and provide reset to identity.
- Label identity maps as pass-through or no remap.
- Show `Phrase` as the fixed v1 scope; do not expose Project, Layer,
  Phrase/Track, or per-track controls as editable production controls.
- Show Off, On, Pending On, Pending Off, unavailable, unassigned, invalid, and
  deletion-blocked states.
- Provide keyboard focus, selection state, labels, and accessibility text that
  do not depend only on color or animation.

Verification:

- View-model or UI tests for picker create/rename/edit/assign/delete-blocked
  states.
- UI/view-model tests for active-map switching, identity labeling, reset,
  fixed phrase scope, unavailable state, and pending toggle rendering.
- Accessibility/focus checks for the 16-cell grid and picker controls.

### 8. Capture Built-Surface Evidence

After implementation, verify the real app surface rather than relying on the
accepted wireframe alone.

Manual or visual evidence should cover:

- creating, naming, editing, resetting, and deleting an unused map;
- assigning a map to the current phrase from the picker;
- switching the active phrase assignment from the editor control;
- assigned-map usage blocking deletion with visible reason;
- fixed `Phrase` scope with no editable per-track v1 controls;
- identity/pass-through labeling;
- output/source grid editing, auto-advance, and end-of-map wrap signal;
- running-playback toggle showing Pending On or Pending Off and clearing at the
  phrase boundary;
- stopped toggle applying immediately without pending state;
- non-16-step or invalid assignment showing unavailable state;
- audible remap and return to sequential playback without changing authored
  clip or phrase data.

Use actual built app screenshots or equivalent visual evidence in the build
loop. Retain `prototypes/step-order-wireframe.html` as PM intent only.

## Verification Sequence

Run verification in this order:

1. Model, validation, Codable, dirty-state, and non-persistence tests.
2. Snapshot compiler and invalidation tests for all assignment states.
3. Playback source-step resolution and sequential-restoration tests.
4. Runtime pending-toggle command, boundary, stopped, and invalidation tests.
5. UI/view-model tests for picker, editor, assignment, fixed phrase scope,
   identity, unavailable, deletion-blocked, and pending states.
6. Regression tests proving clips, generators, pattern slots, phrase cells,
   phrase-layer timing, scenes, transport, unrelated phrases, and unrelated
   tracks are not mutated or behaviorally changed.
7. The full Swift/package/app test command normally used by the build loop.
8. Built-surface manual or visual evidence for the workflow states listed
   above.

If a full suite is too slow or blocked in the build worktree, the builder
should record the blocker and provide the focused automated tests plus the
built-surface evidence that did run.

## Handoff Risks

- The existing-state report's earlier phrase+track recommendation is
  superseded by accepted architecture and spec. V1 must stay phrase-only.
- The largest architecture risk is applying the remap too early and
  accidentally remapping phrase-layer timing. V1 remaps source-step playback
  only; mute, fill, macro, and phrase automation remain output-step based.
- The tick path must read immutable compiled data only. SwiftUI state, live
  document traversal, map-ID lookup, and dynamic array validation do not belong
  on the playback callback.
- Pending toggle state is easy to model as document state by accident. It is
  runtime-only and must not dirty, persist, undo, redo, export, or restore.
- Non-16-step phrases need an explicit unavailable/blocking behavior. Hidden
  modulo behavior would violate the accepted fixed-16 v1 contract.
- Deleting assigned maps is blocked in v1. A builder should not invent an
  unapproved reassignment or cascade-delete flow.
- UI completion depends on assignment and active-map switching paths, not just
  a map editor. The UX review identified assignment as the largest prototype
  gap.

## Out Of Scope For This Build

- Editable per-track Step Order controls or opt-in/out.
- Project-wide Step Order toggles or automatic application across all phrases.
- Layer-level Step Order automation.
- Variable-length maps or modulo behavior for arbitrary phrase lengths.
- Stacked maps or transformations that add notes.
- Sharing data structures or controls with Note Repeat.
- Mutating clips, generators, pattern slots, phrase cells, or phrase-layer
  automation from Step Order playback.
- Writing `implementation-handoff.md`; that remains the next PM artifact.

## Promotion Dependency

This plan closes the bounded implementation-sequence gap. The PM lane still
needs accepted `implementation-handoff.md` before it is ready for build-loop
promotion.
