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
            XCTAssertEqual(Array(project.tracks.suffix(preset.members.count).map(\.name)), preset.members.map(\.trackName), "preset=\(preset.rawValue)")
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
                XCTAssertEqual(
                    noteGridMainStepPattern(clip.content),
                    presetMember.seedPattern,
                    "preset=\(preset.rawValue) clip=\(clip.name)"
                )
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
