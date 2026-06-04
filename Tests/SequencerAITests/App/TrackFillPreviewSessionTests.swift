import Foundation
import Observation
import SwiftUI
import XCTest
@testable import SequencerAI

@MainActor
final class TrackFillPreviewSessionTests: XCTestCase {
    private final class ObservationCounter: @unchecked Sendable {
        private let lock = NSLock()
        private var count = 0

        var didChange: Bool {
            lock.withLock { count > 0 }
        }

        func increment() {
            lock.withLock { count += 1 }
        }
    }

    private final class DocumentBox {
        var document: SeqAIDocument

        init(document: SeqAIDocument) {
            self.document = document
        }
    }

    private func makeSession(
        project: Project? = nil,
        debounceInterval: Duration = .seconds(100)
    ) -> (SequencerDocumentSession, EngineController, DocumentBox) {
        let (defaultProject, _, _) = makeLiveStoreProject()
        let resolvedProject = project ?? defaultProject
        let box = DocumentBox(document: SeqAIDocument(project: resolvedProject))
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

    func test_enableSelectedTrackFillPreviewPublishesRuntimeOnlyState() {
        let (session, engine, box) = makeSession()
        let selectedTrackID = session.store.selectedTrackID
        let documentBefore = box.document.project
        let revisionBefore = session.revision
        let playbackSnapshotApplyCallsBefore = engine.applyPlaybackSnapshotCallCount
        let documentApplyCallsBefore = engine.applyDocumentModelCallCount

        let observedChange = ObservationCounter()
        withObservationTracking {
            _ = session.trackFillPreviewState.activeTrackID
        } onChange: {
            observedChange.increment()
        }

        assertNoExportDuring(session.store) {
            session.enableSelectedTrackFillPreview()
        }

        XCTAssertEqual(session.trackFillPreviewState.activeTrackID, selectedTrackID)
        XCTAssertEqual(engine.currentTrackFillPreviewSnapshotForTesting.activeTrackID, selectedTrackID)
        XCTAssertTrue(observedChange.didChange)
        XCTAssertEqual(session.revision, revisionBefore)
        XCTAssertEqual(engine.applyPlaybackSnapshotCallCount, playbackSnapshotApplyCallsBefore)
        XCTAssertEqual(engine.applyDocumentModelCallCount, documentApplyCallsBefore)
        XCTAssertEqual(box.document.project, documentBefore)

        session.flushToDocument()
        XCTAssertEqual(box.document.project, documentBefore)
    }

    func test_disableAndClearCommandsOnlyChangeMatchingRuntimePreview() {
        let (session, engine, _) = makeSession()
        let selectedTrackID = session.store.selectedTrackID
        let otherTrackID = UUID()

        session.enableSelectedTrackFillPreview()
        session.disableTrackFillPreview(for: otherTrackID)

        XCTAssertEqual(session.trackFillPreviewState.activeTrackID, selectedTrackID)
        XCTAssertEqual(engine.currentTrackFillPreviewSnapshotForTesting.activeTrackID, selectedTrackID)

        session.disableTrackFillPreview(for: selectedTrackID)

        XCTAssertNil(session.trackFillPreviewState.activeTrackID)
        XCTAssertNil(engine.currentTrackFillPreviewSnapshotForTesting.activeTrackID)

        session.enableSelectedTrackFillPreview()
        session.clearTrackFillPreview(reason: .userCleared)

        XCTAssertNil(session.trackFillPreviewState.activeTrackID)
        XCTAssertNil(engine.currentTrackFillPreviewSnapshotForTesting.activeTrackID)
    }

    func test_externalDocumentChangeClearsRuntimePreviewWithoutSerializingIt() {
        let (project, trackID, _) = makeLiveStoreProject()
        let (session, engine, box) = makeSession(project: project)

        session.enableSelectedTrackFillPreview()
        XCTAssertEqual(session.trackFillPreviewState.activeTrackID, trackID)

        var changedProject = project
        changedProject.tracks[0].name = "External"
        session.ingestExternalDocumentChange(changedProject)

        XCTAssertNil(session.trackFillPreviewState.activeTrackID)
        XCTAssertNil(engine.currentTrackFillPreviewSnapshotForTesting.activeTrackID)
        XCTAssertEqual(box.document.project, project)
    }
}
