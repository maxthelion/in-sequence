---
status: drafted
stage: architecture
updated: 2026-06-05
source_artifacts:
  - README.md
  - docs/roadmap/drum-parts-as-group/README.md
  - docs/roadmap/drum-parts-as-group/user-stories.md
  - docs/roadmap/drum-parts-as-group/existing-state.md
  - docs/roadmap/drum-parts-as-group/ux-review.md
  - docs/roadmap/drum-parts-as-group/prototypes/01-part-workspace-header.html
  - docs/roadmap/drum-parts-as-group/prototypes/02-kit-step-matrix.html
  - docs/roadmap/drum-parts-as-group/prototypes/03-group-routing-editor.html
---

# Drum Parts As A Group Architecture

## Purpose

Drum Parts As A Group turns an existing drum `TrackGroup` from a mostly
creation-time model into an editing surface that makes the kit feel coherent:
producers can move between sibling parts, open a full-kit step matrix, see
pattern divergence honestly, and edit shared routing and trigger mapping in one
place.

The architecture should preserve the current model truth: a kit is an ordered
group of independent `StepSequenceTrack` parts. Parts keep their own pattern
banks, destinations, generators, layers, clips, and focused editors. This
feature adds kit-level coordination and visibility; it does not create a new
drum-track type or a kit-pattern abstraction in v1.

## Architectural Decisions

- Keep `StepSequenceTrack` as the part model. A drum part remains a normal
  `.monoMelodic` track with `groupID`.
- Treat `TrackGroup.memberIDs` as the canonical part order for sibling
  navigation and matrix row order.
- Add persisted trigger-mapping state to `TrackGroup` rather than deriving mode
  from dictionary shape.
- Keep pitch mapping and channel mapping as separate concepts. Existing
  `noteMapping` remains pitch-offset data; per-member channel assignment needs
  its own field.
- Reuse existing destination write-target plumbing for group shared
  destination edits.
- Build a dedicated `DrumKitMatrixView` and a standalone post-creation routing
  editor. Reuse destination picker/editor pieces where practical, but do not
  stretch `AddDrumGroupSheet` into an edit surface.
- Use push-style navigation for the kit matrix as the v1 contract. The matrix
  is a workflow destination, not a transient quick-look overlay.
- Keep matrix step cells read-legible in v1. Row taps navigate to the part
  workspace for editing rather than toggling steps inline.

## Model Contract

### `TrackGroup`

Extend `TrackGroup` with explicit mapping state:

```swift
enum DrumTriggerMappingMode: String, Codable, Equatable, Sendable {
    case perNote
    case perChannel
    case individual
}

struct TrackGroup {
    var triggerMappingMode: DrumTriggerMappingMode
    var channelMapping: [UUID: UInt8]
}
```

`triggerMappingMode` is persisted because the UI and playback semantics must
remain stable even when mapping dictionaries are empty, partially filled, or
temporarily invalid during editing. Deriving mode from `noteMapping` cannot
represent per-channel mode, individual mode, or a newly created kit with default
assignments.

`channelMapping` stores zero-based MIDI channels to match `Destination.midi`
channel storage. The UI presents channels as 1-16.

Existing `noteMapping: [UUID: Int]` remains semitone offset from
`DrumKitNoteMap.baselineNote` rather than changing to absolute MIDI note
numbers. The routing editor may show names such as `C2`, but writes convert
them to offsets before mutation.

Decode defaults:

- `triggerMappingMode`: `.perNote`
- `channelMapping`: `[:]`
- `noteMapping`: existing default `[:]`

Normalization must filter both `noteMapping` and `channelMapping` to current
`memberIDs` in `Project.syncPhrasesWithTracks()`.

### Default Mapping Values

Creation should seed useful defaults without changing the meaning of existing
audio/sample kits:

- For shared MIDI destinations, initialize `noteMapping` from each
  `DrumGroupPlan.Member.tag` via `DrumKitNoteMap`, stored as
  `absoluteMIDINote - DrumKitNoteMap.baselineNote`.
- For non-MIDI sample/internal destinations, leaving `noteMapping` empty is
  acceptable because the current sample-backed kit path already pitches each
  part through its own destination.
- Initialize `channelMapping` in member order, clamped/wrapped across MIDI
  channels `0...15`. The spec can choose whether duplicate channel assignments
  are allowed, but the model must be able to store them.

Existing documents decode as `.perNote` with empty mappings. That is safe
because current playback already treats missing note offsets as `0`.

### Mutation Surface

Add project/session mutations instead of editing arrays directly from views:

- set a group's shared destination;
- set a member to inherit the group destination or use its own destination;
- set `triggerMappingMode`;
- set one member's note offset;
- set one member's MIDI channel;
- apply a routing-editor draft atomically.

Destination edits should continue to flow through `Project.DestinationWriteTarget`
and `SequencerDocumentSession` so that engine-apply behavior and macro syncing
stay consistent with the existing destination editor. Mapping-only changes
should still publish project/store structure changes and refresh playback
snapshots; they should not require an AU host rebuild unless the shared
destination itself changes.

## Playback Contract

The engine already resolves `Destination.inheritGroup` by reading the group's
`sharedDestination` and applying `group.noteMapping[trackID] ?? 0` as a pitch
offset. V1 should extend that path rather than create parallel routing.

