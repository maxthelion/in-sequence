---
feature: step-order
created: 2026-06-06
status: spec-ready-for-plan
sources:
  - docs/roadmap/step-order/open-questions.md
  - docs/roadmap/step-order/architecture.md
  - docs/roadmap/step-order/user-stories.md
  - docs/roadmap/step-order/existing-state.md
  - docs/roadmap/step-order/ux-review.md
  - docs/roadmap/step-order/prototypes/step-order-wireframe.html
---

# Step Order Spec

## Product Shape

Step Order v1 is a phrase-scoped playback-order performance override. A
producer creates a named 16-step map, assigns it to a phrase, and enables that
phrase's Step Order state. During playback, the output phrase step remains the
clock position, but note/source playback reads a source step through the active
map.

Step Order is non-destructive. It changes how existing material is read during
playback; it does not rewrite clips, generated source definitions, pattern
slots, phrase cells, phrase-layer timing, scenes, or transport state.

## Accepted V1 Defaults

- One named Step Order map can be assigned to a phrase.
- The assigned map applies to all playable tracks in that phrase when enabled.
- Maps live in a top-level project pool with stable IDs and names.
- Maps are exactly 16 entries, and every entry is a source step in `0...15`.
- Existing projects decode with an empty map pool and no phrase assignments.
- The assigned map and saved enabled state persist as phrase settings.
- Live pending toggle state is runtime-only and is not persisted.
- Toggling during playback applies at the next phrase boundary.
- Toggling while stopped updates the effective phrase state immediately.
- Per-track, project-wide, layer-level, variable-length, and stacked behavior
  are deferred.

## In Scope

- Project-level storage for named Step Order maps.
- Phrase-level storage for optional map assignment and saved enabled state.
- Save/load round-trip for the map pool and phrase assignments.
- Map picker/list workflow for create, rename, edit, assign, and delete when
  unused.
- Two-row 16-cell editor for output-step to source-step assignment.
- Identity/pass-through map labeling and reset to identity.
- Fixed phrase-level scope labeling.
- On, Off, Pending On, Pending Off, and unavailable UI states.
- Engine-safe snapshot compilation of active maps.
- Playback source-step remapping before source/pattern data is read.
- Snapshot invalidation for map edits, assignment changes, enabled-state
  changes, deletion, and invalidation.
- Focused regression coverage for non-mutation, playback resolution,
  persistence, pending state, and invalid data.

## Out Of Scope

- Editable per-track Step Order controls.
- Project-wide Step Order toggle or automatic application across all phrases.
- Layer-level Step Order automation.
- Variable-length maps or modulo behavior for non-16-step phrases.
- Stacked maps or transformations that add notes.
- Sharing data structures or controls with Note Repeat.
- Mutating clips, generators, pattern slots, phrase cells, or phrase-layer
  automation from Step Order playback.
- Build sequencing, implementation ownership, or worktree promotion.

## Acceptance Criteria

### Model And Persistence

AC-M1: The document model stores a top-level Step Order map pool. Each map has
a stable ID, a user-visible name, and exactly 16 source-step values.

AC-M2: Each map value is constrained to `0...15`. UI editing, model mutation,
decoding, and snapshot compilation must not allow out-of-range values into an
active compiled playback map.

AC-M3: Each phrase can store at most one optional Step Order assignment. The
assignment stores a map ID and saved enabled state.

AC-M4: Existing projects without Step Order data decode to an empty map pool,
no phrase assignments, and sequential playback.

AC-M5: Saving and reopening a project preserves map IDs, names, 16 values,
phrase assignments, and saved enabled states.

AC-M6: Changing a map, assigning a map, renaming a map, deleting an unused map,
or changing the saved enabled state marks the document dirty through normal
document-editing behavior.

AC-M7: Runtime pending toggle state is not persisted, exported, restored, or
undoable.

### Validation And Unsupported Data

AC-V1: A map with fewer or more than 16 entries is invalid for v1 and cannot be
edited into the saved model through the production UI.

AC-V2: If invalid saved data is encountered, project load must not crash.
Invalid maps are excluded from compiled playback, and affected phrase
assignments resolve as unavailable/sequential until the user repairs or
reassigns them.

AC-V3: If a phrase is not compatible with 16-step Step Order playback in v1,
the UI prevents assignment or enabling and shows an unavailable state tied to
the phrase. The compiler must not silently modulo arbitrary phrase lengths into
the 16-step map.

