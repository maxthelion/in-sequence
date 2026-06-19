import XCTest
@testable import SequencerAI

final class TransportPhraseNavigationPresentationTests: XCTestCase {
    func test_freeStoppedShowsSelectedPhraseAndNoNextPhrase() {
        let phrases = makePhrases()

        let presentation = TransportPhraseNavigationPresentation.make(
            phrases: phrases,
            selectedPhraseID: phrases[0].id,
            currentPhraseID: nil,
            queuedPhraseID: nil,
            isRunning: false,
            transportMode: .free
        )

        XCTAssertEqual(presentation.currentName, "Phrase A")
        XCTAssertTrue(presentation.hasCurrent)
        XCTAssertEqual(presentation.nextLabel, "NEXT")
        XCTAssertEqual(presentation.nextName, "None")
        XCTAssertFalse(presentation.hasNext)
        XCTAssertTrue(presentation.helpText.contains("No next phrase in Free mode"))
    }

    func test_songRunningShowsArrangementNextPhraseWhenNoQueuedOverride() {
        let phrases = makePhrases()

        let presentation = TransportPhraseNavigationPresentation.make(
            phrases: phrases,
            selectedPhraseID: phrases[0].id,
            currentPhraseID: phrases[0].id,
            queuedPhraseID: nil,
            isRunning: true,
            transportMode: .song
        )

        XCTAssertEqual(presentation.currentName, "Phrase A")
        XCTAssertEqual(presentation.nextLabel, "NEXT")
        XCTAssertEqual(presentation.nextName, "Phrase B")
        XCTAssertTrue(presentation.hasNext)
    }

    func test_queuedPhraseOverridesSongArrangementNextPhrase() {
        let phrases = makePhrases()

        let presentation = TransportPhraseNavigationPresentation.make(
            phrases: phrases,
            selectedPhraseID: phrases[0].id,
            currentPhraseID: phrases[0].id,
            queuedPhraseID: phrases[2].id,
            isRunning: true,
            transportMode: .song
        )

        XCTAssertEqual(presentation.nextLabel, "QUEUED")
        XCTAssertEqual(presentation.nextName, "Phrase C")
        XCTAssertTrue(presentation.hasNext)
    }

    func test_loopingSongPhraseDoesNotInventArrangementNextPhrase() {
        var phrases = makePhrases()
        phrases[0].loopEnabled = true

        let presentation = TransportPhraseNavigationPresentation.make(
            phrases: phrases,
            selectedPhraseID: phrases[0].id,
            currentPhraseID: phrases[0].id,
            queuedPhraseID: nil,
            isRunning: true,
            transportMode: .song
        )

        XCTAssertEqual(presentation.nextName, "None")
        XCTAssertFalse(presentation.hasNext)
    }

    func test_progressPresentationUsesPhrasePlayheadBarAndFraction() {
        let phrase = makePhrase(name: "Phrase A", slotIndex: 0, lengthBars: 2, stepsPerBar: 4)

        let presentation = TransportPhraseProgressPresentation.make(
            phrase: phrase,
            transportTickIndex: 5
        )

        XCTAssertEqual(presentation.label, "bar 2/2")
        XCTAssertEqual(presentation.fraction, 0.75, accuracy: 0.0001)
    }

    private func makePhrases() -> [PhraseModel] {
        [
            makePhrase(name: "Phrase A", slotIndex: 0),
            makePhrase(name: "Phrase B", slotIndex: 1),
            makePhrase(name: "Phrase C", slotIndex: 2),
        ]
    }

    private func makePhrase(
        name: String,
        slotIndex: Int,
        lengthBars: Int = 1,
        stepsPerBar: Int = 4
    ) -> PhraseModel {
        PhraseModel(
            id: UUID(),
            name: name,
            lengthBars: lengthBars,
            stepsPerBar: stepsPerBar,
            cells: []
        )
    }
}
