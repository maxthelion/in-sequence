# Add Drum Group Modal Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Tracks page's `Menu("Add Drum Kit")` with an `Add Drum Group` button opening a modal that lets the user build a group from a preset or a blank starter set, control clip prepopulation, and optionally attach a shared destination with per-member routing.

**Architecture:** A new `DrumGroupPlan` value type describes the group being built. A new `Project.addDrumGroup(plan:library:)` materialises tracks, clips, pattern banks, and the `TrackGroup`. `Project.addDrumKit(_:library:)` becomes a shim around `addDrumGroup`. A new `AddDrumGroupSheet` view owns the form UI, reuses the `AddDestinationSheet` from the single-destination-ui plan for shared-destination picking, and returns a `DrumGroupPlan` to the caller. `TracksMatrixView` swaps the `Menu` for a `Button` + `.sheet`.

**Tech Stack:** Swift 5.9+, SwiftUI (`.sheet`), XCTest. No new dependencies.

**Parent spec:** `docs/specs/2026-04-21-add-drum-group-modal-design.md`.

**Environment note:** Xcode 16. All `xcodebuild` invocations prefix `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`. After creating new files under `Sources/`, run `xcodegen generate` before building or testing.

**Status:** Not started. Tag `v0.0.21-add-drum-group-modal` at completion.

**Depends on:** `docs/plans/2026-04-21-single-destination-ui.md` — needs `AddDestinationSheet` and `DestinationSummary` from that plan. Do not start this plan until single-destination-ui is tagged and merged.

**Deliberately deferred:**

- Editing an existing drum group through this modal (create-only).
- Reordering rows, editing seed patterns inline, editing MIDI notes per row.
- Slice-type drum kits (modal creates `.monoMelodic` tracks only, as today).
- Keyboard shortcuts.

---

## File Structure

```
Sources/Document/
  DrumGroupPlan.swift                        # NEW — value type + .blankDefault / .templated factories
  Project+DrumGroups.swift                   # NEW — addDrumGroup(plan:library:) + defaultDestination(forVoiceTag:library:)
  Project+Tracks.swift                       # MODIFIED — addDrumKit rewritten as shim over addDrumGroup

Sources/UI/
  TracksMatrixView.swift                     # MODIFIED — Menu→Button + .sheet wiring
  DrumGroup/
    AddDrumGroupSheet.swift                  # NEW — the modal

Tests/SequencerAITests/Document/
  DrumGroupPlanFactoryTests.swift            # NEW — .blankDefault / .templated factories
  ProjectDefaultDestinationForVoiceTagTests.swift  # NEW — resolver helper
  ProjectAddDrumGroupTests.swift             # NEW — materialisation variants
  ProjectAddDrumKitShimTests.swift           # NEW — regression for shim
```

---

## Task 1: `DrumGroupPlan` value type + factories

**Files:**
- Create: `Sources/Document/DrumGroupPlan.swift`
- Test: `Tests/SequencerAITests/Document/DrumGroupPlanFactoryTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/SequencerAITests/Document/DrumGroupPlanFactoryTests.swift`:

```swift
import Foundation
import XCTest
@testable import SequencerAI

final class DrumGroupPlanFactoryTests: XCTestCase {
    func test_blankDefault_has_four_members_with_expected_tags() {
        let plan = DrumGroupPlan.blankDefault
        XCTAssertEqual(plan.members.map(\.tag), ["kick", "snare", "hat-closed", "clap"])
        XCTAssertEqual(plan.members.map(\.trackName), ["Kick", "Snare", "Hat", "Clap"])
    }

    func test_blankDefault_members_have_all_false_seed_patterns_of_length_16() {
        let plan = DrumGroupPlan.blankDefault
        for member in plan.members {
            XCTAssertEqual(member.seedPattern.count, 16)
            XCTAssertTrue(member.seedPattern.allSatisfy { $0 == false })
        }
    }

    func test_blankDefault_has_no_shared_destination_and_prepopulate_off() {
        let plan = DrumGroupPlan.blankDefault
        XCTAssertNil(plan.sharedDestination)
        XCTAssertFalse(plan.prepopulateClips)
        XCTAssertEqual(plan.name, "Drum Group")
        XCTAssertEqual(plan.color, "#8AA")
    }

    func test_blankDefault_members_routeToShared_true_by_default() {
        let plan = DrumGroupPlan.blankDefault
        XCTAssertTrue(plan.members.allSatisfy { $0.routesToShared })
    }

    func test_templated_from_kit808_mirrors_preset_members() {
        let plan = DrumGroupPlan.templated(from: .kit808)
        let presetMembers = DrumKitPreset.kit808.members
        XCTAssertEqual(plan.members.count, presetMembers.count)
        for (planMember, presetMember) in zip(plan.members, presetMembers) {
            XCTAssertEqual(planMember.tag, presetMember.tag)
            XCTAssertEqual(planMember.trackName, presetMember.trackName)
            XCTAssertEqual(planMember.seedPattern, presetMember.seedPattern)
            XCTAssertTrue(planMember.routesToShared)
        }
    }

    func test_templated_from_preset_inherits_name_and_color_and_defaults_prepopulate_on() {
        let plan = DrumGroupPlan.templated(from: .kit808)
        XCTAssertEqual(plan.name, DrumKitPreset.kit808.displayName)
        XCTAssertEqual(plan.color, DrumKitPreset.kit808.suggestedGroupColor)
        XCTAssertTrue(plan.prepopulateClips)
        XCTAssertNil(plan.sharedDestination)
    }

    func test_templated_from_each_preset_has_nonempty_members() {
        for preset in DrumKitPreset.allCases {
            let plan = DrumGroupPlan.templated(from: preset)
            XCTAssertFalse(plan.members.isEmpty, "preset=\(preset.rawValue)")
        }
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
xcodegen generate && \
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/DrumGroupPlanFactoryTests \
  2>&1 | tail -25
```

