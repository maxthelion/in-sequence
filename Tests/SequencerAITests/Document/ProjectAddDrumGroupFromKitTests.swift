import Foundation
import XCTest
@testable import SequencerAI

final class ProjectAddDrumGroupFromKitTests: XCTestCase {
    func test_creation_from_each_factory_kit_produces_kit_part_track_names() {
        for kit in DrumAssetLibrary.factoryKits {
            var project = Project.empty
            let initialCount = project.tracks.count

            let groupID = project.addDrumGroup(plan: .from(kit: kit))

            XCTAssertNotNil(groupID, "kit=\(kit.name)")
            XCTAssertEqual(Array(project.tracks.suffix(kit.parts.count).map(\.name)), kit.parts.map(\.trackName), "kit=\(kit.name)")
            XCTAssertEqual(project.tracks.count, initialCount + kit.parts.count)
        }
    }

    func test_creation_from_each_factory_kit_tags_member_tracks_with_part_tags() {
        for kit in DrumAssetLibrary.factoryKits {
            var project = Project.empty

            _ = project.addDrumGroup(plan: .from(kit: kit))

            XCTAssertEqual(
                Array(project.tracks.suffix(kit.parts.count).map(\.voiceTag)),
                kit.parts.map { $0.tag },
                "kit=\(kit.name)"
            )
        }
    }

    func test_creation_from_kit_creates_group_with_kit_name_and_no_shared_destination() {
        for kit in DrumAssetLibrary.factoryKits {
            var project = Project.empty

            let groupID = project.addDrumGroup(plan: .from(kit: kit))

            guard let groupID, let group = project.trackGroups.first(where: { $0.id == groupID }) else {
                return XCTFail("kit=\(kit.name): expected a new group")
            }
            XCTAssertEqual(group.name, kit.name)
            XCTAssertNil(group.sharedDestination)
            XCTAssertEqual(group.memberIDs.count, kit.parts.count)
        }
    }

    func test_creation_with_matching_template_seeds_slot_zero_from_template_patterns() throws {
        for kit in DrumAssetLibrary.factoryKits {
            var project = Project.empty
            let template = DrumKitFixtures.factoryTemplate(named: kit.name)

            let groupID = try XCTUnwrap(
                project.addDrumGroup(
                    plan: .from(kit: kit, templateID: template.id),
                    templateLookup: DrumKitFixtures.factoryTemplateLookup
                ),
                "kit=\(kit.name)"
            )

            let memberIDs = try XCTUnwrap(project.trackGroups.first(where: { $0.id == groupID })?.memberIDs)
            for (memberID, part) in zip(memberIDs, kit.parts) {
                let clipID = try XCTUnwrap(project.patternBank(for: memberID).slot(at: 0).sourceRef.clipID)
                let clip = try XCTUnwrap(project.clipEntry(id: clipID))
                XCTAssertEqual(
                    noteGridMainStepPattern(clip.content),
                    template.patterns[part.tag],
                    "kit=\(kit.name) part=\(part.tag)"
                )
            }
        }
    }

    func test_creation_from_kit_destinations_are_never_inheritGroup() {
        for kit in DrumAssetLibrary.factoryKits {
            var project = Project.empty

            _ = project.addDrumGroup(plan: .from(kit: kit))

            let newTracks = Array(project.tracks.suffix(kit.parts.count))
            for track in newTracks {
                XCTAssertNotEqual(track.destination, .inheritGroup, "kit=\(kit.name) track=\(track.name)")
            }
        }
    }
}
