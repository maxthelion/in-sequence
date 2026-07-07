import Foundation
import XCTest
@testable import SequencerAI

final class ProjectAddDrumGroupTests: XCTestCase {
    private var libraryRoot: URL!

    override func setUpWithError() throws {
        libraryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try ["kick", "snare", "hatClosed", "clap", "ride"].forEach(makeCategory)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: libraryRoot)
    }

    func test_empty_members_creates_empty_kit_with_dedicated_bus() {
        var project = Project.empty
        let busCountBefore = project.buses.count
        let trackCountBefore = project.tracks.count
        let clipCountBefore = project.clipPool.count
        var plan = DrumGroupPlan.blankDefault
        plan.members = []
        plan.name = "Empty Kit"

        let result = project.addDrumGroup(plan: plan, library: testLibrary)

        guard let result,
              let group = project.trackGroups.first(where: { $0.id == result })
        else {
            return XCTFail("expected empty kit creation to create a group")
        }
        XCTAssertTrue(group.memberIDs.isEmpty)
        XCTAssertEqual(group.name, "Empty Kit")
        XCTAssertEqual(project.buses.count, busCountBefore + 1)
        XCTAssertEqual(project.buses.last?.name, "Empty Kit")
        XCTAssertEqual(project.tracks.count, trackCountBefore)
        XCTAssertEqual(project.clipPool.count, clipCountBefore)
    }

    func test_blankDefault_creates_four_tracks_named_kick_snare_hat_clap() {
        var project = Project.empty
        let initialTrackCount = project.tracks.count

        let groupID = project.addDrumGroup(plan: .blankDefault, library: testLibrary)

        XCTAssertNotNil(groupID)
        XCTAssertEqual(project.tracks.count, initialTrackCount + 4)
        XCTAssertEqual(Array(project.tracks.suffix(4).map(\.name)), ["Kick", "Snare", "Hat", "Clap"])
    }

    func test_blankDefault_creates_a_group_with_no_shared_destination() {
        var project = Project.empty

        let groupID = project.addDrumGroup(plan: .blankDefault, library: testLibrary)

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

        _ = project.addDrumGroup(plan: .blankDefault, library: testLibrary)

        let newClips = project.clipPool.suffix(4)
        for clip in newClips {
            XCTAssertTrue(noteGridMainStepPattern(clip.content).allSatisfy { $0 == false }, "blank clip should be all-false")
        }
    }

    func test_kit808_with_template_seeds_slot_zero_clips_from_template_patterns() {
        var project = Project.empty
        let template = DrumKitFixtures.factoryTemplate(named: "808")
        let plan = DrumKitFixtures.templatedPlan(named: "808")

        _ = project.addDrumGroup(
            plan: plan,
            library: testLibrary,
            templateLookup: DrumKitFixtures.factoryTemplateLookup
        )

        let newClips = Array(project.clipPool.suffix(plan.members.count))
        for (clip, planMember) in zip(newClips, plan.members) {
            XCTAssertEqual(noteGridMainStepPattern(clip.content), template.patterns[planMember.tag])
        }
    }

    func test_kit808_without_template_produces_empty_clips() {
        var project = Project.empty
        let plan = DrumGroupPlan.from(kit: DrumKitFixtures.factoryKit(named: "808"))

        _ = project.addDrumGroup(plan: plan, library: testLibrary)

        let newClips = Array(project.clipPool.suffix(plan.members.count))
        for clip in newClips {
            XCTAssertTrue(noteGridMainStepPattern(clip.content).allSatisfy { $0 == false })
        }
    }

    func test_shared_destination_with_all_routed_sets_inheritGroup_on_every_member() {
        var project = Project.empty
        var plan = DrumGroupPlan.from(kit: DrumKitFixtures.factoryKit(named: "808"))
        plan.sharedDestination = .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0)

        _ = project.addDrumGroup(plan: plan, library: testLibrary)

        let newTracks = Array(project.tracks.suffix(plan.members.count))
        for track in newTracks {
            XCTAssertEqual(track.destination, .inheritGroup, "track=\(track.name)")
        }
        guard let group = project.trackGroups.last else {
            return XCTFail("expected a new group")
        }
        XCTAssertEqual(group.sharedDestination, .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0))
    }

    func test_shared_midi_destination_seeds_note_offsets_and_channels_by_member_order() {
        var project = Project.empty
        var plan = DrumGroupPlan.from(kit: DrumKitFixtures.factoryKit(named: "808"))
        plan.sharedDestination = .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0)

        let groupID = project.addDrumGroup(plan: plan, library: testLibrary)

        guard let groupID, let group = project.trackGroups.first(where: { $0.id == groupID }) else {
            return XCTFail("expected a new group")
        }
        let expectedNoteMapping = Dictionary(uniqueKeysWithValues: zip(group.memberIDs, plan.members).map { memberID, member in
            (memberID, Int(DrumKitNoteMap.note(for: member.tag)) - DrumKitNoteMap.baselineNote)
        })
        let expectedChannelMapping = Dictionary(uniqueKeysWithValues: group.memberIDs.enumerated().map { index, memberID in
            (memberID, UInt8(index))
        })

        XCTAssertEqual(group.triggerMappingMode, .perNote)
        XCTAssertEqual(group.noteMapping, expectedNoteMapping)
        XCTAssertEqual(group.channelMapping, expectedChannelMapping)
    }

    func test_removeFromGroup_prunes_note_and_channel_mappings_for_removed_member() {
        var project = Project.empty
        var plan = DrumGroupPlan.from(kit: DrumKitFixtures.factoryKit(named: "808"))
        plan.sharedDestination = .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0)

        let groupID = project.addDrumGroup(plan: plan, library: testLibrary)

        guard let groupID, let removedTrackID = project.trackGroups.first(where: { $0.id == groupID })?.memberIDs[1] else {
            return XCTFail("expected a populated group")
        }

        project.removeFromGroup(trackID: removedTrackID)

        guard let group = project.trackGroups.first(where: { $0.id == groupID }) else {
            return XCTFail("expected group to remain")
        }
        XCTAssertFalse(group.memberIDs.contains(removedTrackID))
        XCTAssertNil(group.noteMapping[removedTrackID])
        XCTAssertNil(group.channelMapping[removedTrackID])
        XCTAssertEqual(Set(group.noteMapping.keys), Set(group.memberIDs))
        XCTAssertEqual(Set(group.channelMapping.keys), Set(group.memberIDs))
    }

    func test_addToGroup_move_prunes_previous_group_note_and_channel_mappings() {
        var project = Project.empty
        var plan = DrumGroupPlan.from(kit: DrumKitFixtures.factoryKit(named: "808"))
        plan.sharedDestination = .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0)

        let sourceGroupID = project.addDrumGroup(plan: plan, library: testLibrary)
        let destinationGroupID = project.addDrumGroup(plan: plan, library: testLibrary)

        guard let sourceGroupID,
              let destinationGroupID,
              let movedTrackID = project.trackGroups.first(where: { $0.id == sourceGroupID })?.memberIDs[2]
        else {
            return XCTFail("expected two populated groups")
        }

        project.addToGroup(trackID: movedTrackID, groupID: destinationGroupID)

        guard let sourceGroup = project.trackGroups.first(where: { $0.id == sourceGroupID }),
              let destinationGroup = project.trackGroups.first(where: { $0.id == destinationGroupID }),
              let movedTrack = project.tracks.first(where: { $0.id == movedTrackID })
        else {
            return XCTFail("expected moved track and groups to remain")
        }
        XCTAssertEqual(movedTrack.groupID, destinationGroupID)
        XCTAssertFalse(sourceGroup.memberIDs.contains(movedTrackID))
        XCTAssertNil(sourceGroup.noteMapping[movedTrackID])
        XCTAssertNil(sourceGroup.channelMapping[movedTrackID])
        XCTAssertEqual(Set(sourceGroup.noteMapping.keys), Set(sourceGroup.memberIDs))
        XCTAssertEqual(Set(sourceGroup.channelMapping.keys), Set(sourceGroup.memberIDs))
        XCTAssertTrue(destinationGroup.memberIDs.contains(movedTrackID))
        XCTAssertTrue(Set(destinationGroup.noteMapping.keys).isSubset(of: Set(destinationGroup.memberIDs)))
        XCTAssertTrue(Set(destinationGroup.channelMapping.keys).isSubset(of: Set(destinationGroup.memberIDs)))
    }

    func test_shared_destination_with_mixed_routing_respects_per_member_flag() {
        var project = Project.empty
        var plan = DrumGroupPlan.from(kit: DrumKitFixtures.factoryKit(named: "808"))
        plan.sharedDestination = .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0)
        for index in plan.members.indices {
            plan.members[index].routesToShared = index < 2
        }

        _ = project.addDrumGroup(plan: plan, library: testLibrary)

        let newTracks = Array(project.tracks.suffix(plan.members.count))
        XCTAssertEqual(newTracks[0].destination, .inheritGroup)
        XCTAssertEqual(newTracks[1].destination, .inheritGroup)
        XCTAssertNotEqual(newTracks[2].destination, .inheritGroup)
        XCTAssertNotEqual(newTracks[3].destination, .inheritGroup)
    }

    func test_no_shared_destination_gives_every_member_a_per_voice_default() {
        var project = Project.empty

        _ = project.addDrumGroup(plan: .from(kit: DrumKitFixtures.factoryKit(named: "808")), library: testLibrary)

        let newTracks = Array(project.tracks.suffix(4))
        for track in newTracks {
            XCTAssertNotEqual(track.destination, .inheritGroup)
            XCTAssertNotEqual(track.destination, .none)
        }
    }

    func test_no_shared_destination_keeps_sample_and_internal_defaults_with_empty_group_mappings() {
        var project = Project.empty
        let plan = DrumGroupPlan(
            name: "Mixed Local Kit",
            color: "#8AA",
            members: [
                DrumGroupPlan.Member(tag: "kick", trackName: "Kick"),
                DrumGroupPlan.Member(tag: "cowbell", trackName: "Cowbell"),
            ],
            sharedDestination: nil
        )

        let groupID = project.addDrumGroup(plan: plan, library: testLibrary)

        guard let groupID, let group = project.trackGroups.first(where: { $0.id == groupID }) else {
            return XCTFail("expected a new group")
        }
        let newTracks = Array(project.tracks.suffix(plan.members.count))
        XCTAssertEqual(newTracks[0].destination.kind, .sample)
        XCTAssertEqual(newTracks[1].destination.kind, .internalSampler)
        XCTAssertEqual(group.noteMapping, [:])
        XCTAssertEqual(group.channelMapping, [:])
    }

    func test_each_member_gets_one_clip_pool_entry_and_one_pattern_bank() {
        var project = Project.empty
        let initialClipCount = project.clipPool.count
        let initialBankCount = project.patternBanks.count

        _ = project.addDrumGroup(plan: .from(kit: DrumKitFixtures.factoryKit(named: "808")), library: testLibrary)

        XCTAssertEqual(project.clipPool.count, initialClipCount + 4)
        XCTAssertEqual(project.patternBanks.count, initialBankCount + 4)
    }

    func test_selected_track_becomes_first_new_member() {
        var project = Project.empty

        _ = project.addDrumGroup(plan: .from(kit: DrumKitFixtures.factoryKit(named: "808")), library: testLibrary)

        let firstNewTrackID = project.tracks.suffix(4).first?.id
        XCTAssertEqual(project.selectedTrackID, firstNewTrackID)
    }

    func test_addDrumGroup_preserves_existing_macroLayers() {
        var project = Project.empty
        let trackID = project.selectedTrackID
        let descriptor = TrackMacroDescriptor(
            id: UUID(),
            displayName: "Cutoff",
            minValue: 0,
            maxValue: 1,
            defaultValue: 0.5,
            valueType: .scalar,
            source: .auParameter(address: 1, identifier: "cutoff")
        )
        XCTAssertTrue(project.addAUMacro(descriptor: descriptor, to: trackID))
        project.syncMacroLayers()

        let macroLayerID = "macro-\(trackID.uuidString)-\(descriptor.id.uuidString)"
        let layerCountBefore = project.layers.count
        let macroLayerIDsBefore = Set(project.layers.map(\.id))

        let groupID = project.addDrumGroup(plan: .from(kit: DrumKitFixtures.factoryKit(named: "808")), library: testLibrary)

        XCTAssertNotNil(groupID)
        XCTAssertEqual(project.tracks.suffix(4).count, 4)

        // The pre-existing macro layer must still be present with the same ID.
        XCTAssertTrue(
            project.layers.contains { $0.id == macroLayerID },
            "Macro layer '\(macroLayerID)' must survive addDrumGroup"
        )

        // No macro layers from before addDrumGroup should have been removed.
        for id in macroLayerIDsBefore {
            XCTAssertTrue(
                project.layers.contains { $0.id == id },
                "Layer '\(id)' present before addDrumGroup must not be removed"
            )
        }

        // Layer count must be preserved: addDrumGroup does not remove existing layers.
        // Drum tracks don't add AU macro layers (they have no bindings), so the
        // count is the same or higher (if the implementation adds track-specific
        // overhead layers in future).
        XCTAssertGreaterThanOrEqual(
            project.layers.count,
            layerCountBefore,
            "addDrumGroup must not remove existing layers"
        )
    }

    func test_new_drum_part_seeds_default_macro_template_m1_direction_m2_length_m3_cutoff() {
        var project = Project.empty

        let groupID = project.addDrumGroup(plan: .blankDefault, library: testLibrary)

        guard let groupID, let group = project.trackGroups.first(where: { $0.id == groupID }),
              let firstMemberID = group.memberIDs.first,
              let track = project.tracks.first(where: { $0.id == firstMemberID })
        else {
            return XCTFail("expected a populated drum group")
        }

        let bySlot = Dictionary(uniqueKeysWithValues: track.macros.map { ($0.slotIndex, $0) })
        XCTAssertEqual(bySlot[0]?.source, .builtin(.sampleStart), "M1 should be sample direction (sampleStart)")
        XCTAssertEqual(bySlot[1]?.source, .builtin(.sampleLength), "M2 should be sample length")
        XCTAssertEqual(bySlot[2]?.source, .builtin(.samplerFilterCutoff), "M3 should be filter cutoff")
        XCTAssertEqual(track.macros.count, 3, "exactly three seeded slots, all editable/removable")

        // Each seeded binding has a backing phrase layer so its value resolves.
        for binding in track.macros {
            let layerID = "macro-\(track.id.uuidString)-\(binding.id.uuidString)"
            XCTAssertTrue(project.layers.contains { $0.id == layerID }, "missing macro layer for slot \(binding.slotIndex)")
        }
    }

    func test_default_routing_creates_dedicated_bus_named_after_group_and_routes_members() {
        var project = Project.empty
        let busCountBefore = project.buses.count
        var plan = DrumGroupPlan.from(kit: DrumKitFixtures.factoryKit(named: "808"))
        plan.name = "My Kit"

        let groupID = project.addDrumGroup(plan: plan, library: testLibrary)

        guard let groupID, let group = project.trackGroups.first(where: { $0.id == groupID }) else {
            return XCTFail("expected a new group")
        }
        XCTAssertEqual(project.buses.count, busCountBefore + 1, "default routing creates exactly one bus")
        guard let newBus = project.buses.last else {
            return XCTFail("expected a new bus")
        }
        XCTAssertEqual(newBus.name, "My Kit", "the dedicated bus is named after the group")
        for memberID in group.memberIDs {
            let track = project.tracks.first { $0.id == memberID }
            XCTAssertEqual(track?.outputBusID, newBus.id, "every member routes to the dedicated bus")
        }
        XCTAssertEqual(Set(project.trackIDsRouted(to: newBus.id)), Set(group.memberIDs))
    }

    func test_master_routing_creates_no_bus_and_leaves_members_on_master() {
        var project = Project.empty
        let busCountBefore = project.buses.count
        var plan = DrumGroupPlan.from(kit: DrumKitFixtures.factoryKit(named: "808"))
        plan.busRouting = .master

        let groupID = project.addDrumGroup(plan: plan, library: testLibrary)

        guard let groupID, let group = project.trackGroups.first(where: { $0.id == groupID }) else {
            return XCTFail("expected a new group")
        }
        XCTAssertEqual(project.buses.count, busCountBefore, "Master routing creates no bus")
        for memberID in group.memberIDs {
            let track = project.tracks.first { $0.id == memberID }
            XCTAssertNil(track?.outputBusID, "Master-routed members have no output bus")
        }
    }

    func test_blankDefault_routes_to_a_dedicated_bus_by_default() {
        var project = Project.empty

        let groupID = project.addDrumGroup(plan: .blankDefault, library: testLibrary)

        guard let groupID, let group = project.trackGroups.first(where: { $0.id == groupID }),
              let firstMemberID = group.memberIDs.first,
              let track = project.tracks.first(where: { $0.id == firstMemberID })
        else {
            return XCTFail("expected a populated group")
        }
        XCTAssertNotNil(track.outputBusID, "the default routing is a dedicated bus, not Master")
        XCTAssertEqual(project.mixerBus(id: track.outputBusID!)?.name, "Drum Group")
    }

    func test_addDrumPart_to_empty_dedicatedBusGroup_routes_new_part_to_kitBus() {
        var project = Project.empty
        var plan = DrumGroupPlan.blankDefault
        plan.members = []
        plan.name = "Empty Kit"
        let groupID = project.addDrumGroup(plan: plan, library: testLibrary)
        let busID = project.buses.last?.id

        let partID = groupID.flatMap { project.addDrumPart(groupID: $0, library: testLibrary) }

        guard let groupID,
              let busID,
              let partID,
              let group = project.trackGroups.first(where: { $0.id == groupID }),
              let track = project.tracks.first(where: { $0.id == partID })
        else {
            return XCTFail("expected the Add Part path to create one kit member")
        }
        XCTAssertEqual(group.memberIDs, [partID])
        XCTAssertEqual(track.groupID, groupID)
        XCTAssertEqual(track.outputBusID, busID)
        XCTAssertEqual(track.destination.kind, .sample)
    }

    private var testLibrary: AudioSampleLibrary {
        AudioSampleLibrary(libraryRoot: libraryRoot)
    }

    private func makeCategory(_ name: String) throws {
        let directory = libraryRoot.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data().write(to: directory.appendingPathComponent("\(name)-default.wav"))
    }
}
