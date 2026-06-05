import Foundation
import XCTest
@testable import SequencerAI

final class TrackDestinationEditingTests: XCTestCase {
    func test_set_edited_destination_updates_group_shared_destination_for_inherited_track() {
        let groupID = UUID()
        let track = StepSequenceTrack(
            name: "Hat",
            trackType: .monoMelodic,
            pitches: [60],
            stepPattern: [true, false, false, false],
            destination: .inheritGroup,
            groupID: groupID,
            velocity: 100,
            gateLength: 4
        )
        var model = makeModel(
            tracks: [track],
            groups: [
                TrackGroup(
                    id: groupID,
                    name: "Kit",
                    memberIDs: [track.id],
                    sharedDestination: .midi(port: .sequencerAIOut, channel: 9, noteOffset: 2)
                )
            ]
        )
        let nextDestination = Destination.auInstrument(
            componentID: AudioInstrumentChoice.testInstrument.audioComponentID,
            stateBlob: Data([0x01, 0x02])
        )

        model.setEditedDestination(nextDestination, for: track.id)

        XCTAssertEqual(model.tracks[0].destination, .inheritGroup)
        XCTAssertEqual(model.trackGroups[0].sharedDestination, nextDestination)
    }

    func test_voice_snapshot_destination_strips_transient_state_for_group_destination() {
        let groupID = UUID()
        let track = StepSequenceTrack(
            name: "Hat",
            trackType: .monoMelodic,
            pitches: [60],
            stepPattern: [true, false, false, false],
            destination: .inheritGroup,
            groupID: groupID,
            velocity: 100,
            gateLength: 4
        )
        let liveDestination = Destination.auInstrument(
            componentID: AudioInstrumentChoice.testInstrument.audioComponentID,
            stateBlob: Data([0xAB, 0xCD])
        )
        let model = makeModel(
            tracks: [track],
            groups: [
                TrackGroup(
                    id: groupID,
                    name: "Kit",
                    memberIDs: [track.id],
                    sharedDestination: liveDestination
                )
            ]
        )

        XCTAssertEqual(
            model.voiceSnapshotDestination(for: track.id),
            .auInstrument(componentID: AudioInstrumentChoice.testInstrument.audioComponentID, stateBlob: nil)
        )
    }

    func test_set_edited_midi_port_preserves_channel_and_offset() {
        let track = StepSequenceTrack(
            name: "Bass",
            trackType: .monoMelodic,
            pitches: [48],
            stepPattern: [true, false, true, false],
            destination: .midi(
                port: MIDIEndpointName(displayName: "Old", isVirtual: false),
                channel: 6,
                noteOffset: -5
            ),
            velocity: 100,
            gateLength: 4
        )
        var model = makeModel(tracks: [track])
        let newPort = MIDIEndpointName(displayName: "New", isVirtual: false)

        model.setEditedMIDIPort(newPort, for: track.id)

        XCTAssertEqual(
            model.tracks[0].destination,
            .midi(port: newPort, channel: 6, noteOffset: -5)
        )
    }

    func test_set_group_shared_destination_syncs_inherited_member_macros() {
        let groupID = UUID()
        let kick = StepSequenceTrack(
            name: "Kick",
            trackType: .monoMelodic,
            pitches: [36],
            stepPattern: [true],
            destination: .inheritGroup,
            groupID: groupID,
            velocity: 100,
            gateLength: 4
        )
        let snare = StepSequenceTrack(
            name: "Snare",
            trackType: .monoMelodic,
            pitches: [38],
            stepPattern: [true],
            destination: .inheritGroup,
            groupID: groupID,
            velocity: 100,
            gateLength: 4
        )
        var model = makeModel(
            tracks: [kick, snare],
            groups: [
                TrackGroup(
                    id: groupID,
                    name: "Kit",
                    memberIDs: [kick.id, snare.id],
                    sharedDestination: .midi(port: .sequencerAIOut, channel: 9, noteOffset: 0)
                )
            ]
        )
        let sampleDestination = Destination.sample(sampleID: UUID(), settings: .default)

        model.setGroupSharedDestinationWithMacros(sampleDestination, groupID: groupID)
        model.syncMacroLayers()

        XCTAssertEqual(model.trackGroups[0].sharedDestination, sampleDestination)
        XCTAssertEqual(model.tracks.map(\.destination), [.inheritGroup, .inheritGroup])
        XCTAssertEqual(model.tracks[0].macros.count, BuiltinMacroKind.allCases.count)
        XCTAssertEqual(model.tracks[1].macros.count, BuiltinMacroKind.allCases.count)
        XCTAssertTrue(model.layers.contains { layer in
            if case let .macroParam(trackID, _) = layer.target {
                return trackID == kick.id
            }
            return false
        })
    }

