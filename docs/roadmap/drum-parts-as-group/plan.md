---
status: drafted
stage: plan
updated: 2026-06-05
source_artifacts:
  - README.md
  - docs/roadmap/drum-parts-as-group/architecture.md
  - docs/roadmap/drum-parts-as-group/spec.md
  - docs/roadmap/drum-parts-as-group/user-stories.md
  - docs/roadmap/drum-parts-as-group/ux-review.md
  - docs/roadmap/drum-parts-as-group/existing-state.md
  - docs/roadmap/drum-parts-as-group/prototypes/01-part-workspace-header.html
  - docs/roadmap/drum-parts-as-group/prototypes/02-kit-step-matrix.html
  - docs/roadmap/drum-parts-as-group/prototypes/03-group-routing-editor.html
---

# Drum Parts As A Group Plan

## Purpose

Implement Drum Parts As A Group as kit-level coordination around the existing
drum-part model. A kit remains an ordered `TrackGroup` of independent
`StepSequenceTrack` members. V1 adds navigation, visibility, routing, mapping,
and playback behavior without introducing a drum-specific track type or a
kit-level pattern abstraction.

This plan is builder-facing. It breaks the feature into bounded phases with
implementation seams, verification points, and review gates. It does not
promote a build loop or replace a later `implementation-handoff.md`.

## Settled V1 Contract

Builders should preserve these decisions from architecture and spec:

- Drum parts remain independent `StepSequenceTrack` values grouped by
  `TrackGroup`.
- `TrackGroup.memberIDs` is the canonical order for header navigation, matrix
  rows, routing rows, and default channel seeding.
- `TrackGroup.triggerMappingMode` is persisted with a safe `.perNote` decode
  default for older documents.
- `noteMapping` and `channelMapping` are separate persisted maps. Switching
  modes does not delete hidden assignments.
- `noteMapping` stores offsets from `DrumKitNoteMap.baselineNote`; UI displays
  DAW note names where MIDI `60` is `C4` and baseline MIDI `36` is `C2`.
- `channelMapping` stores zero-based MIDI channels while the UI presents
  channels `1...16`.
- Group destination edits reuse existing group destination write-target
  plumbing.
- The kit matrix is pushed from the part workspace. It is not a transient
  quick-look overlay in v1.
- Matrix cells are read-legible only. Tapping cells does not toggle steps.
- Tapping a matrix row navigates to that part's normal workspace.
- The routing editor is a standalone post-creation sheet or panel. It may reuse
  destination picker pieces, but it is not `AddDrumGroupSheet`.
- Duplicate per-channel assignments are allowed with non-blocking warnings.
- Matrix behavior is bounded to 32-step display in v1. Longer patterns must
  show a supported-span or overflow treatment and route editing to the part
  workspace.
- Future kit-pattern selection is a non-goal for v1.

## Phase 1: Model, Persistence, And Normalization

### Target Seams

- `Sources/Document/TrackGroup.swift`
- `Sources/Document/Project+DrumGroups.swift`
- `Sources/Document/Project.swift` or the project synchronization site that
  owns `syncPhrasesWithTracks()`
- Existing model tests around `TrackGroup` and drum-group creation

### Work

- Add `DrumTriggerMappingMode` with `.perNote`, `.perChannel`, and
  `.individual`.
- Add persisted `triggerMappingMode` and `channelMapping` fields to
  `TrackGroup`.
- Decode older documents as `.perNote` with empty `channelMapping`.
- Normalize both `noteMapping` and `channelMapping` to current `memberIDs`
  during project synchronization.
- Seed shared MIDI kit defaults at creation:
  - `noteMapping[memberID] = absoluteMIDINote - DrumKitNoteMap.baselineNote`
    from each member's voice tag where available.
  - `channelMapping[memberID]` follows `memberIDs` order and wraps or clamps
    into `0...15`.
- Preserve existing sample/internal kit behavior when no shared MIDI
  destination exists.

### Verification

- `TrackGroup` Codable round-trip includes `triggerMappingMode`, `noteMapping`,
  and `channelMapping`.
- Older document decode covers missing `triggerMappingMode` and
  `channelMapping`.
- Synchronization removes stale note/channel mapping entries and avoids
  duplicate visible members.
- Drum-group creation tests prove shared MIDI kits seed defaults and
  sample-backed kits keep current behavior.

### Review Gate

Review this phase before UI work if possible. The model contract is the
foundation for routing, playback, and view state, and mistakes here create
document compatibility risk.

## Phase 2: Mutations, Destination Writes, And Playback Resolution

### Target Seams

