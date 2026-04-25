import XCTest
import SwiftUI
@testable import SequencerAI

/// Verifies the `session.batch(impact:_:)` helper:
///   - publishes exactly one snapshot regardless of how many typed store mutations run
///   - returns `false` when no state change occurs
///   - properly dispatches the chosen impact

@MainActor
final class SessionBatchHelperTests: XCTestCase {

    // MARK: - Helpers

    private func makeSession(
        project: Project? = nil
    ) -> (SequencerDocumentSession, EngineController, DocumentBox) {
        let (defaultProject, _, _) = makeLiveStoreProject()
        let p = project ?? defaultProject
        let box = DocumentBox(document: SeqAIDocument(project: p))
        let engine = EngineController(client: nil, endpoint: nil)
        let session = SequencerDocumentSession(
            document: Binding(
                get: { box.document },
                set: { box.document = $0 }
            ),
            engineController: engine,
            debounceInterval: .seconds(100) // prevent flush during tests
        )
        session.activate()
        return (session, engine, box)
    }

    // MARK: - One snapshot per batch

    /// A `batch` body that runs two separate typed mutations must publish
    /// exactly one snapshot — not one per typed mutation.
    func test_batch_publishesExactlyOneSnapshot_forMultipleMutations() throws {
        let (project, trackID, clipID) = makeLiveStoreProject()
        let (session, engine, _) = makeSession(project: project)
        let snapshotsBefore = engine.applyPlaybackSnapshotCallCount

        session.batch(impact: .snapshotOnly, changed: .track(trackID).union(.clip(clipID))) { s in
            s.mutateTrack(id: trackID) { track in
                track.name = "Batch Name"
            }
            s.mutateClip(id: clipID) { clip in
                clip.name = "Batch Clip"
            }
        }

        XCTAssertEqual(
            engine.applyPlaybackSnapshotCallCount, snapshotsBefore + 1,
            "batch must publish exactly one snapshot regardless of mutation count"
        )

        SequencerDocumentSessionRegistry.unregister(session)
    }

    // MARK: - Returns false when nothing changed

    func test_batch_returnsFalse_whenNoChangeOccurs() throws {
        let (project, trackID, _) = makeLiveStoreProject()
        let (session, _, _) = makeSession(project: project)

        // Batch that applies the track's existing name (no-op).
        let existingName = session.store.tracks.first(where: { $0.id == trackID })?.name ?? "Track"
        let result = session.batch(impact: .snapshotOnly, changed: .track(trackID)) { s in
            s.mutateTrack(id: trackID) { track in
                track.name = existingName // same value — store won't bump revision
            }
        }

        XCTAssertFalse(result, "batch must return false when nothing changed")

        SequencerDocumentSessionRegistry.unregister(session)
    }

    // MARK: - Returns true when something changed

    func test_batch_returnsTrue_whenChangeOccurs() throws {
        let (project, trackID, _) = makeLiveStoreProject()
        let (session, _, _) = makeSession(project: project)

        let result = session.batch(impact: .snapshotOnly, changed: .track(trackID)) { s in
            s.mutateTrack(id: trackID) { track in
                track.name = "NewName"
            }
        }

        XCTAssertTrue(result, "batch must return true when something changed")

        SequencerDocumentSessionRegistry.unregister(session)
    }

    // MARK: - fullEngineApply dispatches apply(documentModel:) once

    func test_batch_fullEngineApply_callsApplyDocumentModelOnce() throws {
        let (project, trackID, _) = makeLiveStoreProject()
        let (session, engine, _) = makeSession(project: project)
        session.activate()
        let baseline = engine.applyDocumentModelCallCount

        session.batch(impact: .fullEngineApply, changed: .full) { s in
            s.mutateTrack(id: trackID) { track in
                track.name = "Engine Apply"
            }
        }

        XCTAssertEqual(
            engine.applyDocumentModelCallCount, baseline + 1,
            ".fullEngineApply batch must call apply(documentModel:) exactly once"
        )

        SequencerDocumentSessionRegistry.unregister(session)
    }

    // MARK: - Session-level typed methods respect isInBatch guard

    /// When typed session methods are called inside `batch`, they should NOT
    /// publish individually — only the outer batch publishes.
    func test_typedMethods_insideBatch_doNotPublishIndividually() throws {
        let (project, trackID, _) = makeLiveStoreProject()
        let (session, engine, _) = makeSession(project: project)
        let before = engine.applyPlaybackSnapshotCallCount

        session.batch(impact: .snapshotOnly, changed: .track(trackID)) { _ in
            // Call a typed session method inside the batch.
            // This should NOT trigger a publish on its own.
            session.store.mutateTrack(id: trackID) { track in
                track.name = "Inner"
            }
        }

        // Exactly one snapshot from the batch end.
        XCTAssertEqual(
            engine.applyPlaybackSnapshotCallCount, before + 1,
            "typed store methods inside batch must not publish individually"
        )

        SequencerDocumentSessionRegistry.unregister(session)
    }

    func test_batchWithPlaybackInertChange_doesNotPublishSnapshot() throws {
        var (project, _, _) = makeLiveStoreProject()
        let firstTrackID = project.selectedTrackID
        project.appendTrack(trackType: .monoMelodic)
        project.selectedTrackID = firstTrackID
        let trackID = project.tracks[1].id
        let (session, engine, _) = makeSession(project: project)
        let before = engine.applyPlaybackSnapshotCallCount

        let result = session.batch(impact: .snapshotOnly, changed: .selectedTrack) { s in
            s.setSelectedTrackID(trackID)
        }

        XCTAssertTrue(result)
        XCTAssertEqual(engine.applyPlaybackSnapshotCallCount, before)

        SequencerDocumentSessionRegistry.unregister(session)
    }
}

@MainActor
private final class DocumentBox {
    var document: SeqAIDocument

    init(document: SeqAIDocument) {
        self.document = document
    }
}
