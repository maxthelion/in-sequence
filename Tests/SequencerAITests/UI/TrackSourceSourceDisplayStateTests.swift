import AppKit
import SwiftUI
import XCTest
@testable import SequencerAI

final class TrackSourceSourceDisplayStateTests: XCTestCase {
    func test_editorTabsUseSingleTrackDetailGrammar() {
        XCTAssertEqual(
            TrackSourceEditorTab.allCases.map(\.title),
            ["Steps/Clip", "Sound", "FX", "Macros", "Mixer"]
        )
        XCTAssertEqual(TrackSourceEditorTab.stepsClip.id, "steps-clip")
        XCTAssertEqual(TrackSourceEditorTab.sound.id, "sound")
        XCTAssertEqual(TrackSourceEditorTab.mixer.id, "mixer")
    }

    func test_detailTabsStayAvailableInSetupAndPerform() {
        for tab in TrackSourceEditorTab.allCases {
            XCTAssertTrue(tab.isAvailable(in: .setup))
            XCTAssertTrue(tab.isAvailable(in: .perform))
        }
    }

    func test_visualCommandAliasesMapLegacySourceAndRoutingNames() {
        XCTAssertEqual(TrackSourceEditorTab.tab(forVisualCommand: "source"), .stepsClip)
        XCTAssertEqual(TrackSourceEditorTab.tab(forVisualCommand: "routing"), .mixer)
        XCTAssertEqual(TrackSourceEditorTab.tab(forVisualCommand: "steps-clip"), .stepsClip)
        XCTAssertEqual(TrackSourceEditorTab.tab(forVisualCommand: "sound"), .sound)
    }

    @MainActor
    func test_clipHistoryTransferSaveRequiresSourceAndDestination() {
        let model = makeClipHistoryTransferViewModel(noteOffsets: [0: 60])

        XCTAssertFalse(model.canSave)

        model.selectSource(0)
        XCTAssertFalse(model.canSave)
        XCTAssertNil(model.selectedDestinationIndex)

        model.selectDestination(2)
        XCTAssertTrue(model.canSave)
    }

    @MainActor
    func test_clipHistoryLivePreviewUsesCurrentBarWhenNoSelection() throws {
        let trackID = UUID(uuidString: "10000000-0000-0000-0000-000000000401")!
        let model = ClipHistoryTransferViewModel(
            trackID: trackID,
            snapshot: CaptureSnapshot(
                maxSteps: 16,
                steps: [
                    CaptureSnapshot.Step(
                        absoluteStep: 0,
                        notes: [
                            CaptureSnapshot.Note(pitch: 60, velocity: 100, lengthSteps: 1, voiceTag: nil)
                        ]
                    ),
                    CaptureSnapshot.Step(
                        absoluteStep: 5,
                        notes: [
                            CaptureSnapshot.Note(pitch: 72, velocity: 100, lengthSteps: 1, voiceTag: nil)
                        ]
                    )
                ]
            ),
            destinationSlots: [],
            setAuditionOverride: { _ in }
        )

        XCTAssertNil(model.selectedSourceIndex)
        XCTAssertEqual(model.previewLengthSteps, 6)
        XCTAssertEqual(model.previewGridSteps, 16, "Live preview grid should stay one full bar while the bar fills.")
        XCTAssertEqual(model.liveFillStepIndex, 5)
        XCTAssertEqual(model.previewLengthLabel, "1 bar")

        let steps = try XCTUnwrap(model.previewContent?.normalized.noteGridSteps)
        XCTAssertEqual(steps.count, 6)
        XCTAssertEqual(steps[0].main?.notes.first?.pitch, 60)
        XCTAssertEqual(steps[5].main?.notes.first?.pitch, 72)
    }

    @MainActor
    func test_clipHistorySelectedPreviewFreezesUntilDeselected() throws {
        let model = makeClipHistoryTransferViewModel(noteOffsets: [192: 60])
        let updatedSnapshot = makeCaptureSnapshot(noteOffsets: [240: 72])

        model.selectSource(12)
        model.setLengthSteps(32)
        model.updateLiveSnapshot(updatedSnapshot)

        var selectedSteps = try XCTUnwrap(model.previewContent?.normalized.noteGridSteps)
        XCTAssertEqual(model.previewLengthSteps, 32)
        XCTAssertEqual(model.previewGridSteps, 32, "Auditioned preview grid should divide by the selection's step count.")
        XCTAssertNil(model.liveFillStepIndex, "Live fill marker should hide while auditioning a selection.")
        XCTAssertEqual(model.previewLengthLabel, "2 bars")
        XCTAssertEqual(selectedSteps.first?.main?.notes.first?.pitch, 60)
        XCTAssertTrue(model.isAuditioning)

        model.selectSource(12)
        model.updateLiveSnapshot(updatedSnapshot)

        selectedSteps = try XCTUnwrap(model.previewContent?.normalized.noteGridSteps)
        XCTAssertEqual(model.previewLengthSteps, 16)
        XCTAssertEqual(model.previewGridSteps, 16)
        XCTAssertEqual(model.liveFillStepIndex, 15)
        XCTAssertEqual(model.previewLengthLabel, "1 bar")
        XCTAssertEqual(selectedSteps.first?.main?.notes.first?.pitch, 72)
        XCTAssertFalse(model.isAuditioning)
    }

