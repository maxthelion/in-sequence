# Flat Tracks + TrackGroup Reshape Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Migrate the already-shipped track/voicing/routing code to the flat-track + `TrackGroup` model documented in the 2026-04-19 spec delta. Rename `TrackType` cases (`.instrument / .drumRack / .sliceLoop` → `.monoMelodic / .polyMelodic / .slice`, dropping drumRack). Retire per-tag `Voicing`; tracks carry an inline `Destination`. Introduce `TrackGroup` + `Destination.inheritGroup`. Ship a minimal `DrumKitPreset` library so "Add Drum Kit" users land with a kick/snare/hat kit + group + shared destination. Update in-flight plan docs (tracks-matrix, live-view) to reflect the new shape, and add a banner to the already-shipped plans (track-destinations, midi-routing) noting the data model they write to has changed. Verified by: existing documents decode into the new shape (tests prove the migration); `xcodebuild test` stays green; a fresh document with a default drum kit produces 3 mono tracks grouped together, all routing through one shared AU.

**Architecture:** This plan is primarily a data-model reshape plus a migration path. The shipped `Voicing` type (per-tag destination map) becomes a pair: `Track.destination: Destination` (inline, single value) plus `TrackGroup` (project-scoped container). Legacy decoder: if a document has `trackType == .drumRack`, on load we (a) create one new `monoMelodic` track per voice tag in the old Voicing map, (b) create a `TrackGroup` containing those tracks, (c) set the group's `sharedDestination` to whichever destination type all tags agreed on (if they all pointed at the same AU, use it as shared; otherwise split — each member keeps its own destination and the group has `sharedDestination = nil`), (d) populate `noteMapping[trackID]` from the old tag-to-MIDI-note convention (36=kick, 38=snare, 42=hat, …). Legacy `TrackType.instrument` tracks decode to `.monoMelodic`; the poly→mono split for instrument tracks can happen incrementally (MVP = all existing `.instrument` become `.monoMelodic`; users manually upgrade to `.polyMelodic` later if they want multi-note step authoring). `TrackType.sliceLoop` → `.slice`.

`Destination.inheritGroup` is an additive case on the existing `Destination` enum — legacy decoders don't emit it, so no migration beyond adding the case. The only live site that reads destinations (the engine's tick dispatch) gets an `effectiveDestination(for:)` helper that consults the group when the track's destination is `.inheritGroup`.

**Tech Stack:** Swift 5.9+, Foundation, AVFoundation (existing AU hosting), XCTest. No new dependencies.

**Parent spec:** `docs/specs/2026-04-18-north-star-design.md` — §"Vocabulary" (TrackGroup, Destination.inheritGroup), §"Track types, patterns, and phrases", §"Drum tracks as groups".