    func test_resolved_destination_preserves_write_target_while_playback_applies_mapping() {
        let groupID = UUID()
        let memberID = UUID()
        let member = StepSequenceTrack(
            id: memberID,
            name: "Kick",
            trackType: .monoMelodic,
            pitches: [36],
            stepPattern: [true],
            destination: .inheritGroup,
            groupID: groupID,
            velocity: 100,
            gateLength: 4
        )
        let port = MIDIEndpointName(displayName: "Kit Out", isVirtual: false)
        let sharedDestination = Destination.midi(port: port, channel: 9, noteOffset: 12)
        let model = makeModel(
            tracks: [member],
            groups: [
                TrackGroup(
                    id: groupID,
                    name: "Kit",
                    memberIDs: [memberID],
                    sharedDestination: sharedDestination,
                    triggerMappingMode: .perChannel,
                    noteMapping: [memberID: 24],
                    channelMapping: [memberID: 4]
                )
            ]
        )

        XCTAssertEqual(model.resolvedDestination(for: memberID), sharedDestination)
        XCTAssertEqual(
            model.resolvedPlaybackDestination(for: memberID),
            Project.ResolvedPlaybackDestination(
                destination: .midi(port: port, channel: 4, noteOffset: 0),
                pitchOffset: 0
            )
        )
    }

    func test_drum_group_member_inherit_toggle_sets_own_destination() {
        let groupID = UUID()
        let hat = StepSequenceTrack(
            name: "Hat",
            trackType: .monoMelodic,
            pitches: [42],
            stepPattern: [true],
            destination: .inheritGroup,
            groupID: groupID,
            velocity: 100,
            gateLength: 4
        )
        var model = makeModel(
            tracks: [hat],
            groups: [
                TrackGroup(
                    id: groupID,
                    name: "Kit",
                    memberIDs: [hat.id],
                    sharedDestination: .midi(port: .sequencerAIOut, channel: 9, noteOffset: 0)
                )
            ]
        )
        let ownDestination = Destination.midi(
            port: MIDIEndpointName(displayName: "Own", isVirtual: false),
            channel: 4,
            noteOffset: 3
        )

        model.setDrumGroupMemberInheritsDestination(false, trackID: hat.id, ownDestination: ownDestination)

        XCTAssertEqual(model.tracks[0].destination, ownDestination)
        XCTAssertEqual(
            model.trackGroups[0].sharedDestination,
            .midi(port: .sequencerAIOut, channel: 9, noteOffset: 0)
        )

        model.setDrumGroupMemberInheritsDestination(true, trackID: hat.id)

        XCTAssertEqual(model.tracks[0].destination, .inheritGroup)
    }

    func test_apply_drum_group_routing_draft_updates_destination_mode_and_mappings_atomically() {
        let groupID = UUID()
        let kick = StepSequenceTrack(
            name: "Kick",
            trackType: .monoMelodic,
            pitches: [36],
            stepPattern: [true],
            destination: .inheritGroup,
            groupID: groupID,
            velocity: 100,
            gateLength: 4
        )
        let snare = StepSequenceTrack(
            name: "Snare",
            trackType: .monoMelodic,
            pitches: [38],
            stepPattern: [true],
            destination: .inheritGroup,
            groupID: groupID,
            velocity: 100,
            gateLength: 4
        )
        var model = makeModel(
            tracks: [kick, snare],
            groups: [
                TrackGroup(
                    id: groupID,
                    name: "Kit",
                    memberIDs: [kick.id, snare.id],
                    sharedDestination: .midi(port: .sequencerAIOut, channel: 9, noteOffset: 1),
                    noteMapping: [kick.id: 0, snare.id: 2],
                    channelMapping: [kick.id: 0, snare.id: 1]
                )
            ]
        )
        let ownDestination = Destination.midi(
            port: MIDIEndpointName(displayName: "Snare Out", isVirtual: false),
            channel: 2,
            noteOffset: 5
        )
        let nextSharedDestination = Destination.midi(
            port: MIDIEndpointName(displayName: "Kit Out", isVirtual: false),
            channel: 8,
            noteOffset: 6
        )
        let draft = Project.DrumGroupRoutingDraft(
            groupID: groupID,
            sharedDestination: nextSharedDestination,
            triggerMappingMode: .perChannel,
            members: [
                .init(memberID: kick.id, inheritsGroupDestination: true, noteOffset: 12, midiChannel: 3),
                .init(memberID: snare.id, inheritsGroupDestination: false, ownDestination: ownDestination, noteOffset: 14, midiChannel: 20)
            ]
        )

        model.applyDrumGroupRoutingDraft(draft)

        XCTAssertEqual(model.trackGroups[0].sharedDestination, nextSharedDestination)
        XCTAssertEqual(model.trackGroups[0].triggerMappingMode, .perChannel)
        XCTAssertEqual(model.trackGroups[0].noteMapping[kick.id], 12)
        XCTAssertEqual(model.trackGroups[0].noteMapping[snare.id], 14)
        XCTAssertEqual(model.trackGroups[0].channelMapping[kick.id], 3)
        XCTAssertEqual(model.trackGroups[0].channelMapping[snare.id], 15)
        XCTAssertEqual(model.tracks[0].destination, .inheritGroup)
        XCTAssertEqual(model.tracks[1].destination, ownDestination)
    }