    @MainActor
    func test_clipHistoryCurrentLiveBarIsNotSelectableHistory() {
        let model = makeClipHistoryTransferViewModel(noteOffsets: [240: 60])
        let liveCell = model.sourceCells[15]

        XCTAssertFalse(liveCell.isEmpty)
        XCTAssertFalse(liveCell.isSelectable)

        model.selectSource(15)

        XCTAssertNil(model.selectedSourceIndex)
        XCTAssertFalse(model.isAuditioning)
    }

    @MainActor
    func test_clipHistorySelectionCannotSpillIntoCurrentLiveBar() {
        let model = makeClipHistoryTransferViewModel(noteOffsets: [224: 60])

        XCTAssertTrue(model.sourceCells[14].isSelectable)

        model.setLengthSteps(32)

        XCTAssertFalse(model.sourceCells[14].isSelectable)
        model.selectSource(14)
        XCTAssertNil(model.selectedSourceIndex)
        XCTAssertFalse(model.isAuditioning)
    }

    func test_historyDisplayStateUsesTruthfulBadges() {
        let generator = TrackSourceHistoryDisplayState.resolve(
            trackType: .monoMelodic,
            sourceState: .occupiedGenerator
        )
        let clip = TrackSourceHistoryDisplayState.resolve(
            trackType: .monoMelodic,
            sourceState: .occupiedClip
        )
        let empty = TrackSourceHistoryDisplayState.resolve(
            trackType: .monoMelodic,
            sourceState: .empty
        )
        let slice = TrackSourceHistoryDisplayState.resolve(
            trackType: .slice,
            sourceState: .occupiedGenerator
        )

        XCTAssertEqual(generator.badgeTitle, "Live")
        XCTAssertEqual(clip.badgeTitle, "Live")
        XCTAssertEqual(empty.badgeTitle, "N/A")
        XCTAssertEqual(slice.badgeTitle, "N/A")
        XCTAssertTrue(generator.isAvailable)
        XCTAssertTrue(clip.isAvailable, "History must work for clip sources as well as generators.")
        XCTAssertFalse(empty.isAvailable)
        XCTAssertFalse(slice.isAvailable)
        XCTAssertEqual(
            empty,
            .unavailable(reason: "Assign a source to build live history.")
        )
    }

    @MainActor
    func test_clipHistorySelectionStartsAndClearsAudition() {
        var overrideStates: [PseudoClipState?] = []
        let model = makeClipHistoryTransferViewModel(
            noteOffsets: [0: 60],
            setAuditionOverride: { overrideStates.append($0) }
        )

        model.selectSource(0)

        XCTAssertTrue(model.isAuditioning)
        XCTAssertNotNil(overrideStates.last!)

        model.selectSource(0)

        XCTAssertNil(model.selectedSourceIndex)
        XCTAssertFalse(model.isAuditioning)
        XCTAssertNil(overrideStates.last!)
    }

    @MainActor
    func test_clipHistorySelectionUpdatesAuditionWhenLengthChanges() throws {
        var overrideStates: [PseudoClipState?] = []
        let model = makeClipHistoryTransferViewModel(
            noteOffsets: [0: 60, 16: 62],
            setAuditionOverride: { overrideStates.append($0) }
        )

        model.selectSource(0)
        model.setLengthSteps(32)

        let override = try XCTUnwrap(overrideStates.last!)
        XCTAssertEqual(override.noteGrid.stepCount, 32)
        XCTAssertTrue(model.isAuditioning)
    }

    func test_clipHistoryPreviewPitchRowMappingReadsContourVertically() {
        let notes = [
            ClipNote(pitch: 60, startStep: 0, lengthSteps: 1, velocity: 100),
            ClipNote(pitch: 72, startStep: 4, lengthSteps: 1, velocity: 100)
        ]
        let layout = ClipHistoryPreviewLayout.resolve(notes: notes, gridSteps: 16)

        XCTAssertEqual(layout.gridSteps, 16)
        XCTAssertEqual(layout.pitchRange, 58...74, "Pitch range should pad two semitones around the played notes.")
        XCTAssertEqual(layout.pitchRowCount, 17)
        XCTAssertEqual(layout.rowIndex(forPitch: 74), 0, "The highest pitch in range maps to the top row.")
        XCTAssertEqual(layout.rowIndex(forPitch: 72), 2)
        XCTAssertEqual(layout.rowIndex(forPitch: 60), 14)
        XCTAssertLessThan(
            layout.rowIndex(forPitch: 72),
            layout.rowIndex(forPitch: 60),
            "Higher pitches must render above lower pitches."
        )
        XCTAssertEqual(layout.rowIndex(forPitch: 0), layout.rowIndex(forPitch: 58), "Out-of-range pitches clamp to the range edge.")
        XCTAssertEqual(layout.clampedStep(-3), 0)
        XCTAssertEqual(layout.clampedStep(99), 15)
    }

    func test_clipHistoryPreviewLayoutWithoutNotesUsesDefaultRangeAndGrid() {
        let layout = ClipHistoryPreviewLayout.resolve(notes: [], gridSteps: 0)

        XCTAssertEqual(layout.gridSteps, 1)
        XCTAssertEqual(layout.pitchRange, 46...74)
    }

    func test_clipHistoryPreviewStepDivisionEmphasizesBarsAndBeats() {
        let layout = ClipHistoryPreviewLayout.resolve(notes: [], gridSteps: 32)

        XCTAssertEqual(layout.stepDivision(at: 0), .bar)
        XCTAssertEqual(layout.stepDivision(at: 4), .beat)
        XCTAssertEqual(layout.stepDivision(at: 7), .step)
        XCTAssertEqual(layout.stepDivision(at: 15), .step)
        XCTAssertEqual(layout.stepDivision(at: 16), .bar, "A two-bar selection marks the second bar start.")
        XCTAssertEqual(layout.stepDivision(at: 28), .beat)
    }