**Environment note:** Xcode 16. All `xcodebuild` invocations prefix `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

**Status:** <STATUS_PREFIX> <COMPLETED_MARKER> TBD. Tag `v0.0.9-track-group-reshape` at TBD.

**Depends on:**

- `2026-04-19-track-destinations.md` — shipped. This plan migrates its data model.
- `2026-04-19-midi-routing.md` — shipped. This plan adapts its routing to the new shape.
- `2026-04-19-generator-algos.md` — in progress. Interaction: `mono-generator` kind needs to be compatible with any monoMelodic track whether it's used as a drum voice or a melodic voice; compatibility rules don't change.

**Supersedes in spirit (plans whose drum-specific bits this plan retires):**

- `2026-04-19-tracks-matrix.md` — must drop the Drum button from `CreateTrackSheet`, add "Add Drum Kit" flow, and replace drum-track rendering with group-tinted cells. Task 8 below handles the plan-doc update.
- `2026-04-19-live-view.md` — drum-expand affordance retires (members are already separate cells). Add group-aggregate cells. Task 9 below handles the plan-doc update.

**Deliberately deferred:**

- **Full library-scoped drum kit presets** (loading `.seqai-drumkit` files). MVP ships a small hardcoded `DrumKitPreset` enum; library loading lands later.
- **Group bus routing / group insert effects.** Group's `busSink` field exists for future use; MVP wires mute + solo only.
- **UI for editing group membership** beyond the "Add Drum Kit" flow. Move-to-group / remove-from-group affordances land with the tracks-matrix plan.
- **polyMelodic auto-split of legacy `.instrument` tracks.** All legacy instruments migrate to `.monoMelodic`; the user upgrades to `.polyMelodic` manually. A future plan can add heuristic conversion (e.g. if the track's generator produces multi-note output, flag for upgrade).

---

## File Structure

```
Sources/
  Document/
    TrackType.swift                          # NEW OR MODIFIED — 3-case enum with legacy decoder
    Destination.swift                        # MODIFIED — add .inheritGroup case
    TrackGroup.swift                         # NEW
    DrumKitPreset.swift                      # NEW — hardcoded presets
    SeqAIDocumentModel.swift                 # MODIFIED — drop Voicing field; add destination inline; add trackGroups; legacy decoder
    Voicing.swift                            # DELETED — legacy type removed after migration shim
    PhraseModel.swift                        # MODIFIED — any VoiceTag-keyed routing shifts to TrackID-keyed
  Engine/
    EngineController.swift                   # MODIFIED — effectiveDestination(for:) helper; tick dispatch uses it
    MIDIRouter.swift                         # MODIFIED — RouteFilter.voiceTag retired in favour of route-by-trackID; legacy route decoding
    AudioInstrumentHost.swift                # MODIFIED — host an AU per (trackID OR groupID); sharing key for inheritGroup members
    AUWindowHost.swift                       # MODIFIED — window keyed on (trackID OR groupID); when groupID, the title reflects "Drums (shared)"
  Musical/
    DrumKitNoteMap.swift                     # NEW — the canonical GM-drum-ish tag-to-note map used by DrumKitPreset
Tests/
  SequencerAITests/
    Document/
      TrackTypeMigrationTests.swift          # NEW — legacy TrackType rename
      TrackGroupTests.swift                  # NEW — TrackGroup shape + serialisation
      VoicingMigrationTests.swift            # NEW — per-tag Voicing → flat tracks + group
      DestinationInheritGroupTests.swift     # NEW — Destination.inheritGroup round-trip
      DrumKitPresetTests.swift               # NEW — preset → tracks + group expansion
    Engine/
      EffectiveDestinationTests.swift        # NEW — tick-time resolution covers inheritGroup + orphaned case
      MIDIRouterMigrationTests.swift         # NEW — legacy voice-tag routes decode correctly
docs/plans/
  2026-04-19-tracks-matrix.md                # MODIFIED — see Task 8
  2026-04-19-live-view.md                    # MODIFIED — see Task 9
  2026-04-19-track-destinations.md           # MODIFIED — add completion-state banner; note data now migrates on load
  2026-04-19-midi-routing.md                 # MODIFIED — add completion-state banner; note VoiceTag handling updated
wiki/pages/
  track-destinations.md                      # MODIFIED — redocument with new model
  midi-routing.md                            # MODIFIED — redocument
  tracks-matrix.md                           # if created — include group tint
```

---

## Task 1: `TrackType` rename + legacy decoder

**Scope:** Replace the shipped `TrackType` cases. Add a legacy-name decoder so old documents still open.

**Files:**
- Modify: `Sources/Document/SeqAIDocumentModel.swift` — replace `TrackType` enum definition (it lives in this file today); add custom `init(from:)` on `TrackType` handling legacy raw values
- Create: `Tests/SequencerAITests/Document/TrackTypeMigrationTests.swift`

**New enum:**

```swift
public enum TrackType: String, Codable, CaseIterable, Equatable, Sendable {
    case monoMelodic, polyMelodic, slice