Playback behavior by mode:

- `.perNote`: inherited members use the shared destination channel and the
  member's `noteMapping` offset.
- `.perChannel`: inherited MIDI members use the shared destination port and
  per-member `channelMapping`; note offset is `0` unless later spec explicitly
  allows combining channel and note offsets.
- `.individual`: members should use individual destinations. The routing editor
  applies this by changing inheriting members away from `.inheritGroup`; playback
  does not need a special `.individual` branch beyond respecting destinations.

If `.perChannel` is selected while the shared destination is not MIDI, the UI
must prevent apply or show a validation error. The engine should still fail
safe: unresolved or incompatible group routing falls back to existing
destination resolution rather than crashing.

## UI Ownership

### Part Workspace Header

`TrackWorkspaceView` should become kit-aware when the selected track has a
`groupID` that resolves to a `TrackGroup`.

The header band owns:

- previous/next controls based on `TrackGroup.memberIDs`;
- current part name and position in kit;
- kit name and color identity;
- button to open the kit matrix.

Navigation should be bounded at kit edges for v1. The accepted prototype showed
disabled edge arrows, and bounded navigation avoids surprise jumps while users
are making focused edits. The spec may later choose wrap behavior, but builders
should implement bounded controls unless superseded.

### Kit Matrix

Create a dedicated `DrumKitMatrixView` opened from the part workspace. It should
be pushed onto the app's workspace/navigation state and retain the originating
part ID so Back returns to the prior part.

The matrix reads:

- group metadata from `TrackGroup`;
- ordered member tracks from `tracksInGroup(_:)`;
- active pattern slot per member from the existing phrase/pattern layer state;
- step data from each member's active pattern/clip source when it can be
  represented safely.

The matrix displays one row per part with a fixed part-name region, active
pattern badge, read-only step cells, generator/read-only indicators, and a
pattern-coherence warning when visible rows use divergent pattern slots.

Row tap behavior is navigation: tapping a row opens that member's normal part
workspace. It does not mutate the matrix. Back from the part workspace should
return according to the existing navigation stack; the original "return to
previously focused part" behavior is owned by the Back control from the matrix,
not by every row tap.

### Routing Editor

The routing editor is launched from the kit matrix. It owns:

- group shared destination field;
- trigger mapping mode segmented control;
- per-member inherit/own toggle;
- per-member note or channel assignment;
- validation and apply/cancel draft behavior.

The editor should be a standalone post-creation sheet/panel with its own draft
state. It may reuse `AddDestinationSheet` or lower-level destination editor
components for the destination picker. It should not reuse `AddDrumGroupSheet`
as the primary implementation because creation-time member planning and
post-creation routing mutation have different responsibilities.

## Validation Rules

- Note editor accepts canonical note names and absolute MIDI numbers only if
  the spec includes them; internally it must commit an `Int` offset relative to
  `DrumKitNoteMap.baselineNote`.
- Invalid note input blocks Apply and leaves the last valid stored mapping
  intact.
- Channel editor accepts UI values 1-16 and commits zero-based `UInt8` values
  `0...15`.
- Per-channel mode requires a MIDI shared destination.
- Switching mapping mode in the editor must not delete mappings for the mode
  being left. Store note and channel mappings independently so users can switch
  back without data loss.
- A part with an own destination ignores group trigger mapping in playback and
  should show its mapping controls disabled or explicitly marked as not
  applied.

## Non-Goals For V1

- No new drum-specific track type.
- No kit-level pattern object or "kit pattern selector" that stores sets of
  per-part pattern indices.
- No inline step editing from the matrix.
- No matrix editing for generator/layer internals.
- No per-member mute/solo model beyond what already exists on tracks/groups.
- No changes to unrelated phrase, scene, or mixer grammar.

## Tests And Evidence Expectations

Builders should cover:

- `TrackGroup` Codable round-trip with `triggerMappingMode` and
  `channelMapping`, including decode defaults for old documents.
- `Project.syncPhrasesWithTracks()` removes stale mapping entries for removed
  members.
- `addDrumGroup(plan:)` seeds note/channel defaults for shared MIDI kits without
  changing sample-backed kit behavior.
- Project and session mutations for group destination, inherit/own toggle,
  mapping mode, note offset, and channel assignment.
- Engine/store destination resolution for `.perNote` and `.perChannel`.
- Header navigation derives order from `memberIDs` and handles first/last parts.
- Matrix row ordering, pattern badge display, pattern-mismatch warning, and
  generator/read-only row presentation.
- Routing editor validation blocks invalid note/channel input and preserves
  mappings when switching modes.

UX review should include screenshots of the part header, kit matrix, and routing
editor with the accepted adversarial fixture shape: long kit name, six parts,
mixed pattern slots, at least one generator/read-only row, and one own
destination override.

## Remaining Product And Spec Questions

No product-owner lock is required for architecture. The following should be
settled in `spec.md` before implementation handoff:

- Exact note-name grammar and octave convention for the note editor.
- Whether duplicate per-channel assignments are warned, blocked, or allowed.
- Whether 32-step rows compress, page, or horizontally scroll on small widths.
- Exact wording and visual treatment for pattern-coherence warnings.
- Whether a future kit-pattern concept is a separate roadmap item or a later
  extension of this one.
