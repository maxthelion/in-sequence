import Foundation
import XCTest
@testable import SequencerAI

/// Phase 3a: verify that `currentPlaybackSnapshot` reads and writes from concurrent
/// threads produce no torn (partially-written) reads.
///
/// Strategy: 10 000 iterations. Writers call `apply(playbackSnapshot:)` from
/// background threads using snapshots from a fixed pool; each snapshot has a
/// distinct `selectedPhraseID`. Readers call `currentPlaybackSnapshotForTesting`
/// and record the phrase-ID. After all iterations, every recorded ID must be one
/// of the known UUIDs — not a garbled mix of bytes from two concurrent writes.
///
/// Run with Thread Sanitizer enabled for the strongest guarantee.
final class PlaybackSnapshotConcurrencyTests: XCTestCase {

    // MARK: - Concurrent read/write

    func test_snapshot_concurrentReadsAndWrites_noTornRead() throws {
        let engine = EngineController(client: nil, endpoint: nil)
        let (baseProject, _, _) = makeLiveStoreProject()

        // Build a small pool of snapshots with distinct selectedPhraseIDs.
        let phraseIDs: [UUID] = (0..<8).map { _ in UUID() }
        let snapshots: [PlaybackSnapshot] = phraseIDs.map { phraseID in
            // Clone the base project substituting the phrase ID.
            let phrase = PhraseModel(
                id: phraseID,
                name: "P-\(phraseID)",
                lengthBars: 2,
                stepsPerBar: 16,
                cells: []
            )
            let project = Project(
                version: baseProject.version,
                tracks: baseProject.tracks,
                generatorPool: baseProject.generatorPool,
                clipPool: baseProject.clipPool,
                layers: baseProject.layers,
                routes: baseProject.routes,
                patternBanks: baseProject.patternBanks,
                selectedTrackID: baseProject.selectedTrackID,
                phrases: [phrase],
                selectedPhraseID: phraseID
            )
            return SequencerSnapshotCompiler.compile(project: project)
        }

        let validIDs = Set(phraseIDs)
        let iterationCount = 10_000
        let lock = NSLock()
        var readIDs: [UUID] = []
        readIDs.reserveCapacity(iterationCount / 2 + 1)

        // Prime the engine with a known snapshot so reads that fire before the
        // first concurrent write still observe a UUID in `validIDs`. Without
        // this, `concurrentPerform` can schedule a reader-iteration ahead of
        // any writer-iteration, returning the engine's default empty-project
        // snapshot whose phraseID is not in the set.
        engine.apply(playbackSnapshot: snapshots[0])

        DispatchQueue.concurrentPerform(iterations: iterationCount) { i in
            let idx = i % phraseIDs.count
            if i % 2 == 0 {
                // Writer path
                engine.apply(playbackSnapshot: snapshots[idx])
            } else {
                // Reader path
                let snap = engine.currentPlaybackSnapshotForTesting
                lock.lock()
                readIDs.append(snap.selectedPhraseID)
                lock.unlock()
            }
        }

        // Every phrase ID that was read must be a member of the known set.
        // A torn read would produce a UUID not in validIDs, or crash the process.
        for id in readIDs {
            XCTAssertTrue(
                validIDs.contains(id),
                "Read phraseID \(id) was never written — torn read detected."
            )
        }
    }

    // MARK: - apply(documentModel:) is also safe to call concurrently with reads

    func test_applyDocumentModel_concurrentWithReads_noDataRace() {
        let engine = EngineController(client: nil, endpoint: nil)
        let (project, _, _) = makeLiveStoreProject()

        let expectation = expectation(description: "all bg tasks complete")
        expectation.expectedFulfillmentCount = 100

        for i in 0..<100 {
            DispatchQueue.global().async {
                if i % 3 == 0 {
                    engine.apply(documentModel: project)
                } else {
                    _ = engine.currentPlaybackSnapshotForTesting
                }
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 5)
        // Reaching here without a TSan violation confirms both paths are guarded.
    }
}
