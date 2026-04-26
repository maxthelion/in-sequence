import SwiftUI
import XCTest
@testable import SequencerAI

@MainActor
final class SequencerDocumentSessionMasterBusTests: XCTestCase {
    func test_masterBusInsertEdit_updatesStoreAndEngine_withoutSnapshotReplacement() {
        let documentBox = DocumentBox(document: SeqAIDocument(project: .empty))
        let engine = EngineController(client: nil, endpoint: nil)
        let session = SequencerDocumentSession(
            document: Binding(
                get: { documentBox.document },
                set: { documentBox.document = $0 }
            ),
            engineController: engine,
            debounceInterval: .seconds(100)
        )

        let snapshotCallsBefore = engine.applyPlaybackSnapshotCallCount
        let documentApplyCallsBefore = engine.applyDocumentModelCallCount
        let masterBusCallsBefore = engine.masterBusApplyCallCount

        session.addMasterBusInsert(.filter())

        XCTAssertEqual(session.store.masterBus.liveScene.inserts.count, 1)
        XCTAssertTrue(session.store.masterBus.hasUnsavedDraft)
        XCTAssertEqual(engine.applyPlaybackSnapshotCallCount, snapshotCallsBefore)
        XCTAssertEqual(engine.applyDocumentModelCallCount, documentApplyCallsBefore)
        XCTAssertEqual(engine.masterBusApplyCallCount, masterBusCallsBefore + 1)
        XCTAssertEqual(engine.masterBusState.liveScene.inserts.count, 1)

        // Debounce has not flushed yet, so document authority is still unchanged.
        XCTAssertEqual(documentBox.document.project.masterBus.liveScene.inserts.count, 0)

        session.flushToDocument()
        XCTAssertEqual(documentBox.document.project.masterBus.liveScene.inserts.count, 1)

        SequencerDocumentSessionRegistry.unregister(session)
    }

    func test_commitMasterBusDraft_savesEditedScene() {
        let documentBox = DocumentBox(document: SeqAIDocument(project: .empty))
        let session = SequencerDocumentSession(
            document: Binding(
                get: { documentBox.document },
                set: { documentBox.document = $0 }
            ),
            engineController: EngineController(client: nil, endpoint: nil),
            debounceInterval: .seconds(100)
        )

        session.addMasterBusInsert(.bitcrusher())
        session.commitMasterBusDraft(name: "Crush")

        XCTAssertFalse(session.store.masterBus.hasUnsavedDraft)
        XCTAssertEqual(session.store.masterBus.activeScene.name, "Crush")
        XCTAssertEqual(session.store.masterBus.activeScene.inserts.count, 1)

        SequencerDocumentSessionRegistry.unregister(session)
    }
}

private final class DocumentBox {
    var document: SeqAIDocument

    init(document: SeqAIDocument) {
        self.document = document
    }
}