    public var label: String { ... }

    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        switch raw {
        case "monoMelodic": self = .monoMelodic
        case "polyMelodic": self = .polyMelodic
        case "slice":       self = .slice
        // legacy
        case "instrument":  self = .monoMelodic     // default; user can upgrade to poly manually
        case "drumRack":    self = .monoMelodic     // drum-rack tracks are exploded into groups by Task 4
        case "sliceLoop":   self = .slice
        default: throw DecodingError.dataCorruptedError(
            in: decoder.singleValueContainer(),
            debugDescription: "Unknown TrackType: \(raw)")
        }
    }
}
```

**Tests:**

1. `TrackType.allCases.count == 3`.
2. Legacy raw `"instrument"` decodes to `.monoMelodic`.
3. Legacy raw `"drumRack"` decodes to `.monoMelodic` (actual drum-rack conversion happens at document-load time via Task 4's pipeline, not at enum-level).
4. Legacy raw `"sliceLoop"` decodes to `.slice`.
5. New raw values round-trip cleanly.
6. Unknown raw throws.

- [ ] Tests
- [ ] Implement enum + legacy decoder
- [ ] `xcodebuild test` green
- [ ] Commit: `refactor(document): TrackType rename to 3-case with legacy decoder`

---

## Task 2: `Destination.inheritGroup` additive variant

**Scope:** Add the case. No migration needed — legacy decoders never produce it.

**Files:**
- Modify: `Sources/Document/Destination.swift`
- Modify: `Tests/SequencerAITests/Document/DestinationTests.swift`
- Create: `Tests/SequencerAITests/Document/DestinationInheritGroupTests.swift`

**Change:**

```swift
public enum Destination: Codable, Equatable, Sendable {
    case midi(port: MIDIEndpointName?, channel: UInt8, noteOffset: Int)
    case auInstrument(componentID: AudioComponentID, stateBlob: Data?)
    case internalSampler(bankID: InternalSamplerBankID, preset: String)
    case inheritGroup                                  // NEW
    case none

    public var kindLabel: String { ... }               // "MIDI" / "AU" / "Internal" / "Group" / "—"
}
```

**Tests:**

1. `Destination.inheritGroup` round-trips through Codable.
2. `kindLabel == "Group"` for the new case.
3. Existing tests for other variants still pass (sanity).

- [ ] Tests
- [ ] Implement
- [ ] Green
- [ ] Commit: `feat(document): Destination.inheritGroup variant`

---

## Task 3: `TrackGroup` type

**Scope:** New project-scoped entity. Not yet wired; Task 5 adds the field to `SeqAIDocumentModel`.

**Files:**
- Create: `Sources/Document/TrackGroup.swift`
- Create: `Tests/SequencerAITests/Document/TrackGroupTests.swift`

**Type:**

```swift
public typealias TrackGroupID = UUID

public struct TrackGroup: Codable, Equatable, Identifiable, Sendable {
    public let id: TrackGroupID
    public var name: String
    public var color: String                        // hex or named; default "#8AA"
    public var memberIDs: [TrackID]                  // ordered
    public var sharedDestination: Destination?
    public var noteMapping: [TrackID: Int]           // offsets for .inheritGroup members
    public var mute: Bool
    public var solo: Bool
    public var busSink: BusRef?                      // future — stub for now

    public init(id: TrackGroupID = UUID(), name: String, color: String = "#8AA",
                memberIDs: [TrackID] = [], sharedDestination: Destination? = nil,
                noteMapping: [TrackID: Int] = [:], mute: Bool = false, solo: Bool = false,
                busSink: BusRef? = nil)
}

