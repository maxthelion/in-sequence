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

        XCTAssertEqual(session.store.masterBus.activeScene.inserts.count, 1)
        XCTAssertEqual(engine.applyPlaybackSnapshotCallCount, snapshotCallsBefore)
        XCTAssertEqual(engine.applyDocumentModelCallCount, documentApplyCallsBefore)
        XCTAssertEqual(engine.masterBusApplyCallCount, masterBusCallsBefore + 1)
        XCTAssertEqual(engine.masterBusState.activeScene.inserts.count, 1)

        // Debounce has not flushed yet, so document authority is still unchanged.
        XCTAssertEqual(documentBox.document.project.masterBus.activeScene.inserts.count, 0)

        session.flushToDocument()
        XCTAssertEqual(documentBox.document.project.masterBus.activeScene.inserts.count, 1)

        SequencerDocumentSessionRegistry.unregister(session)
    }

    func test_directSceneEditsPersistToSelectedScene() {
        let documentBox = DocumentBox(document: SeqAIDocument(project: .empty))
        let session = SequencerDocumentSession(
            document: Binding(
                get: { documentBox.document },
                set: { documentBox.document = $0 }
            ),
            engineController: EngineController(client: nil, endpoint: nil),
            debounceInterval: .seconds(100)
        )

        let sceneID = session.store.masterBus.activeSceneID
        session.addMasterBusInsert(.bitcrusher(), to: sceneID)
        session.setMasterSceneName(sceneID, name: "Crush")

        XCTAssertEqual(session.store.masterBus.activeScene.name, "Crush")
        XCTAssertEqual(session.store.masterBus.activeScene.inserts.count, 1)

        SequencerDocumentSessionRegistry.unregister(session)
    }

    func test_masterOutputInsertEdit_updatesPostBlendChainWithoutSceneMutation() {
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

        let scenesBefore = session.store.masterBus.scenes
        let masterBusCallsBefore = engine.masterBusApplyCallCount

        session.addMasterOutputInsert(.filter())

        XCTAssertEqual(session.store.masterBus.masterInserts.count, 1)
        XCTAssertEqual(session.store.masterBus.scenes, scenesBefore)
        XCTAssertEqual(engine.masterBusState.masterInserts.count, 1)
        XCTAssertEqual(engine.masterBusApplyCallCount, masterBusCallsBefore + 1)
        XCTAssertTrue(documentBox.document.project.masterBus.masterInserts.isEmpty)

        session.flushToDocument()
        XCTAssertEqual(documentBox.document.project.masterBus.masterInserts.count, 1)
        XCTAssertEqual(documentBox.document.project.masterBus.scenes, scenesBefore)

        SequencerDocumentSessionRegistry.unregister(session)
    }

    func test_setMasterOutputGain_updatesOnlyGlobalMasterGain() {
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

        let scenesBefore = session.store.masterBus.scenes
        let selectionBefore = session.store.masterBus.abSelection
        let trackMixBefore = session.store.selectedTrack.mix
        let snapshotCallsBefore = engine.applyPlaybackSnapshotCallCount
        let documentApplyCallsBefore = engine.applyDocumentModelCallCount
        let masterBusCallsBefore = engine.masterBusApplyCallCount

        session.setMasterOutputGain(1.4)

        XCTAssertEqual(session.store.masterBus.masterOutputGain, 1.4)
        XCTAssertEqual(session.store.masterBus.scenes, scenesBefore)
        XCTAssertEqual(session.store.masterBus.abSelection, selectionBefore)
        XCTAssertEqual(session.store.selectedTrack.mix, trackMixBefore)
        XCTAssertEqual(engine.masterBusState.masterOutputGain, 1.4)
        XCTAssertEqual(engine.applyPlaybackSnapshotCallCount, snapshotCallsBefore)
        XCTAssertEqual(engine.applyDocumentModelCallCount, documentApplyCallsBefore)
        XCTAssertEqual(engine.masterBusApplyCallCount, masterBusCallsBefore + 1)
        XCTAssertEqual(documentBox.document.project.masterBus.masterOutputGain, 1)

        session.flushToDocument()
        XCTAssertEqual(documentBox.document.project.masterBus.masterOutputGain, 1.4)

        SequencerDocumentSessionRegistry.unregister(session)
    }

    func test_liveMasterOutputGainDragAvoidsDocumentMutationUntilCommit() {
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

        let revisionBefore = session.store.revision
        let masterBusCallsBefore = engine.masterBusApplyCallCount

        engine.setLiveMasterOutputGain(0.35)

        XCTAssertEqual(session.store.revision, revisionBefore)
        XCTAssertEqual(session.store.masterBus.masterOutputGain, 1)
        XCTAssertEqual(documentBox.document.project.masterBus.masterOutputGain, 1)
        XCTAssertEqual(engine.masterBusApplyCallCount, masterBusCallsBefore)

        session.setMasterOutputGain(0.35)

        XCTAssertEqual(session.store.masterBus.masterOutputGain, 0.35)
        XCTAssertEqual(engine.masterBusApplyCallCount, masterBusCallsBefore + 1)
        XCTAssertEqual(documentBox.document.project.masterBus.masterOutputGain, 1)

        session.flushToDocument()
        XCTAssertEqual(documentBox.document.project.masterBus.masterOutputGain, 0.35)

        SequencerDocumentSessionRegistry.unregister(session)
    }

    func test_liveMasterCrossfaderOverride_writesRuntimeOverlayOnly() {
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

        let revisionBefore = session.store.revision
        let authoredSelectionBefore = session.store.masterBus.abSelection
        let snapshotCallsBefore = engine.applyPlaybackSnapshotCallCount
        let documentApplyCallsBefore = engine.applyDocumentModelCallCount
        let masterBusCallsBefore = engine.masterBusApplyCallCount

        engine.setLiveMasterCrossfader(0.82)

        XCTAssertEqual(engine.masterBusPerformanceOverlay.crossfaderOverride, 0.82)
        XCTAssertEqual(engine.resolvedMasterBusState.abSelection?.crossfader, 0.82)
        XCTAssertEqual(session.store.revision, revisionBefore)
        XCTAssertEqual(session.store.masterBus.abSelection, authoredSelectionBefore)
        XCTAssertEqual(documentBox.document.project.masterBus.abSelection, authoredSelectionBefore)
        XCTAssertEqual(engine.applyPlaybackSnapshotCallCount, snapshotCallsBefore)
        XCTAssertEqual(engine.applyDocumentModelCallCount, documentApplyCallsBefore)
        XCTAssertEqual(engine.masterBusApplyCallCount, masterBusCallsBefore)

        engine.clearLiveMasterCrossfader()
        XCTAssertNil(engine.masterBusPerformanceOverlay.crossfaderOverride)
        XCTAssertEqual(session.store.masterBus.abSelection, authoredSelectionBefore)

        SequencerDocumentSessionRegistry.unregister(session)
    }

    func test_liveSceneMacroOverlay_doesNotMutateStoreOrSnapshots() {
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

        let sceneID = session.store.masterBus.activeSceneID
        let insert = MasterBusInsert.filter()
        session.addMasterBusInsert(insert, to: sceneID)
        let macro = MasterSceneMacroBinding(slotIndex: 0, target: .filterCutoff(insertID: insert.id))
        session.upsertMasterSceneMacroBinding(macro, in: sceneID)

        let revisionBefore = session.store.revision
        let snapshotCallsBefore = engine.applyPlaybackSnapshotCallCount
        let masterBusCallsBefore = engine.masterBusApplyCallCount

        engine.setMasterSceneMacroOverride(sceneID: sceneID, macroID: macro.id, value: 2_000)

        XCTAssertEqual(session.store.revision, revisionBefore)
        XCTAssertEqual(engine.applyPlaybackSnapshotCallCount, snapshotCallsBefore)
        XCTAssertEqual(engine.masterBusApplyCallCount, masterBusCallsBefore)
        XCTAssertEqual(engine.masterBusState.activeScene.inserts[0].kind.summary, "12000 Hz")
        XCTAssertEqual(engine.resolvedMasterBusState.activeScene.inserts[0].kind.summary, "2000 Hz")

        engine.clearMasterSceneMacroOverrides(sceneID: sceneID)
        XCTAssertEqual(engine.resolvedMasterBusState.activeScene.inserts[0].kind.summary, "12000 Hz")

        SequencerDocumentSessionRegistry.unregister(session)
    }

    func test_savingLiveSceneMacroOverlay_writesBackToScene() {
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

        let sceneID = session.store.masterBus.activeSceneID
        let insert = MasterBusInsert.filter()
        session.addMasterBusInsert(insert, to: sceneID)
        let macro = MasterSceneMacroBinding(slotIndex: 0, target: .filterCutoff(insertID: insert.id))
        session.upsertMasterSceneMacroBinding(macro, in: sceneID)
        engine.setMasterSceneMacroOverride(sceneID: sceneID, macroID: macro.id, value: 2_000)

        session.saveMasterScenePerformanceOverrides(engine.masterSceneMacroOverrides(sceneID: sceneID), to: sceneID)
        engine.clearMasterSceneMacroOverrides(sceneID: sceneID)

        XCTAssertEqual(session.store.masterBus.activeScene.inserts[0].kind.summary, "2000 Hz")
        XCTAssertEqual(engine.resolvedMasterBusState.activeScene.inserts[0].kind.summary, "2000 Hz")

        SequencerDocumentSessionRegistry.unregister(session)
    }
}

private final class DocumentBox {
    var document: SeqAIDocument

    init(document: SeqAIDocument) {
        self.document = document
    }
}