    func test_drum_group_routing_apply_state_survives_project_save_reload_round_trip() throws {
        let groupID = UUID()
        let kick = StepSequenceTrack(
            name: "Kick",
            trackType: .monoMelodic,
            pitches: [36],
            stepPattern: [true, false, false, false],
            destination: .inheritGroup,
            groupID: groupID,
            velocity: 100,
            gateLength: 4
        )
        let snare = StepSequenceTrack(
            name: "Snare",
            trackType: .monoMelodic,
            pitches: [38],
            stepPattern: [false, false, true, false],
            destination: .inheritGroup,
            groupID: groupID,
            velocity: 100,
            gateLength: 4
        )
        let sharedDestination = Destination.midi(
            port: MIDIEndpointName(displayName: "Kit Port", isVirtual: false),
            channel: 9,
            noteOffset: 11
        )
        let ownDestination = Destination.midi(
            port: MIDIEndpointName(displayName: "Snare Port", isVirtual: false),
            channel: 2,
            noteOffset: 5
        )
        var model = makeModel(
            tracks: [kick, snare],
            groups: [
                TrackGroup(
                    id: groupID,
                    name: "808 Bones",
                    memberIDs: [kick.id, snare.id],
                    sharedDestination: .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0),
                    triggerMappingMode: .perNote,
                    noteMapping: [kick.id: 0, snare.id: 2],
                    channelMapping: [kick.id: 0, snare.id: 1]
                )
            ]
        )

        model.applyDrumGroupRoutingDraft(
            Project.DrumGroupRoutingDraft(
                groupID: groupID,
                sharedDestination: sharedDestination,
                triggerMappingMode: .perChannel,
                members: [
                    .init(memberID: kick.id, inheritsGroupDestination: true, noteOffset: 12, midiChannel: 4),
                    .init(memberID: snare.id, inheritsGroupDestination: false, ownDestination: ownDestination, noteOffset: 14, midiChannel: 8),
                ]
            )
        )

        let encoded = try JSONEncoder().encode(model)
        let reloaded = try JSONDecoder().decode(Project.self, from: encoded)
        let reloadedGroup = try XCTUnwrap(reloaded.trackGroups.first(where: { $0.id == groupID }))

        XCTAssertEqual(reloadedGroup.sharedDestination, sharedDestination)
        XCTAssertEqual(reloadedGroup.triggerMappingMode, .perChannel)
        XCTAssertEqual(reloadedGroup.noteMapping, [kick.id: 12, snare.id: 14])
        XCTAssertEqual(reloadedGroup.channelMapping, [kick.id: 4, snare.id: 8])
        XCTAssertEqual(reloaded.tracks.first(where: { $0.id == kick.id })?.destination, .inheritGroup)
        XCTAssertEqual(reloaded.tracks.first(where: { $0.id == snare.id })?.destination, ownDestination)
        XCTAssertEqual(
            reloaded.resolvedPlaybackDestination(for: kick.id),
            Project.ResolvedPlaybackDestination(
                destination: .midi(port: sharedDestination.midiPort, channel: 4, noteOffset: 0),
                pitchOffset: 0
            )
        )
        XCTAssertEqual(
            reloaded.resolvedPlaybackDestination(for: snare.id),
            Project.ResolvedPlaybackDestination(destination: ownDestination, pitchOffset: 0)
        )
    }

    private func makeModel(
        tracks: [StepSequenceTrack],
        groups: [TrackGroup] = []
    ) -> Project {
        let generatorPool = GeneratorPoolEntry.defaultPool
        let clipPool: [ClipPoolEntry] = []
        let layers = PhraseLayerDefinition.defaultSet(for: tracks)
        let phrases = [
            PhraseModel.default(
                tracks: tracks,
                layers: layers,
                generatorPool: generatorPool,
                clipPool: clipPool
            )
        ]

        return Project(
            version: 1,
            tracks: tracks,
            trackGroups: groups,
            generatorPool: generatorPool,
            clipPool: clipPool,
            layers: layers,
            patternBanks: [],
            selectedTrackID: tracks[0].id,
            phrases: phrases,
            selectedPhraseID: phrases[0].id
        )
    }
}
