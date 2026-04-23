import SwiftUI
import XCTest
@testable import SequencerAI

@MainActor
final class SequencerDocumentSessionAuthorityTests: XCTestCase {

    // MARK: - Existing: live mutation updates store before document flush

    func test_live_mutation_updates_store_before_document_flush() {
        let (project, _, clipID) = makeLiveStoreProject(clipPitch: 60)
        let documentBox = DocumentBox(document: SeqAIDocument(project: project))
        let session = SequencerDocumentSession(
            document: Binding(
                get: { documentBox.document },
                set: { documentBox.document = $0 }
            ),
            engineController: EngineController(client: nil, endpoint: nil)
        )

        session.mutateProject {
            $0.updateClipEntry(id: clipID) { entry in
                entry.content = .noteGrid(
                    lengthSteps: 1,
                    steps: [ClipStep(main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 72, velocity: 100, lengthSteps: 4)]), fill: nil)]
                )
            }
        }

        XCTAssertEqual(documentBox.document.project.clipEntry(id: clipID)?.pitchPool, [60])
        XCTAssertEqual(session.store.clipEntry(id: clipID)?.pitchPool, [72])

        session.flushToDocument()

        XCTAssertEqual(documentBox.document.project.clipEntry(id: clipID)?.pitchPool, [72])

        SequencerDocumentSessionRegistry.unregister(session)
    }

    // MARK: - New: mutation publishes fresh snapshot before flush boundary

    /// `mutateProject(.snapshotOnly)` must publish a new playback snapshot synchronously
    /// inside the mutation call — before the 150ms debounce fires and before the document
    /// is written. This verifies the runtime reflects the edit immediately.
    func test_mutation_publishesFreshSnapshot_beforeFlushBoundary() {
        let (project, _, clipID) = makeLiveStoreProject(clipPitch: 60)
        let documentBox = DocumentBox(document: SeqAIDocument(project: project))
        let engine = EngineController(client: nil, endpoint: nil)
        let session = SequencerDocumentSession(
            document: Binding(
                get: { documentBox.document },
                set: { documentBox.document = $0 }
            ),
            engineController: engine,
            debounceInterval: .seconds(100)  // very long — document will not flush during this test
        )

        let snapshotCallsBefore = engine.applyPlaybackSnapshotCallCount

        session.mutateProject {
            $0.updateClipEntry(id: clipID) { entry in
                entry.content = .noteGrid(
                    lengthSteps: 1,
                    steps: [ClipStep(main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 99, velocity: 100, lengthSteps: 4)]), fill: nil)]
                )
            }
        }

        // The snapshot must have been published synchronously inside mutateProject.
        XCTAssertGreaterThan(
            engine.applyPlaybackSnapshotCallCount,
            snapshotCallsBefore,
            "mutateProject must publish a fresh snapshot synchronously, not only after the debounce"
        )

        // The document is still stale (debounce has not fired).
        XCTAssertEqual(documentBox.document.project.clipEntry(id: clipID)?.pitchPool, [60],
            "document must still carry the old pitch — debounce has not fired")

        // But the engine snapshot already reflects the edit.
        let liveSnapshot = engine.currentPlaybackSnapshotForTesting
        let updatedClip = liveSnapshot.clipPool.first(where: { $0.id == clipID })
        XCTAssertEqual(updatedClip?.pitchPool, [99],
            "engine snapshot must already contain the updated pitch")

        SequencerDocumentSessionRegistry.unregister(session)
    }

    // MARK: - New: second mutation within debounce window cancels first debounce

    /// Two synchronous mutations must result in exactly one pending debounce task
    /// (the second cancels the first). After the debounce fires, the document
    /// carries only the final mutation's state.
    ///
    /// Uses the injectable `debounceInterval` to make the test fast.
    func test_secondMutation_withinDebounceWindow_cancelsFirstDebounce() async throws {
        let (project, _, clipID) = makeLiveStoreProject(clipPitch: 60)
        let documentBox = DocumentBox(document: SeqAIDocument(project: project))
        let shortDebounce = Duration.milliseconds(60)
        let session = SequencerDocumentSession(
            document: Binding(
                get: { documentBox.document },
                set: { documentBox.document = $0 }
            ),
            engineController: EngineController(client: nil, endpoint: nil),
            debounceInterval: shortDebounce
        )

        // First mutation at T=0.
        session.mutateProject {
            $0.updateClipEntry(id: clipID) { entry in
                entry.content = .noteGrid(
                    lengthSteps: 1,
                    steps: [ClipStep(main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 72, velocity: 100, lengthSteps: 4)]), fill: nil)]
                )
            }
        }

        // Second mutation immediately after (within debounce window).
        session.mutateProject {
            $0.updateClipEntry(id: clipID) { entry in
                entry.content = .noteGrid(
                    lengthSteps: 1,
                    steps: [ClipStep(main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 88, velocity: 100, lengthSteps: 4)]), fill: nil)]
                )
            }
        }

        // Document is still stale (no debounce has fired yet).
        XCTAssertEqual(documentBox.document.project.clipEntry(id: clipID)?.pitchPool, [60],
            "document must be stale before debounce fires")

        // Wait for the second debounce to fire.
        try await Task.sleep(for: .milliseconds(150))

        // Only the second mutation's state should be in the document.
        XCTAssertEqual(
            documentBox.document.project.clipEntry(id: clipID)?.pitchPool,
            [88],
            "only the final mutation (pitch 88) should be flushed — first debounce must have been cancelled"
        )

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
