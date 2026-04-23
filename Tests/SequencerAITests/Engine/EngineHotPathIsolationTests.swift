import XCTest
@testable import SequencerAI

final class EngineHotPathIsolationTests: XCTestCase {
    func test_snapshot_only_clip_edit_changes_playback_without_destination_resync() {
        let sink = CountingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: sink)
        var (project, _, clipID) = makeLiveStoreProject(clipPitch: 60)

        controller.apply(documentModel: project)
        controller.processTick(tickIndex: 0, now: 0)
        XCTAssertEqual(sink.playedEvents.flatMap { $0 }.map(\.pitch), [60])
        let initialDestinationCalls = sink.destinationCallCount

        project.updateClipEntry(id: clipID) { entry in
            entry.content = .noteGrid(
                lengthSteps: 1,
                steps: [ClipStep(main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 72, velocity: 100, lengthSteps: 4)]), fill: nil)]
            )
        }

        controller.apply(playbackSnapshot: SequencerSnapshotCompiler.compile(project: project))
        sink.resetPlayedEvents()
        controller.processTick(tickIndex: 0, now: 0.1)

        XCTAssertEqual(sink.destinationCallCount, initialDestinationCalls)
        XCTAssertEqual(sink.playedEvents.flatMap { $0 }.map(\.pitch), [72])
    }
}