public struct BusRef: Codable, Equatable, Hashable, Sendable { /* stub; future */ }
```

**Tests:**

1. Round-trip Codable for minimal + full-field variants.
2. Identity: `id` survives round-trip.
3. Default `noteMapping == [:]`, `sharedDestination == nil`, `mute == false`, `solo == false`.
4. Decoding a JSON missing optional fields supplies defaults.

- [ ] Tests
- [ ] Implement
- [ ] Green
- [ ] Commit: `feat(document): TrackGroup + BusRef stub`

---

## Task 4: `VoicingMigration` — legacy `drumRack` + per-tag Voicing → flat tracks + group

**Scope:** The heart of the reshape. Decoder hook on `SeqAIDocumentModel` that runs after `tracks` + the legacy `voicings` are decoded: walks the decoded tracks, finds legacy drum-rack tracks (before TrackType rename this was `"drumRack"`; after Task 1's rename they decode as `.monoMelodic` but carry the old per-tag Voicing payload), and expands them into group + flat tracks.

**Files:**
- Create: `Sources/Document/VoicingMigration.swift`
- Create: `Tests/SequencerAITests/Document/VoicingMigrationTests.swift`
- Modify: `Sources/Document/SeqAIDocumentModel.swift` — call migration from `init(from:)`

**Migration steps (per legacy drum-rack track):**

1. Collect the old track's per-tag Voicing payload (e.g. `["kick": .internalSampler(bank: .drumKitDefault, preset: "kick-909"), "snare": ..., "hat": ...]`).
2. If every tag's destination is identical: decide this is a "one-AU-shared" setup. Create a `TrackGroup` with `sharedDestination = <that destination>`. For each tag, create a new `monoMelodic` track (name = tag, e.g. "kick"), set `track.destination = .inheritGroup`, populate `group.noteMapping[newTrack.id] = DrumKitNoteMap.noteForTag(tag)` (see Task 7).
3. If destinations differ per tag: create the group with `sharedDestination = nil`; each new track carries its own `destination` (the tag's original value); no noteMapping.
4. Append the new tracks to `document.tracks`; append the new group to `document.trackGroups`; set each new track's `groupID = group.id`.
5. Remove the legacy drum-rack track from `document.tracks` and any `document.trackSlots` reference (the new tracks go into freshly-allocated empty slots — or, if the legacy drum track occupied slot N, its first new member takes slot N and subsequent members take N+1, N+2 etc. using the first-empty-slot walker).

**Migration steps (legacy `.instrument` tracks):**

- Just rename to `.monoMelodic` (no structural change). Existing `Voicing.destinations["default"]` payload becomes `track.destination` inline.

**Migration steps (legacy `.sliceLoop` tracks):**

- Rename to `.slice`. `Voicing.destinations["default"]` → `track.destination`.

**Tests:**

1. Legacy drum-rack track with 3 uniform-destination tags migrates to 3 flat mono tracks + 1 group + sharedDestination + noteMapping populated for each.
2. Legacy drum-rack track with mixed destinations per tag migrates to 3 flat mono tracks + 1 group with `sharedDestination == nil`; each track retains its own destination.
3. Legacy instrument track migrates to a mono track with `track.destination = <old voicing default>`.
4. Legacy slice track migrates to a slice track with `track.destination = <old voicing default>`.
5. Migration is idempotent: migrating an already-migrated document is a no-op.
6. A new-format document (no legacy voicings) round-trips unchanged.

- [ ] Tests (6 cases)
- [ ] Implement migration logic + integration into `init(from:)`
- [ ] Green
- [ ] Commit: `feat(document): legacy drumRack + per-tag Voicing → flat tracks + TrackGroup migration`

---

## Task 5: `document.trackGroups` + `track.destination` inline + `track.groupID`

**Scope:** Wire the new fields onto `SeqAIDocumentModel` and `StepSequenceTrack`. Remove the old `Voicing` field (it's migration-only now). Drop the standalone `Voicing.swift` file after tests stop referencing it directly.

**Files:**
- Modify: `Sources/Document/SeqAIDocumentModel.swift` — `trackGroups: [TrackGroup] = []` field
- Modify: `Sources/Document/SeqAIDocumentModel.swift` — `StepSequenceTrack.destination: Destination`, `StepSequenceTrack.groupID: TrackGroupID?`
- Delete (after Task 4 migration no longer needs it as an input shape): `Sources/Document/Voicing.swift`
- Modify: `Tests/SequencerAITests/Document/SeqAIDocumentModelTests.swift`, `Tests/SequencerAITests/Document/VoicingTests.swift` (may be deleted / rewritten)
- Create: helpers on the model: `document.group(for: TrackID) -> TrackGroup?`, `document.tracksInGroup(_:) -> [StepSequenceTrack]`, `document.addToGroup(trackID:groupID:)`, `document.removeFromGroup(trackID:)`

**Tests:**

1. Default document has `trackGroups == []`.
2. A track created via `createTrack` has `destination = .none`, `groupID = nil`.
3. Adding a group via `document.addGroup(name:color:)` appends to `trackGroups`.
4. `addToGroup(trackID:groupID:)` updates the track's `groupID` + the group's `memberIDs`; is idempotent.
5. `removeFromGroup(trackID:)` clears the track's `groupID` + removes from the group's `memberIDs`.
6. Removing a track whose destination was `.inheritGroup` from its group auto-converts the destination to `.none` (with a warning log).

- [ ] Tests
- [ ] Implement fields + helpers
- [ ] Delete `Voicing.swift` + update tests that referenced it
- [ ] Green
- [ ] Commit: `refactor(document): flat track.destination + trackGroups on document model`

---

## Task 6: Engine — `effectiveDestination(for:)` + `AudioInstrumentHost` group-keyed instance sharing

**Scope:** Update the engine's tick-time routing. The `EngineController` resolves each track's effective destination via a helper that consults the group for `.inheritGroup` members. `AudioInstrumentHost` keys AU instances on either `TrackID` (when the track has its own Destination) or `TrackGroupID` (when the track's Destination is `.inheritGroup` and the group has a sharedDestination). Two `.inheritGroup` members of the same group share one AU instance.

**Files:**
- Modify: `Sources/Engine/EngineController.swift` — add `effectiveDestination(for:) -> (Destination, pitchOffset: Int)` helper
- Modify: `Sources/Engine/EngineController.swift` — tick dispatch uses `effectiveDestination`
- Modify: `Sources/Audio/AudioInstrumentHost.swift` — add support for group-scoped AU instance management; track-level API stays but now internally routes to either per-track AU or per-group AU
- Modify: `Sources/Audio/AUWindowHost.swift` — window key becomes an enum `AUWindowKey = .track(TrackID) | .group(TrackGroupID)`; window title reflects the group's name when keyed on group
- Create: `Tests/SequencerAITests/Engine/EffectiveDestinationTests.swift`

**`effectiveDestination` logic:**

```swift
func effectiveDestination(for trackID: TrackID) -> (Destination, pitchOffset: Int) {
    guard let track = document.model.track(withID: trackID) else { return (.none, 0) }
    if case .inheritGroup = track.destination {
        guard let groupID = track.groupID,
              let group = document.model.trackGroup(id: groupID) else {
            return (.none, 0)
        }
        guard let shared = group.sharedDestination else {
            return (.none, 0)
        }
        return (shared, group.noteMapping[trackID] ?? 0)
    }
    return (track.destination, 0)
}
```

**Tests:**

1. Track with `.midi(...)` destination: `effectiveDestination` returns the midi + 0.
2. Track with `.inheritGroup` in a group with `sharedDestination = .auInstrument(Battery)` and `noteMapping[trackID] = 36`: returns `(auInstrument(Battery), 36)`.
3. Track with `.inheritGroup` in a group whose `sharedDestination == nil`: returns `(.none, 0)`.
4. Track with `.inheritGroup` but `groupID == nil`: returns `(.none, 0)`.
5. Track with `.inheritGroup` whose groupID points at a non-existent group: returns `(.none, 0)`.
6. Two `.inheritGroup` members of the same group get the same `AudioInstrumentHost.currentUnit` reference (instance sharing).
7. `AUWindowHost` opens ONE window for `.group(groupID)` when the user clicks Edit on any of the group's `.inheritGroup` member tracks.

- [ ] Tests
- [ ] Implement
- [ ] Green
- [ ] Commit: `feat(engine): effectiveDestination(for:) + AU instance sharing per group`

---

## Task 7: `DrumKitNoteMap` + `DrumKitPreset` + "Add Drum Kit" data API

**Scope:** The hardcoded GM-drum-ish tag-to-note mapping + a couple of seeded presets that spawn tracks + a group.

**Files:**
- Create: `Sources/Musical/DrumKitNoteMap.swift`
- Create: `Sources/Document/DrumKitPreset.swift`
- Create: `Tests/SequencerAITests/Document/DrumKitPresetTests.swift`

**Tag→note map (static):**

```swift
public enum DrumKitNoteMap {
    /// Conventional MIDI drum note numbers (GM-ish). Returned value is the NOTE number;
    /// callers subtract a baseline when computing `noteMapping` offsets.
    public static let table: [String: UInt8] = [
        "kick": 36, "snare": 38, "sidestick": 37, "hat-closed": 42, "hat-open": 46,
        "hat-pedal": 44, "clap": 39, "tom-low": 41, "tom-mid": 45, "tom-hi": 48,
        "ride": 51, "crash": 49, "cowbell": 56, "tambourine": 54, "shaker": 70
    ]

