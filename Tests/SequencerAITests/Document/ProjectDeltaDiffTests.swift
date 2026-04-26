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

    func test_version_change_produces_coarse_resync() {
        let before = Project.empty
        var after = before
        after.version += 1

        XCTAssertEqual(after.deltas(from: before), [.coarseResync])
    }
}
