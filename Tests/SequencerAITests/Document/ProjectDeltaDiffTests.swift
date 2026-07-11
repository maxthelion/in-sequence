import XCTest
@testable import SequencerAI

final class ProjectDeltaDiffTests: XCTestCase {
    func test_identical_projects_produce_no_deltas() {
        let project = Project.empty
        XCTAssertTrue(project.deltas(from: project).isEmpty)
    }

    func test_mix_change_produces_only_trackMixChanged() {
        var before = Project.empty
        before.appendTrack(trackType: .monoMelodic)
        var after = before
        let trackIndex = after.selectedTrackIndex
        let trackID = after.selectedTrack.id
        after.tracks[trackIndex].mix.level = 0.5

        XCTAssertEqual(
            after.deltas(from: before),
            [.trackMixChanged(trackID: trackID, mix: after.selectedTrack.mix)]
        )
    }

    func test_send_amount_change_reuses_trackMixChanged() {
        let before = Project.empty
        var after = before
        let trackID = after.selectedTrack.id
        after.tracks[after.selectedTrackIndex].mix.sendA = 0.4
        after.tracks[after.selectedTrackIndex].mix.sendB = 0.7

        XCTAssertEqual(
            after.deltas(from: before),
            [.trackMixChanged(trackID: trackID, mix: after.selectedTrack.mix)]
        )
    }

    func test_selected_track_change_produces_selectedTrackChanged() {
        var before = Project.empty
        before.appendTrack(trackType: .monoMelodic)
        let firstTrackID = before.tracks.first!.id

        var after = before
        after.selectTrack(id: firstTrackID)

        XCTAssertEqual(after.deltas(from: before), [.selectedTrackChanged(trackID: firstTrackID)])
    }

    func test_destination_change_produces_trackDestinationChanged() {
        var before = Project.empty
        var after = before
        let trackID = after.selectedTrack.id
        after.tracks[after.selectedTrackIndex].destination = .midi(port: .sequencerAIOut, channel: 5, noteOffset: 0)

        XCTAssertEqual(
            after.deltas(from: before),
            [.trackDestinationChanged(trackID: trackID, destination: after.selectedTrack.destination)]
        )
    }

    func test_noteRepeatIntervalChange_producesTrackParameterChanged() {
        let before = Project.empty
        var after = before
        let trackID = after.selectedTrack.id
        after.tracks[after.selectedTrackIndex].noteRepeatInterval = .oneThirtySecond

        XCTAssertEqual(
            after.deltas(from: before),
            [.trackParameterChanged(trackID: trackID)]
        )
    }

    func test_trackFXChange_producesTrackParameterChanged() {
        let before = Project.empty
        var after = before
        let trackID = after.selectedTrack.id
        after.tracks[after.selectedTrackIndex].fxInserts = [.filter()]

        XCTAssertEqual(
            after.deltas(from: before),
            [.trackParameterChanged(trackID: trackID)]
        )

        var bypassed = after
        bypassed.tracks[bypassed.selectedTrackIndex].fxInserts[0].bypassed = true
        XCTAssertEqual(
            bypassed.deltas(from: after),
            [.trackParameterChanged(trackID: trackID)]
        )
    }

    func test_track_insertion_produces_tracksInsertedOrRemoved() {
        let before = Project.empty
        var after = before
        after.appendTrack(trackType: .monoMelodic)

        XCTAssertTrue(after.deltas(from: before).contains(.tracksInsertedOrRemoved))
    }

    func test_mix_and_destination_change_produce_both_deltas() {
        var before = Project.empty
        var after = before
        let trackID = after.selectedTrack.id
        after.tracks[after.selectedTrackIndex].mix.pan = -0.4
        after.tracks[after.selectedTrackIndex].destination = .midi(port: .sequencerAIOut, channel: 2, noteOffset: 0)

        XCTAssertEqual(
            Set(after.deltas(from: before)),
            Set([
                .trackMixChanged(trackID: trackID, mix: after.selectedTrack.mix),
                .trackDestinationChanged(trackID: trackID, destination: after.selectedTrack.destination),
            ])
        )
    }

    func test_master_bus_change_produces_masterBusChanged() {
        let before = Project.empty
        var after = before
        after.masterBus.addInsert(.filter())

        XCTAssertEqual(after.deltas(from: before), [.masterBusChanged])
        XCTAssertTrue(ProjectDelta.masterBusChanged.isPhaseOneHotPath)
    }

    func test_send_bus_change_produces_scoped_sendBusChanged() {
        let before = Project.empty
        var after = before
        after.setSendBusInserts([.filter()], id: .sendA)

        XCTAssertEqual(
            after.deltas(from: before),
            [.sendBusChanged(busID: .sendA, bus: after.sendBusA)]
        )
        XCTAssertTrue(ProjectDelta.sendBusChanged(busID: .sendA, bus: after.sendBusA).isPhaseOneHotPath)
    }

    func test_mixer_bus_change_produces_busesChanged() {
        let before = Project.empty
        var after = before
        after.addMixerBus(name: "Drums")

        XCTAssertEqual(after.deltas(from: before), [.busesChanged])
        XCTAssertFalse(ProjectDelta.busesChanged.isPhaseOneHotPath)
    }

    func test_mixer_bus_mix_change_produces_scoped_mix_delta() {
        var before = Project.empty
        let busID = before.addMixerBus(name: "Drums")
        var after = before
        after.updateMixerBusMix(id: busID) { mix in
            mix.level = 0.5
            mix.pan = -0.25
            mix.isMuted = true
            mix.isSoloed = true
        }

        XCTAssertEqual(
            after.deltas(from: before),
            [.mixerBusMixChanged(busID: busID, mix: after.buses[0].mix)]
        )
        XCTAssertTrue(ProjectDelta.mixerBusMixChanged(busID: busID, mix: after.buses[0].mix).isPhaseOneHotPath)
    }

    func test_mixer_bus_name_change_stays_structural_delta() {
        var before = Project.empty
        let busID = before.addMixerBus(name: "Drums")
        var after = before
        after.renameMixerBus(id: busID, name: "Percussion")

        XCTAssertEqual(after.deltas(from: before), [.busesChanged])
    }

    func test_track_output_bus_change_produces_trackOutputBusChanged() {
        var before = Project.empty
        let busID = before.addMixerBus(name: "Drums")
        var after = before
        let trackID = after.selectedTrackID
        after.setTrackOutputBus(trackID: trackID, busID: busID)

        let delta = ProjectDelta.trackOutputBusChanged(trackID: trackID, busID: busID)
        XCTAssertEqual(after.deltas(from: before), [delta])
        XCTAssertTrue(delta.isPhaseOneHotPath)
    }

    func test_version_change_produces_coarse_resync() {
        let before = Project.empty
        var after = before
        after.version += 1

        XCTAssertEqual(after.deltas(from: before), [.coarseResync])
    }
}