    public static func note(for tag: VoiceTag) -> UInt8 {
        table[tag] ?? 60
    }
}
```

**DrumKitPreset:**

```swift
public enum DrumKitPreset: String, CaseIterable, Sendable {
    case kit808 = "808"
    case acousticBasic = "Acoustic"
    case techno = "Techno"

    public var displayName: String { ... }

    public struct Member: Equatable, Sendable {
        public let tag: VoiceTag           // "kick", "snare", "hat-closed", …
        public let trackName: String
        public let defaultGeneratorKindID: String
        // reserved: default NoteShape, step pattern seed
    }

    public var members: [Member] {
        switch self {
        case .kit808:
            return [
                Member(tag: "kick", trackName: "Kick", defaultGeneratorKindID: "mono-generator"),
                Member(tag: "snare", trackName: "Snare", defaultGeneratorKindID: "mono-generator"),
                Member(tag: "hat-closed", trackName: "Hat", defaultGeneratorKindID: "mono-generator"),
                Member(tag: "clap", trackName: "Clap", defaultGeneratorKindID: "mono-generator")
            ]
        // other presets...
        }
    }

    public var suggestedSharedDestination: Destination {
        // MVP: all presets point at the internal drum-sampler bank for that preset
        .internalSampler(bankID: .drumKitDefault, preset: rawValue)
    }

