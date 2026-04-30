# Drum Parts As A Group — Existing State

Inspected 2026-04-29.

## Summary

A `TrackGroup` / drum-group abstraction already exists in the data model, is
persisted, and is wired into the playback engine. The creation flow
(`AddDrumGroupSheet`) lets users name a group, pick a preset, and optionally
set a shared destination at creation time. The Tracks Matrix displays grouped
parts together under a coloured section header.

What is entirely absent is the experience described in the user stories: there
is no within-part navigation (prev/next sibling), no kit-group view that
renders all parts as a step matrix, no per-kit trigger-mapping mode (channel
vs. note), and no way to edit the shared destination or `noteMapping` after the
group has been created.

---

## 1. Drum-Group Data Model

### `TrackGroup` — `Sources/Document/TrackGroup.swift`

```
struct TrackGroup: Codable, Equatable, Identifiable, Sendable {
    var id: TrackGroupID          // UUID alias
    var name: String
    var color: String
    var memberIDs: [UUID]         // ordered list of drum-part track IDs
    var sharedDestination: Destination?
    var noteMapping: [UUID: Int]  // trackID → MIDI pitch offset (semitones relative to base note)
    var mute: Bool
    var solo: Bool
}
```

`memberIDs` maintains insertion order, which is the natural sequence for
left/right navigation.

### `StepSequenceTrack` — `Sources/Document/StepSequenceTrack.swift`

Each drum part is a full `StepSequenceTrack` with an optional `groupID: TrackGroupID?`.
There is no drum-specific track type; drum parts use `.monoMelodic`.
Each part carries its own independent `stepPattern`, `pitches` (seeded to
`DrumKitNoteMap.baselineNote = 36`), `destination`, and its own
`TrackPatternBank` with up to eight independent pattern slots.

### `Destination.inheritGroup` — `Sources/Document/Destination.swift`

A drum part may set `destination = .inheritGroup`. The engine then resolves it
at playback time by looking up the owning group's `sharedDestination`
(in `EngineController.effectiveDestination(for:in:)`, line 1616) and applying
`group.noteMapping[trackID] ?? 0` as a pitch offset. This is the sole
mechanism that distinguishes parts within a shared destination today.

### `DrumGroupPlan` / `DrumKitPreset` — `Sources/Document/DrumGroupPlan.swift`, `Sources/Musical/DrumKitPreset.swift`

`DrumGroupPlan` is a creation-time value type (not persisted). It carries
`Member` records with a `VoiceTag`, a `trackName`, a `seedPattern [Bool]`, and
a `routesToShared: Bool` flag. `DrumKitPreset` provides three presets (808,
Acoustic, Techno), each with 3–4 members and their associated seed patterns.

### `DrumKitNoteMap` — `Sources/Musical/DrumKitNoteMap.swift`

A static `[VoiceTag: UInt8]` lookup that maps voice tags (e.g. "kick" → 36,
"snare" → 38, "hat-closed" → 42) to GM drum note numbers. Used to seed
`pitches` when a drum kit is created. This table is never surfaced in the UI
or used at playback time beyond clip initialisation; `noteMapping` on
`TrackGroup` is a separate integer-offset mechanism.

---

## 2. Creation Flow

### `AddDrumGroupSheet` — `Sources/UI/DrumGroup/AddDrumGroupSheet.swift`

- Presents Blank / Templated modes with an optional preset picker.
- Lists editable member rows (name, voice tag, `routesToShared` toggle when a
  shared destination is set).
- Lets the user add or remove members (blank mode only).
- Has an "Add shared destination" toggle that opens `AddDestinationSheet`.
- Calls `session.addDrumGroup(plan:)` on confirm.

### `Project.addDrumGroup` — `Sources/Document/Project+DrumGroups.swift`

Creates all `StepSequenceTrack` entries, their `TrackPatternBank` records, and
the `TrackGroup` in one pass. All tracks initially receive `noteMapping: [:]`
(the group's map is empty; the pitch-offset mechanism is not pre-populated
from `DrumKitNoteMap` at creation time).

**Gap:** `noteMapping` is never populated automatically or exposed for editing.
There is no mutation method for it in `SequencerDocumentSession+Mutations.swift`
or `Project+Destinations.swift`.

---

## 3. Track-Page UI

### `TrackWorkspaceView` — `Sources/UI/Track/TrackWorkspaceView.swift`

The part view header shows only the track name (double-tap to rename). There
are no prev/next navigation controls. There is no button to open a kit group
view. The view has no awareness of `groupID`.

**Gap (Story 1):** No sibling navigation controls exist at the top of the part
view.

**Gap (Story 2):** No "open kit group view" button exists anywhere in the part
header.

---

## 4. Tracks Matrix View

### `TracksMatrixView` — `Sources/UI/TracksMatrixView.swift`

The matrix view does render drum groups distinctly: grouped parts are collected
into `GroupSectionView` blocks (line 459), each showing the group name, member
count, and shared-destination summary. Individual `TrackMatrixCard` tiles show
the track name, type badge, pattern index ("P1"), destination kind, and a
`pitchOffsetLabel` if `noteMapping[trackID]` is non-zero (lines 539–568). A
`PhraseCellPreview` shows the current phrase-layer cell value, not the raw step
pattern.

This is a tile-per-track grid layout, not a step-matrix row layout.

**Gap (Story 3):** No "step matrix" view exists that shows each part as a
horizontal row of step buttons with part names on the left. The matrix view
shows phrase-layer metadata per tile, not step triggers.

