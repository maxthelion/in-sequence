import XCTest
@testable import SequencerAI

final class EventQueueInvalidationTests: XCTestCase {

    // MARK: - Running-transport leak scenario (primary invariant)

    /// Proves that a note prepared for tick N+1 does NOT leak through when the snapshot
    /// is mutated to silence that step BEFORE tick N+1 runs.
    ///
    /// Scenario:
    ///   - step 0 is silent, step 1 is active (pitch 60)
    ///   - processTick(0): dispatches nothing, then prepares tick 1 → enqueues pitch 60
    ///   - apply(playbackSnapshot:) with silenced step 1 → eventQueue.clear() + preparedTickIndex = nil
    ///   - processTick(1): re-bootstraps from the new silent snapshot → no note played
    ///
    /// Without the invalidation, the stale pitch-60 event would remain in the event queue
    /// and would be dispatched at tick 1.
    func test_snapshotMutation_invalidatesAlreadyPreparedStaleNote() {
        let sink = CountingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: sink)
        let (initialProject, _, clipID) = makeLiveStoreProject(clipPitch: 60, stepPattern: [false, true])

        // Boot the engine with step 0=off, step 1=on.
        controller.apply(documentModel: initialProject)

        // processTick(0):
        //   1. Bootstraps + dispatches tick 0 → sink gets no notes (step 0 is off).
        //   2. prepareTick(1) → enqueues pitch-60 event into eventQueue.
        controller.processTick(tickIndex: 0, now: 0)
        XCTAssertTrue(sink.playedEvents.flatMap { $0 }.isEmpty, "tick 0 should produce no notes")

        // Confirm that the event queue is non-empty BEFORE the swap — i.e. the note
        // for tick 1 was already staged. This is the stale note that must be cleared.
        XCTAssertFalse(controller.eventQueueIsEmpty, "event queue must be non-empty after prepareTick(1)")

        // Mutate the snapshot so step 1 is now silent.
        var silencedProject = initialProject
        silencedProject.updateClipEntry(id: clipID) { entry in
            entry.content = .noteGrid(lengthSteps: 2, steps: [.empty, .empty])
        }

        // Applying the new snapshot clears the event queue and invalidates preparedTickIndex.
        controller.apply(playbackSnapshot: SequencerSnapshotCompiler.compile(project: silencedProject))

        // Confirm the queue was cleared.
        XCTAssertTrue(controller.eventQueueIsEmpty, "apply(playbackSnapshot:) must clear the event queue")

        sink.resetPlayedEvents()
        controller.processTick(tickIndex: 1, now: 0.1)

        // The stale pitch-60 event must NOT have been dispatched.
        XCTAssertTrue(
            sink.playedEvents.flatMap { $0 }.isEmpty,
            "stale prepared note for tick 1 must not leak after snapshot invalidation"
        )
    }

    // MARK: - Control case: without invalidation the note would have leaked

    /// Confirms that tick 1's note IS played when no snapshot swap occurs between
    /// prepareTick(1) and processTick(1). This validates that the primary test above
    /// tests a real scenario and not a trivially empty path.
    func test_withoutSnapshotSwap_preparedNoteIsDispatched() {
        let sink = CountingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: sink)
        let (project, _, _) = makeLiveStoreProject(clipPitch: 72, stepPattern: [false, true])

        controller.apply(documentModel: project)
        controller.processTick(tickIndex: 0, now: 0)

        sink.resetPlayedEvents()
        controller.processTick(tickIndex: 1, now: 0.1)

        XCTAssertEqual(
            sink.playedEvents.flatMap { $0 }.map(\.pitch),
            [72],
            "tick 1 note should play normally when no snapshot swap occurs"
        )
    }
}