    @MainActor
    func test_clipHistorySaveArmRequiresSelection() {
        let model = makeClipHistoryTransferViewModel(noteOffsets: [0: 60])

        model.armSave()

        XCTAssertFalse(model.isSaveArmed, "Save must not arm without a selected history segment.")
        XCTAssertNotNil(model.saveError)
    }

    @MainActor
    func test_clipHistorySaveArmStateMachineArmAndDisarm() {
        let model = makeClipHistoryTransferViewModel(noteOffsets: [0: 60])

        model.selectSource(0)
        model.armSave()

        XCTAssertTrue(model.isSaveArmed)
        XCTAssertNil(model.saveError)
        XCTAssertNil(model.pendingReplaceSlotIndex)

        model.selectDestination(2)
        XCTAssertTrue(model.canSave)
        XCTAssertNil(model.pendingReplaceSlotIndex, "Empty destinations need no replace confirmation.")

        model.disarmSave()

        XCTAssertFalse(model.isSaveArmed)
        XCTAssertNil(model.selectedDestinationIndex)
        XCTAssertNil(model.pendingReplaceSlotIndex)
        XCTAssertTrue(model.isAuditioning, "Disarming save must not exit audition of the selected segment.")
    }

    @MainActor
    func test_clipHistorySaveArmDeselectionDisarms() {
        let model = makeClipHistoryTransferViewModel(noteOffsets: [0: 60])

        model.selectSource(0)
        model.armSave()
        XCTAssertTrue(model.isSaveArmed)

        model.selectSource(0)

        XCTAssertNil(model.selectedSourceIndex)
        XCTAssertFalse(model.isSaveArmed, "Clearing the history selection must return the pattern row to normal navigation.")
        XCTAssertFalse(model.isAuditioning)
    }

    @MainActor
    func test_clipHistorySaveArmReplaceConfirmationFlow() {
        let model = makeClipHistoryTransferViewModel(
            noteOffsets: [0: 60],
            occupiedSlots: [3]
        )

        model.selectSource(0)
        model.armSave()
        model.selectDestination(3)

        XCTAssertEqual(model.pendingReplaceSlotIndex, 3)
        XCTAssertFalse(model.canSave)

        model.confirmReplace()

        XCTAssertNil(model.pendingReplaceSlotIndex)
        XCTAssertTrue(model.canSave)
    }

    @MainActor
    func test_clipHistorySaveArmLengthChangeInvalidatingSelectionDisarms() {
        let model = makeClipHistoryTransferViewModel(noteOffsets: [224: 60])

        model.selectSource(14)
        model.armSave()
        XCTAssertTrue(model.isSaveArmed)

        model.setLengthSteps(32)

        XCTAssertNil(model.selectedSourceIndex)
        XCTAssertFalse(model.isSaveArmed)
        XCTAssertFalse(model.isAuditioning)
    }

    @MainActor
    func test_clipHistoryTransferOccupiedSlotRequiresReplaceConfirmation() {
        let model = makeClipHistoryTransferViewModel(
            noteOffsets: [0: 60],
            occupiedSlots: [1]
        )

        model.selectSource(0)
        model.selectDestination(1)

        XCTAssertTrue(model.requiresReplaceConfirmation)
        XCTAssertFalse(model.canSave)

        model.confirmReplace()

        XCTAssertFalse(model.requiresReplaceConfirmation)
        XCTAssertTrue(model.canSave)

        model.cancelReplace()

        XCTAssertNil(model.selectedDestinationIndex)
        XCTAssertFalse(model.canSave)
    }

    @MainActor
    func test_clipHistoryTransferGeneratorBackedOccupiedSlotRequiresReplaceConfirmation() throws {
        let trackID = UUID(uuidString: "10000000-0000-0000-0000-000000000411")!
        let generatorID = UUID(uuidString: "10000000-0000-0000-0000-000000000412")!
        let slotIndex = 4
        let bank = TrackPatternBank(
            trackID: trackID,
            slots: [
                TrackPatternSlot(
                    slotIndex: slotIndex,
                    name: "Generated Pattern",
                    sourceRef: .generator(generatorID)
                )
            ]
        )
        let destinationSlots = ClipHistoryTransferViewModel.destinationSlots(
            from: bank,
            clipName: { _ in nil }
        )
        let destinationSlot = try XCTUnwrap(destinationSlots.first(where: { $0.slotIndex == slotIndex }))

        XCTAssertTrue(destinationSlot.isOccupied)
        XCTAssertEqual(destinationSlot.clipName, "Generated Pattern")

        let model = makeClipHistoryTransferViewModel(
            noteOffsets: [0: 60],
            destinationSlots: destinationSlots
        )

        model.selectSource(0)
        model.selectDestination(slotIndex)

        XCTAssertTrue(model.requiresReplaceConfirmation)
        XCTAssertFalse(model.canSave)

        model.confirmReplace()

        XCTAssertFalse(model.requiresReplaceConfirmation)
        XCTAssertTrue(model.canSave)
    }