Expected: compile failure — `DrumGroupPlan` does not exist.

- [ ] **Step 3: Create `DrumGroupPlan`**

Write `Sources/Document/DrumGroupPlan.swift`:

```swift
import Foundation

struct DrumGroupPlan: Equatable {
    struct Member: Equatable {
        var tag: VoiceTag
        var trackName: String
        var seedPattern: [Bool]
        var routesToShared: Bool

        init(tag: VoiceTag, trackName: String, seedPattern: [Bool], routesToShared: Bool = true) {
            self.tag = tag
            self.trackName = trackName
            self.seedPattern = seedPattern
            self.routesToShared = routesToShared
        }
    }

    var name: String
    var color: String
    var members: [Member]
    var prepopulateClips: Bool
    var sharedDestination: Destination?

    static var blankDefault: DrumGroupPlan {
        let emptyPattern = Array(repeating: false, count: 16)
        return DrumGroupPlan(
            name: "Drum Group",
            color: "#8AA",
            members: [
                Member(tag: "kick", trackName: "Kick", seedPattern: emptyPattern),
                Member(tag: "snare", trackName: "Snare", seedPattern: emptyPattern),
                Member(tag: "hat-closed", trackName: "Hat", seedPattern: emptyPattern),
                Member(tag: "clap", trackName: "Clap", seedPattern: emptyPattern),
            ],
            prepopulateClips: false,
            sharedDestination: nil
        )
    }

    static func templated(from preset: DrumKitPreset) -> DrumGroupPlan {
        DrumGroupPlan(
            name: preset.displayName,
            color: preset.suggestedGroupColor,
            members: preset.members.map { presetMember in
                Member(
                    tag: presetMember.tag,
                    trackName: presetMember.trackName,
                    seedPattern: presetMember.seedPattern,
                    routesToShared: true
                )
            },
            prepopulateClips: true,
            sharedDestination: nil
        )
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodegen generate && \
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/DrumGroupPlanFactoryTests \
  2>&1 | tail -15
```

Expected: all seven tests pass.

- [ ] **Step 5: Commit**

```bash
git add Sources/Document/DrumGroupPlan.swift Tests/SequencerAITests/Document/DrumGroupPlanFactoryTests.swift project.yml
git commit -m "feat(document): DrumGroupPlan value type with blankDefault / templated factories"
```

---

## Task 2: `Project.defaultDestination(forVoiceTag:library:)` helper

Extract today's inline voice-tag → destination lookup (currently in `addDrumKit`) so both the new `addDrumGroup` and the shimmed `addDrumKit` call the same resolver.

**Files:**
- Modify: `Sources/Document/Project+Tracks.swift` (add the static helper; do NOT remove the inline use yet — Task 4 replaces the caller)
- Test: `Tests/SequencerAITests/Document/ProjectDefaultDestinationForVoiceTagTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/SequencerAITests/Document/ProjectDefaultDestinationForVoiceTagTests.swift`:

```swift
import Foundation
import XCTest
@testable import SequencerAI

final class ProjectDefaultDestinationForVoiceTagTests: XCTestCase {
    func test_kick_tag_returns_sample_when_library_has_kick() {
        let library = AudioSampleLibrary.shared
        guard AudioSampleCategory(voiceTag: "kick") != nil,
              library.firstSample(in: .kick) != nil
        else {
            throw XCTSkip("Library has no kick sample in the test environment; skipping")
        }
        let dest = Project.defaultDestination(forVoiceTag: "kick", fallbackPresetName: "test", library: library)
        guard case .sample = dest else {
            return XCTFail("expected .sample for kick tag; got \(dest)")
        }
    }

    func test_unknown_tag_returns_internalSampler_fallback() {
        let dest = Project.defaultDestination(forVoiceTag: "does-not-exist", fallbackPresetName: "808 Kit", library: AudioSampleLibrary.shared)
        guard case let .internalSampler(bankID, preset) = dest else {
            return XCTFail("expected .internalSampler fallback; got \(dest)")
        }
        XCTAssertEqual(bankID, .drumKitDefault)
        XCTAssertEqual(preset, "808 Kit")
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/ProjectDefaultDestinationForVoiceTagTests \
  2>&1 | tail -20
```

Expected: compile failure — `Project.defaultDestination(forVoiceTag:fallbackPresetName:library:)` does not exist.

- [ ] **Step 3: Add the helper**

In `Sources/Document/Project+Tracks.swift`, add this static method alongside the existing `defaultDestination(for:)` (around line 151):

```swift
    static func defaultDestination(
        forVoiceTag tag: VoiceTag,
        fallbackPresetName: String,
        library: AudioSampleLibrary = .shared
    ) -> Destination {
        guard let category = AudioSampleCategory(voiceTag: tag),
              let sample = library.firstSample(in: category)
        else {
            return .internalSampler(bankID: .drumKitDefault, preset: fallbackPresetName)
        }
        return .sample(sampleID: sample.id, settings: .default)
    }
```

Leave the existing inline lookup in `addDrumKit` alone for now (Task 4 will replace it).

- [ ] **Step 4: Run the tests to verify they pass**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/ProjectDefaultDestinationForVoiceTagTests \
  2>&1 | tail -15
