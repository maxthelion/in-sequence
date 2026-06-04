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

    func test_trackSwitchClearsRuntimePreviewBeforeNewTrackCanRenderActive() {
        var project = makeLiveStoreProject().0
        let firstTrackID = project.selectedTrackID
        project.appendTrack()
        let secondTrackID = project.selectedTrackID
        project.selectTrack(id: firstTrackID)
        let (session, engine, _) = makeSession(project: project)

        session.enableSelectedTrackFillPreview()
        XCTAssertEqual(session.trackFillPreviewState.activeTrackID, firstTrackID)

        session.setSelectedTrackID(secondTrackID)

        XCTAssertNil(session.trackFillPreviewState.activeTrackID)
        XCTAssertNil(engine.currentTrackFillPreviewSnapshotForTesting.activeTrackID)
        XCTAssertFalse(
            TrackFillPreviewHeaderPresentation.resolve(
                sourceMode: session.store.selectedPattern(for: secondTrackID).sourceRef.mode,
                currentClip: session.store.clipEntry(id: session.store.selectedPattern(for: secondTrackID).sourceRef.clipID),
                selectedTrackID: secondTrackID,
                previewState: session.trackFillPreviewState
            ).isActive
        )
    }

    func test_editorAndDocumentCloseClearRuntimePreviewWithoutMutatingProject() {
        let (session, engine, box) = makeSession()
        let documentBefore = box.document.project

        session.enableSelectedTrackFillPreview()
        session.clearTrackFillPreview(reason: .editorClosed)

        XCTAssertNil(session.trackFillPreviewState.activeTrackID)
        XCTAssertNil(engine.currentTrackFillPreviewSnapshotForTesting.activeTrackID)
        XCTAssertEqual(box.document.project, documentBefore)

        session.enableSelectedTrackFillPreview()
        session.clearTrackFillPreview(reason: .documentClosed)
        session.flushToDocument()

        XCTAssertNil(session.trackFillPreviewState.activeTrackID)
        XCTAssertNil(engine.currentTrackFillPreviewSnapshotForTesting.activeTrackID)
        XCTAssertEqual(box.document.project, documentBefore)
    }

    func test_selectedTrackDeletionClearsRuntimePreview() {
        var project = makeLiveStoreProject().0
        let previewedTrackID = project.selectedTrackID
        project.appendTrack()
        project.selectTrack(id: previewedTrackID)
        let (session, engine, _) = makeSession(project: project)

        session.enableSelectedTrackFillPreview()
        session.removeSelectedTrack()

        XCTAssertFalse(session.store.tracks.contains(where: { $0.id == previewedTrackID }))
        XCTAssertNil(session.trackFillPreviewState.activeTrackID)
        XCTAssertNil(engine.currentTrackFillPreviewSnapshotForTesting.activeTrackID)
    }

    func test_sourceChangeAwayFromClipBackedClearsRuntimePreviewAndDisablesPresentation() throws {
        let (session, engine, _) = makeSession()
        let trackID = session.store.selectedTrackID
        let slotIndex = session.store.selectedPatternIndex(for: trackID)
        let generator = try XCTUnwrap(session.store.compatibleGenerators(for: session.store.selectedTrack).first)

        session.enableSelectedTrackFillPreview()
        session.assignGeneratorSource(generator.id, to: trackID, slotIndex: slotIndex)

        let selectedPattern = session.store.selectedPattern(for: trackID)
        let presentation = TrackFillPreviewHeaderPresentation.resolve(
            sourceMode: selectedPattern.sourceRef.mode,
            currentClip: session.store.clipEntry(id: selectedPattern.sourceRef.clipID),
            selectedTrackID: trackID,
            previewState: session.trackFillPreviewState
        )

        XCTAssertNil(session.trackFillPreviewState.activeTrackID)
        XCTAssertNil(engine.currentTrackFillPreviewSnapshotForTesting.activeTrackID)
        XCTAssertEqual(presentation.availability, .unavailable)
        XCTAssertFalse(presentation.isEnabled)
        XCTAssertEqual(presentation.statusText, "Fill preview is available for clip-backed tracks only in v1.")
    }

    func test_headerPresentationDerivesInactiveActiveAndCurrentTrackOnlyStates() throws {
        let (session, _, _) = makeSession()
        let trackID = session.store.selectedTrackID
        let selectedPattern = session.store.selectedPattern(for: trackID)
        let currentClip = try XCTUnwrap(session.store.clipEntry(id: selectedPattern.sourceRef.clipID))

        let inactive = TrackFillPreviewHeaderPresentation.resolve(
            sourceMode: .clip,
            currentClip: currentClip,
            selectedTrackID: trackID,
            previewState: .inactive
        )
        XCTAssertTrue(inactive.isEnabled)
        XCTAssertFalse(inactive.isActive)
        XCTAssertEqual(inactive.statusText, "Hearing phrase-resolved playback for this track.")

        let active = TrackFillPreviewHeaderPresentation.resolve(
            sourceMode: .clip,
            currentClip: currentClip,
            selectedTrackID: trackID,
            previewState: TrackFillPreviewState(activeTrackID: trackID)
        )
        XCTAssertTrue(active.isEnabled)
        XCTAssertTrue(active.isActive)
        XCTAssertEqual(active.statusText, "Hearing the fill lane for this track only.")

        let siblingTrackID = UUID()
        let sibling = TrackFillPreviewHeaderPresentation.resolve(
            sourceMode: .clip,
            currentClip: currentClip,
            selectedTrackID: siblingTrackID,
            previewState: TrackFillPreviewState(activeTrackID: trackID)
        )
        XCTAssertTrue(sibling.isEnabled)
        XCTAssertFalse(sibling.isActive)
    }

    func test_previewToggleDoesNotMutatePhraseClipDocumentRevisionOrEngineSnapshots() {
        let (session, engine, box) = makeSession()
        let trackID = session.store.selectedTrackID
        let clipID = session.store.selectedPattern(for: trackID).sourceRef.clipID!
        let phraseBefore = session.store.selectedPhrase
        let clipBefore = session.store.clipEntry(id: clipID)
        let documentBefore = box.document.project
        let revisionBefore = session.revision
        let playbackSnapshotApplyCallsBefore = engine.applyPlaybackSnapshotCallCount
        let documentApplyCallsBefore = engine.applyDocumentModelCallCount

        assertNoExportDuring(session.store) {
            session.enableSelectedTrackFillPreview()
            session.disableTrackFillPreview(for: trackID)
        }
        session.flushToDocument()

        XCTAssertNil(session.trackFillPreviewState.activeTrackID)
        XCTAssertEqual(session.store.selectedPhrase, phraseBefore)
        XCTAssertEqual(session.store.clipEntry(id: clipID), clipBefore)
        XCTAssertEqual(session.revision, revisionBefore)
        XCTAssertEqual(engine.applyPlaybackSnapshotCallCount, playbackSnapshotApplyCallsBefore)
        XCTAssertEqual(engine.applyDocumentModelCallCount, documentApplyCallsBefore)
        XCTAssertEqual(box.document.project, documentBefore)
    }

    func test_enablePreviewOnGeneratorBackedSelectedTrackStaysUnavailable() throws {
        let (session, engine, _) = makeSession()
        let trackID = session.store.selectedTrackID
        let slotIndex = session.store.selectedPatternIndex(for: trackID)
        let generator = try XCTUnwrap(session.store.compatibleGenerators(for: session.store.selectedTrack).first)
        session.assignGeneratorSource(generator.id, to: trackID, slotIndex: slotIndex)

        session.enableSelectedTrackFillPreview()

        XCTAssertNil(session.trackFillPreviewState.activeTrackID)
        XCTAssertNil(engine.currentTrackFillPreviewSnapshotForTesting.activeTrackID)
    }
}