    @MainActor
    func test_clipHistoryTransferCancelClearsAuditionWithoutSaving() {
        var overrideStates: [PseudoClipState?] = []
        var didSave = false
        let model = makeClipHistoryTransferViewModel(
            noteOffsets: [0: 60],
            setAuditionOverride: { overrideStates.append($0) }
        )

        model.selectSource(0)
        XCTAssertTrue(model.isAuditioning)
        XCTAssertNotNil(overrideStates.last!)

        model.cancel()

        XCTAssertFalse(model.isAuditioning)
        XCTAssertNil(overrideStates.last!)
        XCTAssertFalse(didSave)

        _ = model.save { _, _ in
            didSave = true
            return true
        }
        XCTAssertFalse(didSave)
    }

    @MainActor
    func test_clipHistoryTransferSaveUsesSelectedMaterializedContent() throws {
        let model = makeClipHistoryTransferViewModel(noteOffsets: [0: 60, 16: 72])
        let latestRollingContent = ClipContent.noteGrid(
            lengthSteps: 16,
            steps: [
                ClipStep(main: ClipLane(chance: 1, notes: [
                    ClipStepNote(pitch: 99, velocity: 100, lengthSteps: 1)
                ]), fill: nil)
            ]
        )

        model.selectSource(1)
        model.selectDestination(3)

        var savedContent: ClipContent?
        XCTAssertTrue(model.save { _, content in
            savedContent = content
            return true
        })

        let savedSteps = try XCTUnwrap(savedContent?.normalized.noteGridSteps)
        let savedPitch = try XCTUnwrap(savedSteps.first?.main?.notes.first?.pitch)
        let latestSteps = try XCTUnwrap(latestRollingContent.normalized.noteGridSteps)
        let latestPitch = try XCTUnwrap(latestSteps.first?.main?.notes.first?.pitch)
        XCTAssertEqual(savedPitch, 72)
        XCTAssertNotEqual(savedPitch, latestPitch)
    }

    @MainActor
    func test_clipHistoryAuditionUsesCapturedTrackIdentity() throws {
        let trackID = UUID(uuidString: "10000000-0000-0000-0000-000000000431")!
        var overrideStates: [PseudoClipState?] = []
        let model = ClipHistoryTransferViewModel(
            trackID: trackID,
            snapshot: makeCaptureSnapshot(noteOffsets: [0: 60]),
            destinationSlots: [],
            setAuditionOverride: { overrideStates.append($0) }
        )

        model.selectSource(0)

        let override = try XCTUnwrap(overrideStates.last!)
        XCTAssertEqual(model.trackID, trackID)
        XCTAssertEqual(override.sourceTrackID, trackID)
    }

    // Colour identifies, it never floods (ux-canon rule 12): the well body
    // is always neutral, so the presentation no longer exposes a tinted
    // "active section fill" — only the stroke style remains stateful.
    func test_selectedWellBodyUsesSolidStrokeForBothStates() {
        let emptyBody = TrackSourceSelectedWellBodyPresentation(isEmpty: true)
        let occupiedBody = TrackSourceSelectedWellBodyPresentation(isEmpty: false)

        XCTAssertFalse(emptyBody.usesDashedStroke)
        XCTAssertFalse(occupiedBody.usesDashedStroke)
    }

    func test_clipSourceWithClip_resolvesToOccupiedClip() {
        let state = TrackSourceSourceDisplayState.resolve(
            sourceMode: .clip,
            currentClip: ClipPoolEntry(
                id: UUID(),
                name: "Pattern Clip",
                trackType: .monoMelodic,
                content: .emptyNoteGrid(lengthSteps: 16)
            ),
            selectedGenerator: nil
        )

        XCTAssertEqual(state, .occupiedClip)
        XCTAssertEqual(state.badgeTitle, "Clip")
    }

    func test_clipSourceWithoutClip_resolvesToEmpty() {
        let state = TrackSourceSourceDisplayState.resolve(
            sourceMode: .clip,
            currentClip: nil,
            selectedGenerator: nil
        )

        XCTAssertEqual(state, .empty)
        XCTAssertEqual(state.badgeTitle, "Empty")
    }

    func test_generatorSourceWithGenerator_resolvesToOccupiedGenerator() {
        let state = TrackSourceSourceDisplayState.resolve(
            sourceMode: .generator,
            currentClip: nil,
            selectedGenerator: GeneratorPoolEntry(
                id: UUID(),
                name: "Euclidean Mono",
                trackType: .monoMelodic,
                kind: .monoGenerator,
                params: .defaultMono
            )
        )

        XCTAssertEqual(state, .occupiedGenerator)
        XCTAssertEqual(state.badgeTitle, "Gen")
    }

    func test_generatorSourceWithoutGenerator_resolvesToEmptyEvenWithRetainedClip() {
        let state = TrackSourceSourceDisplayState.resolve(
            sourceMode: .generator,
            currentClip: ClipPoolEntry(
                id: UUID(),
                name: "Retained Clip",
                trackType: .monoMelodic,
                content: .emptyNoteGrid(lengthSteps: 16)
            ),
            selectedGenerator: nil
        )

        XCTAssertEqual(state, .empty)
        XCTAssertEqual(state.badgeTitle, "Empty")
    }

