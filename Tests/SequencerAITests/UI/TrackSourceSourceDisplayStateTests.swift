import XCTest
@testable import SequencerAI

final class TrackSourceSourceDisplayStateTests: XCTestCase {
    func test_editorTabsKeepHistoryAsTabPeer() {
        XCTAssertEqual(
            TrackSourceEditorTab.allCases.map(\.title),
            ["Source", "Modifier", "History"]
        )
        XCTAssertEqual(TrackSourceEditorTab.history.id, "history")
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
        XCTAssertEqual(model.previewLengthLabel, "2 bars")
        XCTAssertEqual(selectedSteps.first?.main?.notes.first?.pitch, 60)
        XCTAssertTrue(model.isAuditioning)

        model.selectSource(12)
        model.updateLiveSnapshot(updatedSnapshot)

        selectedSteps = try XCTUnwrap(model.previewContent?.normalized.noteGridSteps)
        XCTAssertEqual(model.previewLengthSteps, 16)
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
        XCTAssertEqual(clip.badgeTitle, "N/A")
        XCTAssertEqual(empty.badgeTitle, "N/A")
        XCTAssertEqual(slice.badgeTitle, "N/A")
        XCTAssertTrue(generator.isAvailable)
        XCTAssertFalse(clip.isAvailable)
        XCTAssertFalse(empty.isAvailable)
        XCTAssertFalse(slice.isAvailable)
        XCTAssertEqual(
            clip,
            .unavailable(reason: "Clip playback history needs capture support before it can be saved from History.")
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

    func test_selectedWellBodyKeepsEmptyStateAsActiveSection() {
        let emptyBody = TrackSourceSelectedWellBodyPresentation(isEmpty: true)
        let occupiedBody = TrackSourceSelectedWellBodyPresentation(isEmpty: false)

        XCTAssertTrue(emptyBody.usesActiveSectionFill)
        XCTAssertTrue(occupiedBody.usesActiveSectionFill)
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
}
