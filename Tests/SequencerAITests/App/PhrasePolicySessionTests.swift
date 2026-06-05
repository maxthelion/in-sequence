import SwiftUI
import XCTest
@testable import SequencerAI

@MainActor
final class PhrasePolicySessionTests: XCTestCase {
    func test_phrasePolicyCommandsClampAndPublishPhraseScopedMutation() throws {
        let (session, phraseID, _) = makeSessionWithAuthoredBarValues()
        let snapshotCallsBefore = session.engineController.applyPlaybackSnapshotCallCount

        XCTAssertTrue(session.setPhraseBarCount(999, phraseID: phraseID))
        XCTAssertTrue(session.setPhraseRepeatCount(-1, phraseID: phraseID))
        XCTAssertTrue(session.setPhraseLoopEnabled(true, phraseID: phraseID))

        let phrase = try XCTUnwrap(session.store.phrases.first(where: { $0.id == phraseID }))
        XCTAssertEqual(phrase.lengthBars, 64)
        XCTAssertEqual(phrase.repeatCount, 0)
        XCTAssertTrue(phrase.loopEnabled)
        XCTAssertGreaterThan(session.engineController.applyPlaybackSnapshotCallCount, snapshotCallsBefore)

        SequencerDocumentSessionRegistry.unregister(session)
    }

    func test_setPhraseBarCountShrinksActiveBoundaryWithoutDeletingBarValues() throws {
        let (session, phraseID, layerID) = makeSessionWithAuthoredBarValues()

        XCTAssertTrue(session.setPhraseBarCount(2, phraseID: phraseID))

        let phrase = try XCTUnwrap(session.store.phrases.first(where: { $0.id == phraseID }))
        XCTAssertEqual(phrase.lengthBars, 2)
        guard case let .bars(values) = phrase.cell(for: layerID, trackID: session.store.tracks[0].id) else {
            XCTFail("Expected authored bar values to remain in bar-cell storage")
            SequencerDocumentSessionRegistry.unregister(session)
            return
        }
        XCTAssertEqual(values, [.index(0), .index(1), .index(2), .index(3)])

        SequencerDocumentSessionRegistry.unregister(session)
    }

    func test_phrasePolicyCommandsReturnFalseForNoOpOrMissingPhrase() {
        let (session, phraseID, _) = makeSessionWithAuthoredBarValues()

        XCTAssertFalse(session.setPhraseBarCount(8, phraseID: phraseID))
        XCTAssertFalse(session.setPhraseRepeatCount(1, phraseID: phraseID))
        XCTAssertFalse(session.setPhraseLoopEnabled(false, phraseID: phraseID))
        XCTAssertFalse(session.setPhraseRepeatCount(3, phraseID: UUID()))

        SequencerDocumentSessionRegistry.unregister(session)
    }

    private func makeSessionWithAuthoredBarValues() -> (SequencerDocumentSession, UUID, String) {
        let track = StepSequenceTrack.default
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let layerID = "pattern"
        var phrase = PhraseModel.default(
            tracks: [track],
            layers: layers,
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: []
        )
        phrase.lengthBars = 8
        phrase.setCell(.bars([.index(0), .index(1), .index(2), .index(3)]), for: layerID, trackID: track.id)

        let project = Project(
            version: 1,
            tracks: [track],
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: [],
            layers: layers,
            routes: [],
            patternBanks: [TrackPatternBank.default(for: track, initialClipID: nil)],
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )
        let documentBox = PhrasePolicyDocumentBox(document: SeqAIDocument(project: project))
        let session = SequencerDocumentSession(
            document: Binding(
                get: { documentBox.document },
                set: { documentBox.document = $0 }
            ),
            engineController: EngineController(client: nil, endpoint: nil),
            debounceInterval: .seconds(100)
        )
        return (session, phrase.id, layerID)
    }
}

@MainActor
private final class PhrasePolicyDocumentBox {
    var document: SeqAIDocument

    init(document: SeqAIDocument) {
        self.document = document
    }
}