    public var suggestedGroupColor: String {
        switch self {
        case .kit808: return "#C6A"        // magenta-ish
        case .acousticBasic: return "#8AA" // default
        case .techno: return "#8FC"        // cyan-green
        }
    }
}
```

**`SeqAIDocumentModel.addDrumKit(_ preset: DrumKitPreset) -> TrackGroupID?`:**

- For each member: create a new `monoMelodic` track with `destination = .inheritGroup`, `groupID = (to be set)`, and append it to the flat `tracks` list.
- Create a group: `name = preset.displayName`, `color = preset.suggestedGroupColor`, `memberIDs = [newTrackIDs]`, `sharedDestination = preset.suggestedSharedDestination`, `noteMapping = [trackID: DrumKitNoteMap.note(for: tag) - 36]` (baseline: the shared destination's root note is C2 = 36; offset from that).
- Set each new track's `groupID = group.id`.
- Append the group to `trackGroups`.
- Sync pattern banks / phrases for the appended tracks.
- Return the new group ID. `nil` is reserved for malformed presets (for example, an empty member list), not track-capacity errors.

**Tests:**

1. `DrumKitPreset.kit808.members.count == 4`; members have unique tags.
2. `DrumKitNoteMap.note(for: "kick") == 36`; `"snare" == 38`; `"unknown-tag" == 60`.
3. `addDrumKit(.kit808)` on the default document appends 4 grouped tracks + 1 group. Every new track is `monoMelodic` with `destination = .inheritGroup`, `groupID = <new group>`. Group has `memberIDs.count == 4`, `sharedDestination` non-nil, `noteMapping` has 4 entries.
4. `addDrumKit(.kit808)` also appends pattern banks and phrase pattern indexes for each new track, and selects the first newly-added member.

- [x] Tests
- [x] Implement DrumKitNoteMap, DrumKitPreset, addDrumKit
- [x] Green
- [ ] Commit: `feat(document): DrumKitPreset library + addDrumKit flow`

---

## Task 8: Update `tracks-matrix` plan doc

**Scope:** Edit `docs/plans/2026-04-19-tracks-matrix.md` to reflect the flat-track model.

**Changes to apply:**

- `CreateTrackSheet` (Task 4 in that plan) — drop the `.drum` button. Types become `.monoMelodic / .polyMelodic / .slice` (3 buttons).
- Add a new section / task: **"Add Drum Kit"** button in the Tracks matrix header (or as a menu item) opens `DrumKitPresetPicker` which lists `DrumKitPreset.allCases` and calls `document.model.addDrumKit(preset)`. Navigates to the new group's first member after creation.
- `TrackCard` (Task 3 in that plan) — gains a `groupColor: String?` param; when the track is in a group, the card's border / corner swatch uses the group color.
- New affordance: clicking a group name (perhaps an inset label at the top-left of member cards sharing a color) navigates to a Group detail view. Group detail is deferred to a separate plan; the matrix just needs to indicate membership.
- Update "Change Type…" action: retained but notes that moving from `.polyMelodic` → `.monoMelodic` etc. is the only case that changes behaviour; no drum case any more.

**Files:**
- Modify: `docs/plans/2026-04-19-tracks-matrix.md`

**Tests:** this is a plan-doc update, not code. Verification: no `drumRack` references in the plan; "Add Drum Kit" section present; group-color mention in TrackCard task.

- [ ] Edit plan doc
- [ ] Commit: `docs(plan): tracks-matrix — drop drum type; add Add-Drum-Kit flow + group tinting`

---

## Task 9: Update `live-view` plan doc

**Scope:** Edit `docs/plans/2026-04-19-live-view.md` to reflect the flat-track model.

**Changes to apply:**

- Task 4 (TrackCell + DrumTagCell) — remove `DrumTagCell`. All cells are `TrackCell`; drum-voice tracks render the same way as any other mono track.
- Task 5 (LivePerformanceView) — remove the "Expand Drums" toggle; `activeLayerID` still defaults to `.mute` but the drum-specific branch goes away. Update `LiveDisplayCell` enum to `.track(TrackID) | .groupAggregate(TrackGroupID) | .empty`.
- New cell variant: **group-aggregate cell**. When a group has N members, a `groupAggregate` cell rendering adjacent to (or in place of) the member cells shows collective state for the active layer:
  - Mute layer: filled if all members muted, half if some, outlined if none. Tap = mute/unmute the whole group (writes `group.mute = true/false`).
  - Volume/Intensity layers: shows the AVERAGE of member cells; drag = scale all member cells proportionally.
  - Pattern layer: shows "mixed" if members are on different pattern indices; tap opens a group-level pattern picker that sets all members' Pattern cells at once.
- Layout: an optional "Collapse Groups" toggle in the Live view (default on) renders a group as a single `groupAggregate` cell; off renders the members individually. This replaces the deleted "Expand Drums" toggle.
- Task 6 (CellValue.singleMuteTagSet) — DELETED. Per-tag mute is no longer a data concept because tags aren't a data axis; mute per drum voice = mute that voice's flat track. `CellValue` loses `.singleMuteTagSet`.

**Files:**
- Modify: `docs/plans/2026-04-19-live-view.md`

- [ ] Edit plan doc
- [ ] Commit: `docs(plan): live-view — drop drum expansion; add groupAggregate cell + Collapse Groups toggle`

---

## Task 10: Banners on shipped plans

**Scope:** `track-destinations.md` and `midi-routing.md` are marked as shipped / completed. Add a banner to each noting the reshape.

**Files:**
- Modify: `docs/plans/2026-04-19-track-destinations.md` — prepend a "## Retroactive notes" section right after the Status line, noting that per-tag `Voicing` has been retired by the track-group reshape; any reader following that plan should also consult this reshape plan for the migration.
- Modify: `docs/plans/2026-04-19-midi-routing.md` — prepend a similar section noting `VoiceTag`-keyed routing retires; `RouteFilter.voiceTag` becomes a legacy case preserved for document compatibility but not used in new authoring.

- [ ] Edit both plan docs
- [ ] Commit: `docs(plan): annotate shipped track-destinations + midi-routing plans with reshape context`

---

## Task 11: Wiki + project-layout updates

**Scope:** Keep wiki coherent.

**Files:**
- Modify: `wiki/pages/track-destinations.md` — rewrite or extend to describe the new model (inline `Destination`, `.inheritGroup`, groups)
- Create: `wiki/pages/track-groups.md` — the group concept, drum-kit preset flow, the three setups (one-AU, per-voice-AU, hybrid)
- Modify: `wiki/pages/midi-routing.md` — note `VoiceTag` retires; routes key on `TrackID`
- Modify: `wiki/pages/project-layout.md` — add `Musical/DrumKitNoteMap.swift`, `Document/TrackGroup.swift`, `Document/DrumKitPreset.swift`, `Document/VoicingMigration.swift`

- [ ] Wiki page updates
- [ ] project-layout updated
- [ ] Commit: `docs(wiki): track-groups page + updates for the reshape`

---

## Task 12: Tag + mark completed

- [ ] Replace every `- [ ]` in this file with `- [x]` for completed steps
- [ ] Add a `Status:` line after `Parent spec` in this file's header
- [ ] Commit: `docs(plan): mark track-group-reshape completed`
- [ ] Tag: `git tag -a v0.0.9-track-group-reshape -m "Flat tracks + TrackGroup reshape complete: 3-case TrackType, inline Destination, .inheritGroup, TrackGroup, DrumKitPreset, migration from per-tag Voicing"`

---

## Goal-to-task traceability (self-review)

| Goal / architectural claim | Task |
|---|---|
| 3-case TrackType with legacy decoder | Task 1 |
| `Destination.inheritGroup` variant | Task 2 |
| `TrackGroup` value type | Task 3 |
| Legacy drumRack + per-tag Voicing → flat tracks + group migration | Task 4 |
| `document.trackGroups` + `track.destination` + `track.groupID` wiring | Task 5 |
| Engine tick-time `effectiveDestination` + AU instance sharing | Task 6 |
| `DrumKitPreset` library + `addDrumKit` flow | Task 7 |
| tracks-matrix plan updated | Task 8 |
| live-view plan updated | Task 9 |
| Banners on shipped plans | Task 10 |
| Wiki | Task 11 |
| Tag | Task 12 |

## Open questions resolved for this plan

- **TrackType rename strategy:** direct rename with a legacy-name decoder. No bridging table at the type level; migration happens once at document load.
- **Poly-vs-mono split of legacy `.instrument` tracks:** all migrate to `.monoMelodic`. User manually upgrades to `.polyMelodic` via "Change Type…" if desired. Heuristic auto-upgrade (e.g. detect multi-note generators) deferred to a future plan.
- **Destination migration per tag's uniform-vs-mixed test:** strict equality. If every tag's destination is byte-for-byte identical, create a shared destination; otherwise each new track keeps its own. Edge case: two AUs with the same componentID but different stateBlobs are NOT considered uniform (state differs → member AUs need to stay separate). This is conservative and should rarely be wrong.
- **AU instance sharing when two tracks `.inheritGroup` into the same group:** one AVAudioUnit instance keyed on the group, not per track. Edits to that unit (via AUWindowHost) affect both members simultaneously — this IS the drum-machine use case.
- **AUWindowHost key when the track is `.inheritGroup`:** the window key is `.group(groupID)`, not `.track(trackID)`. The window title reads "{GroupName} (shared)" so the user understands they're editing the group's AU, not a per-track AU.
- **Orphaned `.inheritGroup`** (track is `.inheritGroup` but not in a group, or in a group with `sharedDestination == nil`): resolution returns `.none`; the tick drops events; UI warns via a yellow pill on the track in the matrix + a tooltip "Destination inherits from group but group has no shared destination."
- **Legacy `RouteFilter.voiceTag`** in `midi-routing`: remains decodable (preserves old documents) but acts as `.all` at runtime (no per-tag filter since tags aren't an event axis any more). Legacy routes issue a one-time warning on document load: "Voice-tag routes retired; routing via track IDs now. Please re-author."
- **CellValue.singleMuteTagSet** (live-view plan Task 6): retires. Per-tag mute is now just per-track mute on the relevant flat mono track.
- **Drum-kit preset ergonomics:** MVP ships 3 presets. Picking one appends N grouped tracks atomically into the flat track list. The fresh model no longer has matrix slot-capacity constraints, so there is no "not enough empty slots" failure path at the document layer.
- **What if the user drags a track out of a drum group?** `removeFromGroup(trackID:)` clears `track.groupID`; if the track's destination was `.inheritGroup`, auto-convert to `.none` and surface a warning — the user picks a new destination.
