import XCTest
import Observation
import SwiftUI
@testable import SequencerAI

// Phase 1a guardrail tests — SessionSnapshotPublisher and its integration with
// SequencerDocumentSession.

@MainActor
final class SessionSnapshotPublisherTests: XCTestCase {

    // MARK: - Helpers

    private final class DocumentBox {
        var document: SeqAIDocument
        init(document: SeqAIDocument) { self.document = document }
    }

    private func makeSession(
        project: Project? = nil,
        debounceInterval: Duration = .seconds(100)
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
            debounceInterval: debounceInterval
        )
        return (session, engine, box)
    }

    // MARK: - 1. Initial snapshot matches compiled store state

    /// A fresh session's publisher holds a snapshot equal to
    /// `compile(state: store.compileInput())`.
    func test_publisher_startsWithCompiledInitialSnapshot() {
        let (session, _, _) = makeSession()
        let expected = SequencerSnapshotCompiler.compile(state: session.store.compileInput())
        XCTAssertEqual(session.snapshotPublisher.snapshot, expected)
    }

    // MARK: - 2. publishSnapshot updates both publisher and engine to the same value

    /// After `publishSnapshot()`, the publisher's snapshot equals the engine's
    /// `currentPlaybackSnapshotForTesting`.
    func test_publishSnapshot_updatesPublisherAndEngine_toSameValue() {
        let (session, engine, _) = makeSession()
        session.activate()

        // Mutate the store directly so there is something to publish.
        let trackID = session.store.tracks.first!.id
        session.store.mutateTrack(id: trackID) { track in
            track.name = "Mutated"
        }

        session.publishSnapshot()

        XCTAssertEqual(
            session.snapshotPublisher.snapshot,
            engine.currentPlaybackSnapshotForTesting,
            "Publisher and engine must hold the same compiled snapshot after publishSnapshot()"
        )
    }

    // MARK: - 3. @Observable fires on replace

    /// `replace(_:)` fires the `@Observable` observation notification so that
    /// SwiftUI (and test observers using `withObservationTracking`) can react.
    func test_publisher_firesObservationOnReplace() {
        let publisher = SessionSnapshotPublisher(
            initial: SequencerSnapshotCompiler.compile(state: .empty)
        )

        var notified = false
        // withObservationTracking runs the apply closure immediately to register
        // the tracked access (accessing publisher.snapshot), then calls the
        // change handler on the next mutation of a tracked property.
        withObservationTracking {
            _ = publisher.snapshot
        } onChange: {
            notified = true
        }

        // Replace with a different snapshot — must fire the onChange.
        let (project, _, _) = makeLiveStoreProject()
        let newStore = LiveSequencerStore(project: project)
        let newSnapshot = SequencerSnapshotCompiler.compile(state: newStore.compileInput())
        publisher.replace(newSnapshot)

        XCTAssertTrue(notified, "replace(_:) must fire the @Observable onChange handler")
    }

    // MARK: - 4. activate() updates the publisher

    /// After `activate()`, the publisher's snapshot reflects the activated project.
    func test_activate_updatesPublisher() {
        let (session, engine, _) = makeSession()

        session.activate()

        XCTAssertEqual(
            session.snapshotPublisher.snapshot,
            engine.currentPlaybackSnapshotForTesting,
            "Publisher must be updated by activate()"
        )
    }

    // MARK: - 5. ingestExternalDocumentChange updates the publisher

    /// After `ingestExternalDocumentChange(_:)` with a mutated project, the
    /// publisher's snapshot reflects the new state.
    func test_ingestExternalDocumentChange_updatesPublisher() {
        let (project, trackID, _) = makeLiveStoreProject()
        let (session, engine, _) = makeSession(project: project)
        session.activate()

        // Build a mutated project.
        var mutatedProject = project
        if let idx = mutatedProject.tracks.firstIndex(where: { $0.id == trackID }) {
            mutatedProject.tracks[idx].name = "ExternallyChanged"
        }

        session.ingestExternalDocumentChange(mutatedProject)

        XCTAssertEqual(
            session.snapshotPublisher.snapshot,
            engine.currentPlaybackSnapshotForTesting,
            "Publisher must be updated by ingestExternalDocumentChange"
        )
    }

    // MARK: - 6. publishSnapshot does not double-call exportToProject

    /// `publishSnapshot()` uses `compileInput()`, not `exportToProject()`.
    /// Verify the export counter does not advance during publishSnapshot().
    func test_publishSnapshot_doesNotCallExportToProject() {
        let (session, _, _) = makeSession()
        session.activate()

        assertNoExportDuring(session.store) {
            session.publishSnapshot()
        }
    }
}
