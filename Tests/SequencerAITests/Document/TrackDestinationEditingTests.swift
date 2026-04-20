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

    private func makeModel(
        tracks: [StepSequenceTrack],
        groups: [TrackGroup] = []
    ) -> SeqAIDocumentModel {
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

        return SeqAIDocumentModel(
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