- `Sources/Document/Project+Destinations.swift`
- `Sources/Document/SequencerDocumentSession+Mutations.swift`
- Existing destination write-target plumbing around
  `Project.DestinationWriteTarget`
- `EngineController.effectiveDestination(for:in:)` or the equivalent store
  destination resolver
- Engine/store destination tests

### Work

- Add project/session mutations for:
  - setting group shared destination;
  - toggling a member between inherited group destination and own destination;
  - setting `triggerMappingMode`;
  - setting one member's note offset;
  - setting one member's MIDI channel;
  - applying a full routing-editor draft atomically.
- Route group shared destination writes through existing group destination
  write-target behavior so engine apply and macro syncing remain consistent.
- Extend inherited playback resolution by mode:
  - `.perNote`: inherited members use shared destination port/channel plus
    member note offset.
  - `.perChannel`: inherited MIDI members use shared MIDI destination port plus
    member channel; note offset is `0` in v1.
  - `.individual`: members use own destinations; no special engine branch
    should be needed beyond respecting destination values.
- Fail safe when incompatible persisted data is loaded, especially per-channel
  mode with no MIDI shared destination.

### Verification

- Mutation tests cover group destination edits, inherit/own transitions,
  mapping mode changes, note offsets, channel assignment, and atomic draft
  apply.
- Playback/store tests cover `.perNote`, `.perChannel`, `.individual`, missing
  mappings, own-destination overrides, nil shared destination, and non-MIDI
  shared destination fail-safe behavior.
- Confirm mapping-only changes refresh project/store structure without
  unnecessary AU host rebuild work.

### Review Gate

Review engine/store behavior before the routing editor is wired to it. The UI
must not compensate for ambiguous playback semantics.

## Phase 3: Routing Editor Domain, Validation, And Draft Apply

### Target Seams

- New routing editor draft/view-model type near drum-group UI or document UI
  support code
- New note-name parser/formatter helper, colocated with musical mapping code
  if a suitable package boundary exists
- Destination picker/editor components that can be reused without coupling to
  `AddDrumGroupSheet`
- Focused routing editor tests

### Work

- Build a standalone post-creation routing editor draft with Cancel and Apply.
- Represent:
  - group shared destination;
  - trigger mapping mode;
  - ordered member rows;
  - inherit-group versus own-destination state;
  - per-note assignments;
  - per-channel assignments;
  - disabled or override treatment for members using own destinations.
- Implement DAW note naming:
  - display canonical sharp names such as `C2`, `C#2`, `D2`;
  - accept letters `A...G`, case-insensitive;
  - accept `#` and `b`;
  - accept signed octave values needed for MIDI `0...127`;
  - reject raw numeric MIDI-note input in v1;
  - commit offsets relative to `DrumKitNoteMap.baselineNote`.
- Validate channels as UI values `1...16`, stored as `0...15`.
- Block Apply for invalid note input, impossible individual routing, and
  per-channel mode without a MIDI shared destination.
- Show non-blocking duplicate-channel warnings for inherited members sharing
  a channel.
- Preserve both note and channel maps when switching modes.

### Verification

- Unit tests cover note parsing, canonical display, flats normalization,
  lowercase input, signed octaves, range bounds, empty/partial values, and
  numeric-note rejection.
- View-model tests cover Cancel discard, atomic Apply, mode switching without
  data loss, own-destination disabled mapping controls, duplicate channel
  warnings, and non-MIDI destination blocking.
- Manual or visual evidence covers per-note, per-channel, individual, invalid
  note, duplicate-channel warning, and non-MIDI destination validation states.

### Review Gate

Review this phase against prototype `03-group-routing-editor.html` and the
spec before connecting it to the kit matrix. Pay attention to data-loss paths
and validation copy.

## Phase 4: Part Workspace Header And Sibling Navigation

### Target Seams

- `Sources/UI/Track/TrackWorkspaceView.swift`
- Track selection/navigation state used by the workspace
- Store helpers for resolving a selected track's group and siblings
- Focused UI/view-model tests where available

### Work

- Make the track workspace kit-aware when the selected track has a resolved
  `groupID`.
- Add the header band from prototype `01-part-workspace-header.html`:
  - previous and next controls;
  - current part name with existing rename affordance preserved;
  - `N of M` position;
  - kit name and color identity;
  - `Open Kit View` action.
- Derive previous/next from `TrackGroup.memberIDs`.
- Keep navigation bounded at the first and last parts.
- Keep navigation available for generator-backed or read-only members.
- Preserve existing non-kit track workspace behavior.
- Opening kit view pushes a matrix destination while retaining the originating
  part ID for Back behavior.

### Verification

- Tests or manual evidence cover first, middle, last, one-member, long-name,
  generator/read-only, stale group, and non-kit states.