    func test_occupiedSourceWellPresentationExposesOnlyRemoveAffordance() {
        let occupiedClip = TrackSourceSourceWellPresentation(displayState: .occupiedClip)
        let occupiedGenerator = TrackSourceSourceWellPresentation(displayState: .occupiedGenerator)

        XCTAssertEqual(occupiedClip.occupiedAffordanceLabels, ["Remove Source"])
        XCTAssertEqual(occupiedGenerator.occupiedAffordanceLabels, ["Remove Source"])
        XCTAssertFalse(occupiedClip.occupiedAffordanceLabels.contains("Change Source"))
        XCTAssertFalse(occupiedGenerator.occupiedAffordanceLabels.contains("Change Source"))
        XCTAssertTrue(occupiedClip.emptyAffordanceLabels.isEmpty)
        XCTAssertTrue(occupiedGenerator.emptyAffordanceLabels.isEmpty)
    }

    func test_emptySourceWellPresentationExposesAddSourceAfterRemoval() {
        let empty = TrackSourceSourceWellPresentation(displayState: .empty)

        XCTAssertTrue(empty.occupiedAffordanceLabels.isEmpty)
        XCTAssertEqual(empty.emptyAffordanceLabels, ["Add Source"])
    }

    func test_containedSourcePickerRootPresentationGroupsGeneratorBeforeClip() {
        let presentation = TrackSourceContainedSourcePickerPresentation.resolve(
            step: .root,
            compatibleGeneratorCount: 0,
            compatibleClipCount: 0
        )

        XCTAssertEqual(presentation.rootGroups.map(\.title), ["Generator", "Clip"])
        XCTAssertEqual(
            presentation.rootGroups.flatMap { [$0.primary.title, $0.secondary.title] },
            [
                "New Blank Generator",
                "Select Generator From Pool",
                "New Blank Clip",
                "Select Clip From Pool"
            ]
        )
        XCTAssertEqual(presentation.rootGroups.first?.primary.id, .createBlankGenerator)
        XCTAssertEqual(presentation.rootGroups.first?.primary.role, .primaryRecovery)
        XCTAssertEqual(presentation.rootGroups.first?.secondary.id, .showGeneratorPool)

        let clipGroup = presentation.rootGroups.last
        XCTAssertEqual(clipGroup?.primary.id, .createBlankClip)
        XCTAssertEqual(clipGroup?.primary.role, .secondaryRecovery)
        XCTAssertEqual(clipGroup?.primary.detail, "Start this slot from an empty clip.")
        XCTAssertNotEqual(clipGroup?.primary.detail, presentation.rootGroups.first?.primary.detail)
    }

    func test_containedSourcePickerEmptyPoolBranchesExposeRecoveryActions() {
        let generatorPool = TrackSourceContainedSourcePickerPresentation.resolve(
            step: .generatorPool,
            compatibleGeneratorCount: 0,
            compatibleClipCount: 1
        )
        XCTAssertEqual(generatorPool.emptyState?.title, "No compatible generators are in the pool yet.")
        XCTAssertEqual(generatorPool.emptyState?.recoveryAction.id, .createBlankGenerator)
        XCTAssertEqual(generatorPool.emptyState?.recoveryAction.title, "New Blank Generator")

        let clipPool = TrackSourceContainedSourcePickerPresentation.resolve(
            step: .clipPool,
            compatibleGeneratorCount: 1,
            compatibleClipCount: 0
        )
        XCTAssertEqual(clipPool.emptyState?.title, "No compatible clips are in the pool yet.")
        XCTAssertEqual(clipPool.emptyState?.recoveryAction.id, .createBlankClip)
        XCTAssertEqual(clipPool.emptyState?.recoveryAction.title, "New Blank Clip")
    }

    func test_containedSourcePickerNonEmptyPoolBranchesDoNotRenderEmptyState() {
        let generatorPool = TrackSourceContainedSourcePickerPresentation.resolve(
            step: .generatorPool,
            compatibleGeneratorCount: 1,
            compatibleClipCount: 0
        )
        let clipPool = TrackSourceContainedSourcePickerPresentation.resolve(
            step: .clipPool,
            compatibleGeneratorCount: 0,
            compatibleClipCount: 1
        )

        XCTAssertNil(generatorPool.emptyState)
        XCTAssertNil(clipPool.emptyState)
    }

    func test_containedSourcePickerNavigationBackAndCancelDoNotMutateSelection() throws {
        var project = Project.empty
        project.appendTrack(trackType: .monoMelodic)
        let trackID = project.selectedTrack.id
        let slotIndex = 2
        let generator = try XCTUnwrap(project.attachNewGenerator(to: trackID))
        project.assignGeneratorSource(generator.id, to: trackID, slotIndex: slotIndex)
        let sourceBeforeNavigation = project.patternBank(for: trackID).slot(at: slotIndex).sourceRef

        var pickerStep: TrackSourceContainedSourcePickerStep? = .generatorPool
        pickerStep = TrackSourceContainedSourcePickerNavigation.destination(from: pickerStep, action: .back)
        XCTAssertEqual(pickerStep, .root)
        XCTAssertEqual(project.patternBank(for: trackID).slot(at: slotIndex).sourceRef, sourceBeforeNavigation)

        pickerStep = TrackSourceContainedSourcePickerNavigation.destination(from: pickerStep, action: .cancel)
        XCTAssertNil(pickerStep)
        XCTAssertEqual(project.patternBank(for: trackID).slot(at: slotIndex).sourceRef, sourceBeforeNavigation)

        XCTAssertNil(TrackSourceContainedSourcePickerNavigation.destination(from: .root, action: .back))
    }

