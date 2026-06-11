---
status: drafted
stage: spec
updated: 2026-06-05
source_artifacts:
  - README.md
  - docs/roadmap/drum-parts-as-group/README.md
  - docs/roadmap/drum-parts-as-group/architecture.md
  - docs/roadmap/drum-parts-as-group/user-stories.md
  - docs/roadmap/drum-parts-as-group/existing-state.md
  - docs/roadmap/drum-parts-as-group/ux-review.md
  - docs/roadmap/drum-parts-as-group/prototypes/01-part-workspace-header.html
  - docs/roadmap/drum-parts-as-group/prototypes/02-kit-step-matrix.html
  - docs/roadmap/drum-parts-as-group/prototypes/03-group-routing-editor.html
---

# Drum Parts As A Group Spec

## Purpose

Drum Parts As A Group gives a producer a coherent kit-level editing workflow
without replacing the current model: each drum part remains an independent
`StepSequenceTrack`, and the kit is the existing ordered `TrackGroup` around
those parts.

V1 adds observable kit coordination:

- sibling navigation from an individual drum-part workspace;
- a pushed kit matrix that shows all member parts and their active patterns;
- read-legible step rows with row-tap navigation back into normal part editing;
- a post-creation routing editor for shared destination and trigger mapping;
- persisted trigger mapping mode with separate per-note and per-channel
  mappings.

V1 does not create a drum-specific track type or a kit-pattern model.

## V1 User Experience

### Part Workspace Header

When the selected track belongs to a drum `TrackGroup`, the track workspace
shows a kit-aware header band above the existing part editor.

The header displays:

- previous and next part controls derived from `TrackGroup.memberIDs`;
- current part name, preserving the existing rename affordance;
- current position as `N of M`;
- kit name and kit color identity;
- an `Open Kit View` action.

Sibling navigation is bounded in v1. The first member disables the previous
control; the last member disables the next control. Navigation still works when
the current part is generator-backed or otherwise read-only.

Opening the kit view pushes a kit matrix destination. Returning from the matrix
returns to the originating part workspace.

### Kit Matrix

The kit matrix is a workflow destination, not a transient quick-look overlay.
It is opened from the part workspace and can launch the routing editor.

The matrix displays rows in `TrackGroup.memberIDs` order. Each row shows:

- part name;
- active pattern slot badge, such as `P1`;
- read-only step cells for the part's active pattern when safely representable;
- generator or read-only indicators when direct step representation is limited.

Matrix cells are read-legible only in v1. Tapping a cell must not toggle a
step. Tapping a row navigates to that part's normal workspace, where editing
continues through the existing part editor.

The matrix defaults to 16-step display. A 32-step display is allowed when the
active pattern length requires it or when the user selects it. In 32-step mode,
part names and pattern badges remain fixed and visible. Step cells compress to
fit while preserving readable beat grouping; if the available width would make
cells illegible, only the step-cell region scrolls horizontally. The part-name
region must not scroll out of view.

### Pattern Coherence Warning

Pattern independence is a first-class constraint. The matrix must show each
part's current active pattern slot and must not imply a group-level pattern
exists.

When visible member rows do not all use the same active pattern slot, the
matrix shows:

- an amber warning banner above the rows;
- amber treatment on rows whose slot differs from the first visible member's
  slot.

The warning is informational, not blocking. It does not change playback,
navigation, pattern selection, or routing apply behavior.

Warning language should stay compact and factual:

> Pattern mismatch: parts are showing different active pattern slots.

Supporting text may add that rows show each part's current slot. The warning
must not refer to a missing kit-pattern feature as though it already exists.

### Routing Editor

The routing editor is launched from the kit matrix as a standalone
post-creation sheet or panel. It owns a draft state and applies changes
atomically.

The editor displays:

- group shared destination;
- trigger mapping mode segmented control;
- one row per member in `TrackGroup.memberIDs` order;
- per-member inherit-group versus own-destination control;
- note assignment fields in per-note mode;
- channel assignment fields in per-channel mode;
- disabled or override treatment for members using their own destination.

Cancel closes the editor without committing draft changes. Apply commits valid
destination, mode, inherit/own, note, and channel changes together.

## Model And Persistence Behavior

### Track And Group Identity

Each part remains a normal `StepSequenceTrack` with a `groupID`. The group is
the existing `TrackGroup`. `TrackGroup.memberIDs` is the canonical part order
for header navigation, matrix rows, routing rows, and default channel seeding.

### Trigger Mapping State

`TrackGroup` gains persisted trigger mapping state:

