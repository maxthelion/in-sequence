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

    func test_structuralMixerBusMutations_updateStoreAndApplyDocumentModel() {
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
        let trackID = session.store.selectedTrackID
        let documentApplyCallsBefore = engine.applyDocumentModelCallCount

        let busID = session.addMixerBus(name: "", color: " red ")
        session.renameMixerBus(busID, name: " Stems ")
        session.setMixerBusColor(" blue ", busID: busID)
        session.setTrackOutputBus(trackID: trackID, busID: busID)

        let bus = session.store.buses[0]
        XCTAssertEqual(bus.id, busID)
        XCTAssertEqual(bus.name, "Stems")
        XCTAssertEqual(bus.color, "blue")
        XCTAssertEqual(bus.mix, .default)
        XCTAssertEqual(session.store.selectedTrack.outputBusID, busID)
        XCTAssertGreaterThan(engine.applyDocumentModelCallCount, documentApplyCallsBefore)
        XCTAssertTrue(documentBox.document.project.buses.isEmpty)

        session.flushToDocument()
        XCTAssertEqual(documentBox.document.project.buses.first?.id, busID)
        XCTAssertEqual(documentBox.document.project.selectedTrack.outputBusID, busID)

        SequencerDocumentSessionRegistry.unregister(session)
    }

    func test_mixerBusPerformanceMutations_doNotExportOrApplyDocumentModel() {
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
        let busID = session.addMixerBus(name: "Bus")
        let exportCallsBefore = session.store.exportToProjectCallCount
        let documentApplyCallsBefore = engine.applyDocumentModelCallCount

        assertNoExportDuring(session.store) {
            session.setMixerBusMix(
                busID: busID,
                mix: BusMixSettings(level: 0.3, pan: 0.2, isMuted: false, isSoloed: false)
            )
            session.setMixerBusLevel(0.45, busID: busID)
            session.setMixerBusPan(-0.3, busID: busID)
            session.setMixerBusMuted(true, busID: busID)
            session.setMixerBusSoloed(true, busID: busID)
        }

        XCTAssertEqual(session.store.exportToProjectCallCount, exportCallsBefore)
        XCTAssertEqual(engine.applyDocumentModelCallCount, documentApplyCallsBefore)
        XCTAssertEqual(
            session.store.buses[0].mix,
            BusMixSettings(level: 0.45, pan: -0.3, isMuted: true, isSoloed: true)
        )
        XCTAssertTrue(documentBox.document.project.buses.isEmpty)

        session.flushToDocument()
        XCTAssertEqual(documentBox.document.project.buses.first?.mix, session.store.buses[0].mix)

        SequencerDocumentSessionRegistry.unregister(session)
    }

    func test_trackSoloPerformanceMutation_doesNotExportOrApplyDocumentModel() {
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
        let trackID = session.store.selectedTrackID
        let documentApplyCallsBefore = engine.applyDocumentModelCallCount

        assertNoExportDuring(session.store) {
            session.setTrackSoloed(true, trackID: trackID)
        }

        XCTAssertEqual(engine.applyDocumentModelCallCount, documentApplyCallsBefore)
        XCTAssertTrue(session.store.selectedTrack.mix.isSoloed)
        XCTAssertFalse(documentBox.document.project.selectedTrack.mix.isSoloed)

        session.flushToDocument()
        XCTAssertTrue(documentBox.document.project.selectedTrack.mix.isSoloed)

        SequencerDocumentSessionRegistry.unregister(session)
    }

    func test_clearAllSoloPerformanceMutation_doesNotExportOrApplyDocumentModel() {
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
        let trackID = session.store.selectedTrackID
        let busID = session.addMixerBus(name: "Bus")
        session.setTrackSoloed(true, trackID: trackID)
        session.setMixerBusSoloed(true, busID: busID)
        let documentApplyCallsBefore = engine.applyDocumentModelCallCount

        assertNoExportDuring(session.store) {
            session.clearAllSolo()
        }

        XCTAssertEqual(engine.applyDocumentModelCallCount, documentApplyCallsBefore)
        XCTAssertFalse(session.store.selectedTrack.mix.isSoloed)
        XCTAssertFalse(session.store.buses[0].mix.isSoloed)

        SequencerDocumentSessionRegistry.unregister(session)
    }

    func test_clearAllSolo_clearsTrackAndBusSoloState() {
        let documentBox = DocumentBox(document: SeqAIDocument(project: .empty))
        let session = SequencerDocumentSession(
            document: Binding(
                get: { documentBox.document },
                set: { documentBox.document = $0 }
            ),
            engineController: EngineController(client: nil, endpoint: nil),
            debounceInterval: .seconds(100)
        )
        let trackID = session.store.selectedTrackID
        let busID = session.addMixerBus(name: "Bus")
        session.setTrackSoloed(true, trackID: trackID)
        session.setMixerBusSoloed(true, busID: busID)

        session.clearAllSolo()

        XCTAssertFalse(session.store.selectedTrack.mix.isSoloed)
        XCTAssertFalse(session.store.buses[0].mix.isSoloed)

        SequencerDocumentSessionRegistry.unregister(session)
    }

    func test_deleteMixerBus_returnsAffectedTracksToMaster() {
        let documentBox = DocumentBox(document: SeqAIDocument(project: .empty))
        let session = SequencerDocumentSession(
            document: Binding(
                get: { documentBox.document },
                set: { documentBox.document = $0 }
            ),
            engineController: EngineController(client: nil, endpoint: nil),
            debounceInterval: .seconds(100)
        )
        let routedTrackID = session.store.selectedTrackID
        let busID = session.addMixerBus(name: "Drums")
        session.setTrackOutputBus(trackID: routedTrackID, busID: busID)

        let affectedTrackIDs = session.deleteMixerBus(id: busID)

        XCTAssertEqual(affectedTrackIDs, [routedTrackID])
        XCTAssertTrue(session.store.buses.isEmpty)
        XCTAssertNil(session.store.selectedTrack.outputBusID)

        session.flushToDocument()
        XCTAssertTrue(documentBox.document.project.buses.isEmpty)
        XCTAssertNil(documentBox.document.project.selectedTrack.outputBusID)

        SequencerDocumentSessionRegistry.unregister(session)
    }
}

private final class DocumentBox {
    var document: SeqAIDocument

    init(document: SeqAIDocument) {
        self.document = document
    }
}
