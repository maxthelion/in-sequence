import SwiftUI
import XCTest
@testable import SequencerAI

@MainActor
final class LiveWorkspaceViewTests: XCTestCase {
    private final class DocumentBox {
        var document: SeqAIDocument

        init(document: SeqAIDocument) {
            self.document = document
        }
    }

    func test_view_initializes_for_default_document() {
        let view = LiveWorkspaceView(
            document: .constant(SeqAIDocument()),
            selectedLayerID: .constant("pattern")
        )

        XCTAssertNotNil(view)
    }

    func test_tracksBasisResolver_prefersValidEngineBasisBeforeSelectedPhrase() {
        let project = makeBasisProject()
        let engineBasisID = project.phrases[1].id

        let resolvedID = TracksBasisPhraseResolver.resolveID(
            engineBasisPhraseID: engineBasisID,
            selectedPhraseID: project.selectedPhraseID,
            phrases: project.phrases
        )
        let invalidEngineFallback = TracksBasisPhraseResolver.resolveID(
            engineBasisPhraseID: UUID(),
            selectedPhraseID: project.selectedPhraseID,
            phrases: project.phrases
        )

        XCTAssertEqual(resolvedID, engineBasisID)
        XCTAssertEqual(invalidEngineFallback, project.selectedPhraseID)
    }

    func test_queuedBasisEditTargetsQueuedPhraseAndSurvivesQueueReplacementAndNow() throws {
        let project = makeBasisProject()
        let selectedPhraseID = project.phrases[0].id
        let queuedPhraseID = project.phrases[1].id
        let replacementPhraseID = project.phrases[2].id
        let muteLayerID = try XCTUnwrap(project.layers.first(where: { $0.target == .mute })?.id)
        let trackID = project.selectedTrackID
        let (session, engine) = makeSession(project: project)
        defer {
            engine.stop()
            SequencerDocumentSessionRegistry.unregister(session)
        }

        engine.start()
        engine.clock.stop()
        XCTAssertTrue(engine.queuePhrase(queuedPhraseID))

        let editTargetID = try XCTUnwrap(TracksBasisPhraseResolver.resolveID(
            engineBasisPhraseID: engine.basisPhraseID,
            selectedPhraseID: session.store.selectedPhraseID,
            phrases: session.store.phrases
        ))
        session.setPhraseCell(
            .single(.bool(true)),
            layerID: muteLayerID,
            trackIDs: [trackID],
            phraseID: editTargetID
        )

        XCTAssertEqual(editTargetID, queuedPhraseID)
        XCTAssertEqual(
            session.store.phrases.first(where: { $0.id == selectedPhraseID })?.cell(for: muteLayerID, trackID: trackID),
            .inheritDefault
        )
        XCTAssertEqual(
            session.store.phrases.first(where: { $0.id == queuedPhraseID })?.cell(for: muteLayerID, trackID: trackID),
            .single(.bool(true))
        )

        XCTAssertTrue(engine.queuePhrase(replacementPhraseID))
        XCTAssertTrue(engine.switchPhraseNow(selectedPhraseID))

        XCTAssertEqual(
            session.store.phrases.first(where: { $0.id == queuedPhraseID })?.cell(for: muteLayerID, trackID: trackID),
            .single(.bool(true))
        )
        XCTAssertEqual(
            session.store.phrases.first(where: { $0.id == replacementPhraseID })?.cell(for: muteLayerID, trackID: trackID),
            .inheritDefault
        )
    }

    func test_tracksBasisResolverReturnsDifferentLengthEngineBasisPhraseForGridSizing() {
        let project = makeBasisProject()
        let selectedPhrase = project.phrases[0]
        let longerPhrase = project.phrases[1]

        let resolvedPhrase = TracksBasisPhraseResolver.resolvePhrase(
            engineBasisPhraseID: longerPhrase.id,
            selectedPhraseID: selectedPhrase.id,
            selectedPhrase: selectedPhrase,
            phrases: project.phrases
        )

        XCTAssertEqual(resolvedPhrase.id, longerPhrase.id)
        XCTAssertEqual(selectedPhrase.stepCount, 2)
        XCTAssertEqual(resolvedPhrase.stepCount, 12)
        XCTAssertEqual(resolvedPhrase.lengthBars, 3)
    }

    private func makeSession(project: Project) -> (SequencerDocumentSession, EngineController) {
        let documentBox = DocumentBox(document: SeqAIDocument(project: project))
        let engine = EngineController(client: nil, endpoint: nil)
        let session = SequencerDocumentSession(
            document: Binding(
                get: { documentBox.document },
                set: { documentBox.document = $0 }
            ),
            engineController: engine,
            debounceInterval: .seconds(100)
        )
        session.activate()
        return (session, engine)
    }

    private func makeBasisProject() -> Project {
        var project = makeLiveStoreProject().0
        var selectedPhrase = project.phrases[0]
        selectedPhrase.id = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
        selectedPhrase.name = "Selected"
        selectedPhrase.lengthBars = 1
        selectedPhrase.stepsPerBar = 2

        var queuedPhrase = selectedPhrase
        queuedPhrase.id = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
        queuedPhrase.name = "Queued Longer"
        queuedPhrase.lengthBars = 3
        queuedPhrase.stepsPerBar = 4

        var replacementPhrase = selectedPhrase
        replacementPhrase.id = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        replacementPhrase.name = "Replacement"
        replacementPhrase.lengthBars = 2
        replacementPhrase.stepsPerBar = 3

        project.phrases = [selectedPhrase, queuedPhrase, replacementPhrase].map {
            $0.synced(with: project.tracks, layers: project.layers)
        }
        project.selectedPhraseID = selectedPhrase.id
        return project
    }
}