    func test_modifierDisplayStateBadgesReflectEmptyPresentAndBypassedStates() {
        let modifier = GeneratorPoolEntry(
            id: UUID(),
            name: "Humanize",
            trackType: .monoMelodic,
            kind: .monoGenerator,
            params: .defaultMono
        )

        let empty = TrackSourceModifierDisplayState.resolve(
            trackType: .monoMelodic,
            selectedGenerator: nil,
            isBypassed: false
        )
        let present = TrackSourceModifierDisplayState.resolve(
            trackType: .monoMelodic,
            selectedGenerator: modifier,
            isBypassed: false
        )
        let bypassed = TrackSourceModifierDisplayState.resolve(
            trackType: .monoMelodic,
            selectedGenerator: modifier,
            isBypassed: true
        )

        XCTAssertEqual(empty, .empty)
        XCTAssertEqual(empty.badgeTitle, "Empty")
        XCTAssertEqual(present, .occupied)
        XCTAssertEqual(present.badgeTitle, "Mod")
        XCTAssertEqual(bypassed, .bypassed)
        XCTAssertEqual(bypassed.badgeTitle, "Byp")
    }

    func test_modifierDisplayStateShowsUnavailableForUnsupportedTrackTypes() {
        XCTAssertTrue(TrackSourceModifierDisplayState.supportsModifierStage(trackType: .monoMelodic))
        XCTAssertTrue(TrackSourceModifierDisplayState.supportsModifierStage(trackType: .polyMelodic))
        XCTAssertFalse(TrackSourceModifierDisplayState.supportsModifierStage(trackType: .slice))

        let state = TrackSourceModifierDisplayState.resolve(
            trackType: .slice,
            selectedGenerator: nil,
            isBypassed: false
        )

        XCTAssertEqual(state, .unavailable)
        XCTAssertEqual(state.badgeTitle, "N/A")
    }

    func test_emptyModifierTabUsesVioletSelectedAccentWithMutedBadge() {
        let presentation = TrackSourceSlotWellTabAccentPresentation.modifier(for: .empty)

        XCTAssertEqual(presentation.badge, .border)
        XCTAssertEqual(presentation.selected, .violet)
    }

    func test_containedModifierPickerRootAndEmptyPoolPresentation() {
        let root = TrackSourceContainedModifierPickerPresentation.resolve(
            step: .root,
            compatibleModifierCount: 0
        )
        XCTAssertEqual(root.actions, [.createBlankModifier, .showModifierPool])
        XCTAssertNil(root.emptyStateTitle)

        let emptyPool = TrackSourceContainedModifierPickerPresentation.resolve(
            step: .modifierPool,
            compatibleModifierCount: 0
        )
        XCTAssertEqual(emptyPool.emptyStateTitle, "No compatible modifiers are in the pool yet.")

        let nonEmptyPool = TrackSourceContainedModifierPickerPresentation.resolve(
            step: .modifierPool,
            compatibleModifierCount: 1
        )
        XCTAssertNil(nonEmptyPool.emptyStateTitle)
    }

    func test_containedModifierPickerNavigationDoesNotMutateEmptySource() throws {
        var project = Project.empty
        project.appendTrack(trackType: .monoMelodic)
        let trackID = project.selectedTrack.id
        let slotIndex = 1
        project.removeSelectedSlotSource(trackID: trackID, slotIndex: slotIndex)
        let sourceBeforeNavigation = project.patternBank(for: trackID).slot(at: slotIndex).sourceRef

        var pickerStep: TrackSourceContainedModifierPickerStep? = .modifierPool
        pickerStep = TrackSourceContainedModifierPickerNavigation.destination(from: pickerStep, action: .back)
        XCTAssertEqual(pickerStep, .root)
        XCTAssertEqual(project.patternBank(for: trackID).slot(at: slotIndex).sourceRef, sourceBeforeNavigation)

        pickerStep = TrackSourceContainedModifierPickerNavigation.destination(from: pickerStep, action: .cancel)
        XCTAssertNil(pickerStep)
        XCTAssertEqual(project.patternBank(for: trackID).slot(at: slotIndex).sourceRef, sourceBeforeNavigation)
        XCTAssertNil(project.patternBank(for: trackID).slot(at: slotIndex).sourceRef.clipID)
    }

    @MainActor
    func test_renderClipHistoryInlineHistoryTabVisualEvidence() throws {
        guard let outputPath = clipHistoryVisualEvidenceOutputPath(),
              !outputPath.isEmpty
        else {
            throw XCTSkip("Set SEQUENCERAI_CLIP_HISTORY_VISUAL_EVIDENCE_DIR or .clip-history-visual-evidence-output to render clip-history visual evidence.")
        }

        let outputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true)
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

        let liveModel = makeClipHistoryTransferViewModel(
            noteOffsets: [
                48: 55,
                64: 62,
                96: 67,
                160: 72,
                176: 64,
                240: 59,
                244: 71
            ]
        )
        try renderEvidence(
            ClipHistoryEvidenceSurface(model: liveModel),
            to: outputDirectory.appendingPathComponent("01-generator-live-current-bar-nonselectable.png")
        )

        let selectedModel = makeClipHistoryTransferViewModel(
            noteOffsets: [
                48: 55,
                64: 62,
                96: 67,
                160: 72,
                176: 64,
                240: 59,
                244: 71
            ]
        )
        selectedModel.selectSource(10)
        selectedModel.setLengthSteps(32)
        try renderEvidence(
            ClipHistoryEvidenceSurface(model: selectedModel),
            to: outputDirectory.appendingPathComponent("02-selected-prior-region-2-bars-audition-save-enabled.png")
        )