```

Expected: both tests pass (the kick test may be skipped if the library lacks a kick sample).

- [ ] **Step 5: Run the full test suite to check for regressions**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  2>&1 | tail -15
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/Document/Project+Tracks.swift Tests/SequencerAITests/Document/ProjectDefaultDestinationForVoiceTagTests.swift
git commit -m "feat(document): defaultDestination(forVoiceTag:fallbackPresetName:library:) helper"
```

---

## Task 3: `Project.addDrumGroup(plan:library:)` — materialise a plan

Takes a `DrumGroupPlan` and appends the tracks, clip pool entries, pattern banks, and `TrackGroup` to the project. This is a new method; `addDrumKit` stays untouched until Task 4.

**Files:**
- Create: `Sources/Document/Project+DrumGroups.swift`
- Test: `Tests/SequencerAITests/Document/ProjectAddDrumGroupTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `Tests/SequencerAITests/Document/ProjectAddDrumGroupTests.swift`:

```swift
import Foundation
import XCTest
@testable import SequencerAI

final class ProjectAddDrumGroupTests: XCTestCase {
    func test_empty_members_returns_nil_and_leaves_project_unchanged() {
        var project = Project.empty
        let snapshot = project
        var plan = DrumGroupPlan.blankDefault
        plan.members = []
        let result = project.addDrumGroup(plan: plan)
        XCTAssertNil(result)
        XCTAssertEqual(project.tracks, snapshot.tracks)
        XCTAssertEqual(project.trackGroups, snapshot.trackGroups)
        XCTAssertEqual(project.clipPool, snapshot.clipPool)
    }

    func test_blankDefault_creates_four_tracks_named_kick_snare_hat_clap() {
        var project = Project.empty
        let initialTrackCount = project.tracks.count
        let groupID = project.addDrumGroup(plan: .blankDefault)
        XCTAssertNotNil(groupID)
        XCTAssertEqual(project.tracks.count, initialTrackCount + 4)
        let newNames = project.tracks.suffix(4).map(\.name)
        XCTAssertEqual(newNames, ["Kick", "Snare", "Hat", "Clap"])
    }

    func test_blankDefault_creates_a_group_with_no_shared_destination() {
        var project = Project.empty
        let groupID = project.addDrumGroup(plan: .blankDefault)
        guard let groupID, let group = project.trackGroups.first(where: { $0.id == groupID }) else {
            return XCTFail("expected a new group to exist")
        }
        XCTAssertNil(group.sharedDestination)
        XCTAssertEqual(group.memberIDs.count, 4)
        XCTAssertEqual(group.color, "#8AA")
        XCTAssertEqual(group.name, "Drum Group")
    }

    func test_blankDefault_all_clips_have_all_false_step_patterns() {
        var project = Project.empty
        _ = project.addDrumGroup(plan: .blankDefault)
        let newClips = project.clipPool.suffix(4)
        for clip in newClips {
            guard case let .stepSequence(stepPattern, _) = clip.content else {
                return XCTFail("expected .stepSequence content")
            }
            XCTAssertTrue(stepPattern.allSatisfy { $0 == false }, "blank clip should be all-false")
        }
    }

    func test_templated_kit808_seeds_match_preset_patterns_when_prepopulate_on() {
        var project = Project.empty
        let plan = DrumGroupPlan.templated(from: .kit808)
        _ = project.addDrumGroup(plan: plan)
        let newClips = Array(project.clipPool.suffix(plan.members.count))
        for (clip, planMember) in zip(newClips, plan.members) {
            guard case let .stepSequence(stepPattern, _) = clip.content else {
                return XCTFail("expected .stepSequence content")
            }
            XCTAssertEqual(stepPattern, planMember.seedPattern)
        }
    }

    func test_templated_kit808_with_prepopulate_off_produces_empty_clips() {
        var project = Project.empty
        var plan = DrumGroupPlan.templated(from: .kit808)
        plan.prepopulateClips = false
        _ = project.addDrumGroup(plan: plan)
        let newClips = Array(project.clipPool.suffix(plan.members.count))
        for clip in newClips {
            guard case let .stepSequence(stepPattern, _) = clip.content else {
                return XCTFail("expected .stepSequence content")
            }
            XCTAssertTrue(stepPattern.allSatisfy { $0 == false })
        }
    }