**Gap (Story 4):** Active pattern per part is shown ("P1") in each tile, but
whether those patterns are set up to play together (i.e. are the same index
across parts) is not surfaced visually.

---

## 5. Output Destination Model

### Group-level `sharedDestination` — `Sources/Document/TrackGroup.swift`

`TrackGroup.sharedDestination: Destination?` stores a group-level output.
It is set at creation time (optional) or left nil. There is no UI to edit it
after creation.

### `Destination.inheritGroup` resolution

Parts with `destination = .inheritGroup` resolve to the group's
`sharedDestination` at playback time (engine), and to a `.group(groupID)`
write-target for destination editing purposes.

`Project.setEditedDestination` and `SequencerDocumentSession.setEditedDestination`
route writes to the group's `sharedDestination` when the write-target is
`.group`. This is already plumbed.

**Gap (Story 5):** No UI exists to edit the group's shared destination after
creation. `TrackDestinationEditor` resolves and displays the effective
destination for the selected part, but it operates through the
`destinationWriteTarget` dispatch — it would write to the group when the
part uses `inheritGroup`. However, no kit-group view panel surfaces a
"group destination" field separate from the per-part editor, and there is no
way to switch a part between own-destination and inherit-group after
creation.

---

## 6. MIDI Trigger Model

### `noteMapping: [UUID: Int]`

`TrackGroup.noteMapping` maps member track IDs to integer pitch offsets applied
at playback time (`group.noteMapping[trackID] ?? 0`, engine line 1629). This
effectively supports a "one part per MIDI note" mapping when a shared MIDI
destination is used: each part sends to the same channel but a different pitch.

The matrix card shows the offset as "+n" / "−n" if non-zero (line 540–568), but
this display is read-only and the offset is never written by any existing
mutation path.

### Per-channel mapping

There is no mechanism for "one part per MIDI channel". The `Destination.midi`
case carries `channel: UInt8` and `noteOffset: Int`, but this is a single value
on the whole `sharedDestination`, not a per-member field. To implement
per-channel routing, either `noteMapping` would need to store a channel value
per member (alongside or instead of a note offset), or a second per-member
dictionary would be required.

**Gap (Story 6):** The data model has partial infrastructure for "one part per
MIDI note" via `noteMapping`, but:
- `noteMapping` is never pre-populated (all entries are `[:]` after creation).
- There is no mutation method to write to it.
- There is no UI to configure it.
- "One part per channel" is not modelled; only pitch-offset exists.
- No trigger-mapping mode enum exists (channel-mode vs. note-mode).

---

## 7. Pattern Independence

Each drum part has its own `TrackPatternBank` with up to eight independent
pattern slots. Pattern selection per part per phrase step is driven by the
phrase's `patternIndex` layer, which is per-track per-step. There is no
group-level pattern concept ("kit pattern" with a set of per-member pattern
indices) and no "kit pattern selector" as described in the notes.

**Gap:** No "kit pattern" abstraction exists. Each part's active pattern is
independent and visible only as "P1" / "P2" etc. in the matrix tile. A
holistic view of which pattern each part is on at a given phrase step does not
exist.

---

## 8. Generator / Layer Parts

Parts with generator sources or multiple layers are regular `StepSequenceTrack`
records. In the step matrix view (if built), they would need to be shown
read-only or with a link to their own editor, as stated in the user-story
assumptions. Nothing in the current model prevents representation, but no
display logic for this case has been designed.

---

## 9. Relevant Tests

| Test file | What it covers |
|-----------|----------------|
| `Tests/.../Document/TrackGroupTests.swift` | Codable round-trip for `TrackGroup`, including `noteMapping` and `sharedDestination` |
| `Tests/.../Document/ProjectAddDrumGroupTests.swift` | `addDrumGroup` mutations |
| `Tests/.../Document/DrumGroupPlanFactoryTests.swift` | `DrumGroupPlan` factory methods |
| `Tests/.../Document/TrackDestinationEditingTests.swift` | `destinationWriteTarget`, `setEditedDestination`, group-inheritance routing |
| `Tests/.../Engine/StoreAccessorHelpersTests.swift` | `tracksInGroup`, `group(for:)`, `resolvedDestination` |

**Missing coverage:**
- No test for `noteMapping` being written (no mutation exists to test).
- No test for sibling navigation (no feature exists).
- No test for "kit pattern" selection affecting multiple parts.
- No test for trigger-mapping mode (no enum exists).

---

## 10. Architecture Constraints

- Drum parts are plain `StepSequenceTrack` values with `.monoMelodic` type; there is no drum-specific type flag that would simplify discovery.
- `TracksMatrixView` is the closest existing thing to a multi-part row view, but it uses a tile grid, not a step-row layout. A new `DrumKitMatrixView` would need to be purpose-built.
- `noteMapping` stores pitch offsets (Int, in semitones), not absolute note numbers. Populating it from `DrumKitNoteMap` for a new kit would require a migration or a creation-time change to `addDrumGroup`.
- The `TrackGroup` model has no `triggerMappingMode` enum. Adding one (`.perNote` / `.perChannel`) would be a model change and must be added to the `CodingKeys` with a safe `decodeIfPresent` default.
- `AddDrumGroupSheet` does not surface `noteMapping` initialisation; `DrumGroupPlan.Member` has no per-member trigger value.
- The part view (`TrackWorkspaceView`) does not receive a `TrackGroup` reference or sibling list; it would need one passed in (or derived from the live store) to show navigation controls.