        selectedModel.selectSource(10)
        try renderEvidence(
            ClipHistoryEvidenceSurface(model: selectedModel),
            to: outputDirectory.appendingPathComponent("03-deselected-rolling-live-preview.png")
        )

        let armedModel = makeClipHistoryTransferViewModel(
            noteOffsets: [
                48: 55,
                64: 62,
                96: 67,
                160: 72,
                176: 64,
                240: 59,
                244: 71
            ]
        )
        armedModel.selectSource(10)
        armedModel.setLengthSteps(32)
        try renderEvidence(
            ClipHistoryDestinationEvidenceSurface(
                model: armedModel,
                occupiedSlots: [0, 4],
                pendingReplaceSlot: nil
            ),
            to: outputDirectory.appendingPathComponent("04-save-clip-destination-arm-pattern-row.png")
        )

        let replaceModel = makeClipHistoryTransferViewModel(
            noteOffsets: [
                48: 55,
                64: 62,
                96: 67,
                160: 72,
                176: 64,
                240: 59,
                244: 71
            ],
            occupiedSlots: [3]
        )
        replaceModel.selectSource(10)
        replaceModel.setLengthSteps(32)
        replaceModel.selectDestination(3)
        try renderEvidence(
            ClipHistoryDestinationEvidenceSurface(
                model: replaceModel,
                occupiedSlots: [3],
                pendingReplaceSlot: 3
            ),
            to: outputDirectory.appendingPathComponent("05-occupied-destination-inline-replace.png")
        )

        let clipSourceModel = makeClipHistoryTransferViewModel(
            noteOffsets: [
                48: 55,
                64: 62,
                96: 67,
                160: 72,
                176: 64,
                240: 59,
                244: 71
            ]
        )
        try renderEvidence(
            ClipHistoryEvidenceSurface(
                model: clipSourceModel,
                sourceState: .occupiedClip,
                sourceSummary: "Clip source: Saved Riff"
            ),
            to: outputDirectory.appendingPathComponent("06-clip-source-history-live.png")
        )
        try renderEvidence(
            ClipHistoryUnavailableEvidenceSurface(
                sourceState: .empty,
                historyState: TrackSourceHistoryDisplayState.resolve(
                    trackType: .monoMelodic,
                    sourceState: .empty
                )
            ),
            to: outputDirectory.appendingPathComponent("07-empty-source-history-na.png")
        )
        try renderEvidence(
            ClipHistoryUnavailableEvidenceSurface(
                sourceState: .occupiedGenerator,
                historyState: TrackSourceHistoryDisplayState.resolve(
                    trackType: .slice,
                    sourceState: .occupiedGenerator
                )
            ),
            to: outputDirectory.appendingPathComponent("08-slice-source-history-na.png")
        )

        let renderedFiles = try FileManager.default.contentsOfDirectory(
            at: outputDirectory,
            includingPropertiesForKeys: [.fileSizeKey]
        ).filter { $0.pathExtension == "png" }