AC-V4: Missing map IDs, deleted maps, invalid maps, and invalid assignment data
compile to sequential playback for the affected phrase and produce visible
unavailable or unassigned UI state.

AC-V5: Deleting a map that is assigned to any phrase is blocked in v1. The map
picker shows enough usage information for the user to understand why deletion
is unavailable.

### Map Picker And Editor

AC-U1: The Step Order workflow exposes a named map list or picker with create,
rename, edit, assign, and delete-when-unused actions.

AC-U2: The map picker shows which map is assigned to the current phrase and
allows assigning a selected map to that phrase without leaving the Step Order
workflow.

AC-U3: The active-map control in the editor opens the picker or otherwise lets
the user switch the current phrase assignment.

AC-U4: The editor uses the accepted two-row interaction: select an output step,
then choose the source step that output step should read.

AC-U5: Editing a cell updates the map value for the selected output step,
auto-advances to the next output step, and gives a visible wrap/end indication
when output step 15 has been edited.

AC-U6: New maps default to identity
`[0,1,2,3,4,5,6,7,8,9,10,11,12,13,14,15]` unless the implementation adds only
equally valid 16-entry presets accepted by the plan.

AC-U7: Identity maps are labeled as pass-through or no remap so the user can
distinguish an enabled identity map from an intentional variation.

AC-U8: Resetting a map to identity is available and does not create an
unsupported empty-map state.

AC-U9: The UI presents `Phrase` as the fixed v1 scope. It does not expose
Project, Layer, Phrase/Track, or per-track scope as editable production
controls.

AC-U10: Keyboard focus, selection state, labels, and accessibility text make
the map grid and picker usable without relying only on color or animation.

### Toggle And Pending State

AC-T1: A phrase with a valid assigned map exposes a Step Order toggle with
visible Off and On states.

AC-T2: Toggling while playback is running sends a command to request the new
enabled value for the current phrase. Current playback continues with the
existing effective state until the phrase boundary.

AC-T3: After a running-playback toggle request, the UI immediately shows
Pending On or Pending Off for the affected phrase.

AC-T4: At the next phrase boundary, the pending value becomes effective, the
compiled playback path uses the new effective state, and the UI clears the
pending state.

AC-T5: Toggling while stopped updates the phrase's effective saved enabled
state immediately and does not show a boundary-pending state.

AC-T6: Pending state is explicit engine/session state that includes the phrase
ID and requested enabled value. SwiftUI must not infer pending state by polling
map arrays or comparing compiled snapshot contents.

AC-T7: If the assigned map becomes invalid, missing, or deleted while a pending
request exists, the pending request is cleared or resolved to unavailable
sequential playback without crashing.

### Snapshot Compilation

AC-C1: Snapshot compilation resolves the phrase assignment's map ID to an
immutable engine-safe 16-entry value before playback tick resolution.

AC-C2: A valid assigned and enabled phrase compiles to a non-`nil` Step Order
map, or equivalent active immutable value, for that phrase.

AC-C3: Disabled, unassigned, missing, invalid, or unsupported phrase states
compile to sequential playback for that phrase.

AC-C4: The playback tick path does not traverse the live document model, query
SwiftUI state, perform map-ID lookup, or validate dynamic arrays.

AC-C5: Snapshot invalidation recompiles the affected phrase buffer when the
assigned map ID changes, the saved enabled state changes, assigned map values
change, an assigned map is deleted, or an assigned map becomes invalid.

AC-C6: If the implementation stores compiled Step Order data on per-track
buffers, all playable tracks in the phrase still receive the same active map
and the UI still exposes phrase-only v1 scope.

### Playback Resolution

AC-P1: For an active map, playback resolves source steps conceptually as
`sourceStep = map[outputStep]` before reading source/pattern note data.

AC-P2: For inactive or unavailable Step Order, playback resolves source steps
sequentially as it does today.

AC-P3: The output step remains the phrase clock position. Phrase-layer timing
for mute, fill, macro lanes, and other phrase automation remains anchored to
the output step in v1.

AC-P4: Step Order remapping affects note/source playback reads only. It must
not mutate clips, generated source definitions, pattern slot cells, phrase
cells, phrase-layer data, scenes, selected phrase state, or transport position.

AC-P5: The map
`[0,1,2,3,3,3,3,3,7,8,9,0,1,2,3,3]` resolves the first 16 output steps to
those exact source-step indexes for every playable track in the enabled phrase.

