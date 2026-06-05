import XCTest
@testable import SequencerAI

final class PhraseButtonControlPresentationTests: XCTestCase {
    func test_openStateAllowsOnlyOnePhrasePanelAndTogglesCurrentPanelClosed() {
        let phraseA = UUID()
        let phraseB = UUID()
        var state = PhraseButtonControlsState()

        state.toggleControls(for: phraseA)
        XCTAssertEqual(state.openPhraseID, phraseA)

        state.toggleControls(for: phraseB)
        XCTAssertEqual(state.openPhraseID, phraseB)

        state.toggleControls(for: phraseB)
        XCTAssertNil(state.openPhraseID)
    }

    func test_openStateClosesWhenOpenPhraseIsRemoved() {
        let phraseA = UUID()
        let phraseB = UUID()
        var state = PhraseButtonControlsState()

        state.toggleControls(for: phraseA)
        state.reconcile(availablePhraseIDs: [phraseB])

        XCTAssertNil(state.openPhraseID)
    }

    func test_collapsedSummaryAndAccessibilityExposeSelectionPlaybackLoopAndTruncatedNameText() {
        var phrase = makePhrase(name: "Phrase D Outro Bridge With A Long User Authored Name")
        phrase.lengthBars = 12
        phrase.repeatCount = 4
        phrase.loopEnabled = true

        let presentation = PhraseButtonControlPresentation(
            phrase: phrase,
            isSelected: true,
            isPlaying: true,
            isQueued: false,
            isOpen: true
        )

        XCTAssertEqual(presentation.barCountSummary, "12 bars")
        XCTAssertEqual(presentation.repeatSummary, "Loop overrides 4 repeat")
        XCTAssertEqual(presentation.collapsedSummary, "12 bars | Loop overrides 4 repeat")
        XCTAssertEqual(presentation.loopStatusLabel, "Loop on")
        XCTAssertTrue(presentation.accessibilityLabel.contains(phrase.name))
        XCTAssertTrue(presentation.accessibilityLabel.contains("selected"))
        XCTAssertTrue(presentation.accessibilityLabel.contains("playing"))
        XCTAssertTrue(presentation.accessibilityLabel.contains("loop on"))
        XCTAssertTrue(presentation.accessibilityLabel.contains("controls open"))
    }

    func test_repeatZeroIsCommunicatedAsUnlimited() {
        var phrase = makePhrase()
        phrase.repeatCount = 0

        let presentation = PhraseButtonControlPresentation(
            phrase: phrase,
            isSelected: false,
            isPlaying: false,
            isQueued: false,
            isOpen: false
        )

        XCTAssertEqual(presentation.repeatValueLabel, "Unlimited")
        XCTAssertEqual(presentation.repeatSummary, "Unlimited repeat")
        XCTAssertEqual(
            presentation.effectivePlaybackSummary,
            "unlimited repeat keeps this phrase playing until another phrase is chosen."
        )
    }

    func test_loopSummaryPreservesStoredRepeatAndQueuedPrecedence() {
        var phrase = makePhrase()
        phrase.repeatCount = 7
        phrase.loopEnabled = true

        let presentation = PhraseButtonControlPresentation(
            phrase: phrase,
            isSelected: false,
            isPlaying: false,
            isQueued: true,
            isOpen: true
        )

        XCTAssertEqual(
            presentation.effectivePlaybackSummary,
            "Queued: starts at the next phrase boundary, then loop stays on this phrase. Stored repeat 7 is preserved for when loop is off."
        )
    }

    func test_summaryHelpersClampDisplayedBounds() {
        XCTAssertEqual(PhraseButtonControlPresentation.barCountSummary(-50), "1 bar")
        XCTAssertEqual(PhraseButtonControlPresentation.barCountSummary(999), "64 bars")
        XCTAssertEqual(PhraseButtonControlPresentation.repeatValueLabel(-50), "Unlimited")
        XCTAssertEqual(PhraseButtonControlPresentation.repeatValueLabel(999), "64")
    }

    private func makePhrase(name: String = "Phrase A") -> PhraseModel {
        PhraseModel(
            id: UUID(),
            name: name,
            lengthBars: 8,
            stepsPerBar: 16,
            cells: []
        )
    }
}