```swift
enum DrumTriggerMappingMode: String, Codable, Equatable, Sendable {
    case perNote
    case perChannel
    case individual
}
```

`triggerMappingMode` defaults to `.perNote` when older documents decode.

Per-note mapping continues to use the existing `noteMapping: [UUID: Int]`,
where values are semitone offsets from `DrumKitNoteMap.baselineNote`.

Per-channel mapping uses a separate `channelMapping: [UUID: UInt8]`, where
stored values are zero-based MIDI channels `0...15`. UI values are `1...16`.
`channelMapping` defaults to an empty dictionary when older documents decode.

`noteMapping` and `channelMapping` are independent. Switching modes in the
routing editor does not clear assignments for the mode being left.

### Destination Behavior

Members set to inherit use `Destination.inheritGroup` and resolve through the
group `sharedDestination`. Group shared destination edits must use existing
group destination write-target plumbing so engine apply behavior stays
consistent with current destination editing.

Members set to own destination do not use group trigger mapping in playback.
Their mapping controls are disabled or replaced with explicit override
treatment in the routing editor.

In `.individual` mode, applying the routing editor moves inheriting members to
own destinations where a safe prior or default destination exists. If a member
cannot be assigned an own destination without losing routing information, Apply
must block with a validation error for that member.

## Trigger Mapping Rules

### Per MIDI Note

Per-note mode sends inherited members through the shared destination's port and
channel, applying each member's `noteMapping` offset. Missing offsets resolve
as `0`, matching existing playback behavior.

For newly created shared MIDI kits, defaults should be seeded from each
member's `DrumGroupPlan.Member.tag` through `DrumKitNoteMap`:

- stored offset = `absoluteMIDINote - DrumKitNoteMap.baselineNote`;
- baseline note `36` displays as `C2`.

### Note Name Grammar

The note assignment editor presents canonical note names using the common DAW
octave convention where MIDI note `60` is `C4`; therefore MIDI note `36` is
`C2`.

Canonical display grammar:

```text
<letter><optional-sharp><octave>
```

Examples: `C2`, `C#2`, `D2`, `F#2`.

Input validation:

- trim surrounding whitespace;
- accept letters `A` through `G`, case-insensitive;
- accept `#` or `b` accidentals;
- accept signed decimal octave values required to cover MIDI notes `0...127`;
- normalize flats and lowercase input to canonical sharp names on commit;
- reject values outside MIDI note `0...127`;
- reject raw numeric MIDI-note input in v1;
- reject empty or partially parsed values.

The parser converts the accepted note name to an absolute MIDI note, then
commits `absoluteMIDINote - DrumKitNoteMap.baselineNote` to `noteMapping`.
Invalid input blocks Apply and leaves the stored mapping unchanged.

### Per MIDI Channel

Per-channel mode sends inherited members through the shared MIDI destination's
port with each member's `channelMapping` channel. Note offset is `0` in v1 for
per-channel playback.

Per-channel mode requires the group shared destination to be MIDI. If the
shared destination is absent or non-MIDI, Apply is blocked with a validation
error. The engine should still fail safe if an incompatible state is loaded.

Channel input accepts UI values `1...16` and commits zero-based `UInt8` values
`0...15`.

Duplicate channel assignments are allowed in v1 because users may intentionally
layer parts on the same external channel. They are not an Apply blocker. The
routing editor should show a non-blocking warning when two or more inherited
members share the same channel in per-channel mode:

> Multiple parts use MIDI channel N.

### Individual

Individual mode means parts use their own destinations. The group shared
destination may remain stored for future use, but it is visually disabled while
the editor is in individual mode.

Switching away from individual mode does not erase part destinations. Applying
per-note or per-channel mode changes only members whose row is set to inherit
the group destination.

## Acceptance Criteria

### Header Navigation

- Given a selected drum part whose `groupID` resolves to a `TrackGroup`, the
  part workspace shows the kit header.
- Given `memberIDs = [kick, snare, clap]` and `snare` is selected, Previous
  selects `kick` and Next selects `clap`.
- Given the first member is selected, Previous is disabled and does not wrap.
- Given the last member is selected, Next is disabled and does not wrap.
- Given a generator/read-only member is selected, sibling navigation remains
  available.
- Given a track without a resolved group, the existing non-kit track workspace
  behavior remains available.

### Kit Matrix

- Opening Kit View from a part pushes a kit matrix for that part's group.
- Back from the matrix returns to the originating part workspace.
- Matrix row order matches `TrackGroup.memberIDs`.
- Each row shows the part name and active pattern badge.
- Step cells are visible for representable active patterns and do not mutate
  when tapped.