    func test_shared_destination_with_all_routed_sets_inheritGroup_on_every_member() {
        var project = Project.empty
        var plan = DrumGroupPlan.templated(from: .kit808)
        plan.sharedDestination = .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0)
        _ = project.addDrumGroup(plan: plan)
        let newTracks = Array(project.tracks.suffix(plan.members.count))
        for track in newTracks {
            XCTAssertEqual(track.destination, .inheritGroup, "track=\(track.name)")
        }
        guard let group = project.trackGroups.last else {
            return XCTFail("expected a new group")
        }
        XCTAssertEqual(group.sharedDestination, .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0))
    }

    func test_shared_destination_with_mixed_routing_respects_per_member_flag() {
        var project = Project.empty
        var plan = DrumGroupPlan.templated(from: .kit808)
        plan.sharedDestination = .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0)
        // Keep kick and snare routed, unroute hat and clap
        for index in plan.members.indices {
            plan.members[index].routesToShared = (index < 2)
        }
        _ = project.addDrumGroup(plan: plan)
        let newTracks = Array(project.tracks.suffix(plan.members.count))
        XCTAssertEqual(newTracks[0].destination, .inheritGroup, "kick expected to route to shared")
        XCTAssertEqual(newTracks[1].destination, .inheritGroup, "snare expected to route to shared")
        XCTAssertNotEqual(newTracks[2].destination, .inheritGroup, "hat expected to use per-voice default")
        XCTAssertNotEqual(newTracks[3].destination, .inheritGroup, "clap expected to use per-voice default")
    }

    func test_no_shared_destination_gives_every_member_a_per_voice_default() {
        var project = Project.empty
        _ = project.addDrumGroup(plan: .templated(from: .kit808))
        let newTracks = Array(project.tracks.suffix(4))
        for track in newTracks {
            XCTAssertNotEqual(track.destination, .inheritGroup)
            XCTAssertNotEqual(track.destination, .none)
        }
    }

    func test_each_member_gets_one_clip_pool_entry_and_one_pattern_bank() {
        var project = Project.empty
        let initialClipCount = project.clipPool.count
        let initialBankCount = project.patternBanks.count
        _ = project.addDrumGroup(plan: .templated(from: .kit808))
        XCTAssertEqual(project.clipPool.count, initialClipCount + 4)
        XCTAssertEqual(project.patternBanks.count, initialBankCount + 4)
    }

    func test_selected_track_becomes_first_new_member() {
        var project = Project.empty
        _ = project.addDrumGroup(plan: .templated(from: .kit808))
        let firstNewTrackID = project.tracks.suffix(4).first!.id
        XCTAssertEqual(project.selectedTrackID, firstNewTrackID)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/ProjectAddDrumGroupTests \
  2>&1 | tail -25
```

Expected: compile failure — `addDrumGroup(plan:)` does not exist.

- [ ] **Step 3: Implement `addDrumGroup`**

Create `Sources/Document/Project+DrumGroups.swift`:

```swift
import Foundation

extension Project {
    @discardableResult
    mutating func addDrumGroup(
        plan: DrumGroupPlan,
        library: AudioSampleLibrary = .shared
    ) -> TrackGroupID? {
        guard !plan.members.isEmpty else {
            return nil
        }

        let groupID = TrackGroupID()
        var newTracks: [StepSequenceTrack] = []
        var newBanks: [TrackPatternBank] = []

        for member in plan.members {
            let destination: Destination
            if plan.sharedDestination != nil, member.routesToShared {
                destination = .inheritGroup
            } else {
                destination = Self.defaultDestination(
                    forVoiceTag: member.tag,
                    fallbackPresetName: plan.name,
                    library: library
                )
            }

            let effectiveSeedPattern = plan.prepopulateClips
                ? member.seedPattern
                : Array(repeating: false, count: member.seedPattern.count)

            let track = StepSequenceTrack(
                name: member.trackName,
                trackType: .monoMelodic,
                pitches: [DrumKitNoteMap.baselineNote],
                stepPattern: effectiveSeedPattern,
                destination: destination,
                groupID: groupID,
                velocity: StepSequenceTrack.default.velocity,
                gateLength: StepSequenceTrack.default.gateLength
            )
            let clip = ClipPoolEntry(
                id: UUID(),
                name: member.trackName,
                trackType: .monoMelodic,
                content: .stepSequence(
                    stepPattern: effectiveSeedPattern,
                    pitches: [DrumKitNoteMap.baselineNote]
                )
            )
            clipPool.append(clip)
            newTracks.append(track)
            newBanks.append(TrackPatternBank.default(for: track, initialClipID: clip.id))
        }

        tracks.append(contentsOf: newTracks)
        patternBanks.append(contentsOf: newBanks)
        trackGroups.append(
            TrackGroup(
                id: groupID,
                name: plan.name,
                color: plan.color,
                memberIDs: newTracks.map(\.id),
                sharedDestination: plan.sharedDestination,
                noteMapping: [:]
            )
        )
        selectedTrackID = newTracks.first?.id ?? selectedTrackID
        syncPhrasesWithTracks()
        return groupID
    }
}
```

- [ ] **Step 4: Run the tests to verify they pass**

```bash
xcodegen generate && \
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/ProjectAddDrumGroupTests \
  2>&1 | tail -15
```

Expected: all eleven tests pass.

- [ ] **Step 5: Run the full test suite**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  2>&1 | tail -15
```

Expected: all tests pass (existing `addDrumKit` tests unaffected — that function is untouched).

- [ ] **Step 6: Commit**

```bash
git add Sources/Document/Project+DrumGroups.swift Tests/SequencerAITests/Document/ProjectAddDrumGroupTests.swift project.yml
git commit -m "feat(document): Project.addDrumGroup(plan:) materialises a DrumGroupPlan"
```

---

## Task 4: Rewrite `addDrumKit` as a shim over `addDrumGroup`

Rewrite `Project.addDrumKit(_:library:)` to compose a `DrumGroupPlan.templated(from:)` and delegate to `addDrumGroup(plan:library:)`. Observable behavior must match today's implementation exactly.

**Files:**
- Modify: `Sources/Document/Project+Tracks.swift` (replace `addDrumKit` body)
- Test: `Tests/SequencerAITests/Document/ProjectAddDrumKitShimTests.swift`

- [ ] **Step 1: Write the regression tests**

Create `Tests/SequencerAITests/Document/ProjectAddDrumKitShimTests.swift`:

```swift
import Foundation
import XCTest
@testable import SequencerAI

final class ProjectAddDrumKitShimTests: XCTestCase {
    func test_addDrumKit_produces_same_track_names_as_preset_members_for_each_preset() {
        for preset in DrumKitPreset.allCases {
            var project = Project.empty
            let initialCount = project.tracks.count
            let groupID = project.addDrumKit(preset)
            XCTAssertNotNil(groupID, "preset=\(preset.rawValue)")
            let expectedNames = preset.members.map(\.trackName)
            let actualNames = project.tracks.suffix(preset.members.count).map(\.name)
            XCTAssertEqual(Array(actualNames), expectedNames, "preset=\(preset.rawValue)")
            XCTAssertEqual(project.tracks.count, initialCount + preset.members.count)
        }
    }

    func test_addDrumKit_creates_group_with_preset_name_and_color_and_no_shared_destination() {
        for preset in DrumKitPreset.allCases {
            var project = Project.empty
            let groupID = project.addDrumKit(preset)
            guard let groupID, let group = project.trackGroups.first(where: { $0.id == groupID }) else {
                return XCTFail("preset=\(preset.rawValue): expected a new group")
            }
            XCTAssertEqual(group.name, preset.displayName)
            XCTAssertEqual(group.color, preset.suggestedGroupColor)
            XCTAssertNil(group.sharedDestination)
            XCTAssertEqual(group.memberIDs.count, preset.members.count)
        }
    }

    func test_addDrumKit_seeds_step_patterns_from_preset_members() {
        for preset in DrumKitPreset.allCases {
            var project = Project.empty
            _ = project.addDrumKit(preset)
            let newClips = Array(project.clipPool.suffix(preset.members.count))
            for (clip, presetMember) in zip(newClips, preset.members) {
                guard case let .stepSequence(stepPattern, _) = clip.content else {
                    return XCTFail("preset=\(preset.rawValue) expected .stepSequence")
                }
                XCTAssertEqual(stepPattern, presetMember.seedPattern, "preset=\(preset.rawValue) clip=\(clip.name)")
            }
        }
    }

    func test_addDrumKit_destinations_are_never_inheritGroup() {
        for preset in DrumKitPreset.allCases {
            var project = Project.empty
            _ = project.addDrumKit(preset)
            let newTracks = Array(project.tracks.suffix(preset.members.count))
            for track in newTracks {
                XCTAssertNotEqual(track.destination, .inheritGroup, "preset=\(preset.rawValue) track=\(track.name)")
            }
        }
    }
}
```

- [ ] **Step 2: Run the tests — they should PASS against today's implementation**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/ProjectAddDrumKitShimTests \
  2>&1 | tail -15
```

Expected: all four tests pass. This is a regression guard — they must already pass before we change `addDrumKit`, then continue to pass after.

- [ ] **Step 3: Replace `addDrumKit`'s body**

In `Sources/Document/Project+Tracks.swift`, replace the `addDrumKit(_:library:)` function (currently lines 24–84) with:

```swift
    @discardableResult
    mutating func addDrumKit(
        _ preset: DrumKitPreset,
        library: AudioSampleLibrary = .shared
    ) -> TrackGroupID? {
        addDrumGroup(plan: .templated(from: preset), library: library)
    }
```

- [ ] **Step 4: Run the shim tests to verify they still pass**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  -only-testing:SequencerAITests/ProjectAddDrumKitShimTests \
  2>&1 | tail -15
```

Expected: all four tests pass.

- [ ] **Step 5: Run the full test suite**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  2>&1 | tail -20
```

Expected: all tests pass, including `ProjectAddDrumKitClipTests` and `DrumKitPresetSampleTests`. If any existing test fails: investigate — the shim is supposed to be a pure refactor. If a test assertion is brittle (e.g., compares the exact order of `patternBanks.append` vs `tracks.append`) but the observable shape is preserved, update the assertion to match the new ordering only after confirming the shape is still correct.

- [ ] **Step 6: Commit**

```bash
git add Sources/Document/Project+Tracks.swift Tests/SequencerAITests/Document/ProjectAddDrumKitShimTests.swift
git commit -m "refactor(document): addDrumKit becomes a shim over addDrumGroup"
```

---

## Task 5: `AddDrumGroupSheet` — the modal view

The SwiftUI sheet. Owns form state, presents a nested `AddDestinationSheet` (from single-destination-ui) for picking the shared destination, and returns a `DrumGroupPlan` via `onCreate`.

**Files:**
- Create: `Sources/UI/DrumGroup/AddDrumGroupSheet.swift`

This task is UI-only with no automated tests (matching the project's existing UI-testing posture). Build + manual smoke verification live in Task 7.

- [ ] **Step 1: Create the sheet**

Write `Sources/UI/DrumGroup/AddDrumGroupSheet.swift`:

```swift
import SwiftUI

struct AddDrumGroupSheet: View {
    let auInstruments: [AudioInstrumentChoice]
    let onCreate: (DrumGroupPlan) -> Void
    let onCancel: () -> Void

    @State private var mode: Mode = .blank
    @State private var selectedPreset: DrumKitPreset = .kit808
    @State private var plan: DrumGroupPlan = .blankDefault
    @State private var addSharedDestinationOn: Bool = false
    @State private var isPresentingDestinationPicker: Bool = false
    @State private var destinationPickerTrigger: PickerTrigger = .initial

    private enum Mode: Hashable { case blank, templated }
    private enum PickerTrigger { case initial, repick }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            templateSection
            tracksSection
            optionsSection
            Spacer(minLength: 0)
            footer
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 560)
        .background(StudioTheme.background)
        .sheet(isPresented: $isPresentingDestinationPicker) {
            AddDestinationSheet(
                isInGroup: false,
                auInstruments: auInstruments,
                onCommit: { destination in
                    isPresentingDestinationPicker = false
                    plan.sharedDestination = destination
                    addSharedDestinationOn = true
                },
                onCancel: {
                    isPresentingDestinationPicker = false
                    if destinationPickerTrigger == .initial {
                        addSharedDestinationOn = false
                        plan.sharedDestination = nil
                    }
                }
            )
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Add Drum Group")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(StudioTheme.text)
            Text("Pick a template or start blank. Configure optional shared routing before creating.")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(StudioTheme.mutedText)
        }
    }

    private var templateSection: some View {
        HStack(spacing: 16) {
            Picker("Template", selection: $mode) {
                Text("Blank").tag(Mode.blank)
                Text("Templated").tag(Mode.templated)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 260)
            .onChange(of: mode) { _, newValue in
                applyMode(newValue)
            }

            if mode == .templated {
                Picker("Preset", selection: $selectedPreset) {
                    ForEach(DrumKitPreset.allCases, id: \.self) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .onChange(of: selectedPreset) { _, newValue in
                    applyTemplatedPreset(newValue)
                }
            }
            Spacer()
        }
    }

    private var tracksSection: some View {
        StudioPanel(title: "Tracks", eyebrow: tracksEyebrow, accent: StudioTheme.cyan) {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(plan.members.indices, id: \.self) { index in
                    trackRow(at: index)
                }
                if mode == .blank {
                    Button(action: appendBlankRow) {
                        Label("Add track", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, 4)
                }
            }
        }
    }

    private var tracksEyebrow: String {
        "\(plan.members.count) track\(plan.members.count == 1 ? "" : "s") — \(mode == .blank ? "editable" : "read-only preview")"
    }

    @ViewBuilder
    private func trackRow(at index: Int) -> some View {
        HStack(spacing: 12) {
            if mode == .blank {
                TextField("Track name", text: Binding(
                    get: { plan.members[index].trackName },
                    set: { plan.members[index].trackName = $0 }
                ))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 200)
            } else {
                Text(plan.members[index].trackName)
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .foregroundStyle(StudioTheme.text)
                    .frame(maxWidth: 200, alignment: .leading)
            }

            Text(plan.members[index].tag)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(StudioTheme.mutedText)
                .frame(maxWidth: 120, alignment: .leading)

            if plan.sharedDestination != nil {
                Toggle("Routes to shared", isOn: Binding(
                    get: { plan.members[index].routesToShared },
                    set: { plan.members[index].routesToShared = $0 }
                ))
                .toggleStyle(.checkbox)
            }

            Spacer(minLength: 0)

            if mode == .blank {
                Button {
                    plan.members.remove(at: index)
                } label: {
                    Image(systemName: "minus.circle")
                        .foregroundStyle(StudioTheme.mutedText)
                }
                .buttonStyle(.plain)
                .disabled(plan.members.count <= 1)
            }
        }
        .padding(.vertical, 4)
    }

    private var optionsSection: some View {
        StudioPanel(title: "Options", eyebrow: "Seed patterns and shared destination", accent: StudioTheme.violet) {
            VStack(alignment: .leading, spacing: 12) {
                if mode == .templated {
                    Toggle("Prepopulate step patterns", isOn: $plan.prepopulateClips)
                        .toggleStyle(.checkbox)
                }

                Toggle("Add shared destination", isOn: Binding(
                    get: { addSharedDestinationOn },
                    set: { newValue in
                        addSharedDestinationOn = newValue
                        if newValue {
                            destinationPickerTrigger = .initial
                            isPresentingDestinationPicker = true
                        } else {
                            plan.sharedDestination = nil
                        }
                    }
                ))
                .toggleStyle(.checkbox)

                if let destination = plan.sharedDestination {
                    HStack(spacing: 12) {
                        let summary = DestinationSummary.make(for: destination, in: .empty, trackID: Project.empty.selectedTrackID)
                        Image(systemName: summary.iconName.isEmpty ? "dot.radiowaves.left.and.right" : summary.iconName)
                            .foregroundStyle(StudioTheme.cyan)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(summary.typeLabel.isEmpty ? "Destination" : summary.typeLabel)
                                .font(.system(size: 13, weight: .bold, design: .rounded))
                                .foregroundStyle(StudioTheme.text)
                            Text(summary.detail)
                                .font(.system(size: 12, weight: .medium, design: .rounded))
                                .foregroundStyle(StudioTheme.mutedText)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button("Pick…") {
                            destinationPickerTrigger = .repick
                            isPresentingDestinationPicker = true
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(10)
                    .background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Cancel", action: onCancel)
                .buttonStyle(.bordered)
            Button("Create Group") {
                onCreate(plan)
            }
            .buttonStyle(.borderedProminent)
            .tint(StudioTheme.success)
            .disabled(plan.members.isEmpty)
        }
    }

    private func applyMode(_ newMode: Mode) {
        switch newMode {
        case .blank:
            let preserved = (plan.prepopulateClips, plan.sharedDestination)
            plan = .blankDefault
            plan.prepopulateClips = preserved.0
            plan.sharedDestination = preserved.1
        case .templated:
            applyTemplatedPreset(selectedPreset)
        }
    }

    private func applyTemplatedPreset(_ preset: DrumKitPreset) {
        let preserved = (plan.prepopulateClips, plan.sharedDestination)
        plan = .templated(from: preset)
        plan.prepopulateClips = preserved.0 || plan.prepopulateClips
        plan.sharedDestination = preserved.1
    }

    private func appendBlankRow() {
        let nextIndex = plan.members.count + 1
        plan.members.append(
            DrumGroupPlan.Member(
                tag: "kick",
                trackName: "Track \(nextIndex)",
                seedPattern: Array(repeating: false, count: 16)
            )
        )
    }
}
```

Notes on the tricky bits — if the build fails, fix inline:
- `AddDestinationSheet` and `DestinationSummary` come from the single-destination-ui plan. Their signatures are `AddDestinationSheet(isInGroup: Bool, auInstruments: [AudioInstrumentChoice], onCommit: (Destination) -> Void, onCancel: () -> Void)` and `DestinationSummary.make(for: Destination, in: Project, trackID: UUID) -> DestinationSummary`. If the shipped single-destination-ui code used a slightly different signature, adjust the call sites.
- `StudioPanel(title:eyebrow:accent:) { … }` is the existing panel helper. If its actual initialiser takes different parameter names, match them.
- `StudioTheme.background / StudioTheme.text / StudioTheme.mutedText / StudioTheme.cyan / StudioTheme.violet / StudioTheme.success` are already in use elsewhere in the project.

- [ ] **Step 2: Build**

```bash
xcodegen generate && \
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' 2>&1 | tail -20
```

Expected: build succeeds. If it fails due to API mismatches with `AddDestinationSheet`, `DestinationSummary`, or `StudioPanel` signatures, fix inline and rebuild.

- [ ] **Step 3: Commit**

```bash
git add Sources/UI/DrumGroup/AddDrumGroupSheet.swift project.yml
git commit -m "feat(ui): AddDrumGroupSheet — modal for blank or templated drum group creation"
```

---

## Task 6: Wire the Tracks page button + sheet

Replace the `Menu("Add Drum Kit")` in `TracksMatrixView` with a `Button` that presents `AddDrumGroupSheet`.

**Files:**
- Modify: `Sources/UI/TracksMatrixView.swift`

- [ ] **Step 1: Add state and the new button**

Open `Sources/UI/TracksMatrixView.swift`. Add an `@Environment(EngineController.self)` property near the top of the struct (after `@Binding var document`):

```swift
    @Environment(EngineController.self) private var engineController
```

Add a new `@State` property alongside the existing `isPresentingCreateTrack`:

```swift
    @State private var isPresentingAddDrumGroup = false
```

- [ ] **Step 2: Replace the Menu**

Replace the `Menu("Add Drum Kit") { … }` block (currently lines 90–97) with:

```swift
            Button("Add Drum Group") {
                isPresentingAddDrumGroup = true
            }
            .buttonStyle(.bordered)
```

- [ ] **Step 3: Add the sheet modifier**

Below the existing `.sheet(isPresented: $isPresentingCreateTrack) { … }` (around line 51–53), add a second sheet modifier:

```swift
        .sheet(isPresented: $isPresentingAddDrumGroup) {
            AddDrumGroupSheet(
                auInstruments: engineController.availableAudioInstruments,
                onCreate: { plan in
                    _ = document.project.addDrumGroup(plan: plan)
                    isPresentingAddDrumGroup = false
                    onOpenTrack()
                },
                onCancel: {
                    isPresentingAddDrumGroup = false
                }
            )
        }
```

- [ ] **Step 4: Build**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild build \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' 2>&1 | tail -15
```

Expected: build succeeds. If the `@Environment(EngineController.self)` attribute fails (older Swift / SwiftUI observation attribute mismatch), check how other views in `Sources/UI/` access the engine controller and match the style exactly (for example `TrackDestinationEditor.swift` uses `@Environment(EngineController.self)` — this should work).

- [ ] **Step 5: Run the full test suite**

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild test \
  -project SequencerAI.xcodeproj \
  -scheme SequencerAI \
  -destination 'platform=macOS' \
  2>&1 | tail -15
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add Sources/UI/TracksMatrixView.swift
git commit -m "feat(ui): Tracks page uses Add Drum Group button + modal"
```

---

## Task 7: Manual smoke + plan status + tag

**Files:** none beyond doc updates

- [ ] **Step 1: Build and open the app**

```bash
./scripts/open-latest-build.sh
```

- [ ] **Step 2: Verify action-bar swap**

- Open a fresh project. The Tracks action bar should show `Add Mono`, `Add Poly`, `Add Slice`, `Add Drum Group`. No `Menu("Add Drum Kit")` remains.

- [ ] **Step 3: Verify Blank flow**

- Tap `Add Drum Group`. Modal opens in Blank mode with four rows: `Kick, Snare, Hat, Clap`. `Add shared destination` toggle is off; no `Prepopulate step patterns` toggle visible.
- Rename `Kick` to `Boom`. Remove `Clap`. Tap `+ Add track` — a fifth row `Track 4` appears with tag `kick`.
- Tap `Create Group`. Modal closes. Tracks matrix shows a new group with four tracks (`Boom, Snare, Hat, Track 4`) all with per-voice default destinations. Group's `sharedDestination` is nil.

- [ ] **Step 4: Verify Templated flow with prepopulate on**

- Reopen the modal. Switch to Templated — preset defaults to `808 Kit`. Rows become read-only: `Kick, Snare, Hat, Clap`. `Prepopulate step patterns` toggle visible and on.
- Change preset to `Techno Kit`. Rows update to `Kick, Snare, Hat, Ride`.
- Tap `Create Group`. Verify the new tracks have their preset seed patterns on the matrix view.

- [ ] **Step 5: Verify Templated flow with prepopulate off**

- Reopen. Switch to Templated → `808 Kit`. Turn `Prepopulate step patterns` off.
- Tap `Create Group`. Open one of the new tracks in the Track workspace. Its phrase is empty (no seeded steps).

- [ ] **Step 6: Verify shared destination — all routed**

- Reopen. Switch to Templated → `808 Kit`. Flip `Add shared destination` on. Nested `Add Destination` sheet opens. Pick `Virtual MIDI Out`. Nested sheet closes. A destination summary row appears. Per-row `Routes to shared` checkboxes appear, all checked.
- Tap `Create Group`. Every new track's Output panel shows `Inherit Group` (per single-destination-ui surface). The group's shared destination is `MIDI · SequencerAI Out · ch 1`.

- [ ] **Step 7: Verify shared destination — mixed routing**

- Reopen. Templated → `808 Kit`. Flip `Add shared destination` on, pick `Virtual MIDI Out`. Uncheck `Routes to shared` on the `Hat` and `Clap` rows.
- Tap `Create Group`. `Kick` and `Snare` show `Inherit Group`; `Hat` and `Clap` show their per-voice default destinations.

- [ ] **Step 8: Verify nested picker cancel**

- Reopen. Flip `Add shared destination` on. Nested sheet opens. Tap `Cancel`. Nested sheet dismisses; the toggle flips back off; no checkboxes appear on rows.

- [ ] **Step 9: Verify repick cancel**

- Reopen. Flip `Add shared destination` on, pick `Virtual MIDI Out`. Tap `Pick…`. Nested sheet opens. Tap `Cancel`. `plan.sharedDestination` is preserved (still `MIDI · SequencerAI Out · ch 1`); checkboxes remain visible.

- [ ] **Step 10: Flip plan status + tag**

Edit `docs/plans/2026-04-21-add-drum-group-modal.md`: replace `**Status:** Not started.` with `**Status:** ✅ Completed 2026-04-21. Tag v0.0.21-add-drum-group-modal.`

```bash
git add docs/plans/2026-04-21-add-drum-group-modal.md
git commit -m "docs(plan): mark add-drum-group-modal completed"
git tag -a v0.0.21-add-drum-group-modal -m "Add Drum Group modal: blank / templated, shared destination + per-member routing"
```

- [ ] **Step 11: Dispatch `wiki-maintainer` to refresh `wiki/pages/track-destinations.md` and `wiki/pages/automation-setup.md` if relevant**

Brief:
- Diff range: `v0.0.20-single-destination-ui..HEAD` (or the previous tag).
- Plan: `docs/plans/2026-04-21-add-drum-group-modal.md`.
- Task: document the new Add Drum Group button and modal, and the `DrumGroupPlan` / `addDrumGroup` split from `addDrumKit`.
- Commit under `docs(wiki):` prefix.

---

## Self-Review

**Spec coverage:**
- Button replaces Menu on Tracks page — Task 6. ✓
- Modal lists tracks to be created — Task 5 `tracksSection`. ✓
- Blank vs Templated toggle (with preset dropdown when templated) — Task 5 `templateSection`. ✓
- Prepopulate toggle for Templated — Task 5 `optionsSection` (templated-only). ✓
- Shared destination option + per-row checkboxes — Task 5 `optionsSection` + `trackRow` checkbox branch. ✓
- Per-row checkbox default checked — DrumGroupPlan.Member.init `routesToShared: Bool = true` in Task 1 + `DrumGroupPlan.blankDefault` and `.templated` factories set all members to true. ✓
- Shared destination defaulting + cancel behavior — Task 5 `.sheet` callbacks + `PickerTrigger`. ✓
- `addDrumGroup` materialisation per spec semantics (per-voice fallback for unchecked or no-shared-dest tracks, empty clips when `prepopulateClips = false`) — Task 3. ✓
- `addDrumKit` preserved as a shim — Task 4. ✓
- Tests for each variant — Tasks 1, 2, 3, 4. ✓

**Placeholder scan:** no TBDs or TODOs. Every step has exact code or exact commands. Defensive branches (picker cancel, preset switch, empty library) are covered inline. ✓

**Type consistency:**
- `DrumGroupPlan` / `DrumGroupPlan.Member` initialiser signatures match across Task 1 definitions and Task 3 usage (`.tag`, `.trackName`, `.seedPattern`, `.routesToShared`). ✓
- `DrumGroupPlan.blankDefault` and `.templated(from:)` match the callsite in `AddDrumGroupSheet` (`applyMode`, `applyTemplatedPreset`). ✓
- `Project.defaultDestination(forVoiceTag:fallbackPresetName:library:)` signature in Task 2 matches its use in Task 3's `addDrumGroup`. ✓
- `AddDrumGroupSheet(auInstruments:onCreate:onCancel:)` signature in Task 5 matches the call in Task 6. ✓
- `AddDestinationSheet(isInGroup:auInstruments:onCommit:onCancel:)` and `DestinationSummary.make(for:in:trackID:)` are documented in the single-destination-ui plan and re-used here. ✓

**Risks:**
- `single-destination-ui` plan may not be landed at implementation time — stated explicitly under `Depends on:` and at the top of Task 5. Blocks execution until that plan is tagged.
- SwiftUI nested `.sheet` on macOS — expect a second modal sheet to stack atop the first. This matches the single-destination-ui plan's nested picker pattern (which also uses a nested AU sheet), so it should work the same way.
- `Toggle("Routes to shared", …)` style — if `.checkbox` isn't the desired look on macOS, switch to `.switch`. Cosmetic; data flow unchanged.
- Existing `addDrumKit` tests might be order-sensitive (e.g., asserting that pattern banks are appended in a particular position). If a regression shows up in Task 4 Step 5, update only the brittle ordering assertion — not the shape.