AC-P6: Disabling Step Order restores sequential source-step playback at the
next phrase boundary during playback, or immediately while stopped.

AC-P7: Normal playback behavior for phrases without active Step Order is
unchanged, including phrase advancement, pattern-slot selection, probability
resolution, fill/main lane evaluation, macro timing, and output timing.

## Edge Cases

### Identity Map Enabled

An enabled identity map is valid but musically pass-through. The UI should show
both that Step Order is enabled and that the selected map is identity/no remap.

### No Assigned Map

No assignment means Step Order is unavailable/off for the phrase. The toggle
must not imply that an unnamed or implicit map exists.

### Assigned Map Deleted

Assigned-map deletion is blocked in v1. If corrupted or migrated data leaves a
phrase pointing at a missing map, playback is sequential and the UI shows an
unavailable or missing-assignment state.

### Non-16-Step Phrase

V1 does not support applying a 16-step map to arbitrary phrase lengths. The UI
prevents assignment or enabling for unsupported phrase lengths, and the
compiler treats any pre-existing unsupported assignment as inactive/sequential.

### Map Edit During Playback

Editing an assigned enabled map is a document edit. The affected phrase buffer
is invalidated and rebuilt through the existing snapshot path. The tick path
must continue to read an immutable compiled value and must not observe a
partially edited array.

### Phrase Boundary Race

If a toggle request and phrase boundary occur close together, the engine/session
state owns the ordering. The UI may briefly show pending, but the final
effective state must match the applied engine/session state and no duplicate
toggle application should occur.

## Verification Requirements

### Automated Checks

The build should include focused automated coverage for:

- project decode defaults for empty map pools and no assignments;
- save/load round-trip for map pool, names, IDs, values, assignments, and saved
  enabled state;
- rejection or safe recovery for wrong-length, out-of-range, missing-map, and
  non-16-step phrase cases;
- dirty-state behavior for map edits, assignment changes, and enabled-state
  changes;
- no persistence or undo behavior for runtime pending state;
- compiler output for enabled, disabled, unassigned, missing, invalid, and
  unsupported phrase states;
- snapshot invalidation for map edits, assignment changes, enabled-state
  changes, map deletion, and invalidation;
- playback source-step resolution for
  `[0,1,2,3,3,3,3,3,7,8,9,0,1,2,3,3]`;
- disabling Step Order restoring sequential playback;
- phrase-layer timing remaining output-step based;
- no mutation of clips, generated sources, pattern slots, phrase cells, phrase
  layers, scenes, or transport state from Step Order playback;
- pending On/Pending Off state publication and phrase-boundary application;
- stopped-transport toggle behavior without pending boundary state.

### Manual Or Visual Checks

Verification should also exercise the built surface:

- create, name, edit, reset, and delete an unused map;
- assign a map to the current phrase from the picker and active-map control;
- confirm an assigned map's usage blocks deletion;
- confirm the fixed `Phrase` scope is visible and no per-track v1 controls are
  editable;
- confirm identity/pass-through labeling;
- confirm output/source grid editing, auto-advance, and end-of-map wrap signal;
- toggle while playback is running and confirm Pending On/Pending Off clears at
  phrase boundary;
- toggle while stopped and confirm immediate effective state;
- confirm non-16-step or invalid assignments show unavailable state;
- confirm audible remap and return to sequential playback without changing
  authored clip or phrase data.

Visual evidence should use the actual built app surface after implementation,
with the accepted wireframe retained only as PM intent.

## Required Build Evidence

A future build loop should provide evidence for:

- model and codable tests for map pool and phrase assignments;
- compiler tests for active, inactive, invalid, deleted, and unsupported
  assignment states;
- playback tests proving source-step remapping and sequential restoration;
- engine/session tests for running and stopped toggle behavior;
- UI or view-model tests for picker/editor/assignment/toggle states;
- visual evidence for map editing, assignment, phrase-only scope,
  identity/pass-through, pending toggle, deletion-blocked, and unavailable
  states;
- regression evidence that clips, generators, pattern slots, phrase cells,
  phrase-layer timing, scenes, transport, and unrelated phrases/tracks are not
  mutated or behaviorally changed.

## Readiness

This spec is ready to feed a PM `plan.md` pass. It is not an implementation
handoff and does not promote Step Order to a build loop by itself.
