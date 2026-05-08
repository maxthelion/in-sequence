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
}
