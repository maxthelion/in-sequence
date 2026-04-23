import XCTest
@testable import SequencerAI

final class EventQueueInvalidationTests: XCTestCase {
    func test_snapshot_swap_clears_prepared_future_events() {
        let sink = CountingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: sink)
        let (initialProject, _, clipID) = makeLiveStoreProject(clipPitch: 60, stepPattern: [false, true])

        controller.apply(documentModel: initialProject)
        controller.processTick(tickIndex: 0, now: 0)
        XCTAssertTrue(sink.playedEvents.flatMap { $0 }.isEmpty)

        var nextProject = initialProject
        nextProject.updateClipEntry(id: clipID) { entry in
            entry.content = .noteGrid(lengthSteps: 2, steps: [.empty, .empty])
        }

        controller.apply(playbackSnapshot: SequencerSnapshotCompiler.compile(project: nextProject))
        sink.resetPlayedEvents()
        controller.processTick(tickIndex: 1, now: 0.1)

        XCTAssertTrue(sink.playedEvents.flatMap { $0 }.isEmpty)
    }
}
