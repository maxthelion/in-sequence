import XCTest
@testable import SequencerAI

final class TrackSourceSourceDisplayStateTests: XCTestCase {
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
}