        XCTAssertEqual(renderedFiles.count, 8)
        for file in renderedFiles {
            let values = try file.resourceValues(forKeys: [.fileSizeKey])
            XCTAssertGreaterThan(values.fileSize ?? 0, 10_000, "Expected non-empty visual evidence for \(file.lastPathComponent)")
        }
    }

    private func clipHistoryVisualEvidenceOutputPath() -> String? {
        if let outputPath = ProcessInfo.processInfo.environment["SEQUENCERAI_CLIP_HISTORY_VISUAL_EVIDENCE_DIR"] {
            return outputPath
        }

        let testFile = URL(fileURLWithPath: #filePath)
        let worktreeRoot = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sentinel = worktreeRoot.appendingPathComponent(".clip-history-visual-evidence-output")
        return try? String(contentsOf: sentinel, encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private func makeClipHistoryTransferViewModel(
        noteOffsets: [Int: Int],
        occupiedSlots: Set<Int> = [],
        destinationSlots: [ClipHistoryTransferViewModel.DestinationSlot]? = nil,
        setAuditionOverride: @escaping (PseudoClipState?) -> Void = { _ in }
    ) -> ClipHistoryTransferViewModel {
        let trackID = UUID(uuidString: "10000000-0000-0000-0000-000000000401")!

        return ClipHistoryTransferViewModel(
            trackID: trackID,
            snapshot: makeCaptureSnapshot(noteOffsets: noteOffsets),
            destinationSlots: destinationSlots ?? (0..<TrackPatternBank.slotCount).map { index in
                ClipHistoryTransferViewModel.DestinationSlot(
                    slotIndex: index,
                    isOccupied: occupiedSlots.contains(index),
                    clipName: occupiedSlots.contains(index) ? "Existing P\(index + 1)" : nil
                )
            },
            setAuditionOverride: setAuditionOverride
        )
    }

    private func makeCaptureSnapshot(noteOffsets: [Int: Int], maxSteps: Int = 256) -> CaptureSnapshot {
        var steps = noteOffsets.map { offset, pitch in
            CaptureSnapshot.Step(
                absoluteStep: offset,
                notes: [
                    CaptureSnapshot.Note(
                        pitch: pitch,
                        velocity: 100,
                        lengthSteps: 1,
                        voiceTag: nil
                    )
                ]
            )
        }
        if noteOffsets[maxSteps - 1] == nil {
            steps.append(CaptureSnapshot.Step(absoluteStep: maxSteps - 1, notes: []))
        }
        steps.sort { $0.absoluteStep < $1.absoluteStep }
        return CaptureSnapshot(maxSteps: maxSteps, steps: steps)
    }

    @MainActor
    private func renderEvidence<Content: View>(_ content: Content, to url: URL) throws {
        let size = CGSize(width: 1180, height: 720)
        let renderer = ImageRenderer(
            content: content
                .frame(width: size.width, height: size.height)
        )
        renderer.proposedSize = ProposedViewSize(size)
        renderer.scale = 2

        guard let cgImage = renderer.cgImage else {
            XCTFail("Could not render \(url.lastPathComponent)")
            return
        }

        let bitmap = NSBitmapImageRep(cgImage: cgImage)
        guard let data = bitmap.representation(using: .png, properties: [:]) else {
            XCTFail("Could not encode \(url.lastPathComponent)")
            return
        }
        try data.write(to: url, options: .atomic)
    }
}

private struct ClipHistoryEvidenceSurface: View {
    let model: ClipHistoryTransferViewModel
    var sourceState: TrackSourceSourceDisplayState = .occupiedGenerator
    var sourceSummary: String = "Generator live history: Euclidean Mono"

    var body: some View {
        ClipHistoryEvidenceShell {
            TrackSourceSlotWellTabBar(
                selectedTab: .constant(.stepsClip),
                sourceState: sourceState,
                modifierState: .empty,
                routingState: TrackSourceRoutingDisplayState(
                    pillSummary: "AU Instrument → Master",
                    soundBadgeTitle: "AU Instrument"
                ),
                accent: StudioTheme.cyan
            )

            TrackSourceClipHistoryTabContent(
                model: model,
                accent: StudioTheme.success,
                sourceSummary: sourceSummary,
                isDestinationMode: false,
                onSaveClip: {}
            )
        }
    }
}

private struct ClipHistoryDestinationEvidenceSurface: View {
    let model: ClipHistoryTransferViewModel
    let occupiedSlots: Set<Int>
    let pendingReplaceSlot: Int?

    var body: some View {
        ClipHistoryEvidenceShell {
            StudioPanel(title: "Pattern", accent: StudioTheme.success) {
                VStack(alignment: .leading, spacing: 10) {
                    TrackPatternSlotPalette(
                        selectedSlot: .constant(0),
                        occupiedSlots: occupiedSlots,
                        bypassState: .notApplicable,
                        onBypassToggle: { _ in },
                        destinationMode: TrackPatternSlotPalette.DestinationMode(
                            pendingReplaceSlot: pendingReplaceSlot,
                            accent: StudioTheme.success
                        ),
                        onDestinationSelect: { _ in }
                    )

                    destinationRow
                }
            }

            TrackSourceSlotWellTabBar(
                selectedTab: .constant(.stepsClip),
                sourceState: .occupiedGenerator,
                modifierState: .empty,
                routingState: TrackSourceRoutingDisplayState(
                    pillSummary: "AU Instrument → Master",
                    soundBadgeTitle: "AU Instrument"
                ),
                accent: StudioTheme.cyan
            )

            TrackSourceClipHistoryTabContent(
                model: model,
                accent: StudioTheme.success,
                sourceSummary: "Generator live history: Euclidean Mono",
                isDestinationMode: true,
                onSaveClip: {}
            )
        }
    }

    @ViewBuilder
    private var destinationRow: some View {
        HStack(spacing: 10) {
            if let pendingReplaceSlot {
                Text("P\(pendingReplaceSlot + 1) is occupied.")
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.amber)
                Spacer(minLength: 0)
                Button("Replace") {}
                    .buttonStyle(.plain)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.text)
                Button("Cancel") {}
                    .buttonStyle(.plain)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.mutedText)
            } else {
                Text("Choose a pulsing pattern slot to save the selected history clip.")
                    .studioText(.label)
                    .foregroundStyle(StudioTheme.mutedText)
                Spacer(minLength: 0)
                Button("Cancel") {}
                    .buttonStyle(.plain)
                    .studioText(.labelBold)
                    .foregroundStyle(StudioTheme.mutedText)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            StudioTheme.success.opacity(StudioOpacity.selectedFill),
            in: RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: StudioMetrics.CornerRadius.control, style: .continuous)
                .stroke(StudioTheme.success.opacity(StudioOpacity.ghostStroke), lineWidth: 1)
        )
    }
}

private struct ClipHistoryUnavailableEvidenceSurface: View {
    let sourceState: TrackSourceSourceDisplayState
    let historyState: TrackSourceHistoryDisplayState

    var body: some View {
        ClipHistoryEvidenceShell {
            TrackSourceSlotWellTabBar(
                selectedTab: .constant(.stepsClip),
                sourceState: sourceState,
                modifierState: .empty,
                routingState: TrackSourceRoutingDisplayState(
                    pillSummary: "AU Instrument → Master",
                    soundBadgeTitle: "AU Instrument"
                ),
                accent: StudioTheme.cyan
            )

            TrackSourceSelectedWellBody(accent: StudioTheme.success, isEmpty: false) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("History")
                        .studioText(.bodyBold)
                        .foregroundStyle(StudioTheme.text)
                    Text(unavailableReason)
                        .studioText(.body)
                        .foregroundStyle(StudioTheme.mutedText)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            }
        }
    }

    private var unavailableReason: String {
        if case let .unavailable(reason) = historyState {
            return reason
        }
        return "History is unavailable for this source."
    }
}

private struct ClipHistoryEvidenceShell<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ZStack {
            StudioTheme.stageFill

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}