- Verify previous/next never wraps in v1 and does not reorder by track list or
  display name.
- Verify returning from the matrix restores the originating part workspace.

### Review Gate

Review header screenshots before matrix implementation is treated as complete.
The header is the entry point to the rest of the workflow and must preserve the
existing part editor's editing affordances.

## Phase 5: Pushed Kit Matrix

### Target Seams

- New `DrumKitMatrixView`
- Workspace/navigation destination state for pushed matrix routing
- Store helpers for ordered group members and active pattern slots
- Step-pattern preview/read-model helpers

### Work

- Build a pushed kit matrix destination from the selected part header.
- Display rows in `TrackGroup.memberIDs` order.
- Keep part names and active pattern badges fixed and visible.
- Show read-legible cells for representable active patterns.
- Show generator/read-only indicators when inline step representation is
  limited.
- Do not mutate steps from matrix cells.
- Navigate to a member's normal workspace when its row is tapped.
- Show compact, factual pattern coherence warnings:
  - no warning when visible rows share the same active pattern slot;
  - amber warning banner and divergent badge treatment when slots differ.
- Default to 16-step display and support bounded 32-step display. If width
  makes 32-step cells illegible, only the step-cell region may scroll; the
  part-name region must remain visible.
- Launch the standalone routing editor from the matrix.

### Verification

- Tests or manual evidence cover member ordering, active pattern badges,
  coherent and mixed-pattern states, row-tap navigation, read-only cell
  behavior, generator rows, 16-step display, 32-step display, long kit/part
  names, zero-member groups, and stale member IDs.
- Confirm cells do not toggle steps and do not imply a kit-pattern model.
- Confirm Back behavior from matrix to originating part and routing editor to
  matrix.

### Review Gate

Run a UX/visual review against prototypes
`01-part-workspace-header.html` and `02-kit-step-matrix.html`. Use the accepted
fixture shape: long kit name, six parts, mixed pattern slots, at least one
generator/read-only row, and at least one own destination override.

## Phase 6: Integration, Evidence, And Readiness Review

### Target Seams

- End-to-end app workflow from part workspace to matrix to routing editor
- Document save/load path
- Engine/store playback path
- Focused test suite and visual evidence scripts where relevant

### Work

- Exercise the complete flow:
  - select drum part;
  - navigate siblings;
  - push kit matrix;
  - inspect pattern divergence;
  - tap a row to part workspace;
  - return to matrix;
  - open routing editor;
  - apply destination and mapping changes;
  - save/reload;
  - confirm playback/store resolution.
- Capture visual evidence for the states required by the spec.
- Confirm model changes do not disturb unrelated melodic, slicer, phrase,
  scene, or mixer behavior.
- Update feature evidence with test commands, screenshots, known residual
  risks, and deviations from the plan.

### Verification

- Focused model/document tests pass.
- Focused engine/store tests pass.
- Focused UI/view-model tests pass where available.
- Manual or automated visual evidence covers header, matrix, and routing
  editor states.
- Save/load smoke evidence proves persisted mapping state survives reload.

### Review Gate

Complete a spec-compliance review and code-quality review before any
integration decision. If those pass, run adversarial review before merge
consideration.

## Handoff Dependencies

- `implementation-handoff.md` should be authored after this plan and before
  build-loop promotion. It should identify the exact branch/worktree, first
  builder slice, review expectations, and evidence paths.
- Builders need access to the accepted prototypes and should use them as UX
  evidence, not as production styling source.
- If implementation discovers that current navigation state cannot support a
  pushed matrix without broad unrelated refactor, record that as build-loop
  evidence. Do not quietly downgrade to a transient overlay, because push
  navigation is part of the v1 contract.
- If routing-editor reuse of destination picker components forces coupling to
  creation-time `AddDrumGroupSheet`, prefer a small reusable destination picker
  seam over reusing the creation sheet as the editor.

## Non-Goals

- No new drum-specific track type.
- No kit-level pattern object, kit pattern selector, or group pattern bank.
- No inline step editing in the matrix.
- No matrix editing for generator internals, layered clips, probability rules,
  or phrase-layer rules.
- No new per-member mute/solo model.
- No changes to unrelated phrase, scene, mixer, slicer, or melodic-track
  grammar.
- No broad visual redesign outside the header, matrix, and routing editor
  surfaces required by this feature.

## Remaining Readiness Gaps

- `implementation-handoff.md` is still missing.
- Build-loop promotion is premature until the handoff identifies the first
  bounded builder request and target evidence path.
- No product-owner decision is currently required. The architecture and spec
  already settle the owner-adjacent v1 choices in a conservative direction.