- Tapping a row navigates to that part's workspace.
- Generator or otherwise non-inline-editable rows remain represented and are
  clearly marked read-only.
- 32-step mode keeps part names and pattern badges visible; only the step
  region may scroll when compression would make cells illegible.

### Pattern Coherence

- If all visible members use the same active pattern slot, no mismatch warning
  is shown.
- If visible members use different active pattern slots, the matrix shows the
  warning banner and highlights divergent badges.
- The warning does not block matrix navigation, routing edits, or playback.

### Routing Editor

- The routing editor opens from the kit matrix and returns to the matrix on
  Cancel or successful Apply.
- Cancel discards draft changes.
- Apply commits group shared destination, trigger mapping mode, inherit/own
  state, note mappings, and channel mappings atomically.
- Members with own destinations do not use group trigger mapping and display
  override treatment.
- Switching between mapping modes preserves hidden note and channel mappings.
- Per-note mode accepts valid note names and writes offsets relative to
  `DrumKitNoteMap.baselineNote`.
- Invalid note names block Apply and preserve previous stored values.
- Per-channel mode accepts channels `1...16` and stores `0...15`.
- Per-channel mode with duplicate inherited channels warns but still applies.
- Per-channel mode with no MIDI shared destination blocks Apply.

### Persistence And Playback

- Older documents decode with `.perNote` and empty `channelMapping`.
- `TrackGroup` Codable round-trips `triggerMappingMode`, `noteMapping`, and
  `channelMapping`.
- Removed members are removed from both note and channel mapping dictionaries
  during project synchronization.
- Per-note inherited playback continues to use the group shared destination
  with member pitch offset.
- Per-channel inherited playback uses the group MIDI destination port and
  member channel mapping.
- Own-destination members resolve through existing individual destination
  behavior.

## Edge Cases

- Missing or stale member IDs are omitted from UI rows and removed during
  synchronization.
- Duplicate member IDs in a malformed group should not duplicate visible rows;
  preserve first occurrence order for display and treat later duplicates as
  invalid data to normalize.
- A group with zero resolved members should show an empty matrix state and
  should not crash.
- A group with one member shows disabled Previous and Next controls.
- Long kit and part names truncate without hiding navigation controls or
  pattern badges.
- A nil `sharedDestination` is allowed in per-note mode, but inherited playback
  continues to fail safe through existing destination resolution.
- Per-channel mode cannot be applied until the shared destination is MIDI.
- Pattern slots that cannot be represented as simple steps show a read-only or
  generator state rather than fake editable cells.
- Pattern lengths above 32 steps are out of v1 matrix scope; show the first
  supported span with an explicit read-only overflow indicator or route the
  user to the part workspace.

## Exclusions And Non-Goals

- No new drum-specific track type.
- No kit-level pattern object, kit pattern selector, or group pattern bank in
  v1.
- No inline matrix step editing.
- No matrix editing for generator internals, layered clips, or probability
  rules.
- No per-member mute or solo feature beyond existing track/group behavior.
- No changes to unrelated phrase, scene, or mixer grammar.
- No reuse of `AddDrumGroupSheet` as the primary post-creation editor.

Future kit-pattern work is a separate extension boundary: it may define a
named set of per-member pattern indices and a selector for those sets. V1 only
reports current per-part pattern state and warns about divergence.

## Validation And Evidence Expectations

Builder validation should include:

- model tests for `TrackGroup` decode defaults and Codable round-trip;
- synchronization tests for removing stale `noteMapping` and `channelMapping`
  entries;
- creation tests for shared MIDI default note and channel seeding;
- mutation tests for shared destination, inherit/own state, mapping mode, note
  mapping, channel mapping, and atomic routing-editor draft apply;
- note parser tests for sharps, flats, lowercase input, signed octaves,
  canonical display, MIDI range bounds, and rejection of raw numeric input;
- channel validation tests for bounds, zero-based storage, duplicate warning,
  and non-MIDI shared destination blocking;
- playback/store tests for `.perNote`, `.perChannel`, `.individual`, and
  own-destination overrides;
- UI tests or focused view-model tests for header bounds, member order, matrix
  row ordering, pattern mismatch warning, 32-step layout behavior, row-tap
  navigation, and generator/read-only row treatment.

UX evidence should include screenshots or visual evidence for:

- first, middle, and last part header states;
- a long kit name with six parts;
- coherent and mixed-pattern matrix states;
- 16-step and 32-step matrix states;
- a generator/read-only row;
- routing editor per-note, per-channel, individual, duplicate-channel warning,
  invalid-note, and non-MIDI destination validation states.
