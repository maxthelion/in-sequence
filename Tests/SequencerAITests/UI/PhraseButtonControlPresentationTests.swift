import XCTest
@testable import SequencerAI

final class PhraseButtonControlPresentationTests: XCTestCase {
    func test_openStateAllowsOnlyOnePhrasePanelAndTogglesCurrentPanelClosed() {
        let phraseA = UUID()
        let phraseB = UUID()
        var state = PhraseButtonControlsState()

        state.openControls(for: phraseA)
        XCTAssertEqual(state.openPhraseID, phraseA)

        state.toggleControls(for: phraseA)
        XCTAssertNil(state.openPhraseID)

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

    func test_stepOrderSurfaceSeparatesUnassignedUnavailableInvalidAndPendingStates() {
        let validMapID = UUID()
        let invalidMapID = UUID()
        let missingMapID = UUID()
        let validMap = StepOrderMap(id: validMapID, name: "Break Fold")
        let invalidMap = StepOrderMap(id: invalidMapID, name: "Short", values: [0, 1, 2])

        var phrase = makePhrase(lengthBars: 1)
        var presentation = StepOrderPhraseSurfacePresentation(
            phrase: phrase,
            maps: [validMap],
            toggleState: .unavailable
        )
        XCTAssertEqual(presentation.status, .unassigned)
        XCTAssertEqual(presentation.statusLabel, "Unassigned")
        XCTAssertEqual(presentation.scopeLabel, "Phrase")
        XCTAssertFalse(presentation.canToggle)

        phrase.lengthBars = 2
        phrase.stepOrderAssignment = StepOrderAssignment(mapID: validMapID, isEnabled: false)
        presentation = StepOrderPhraseSurfacePresentation(
            phrase: phrase,
            maps: [validMap],
            toggleState: .off
        )
        XCTAssertEqual(presentation.status, .unavailable("16-step phrases only"))
        XCTAssertEqual(presentation.statusLabel, "Unavailable")

        phrase.lengthBars = 1
        phrase.stepOrderAssignment = StepOrderAssignment(mapID: invalidMapID, isEnabled: true)
        presentation = StepOrderPhraseSurfacePresentation(
            phrase: phrase,
            maps: [validMap, invalidMap],
            toggleState: .unavailable
        )
        XCTAssertEqual(presentation.status, .invalid("Invalid: 3 steps saved"))
        XCTAssertEqual(presentation.statusLabel, "Invalid")
        XCTAssertFalse(presentation.canToggle)

        phrase.stepOrderAssignment = StepOrderAssignment(mapID: missingMapID, isEnabled: true)
        presentation = StepOrderPhraseSurfacePresentation(
            phrase: phrase,
            maps: [validMap],
            toggleState: .unavailable
        )
        XCTAssertEqual(presentation.status, .invalid("Assigned map is missing"))

        phrase.stepOrderAssignment = StepOrderAssignment(mapID: validMapID, isEnabled: false)
        presentation = StepOrderPhraseSurfacePresentation(
            phrase: phrase,
            maps: [validMap],
            toggleState: .pendingOn
        )
        XCTAssertEqual(presentation.status, .pendingOn)
        XCTAssertEqual(presentation.statusLabel, "Pending On")
        XCTAssertTrue(presentation.canToggle)
        XCTAssertFalse(presentation.nextToggleValue)
        XCTAssertTrue(presentation.toggleAccessibilityLabel.contains("scope Phrase"))
    }

    func test_stepOrderSurfacePresentsValidAssignedOffOnAndPendingOffStates() {
        let mapID = UUID()
        let map = StepOrderMap(id: mapID, name: "Break Fold")
        var phrase = makePhrase(lengthBars: 1)
        phrase.stepOrderAssignment = StepOrderAssignment(mapID: mapID, isEnabled: false)

        var presentation = StepOrderPhraseSurfacePresentation(
            phrase: phrase,
            maps: [map],
            toggleState: .off
        )
        XCTAssertEqual(presentation.status, .off)
        XCTAssertEqual(presentation.statusLabel, "Off")
        XCTAssertEqual(presentation.statusSummary, "Break Fold is assigned and ready.")
        XCTAssertTrue(presentation.canToggle)
        XCTAssertTrue(presentation.nextToggleValue)
        XCTAssertEqual(
            presentation.toggleAccessibilityLabel,
            "Step Order Off, scope Phrase, active map Break Fold"
        )

        phrase.stepOrderAssignment = StepOrderAssignment(mapID: mapID, isEnabled: true)
        presentation = StepOrderPhraseSurfacePresentation(
            phrase: phrase,
            maps: [map],
            toggleState: .on
        )
        XCTAssertEqual(presentation.status, .on)
        XCTAssertEqual(presentation.statusLabel, "On")
        XCTAssertEqual(presentation.statusSummary, "Break Fold remaps source-step reads for this phrase.")
        XCTAssertTrue(presentation.canToggle)
        XCTAssertFalse(presentation.nextToggleValue)
        XCTAssertEqual(
            presentation.toggleAccessibilityLabel,
            "Step Order On, scope Phrase, active map Break Fold"
        )

        presentation = StepOrderPhraseSurfacePresentation(
            phrase: phrase,
            maps: [map],
            toggleState: .pendingOff
        )
        XCTAssertEqual(presentation.status, .pendingOff)
        XCTAssertEqual(presentation.statusLabel, "Pending Off")
        XCTAssertEqual(presentation.statusSummary, "Will turn off at the next phrase boundary.")
        XCTAssertTrue(presentation.canToggle)
        XCTAssertTrue(presentation.nextToggleValue)
        XCTAssertEqual(
            presentation.toggleAccessibilityLabel,
            "Step Order Pending Off, scope Phrase, active map Break Fold"
        )
    }

    func test_stepOrderPresentationLabelsIdentityRowsDeleteBlocksFocusAndWrap() {
        let assignedID = UUID()
        let unusedID = UUID()
        let phraseID = UUID()
        let assignedMap = StepOrderMap(id: assignedID, name: "Identity")
        let unusedMap = StepOrderMap(id: unusedID, name: "Variation", values: [0, 1, 2, 3, 3, 3, 3, 3, 7, 8, 9, 0, 1, 2, 3, 3])
        let assignment = StepOrderAssignment(mapID: assignedID, isEnabled: false)

        let assignedRow = StepOrderMapRowPresentation(
            map: assignedMap,
            deletionStatus: StepOrderMapDeletionStatus(mapID: assignedID, assignedPhraseIDs: [phraseID]),
            currentPhraseAssignment: assignment
        )
        XCTAssertEqual(assignedRow.detailLabel, "Pass-through / no remap")
        XCTAssertEqual(assignedRow.usageLabel, "1 phrase")
        XCTAssertTrue(assignedRow.isAssignedToCurrentPhrase)
        XCTAssertFalse(assignedRow.canDelete)
        XCTAssertEqual(assignedRow.deleteBlockedReason, "Assigned to 1 phrase")
        XCTAssertTrue(assignedRow.accessibilityLabel.contains("delete blocked"))

        let unusedRow = StepOrderMapRowPresentation(
            map: unusedMap,
            deletionStatus: StepOrderMapDeletionStatus(mapID: unusedID, assignedPhraseIDs: []),
            currentPhraseAssignment: assignment
        )
        XCTAssertEqual(unusedRow.detailLabel, "Remap active")
        XCTAssertEqual(unusedRow.usageLabel, "0 phrases")
        XCTAssertFalse(unusedRow.isAssignedToCurrentPhrase)
        XCTAssertTrue(unusedRow.canDelete)
        XCTAssertNil(unusedRow.deleteBlockedReason)

        XCTAssertEqual(
            StepOrderPhraseSurfacePresentation.outputStepAccessibilityLabel(outputIndex: 4, sourceIndex: 3),
            "Output step 5 reads source step 4"
        )
        XCTAssertEqual(
            StepOrderPhraseSurfacePresentation.sourceStepAccessibilityLabel(sourceIndex: 7, selectedOutputIndex: 4),
            "Assign source step 8 to output step 5"
        )
        XCTAssertEqual(
            StepOrderPhraseSurfacePresentation.stepCandidateValues(),
            Array(0..<StepOrderMap.stepCount)
        )
        XCTAssertEqual(StepOrderPhraseSurfacePresentation.advancedOutputIndex(after: 14), 15)
        XCTAssertEqual(StepOrderPhraseSurfacePresentation.advancedOutputIndex(after: 15), 0)
        XCTAssertFalse(StepOrderPhraseSurfacePresentation.didWrapAfterEditing(outputIndex: 14))
        XCTAssertTrue(StepOrderPhraseSurfacePresentation.didWrapAfterEditing(outputIndex: 15))
    }

    func test_stepOrderNewMapNameSkipsExistingNames() {
        let maps = [
            StepOrderMap(name: "Step Order 1"),
            StepOrderMap(name: "Step Order 2"),
            StepOrderMap(name: "Custom"),
        ]

        XCTAssertEqual(StepOrderPhraseSurfacePresentation.newMapName(existingMaps: maps), "Step Order 4")
    }

    private func makePhrase(name: String = "Phrase A", lengthBars: Int = 8) -> PhraseModel {
        PhraseModel(
            id: UUID(),
            name: name,
            lengthBars: lengthBars,
            stepsPerBar: 16,
            cells: []
        )
    }
}
