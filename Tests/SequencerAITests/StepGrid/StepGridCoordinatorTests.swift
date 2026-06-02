import XCTest
@testable import SequencerAI

@MainActor
final class StepGridCoordinatorTests: XCTestCase {
    func test_selectionModel_clearsWhenActiveClipChanges() {
        let firstClipID = UUID()
        let secondClipID = UUID()
        var model = StepSelectionModel(clipID: firstClipID, selectedStepIndexes: [0, 2, 4])

        model.updateActiveClip(secondClipID)

        XCTAssertEqual(model.clipID, secondClipID)
        XCTAssertTrue(model.selectedStepIndexes.isEmpty)
    }

    func test_selectionDoesNotClearWhenOnlyActiveLayerChanges() {
        let clipID = UUID()
        let mutator = RecordingClipMutator(clip: Self.makeNoteClip(id: clipID))
        let coordinator = StepGridCoordinator(clipID: clipID, clipMutator: mutator)
        coordinator.toggleSelection(at: 1)
        coordinator.toggleSelection(at: 5)

        coordinator.updateActiveLayer(.velocity)

        XCTAssertEqual(coordinator.selection.selectedStepIndexes, [1, 5])
    }

    func test_clearSelectionEmptiesSelectedStepIndexes() {
        let clipID = UUID()
        let mutator = RecordingClipMutator(clip: Self.makeNoteClip(id: clipID))
        let coordinator = StepGridCoordinator(clipID: clipID, clipMutator: mutator)
        [0, 3, 7].forEach { coordinator.toggleSelection(at: $0) }

        coordinator.clearSelection()

        XCTAssertTrue(coordinator.selection.selectedStepIndexes.isEmpty)
        XCTAssertFalse(coordinator.isSelectionActive)
        XCTAssertFalse(coordinator.shouldShowRotaryRow)
        XCTAssertFalse(coordinator.shouldShowBatchActionBar)
    }

    func test_selectionModel_acceptsNonContiguousStepIndexes() {
        let clipID = UUID()
        let model = StepSelectionModel(clipID: clipID, selectedStepIndexes: [0, 3, 7])

        XCTAssertEqual(model.selectedStepIndexes, [0, 3, 7])
    }

    func test_copySelectedSteps_capturesAllSupportedNoteAndMacroFields() throws {
        let clipID = UUID()
        let track = Self.makeTrack(macros: [
            Self.makeBinding(kind: .sampleStart),
            Self.makeBinding(kind: .sampleLength)
        ])
        let mutator = RecordingClipMutator(clip: Self.makeNoteClip(id: clipID, activeIndexes: [1, 3]))
        mutator.clip.macroLanes[track.macros[1].id] = MacroLane(values: [nil, 0.25, nil, 0.75])
        let coordinator = StepGridCoordinator(clipID: clipID, clipMutator: mutator)
        coordinator.toggleSelection(at: 1)
        coordinator.toggleSelection(at: 3)

        coordinator.copySelectedSteps(from: mutator.clip, track: track)

        let clipboard = try XCTUnwrap(coordinator.clipboard)
        XCTAssertEqual(clipboard.sourceClipID, clipID)
        XCTAssertEqual(clipboard.steps.count, 2)

        let first = try XCTUnwrap(clipboard.steps[1])
        XCTAssertTrue(first.active)
        XCTAssertEqual(try XCTUnwrap(first.velocity), 100.0 / 127.0, accuracy: 0.0001)
        XCTAssertEqual(first.chance, 0.5)
        XCTAssertNil(try XCTUnwrap(first.macroOverrides[track.macros[0].id]))
        XCTAssertEqual(try XCTUnwrap(first.macroOverrides[track.macros[1].id]), 0.25)
        XCTAssertNil(first.sliceIndex)
        XCTAssertNil(first.sliceMode)

        let second = try XCTUnwrap(clipboard.steps[3])
        XCTAssertEqual(try XCTUnwrap(second.macroOverrides[track.macros[1].id]), 0.75)
    }

    func test_copySelectedStepsDoesNotMutateClipData() throws {
        let clipID = UUID()
        let track = Self.makeTrack(macros: [Self.makeBinding(kind: .sampleStart)])
        var clip = Self.makeNoteClip(id: clipID, activeIndexes: [1, 3])
        Self.setNoteStep(in: &clip, at: 1, velocity: 48, chance: 0.35)
        clip.macroLanes[track.macros[0].id] = MacroLane(values: [nil, 0.4, nil, 0.8, nil, nil, nil, nil])
        let mutator = RecordingClipMutator(clip: clip)
        let coordinator = StepGridCoordinator(clipID: clipID, clipMutator: mutator)
        [1, 3].forEach { coordinator.toggleSelection(at: $0) }

        coordinator.copySelectedSteps(from: mutator.clip, track: track)

        XCTAssertEqual(mutator.mutationCount, 0)
        XCTAssertEqual(mutator.clip, clip)
        let clipboard = try XCTUnwrap(coordinator.clipboard)
        XCTAssertEqual(Set(clipboard.steps.keys), [1, 3])
        XCTAssertEqual(try XCTUnwrap(clipboard.steps[1]?.velocity), 48.0 / 127.0, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(clipboard.steps[1]?.chance), 0.35, accuracy: 0.0001)
        let macroOverride = try XCTUnwrap(try XCTUnwrap(clipboard.steps[1]?.macroOverrides[track.macros[0].id]))
        XCTAssertEqual(macroOverride, 0.4, accuracy: 0.0001)
    }

    func test_singleStepTap_dispatchesOneMutationAndMutatesOnlyTappedStep() {
        let clipID = UUID()
        let mutator = RecordingClipMutator(clip: Self.makeNoteClip(id: clipID))
        let coordinator = StepGridCoordinator(clipID: clipID, clipMutator: mutator)

        coordinator.onTap(stepIndex: 2, layer: .trigger)

        XCTAssertEqual(mutator.mutationCount, 1)
        XCTAssertEqual(Self.activeIndexes(in: mutator.clip), [2])
    }

    func test_selectedTap_dispatchesOneMutationAndMutatesAllSelectedSteps() {
        let clipID = UUID()
        let mutator = RecordingClipMutator(clip: Self.makeNoteClip(id: clipID))
        let coordinator = StepGridCoordinator(clipID: clipID, clipMutator: mutator)
        [0, 3, 5, 7].forEach { coordinator.toggleSelection(at: $0) }

        coordinator.onTap(stepIndex: 3, layer: .trigger)

        XCTAssertEqual(mutator.mutationCount, 1)
        XCTAssertEqual(Self.activeIndexes(in: mutator.clip), [0, 3, 5, 7])
    }

    func test_selectedAbsoluteVelocityWrite_appliesSameValueToAllSelectedStepsInOneMutation() {
        let clipID = UUID()
        let mutator = RecordingClipMutator(clip: Self.makeNoteClip(id: clipID, activeIndexes: [0, 1, 2, 3]))
        let coordinator = StepGridCoordinator(clipID: clipID, clipMutator: mutator)
        [0, 1, 2, 3].forEach { coordinator.toggleSelection(at: $0) }

        coordinator.writeAbsoluteValue(0.5, stepIndex: 2, layer: .velocity)

        XCTAssertEqual(mutator.mutationCount, 1)
        XCTAssertEqual(Self.velocities(in: mutator.clip, at: [0, 1, 2, 3]), [64, 64, 64, 64])
    }

    func test_macroWriteResolvesBindingFromTrackMacroArrayAndPersistsByBindingID() throws {
        let clipID = UUID()
        let firstBinding = Self.makeBinding(kind: .sampleStart, slotIndex: 7)
        let secondBinding = Self.makeBinding(kind: .sampleLength, slotIndex: 0)
        let track = Self.makeTrack(macros: [firstBinding, secondBinding])
        let mutator = RecordingClipMutator(clip: Self.makeNoteClip(id: clipID, activeIndexes: [1]))
        let coordinator = StepGridCoordinator(clipID: clipID, clipMutator: mutator)
        coordinator.toggleSelection(at: 1)

        coordinator.writeAbsoluteValue(0.42, stepIndex: 1, layer: .macro(index: 1), track: track)

        XCTAssertEqual(track.macros.count, 2)
        let selectedBinding = track.macros[1]
        let unselectedBinding = track.macros[0]
        XCTAssertEqual(selectedBinding.id, firstBinding.id)
        XCTAssertEqual(unselectedBinding.id, secondBinding.id)

        XCTAssertEqual(mutator.mutationCount, 1)
        XCTAssertNil(mutator.clip.macroLanes[unselectedBinding.id])
        let lane = try XCTUnwrap(mutator.clip.macroLanes[selectedBinding.id])
        XCTAssertEqual(try XCTUnwrap(lane.values[1]), 0.42, accuracy: 0.0001)
    }

    func test_macroLayerTabsResolveToTrackMacroArrayIndexNotVisualSlotPosition() throws {
        let firstBinding = Self.makeBinding(kind: .sampleStart, slotIndex: 7)
        let secondBinding = Self.makeBinding(kind: .sampleLength, slotIndex: 0)
        let macroBindings = [firstBinding, secondBinding]
        let macroSlots = [
            MacroSlot(slotIndex: 0, binding: secondBinding),
            MacroSlot(slotIndex: 7, binding: firstBinding)
        ]

        let tabs = ClipMacroLayerTab.tabs(macroSlots: macroSlots, macroBindings: macroBindings)

        let firstSlotTab = try XCTUnwrap(tabs.first { $0.slotIndex == 0 })
        XCTAssertEqual(firstSlotTab.binding.id, secondBinding.id)
        XCTAssertEqual(firstSlotTab.macroIndex, 1)

        let seventhSlotTab = try XCTUnwrap(tabs.first { $0.slotIndex == 7 })
        XCTAssertEqual(seventhSlotTab.binding.id, firstBinding.id)
        XCTAssertEqual(seventhSlotTab.macroIndex, 0)
    }

    func test_staticCellContentUsesMacroBindingArrayIndexAndBindingIDStorage() {
        let clipID = UUID()
        let firstBinding = Self.makeBinding(kind: .sampleStart, slotIndex: 7)
        let secondBinding = Self.makeBinding(kind: .sampleLength, slotIndex: 0)
        let macroBindings = [firstBinding, secondBinding]
        var clip = Self.makeNoteClip(id: clipID, activeIndexes: [1])
        clip.macroLanes[secondBinding.id] = MacroLane(values: [nil, 0.75, nil, nil, nil, nil, nil, nil])
        clip.macroLanes[firstBinding.id] = MacroLane(values: [nil, 0.25, nil, nil, nil, nil, nil, nil])

        let content = StepGridCoordinator.cellContent(
            for: 1,
            in: clip,
            layer: .macro(index: 1),
            macroBindings: macroBindings
        )

        XCTAssertEqual(content, .valueBar(fraction: 0.75))
    }

    func test_clearAndPasteUseOneMutationAndMacroBindingIDStorage() throws {
        let clipID = UUID()
        let binding = Self.makeBinding(kind: .sampleStart)
        let track = Self.makeTrack(macros: [binding])
        var clip = Self.makeNoteClip(id: clipID, activeIndexes: [1, 4])
        Self.setNoteStep(in: &clip, at: 1, velocity: 32, chance: 0.25)
        Self.setNoteStep(in: &clip, at: 4, velocity: 96, chance: 0.85)
        clip.macroLanes[binding.id] = MacroLane(values: [nil, 0.12, nil, nil, 0.88, nil, nil, nil])

        let mutator = RecordingClipMutator(clip: clip)
        let coordinator = StepGridCoordinator(clipID: clipID, clipMutator: mutator)
        [1, 4].forEach { coordinator.toggleSelection(at: $0) }
        coordinator.copySelectedSteps(from: mutator.clip, track: track)

        coordinator.clearSelectedSteps(track: track)
        XCTAssertEqual(mutator.mutationCount, 1)
        XCTAssertEqual(Self.activeIndexes(in: mutator.clip), [])
        XCTAssertFalse(coordinator.isSelectionActive)
        XCTAssertNil(mutator.clip.macroLanes[binding.id]?.values[1] ?? nil)

        coordinator.pasteClipboard(track: track)

        XCTAssertEqual(mutator.mutationCount, 2)
        XCTAssertEqual(Self.activeIndexes(in: mutator.clip), [1, 4])
        XCTAssertEqual(Self.velocities(in: mutator.clip, at: [1, 4]), [32, 96])
        XCTAssertEqual(Self.chances(in: mutator.clip, at: [1, 4]), [0.25, 0.85])

        let pastedLane = try XCTUnwrap(mutator.clip.macroLanes[binding.id])
        XCTAssertEqual(try XCTUnwrap(pastedLane.values[1]), 0.12, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(pastedLane.values[4]), 0.88, accuracy: 0.0001)
    }

    func test_clearSelectedStepsTurnsAllSelectedStepsOffInOneMutationAndClearsSelection() {
        let clipID = UUID()
        let binding = Self.makeBinding(kind: .sampleStart)
        let track = Self.makeTrack(macros: [binding])
        var clip = Self.makeNoteClip(id: clipID, activeIndexes: [1, 4, 6])
        clip.macroLanes[binding.id] = MacroLane(values: [nil, 0.12, nil, nil, 0.88, nil, 0.4, nil])
        let mutator = RecordingClipMutator(clip: clip)
        let coordinator = StepGridCoordinator(clipID: clipID, clipMutator: mutator)
        [1, 4].forEach { coordinator.toggleSelection(at: $0) }

        let didClear = coordinator.clearSelectedSteps(track: track)

        XCTAssertTrue(didClear)
        XCTAssertEqual(mutator.mutationCount, 1)
        XCTAssertEqual(mutator.impacts.count, 1)
        XCTAssertEqual(Self.activeIndexes(in: mutator.clip), [6])
        XCTAssertFalse(coordinator.isSelectionActive)
        XCTAssertNil(mutator.clip.macroLanes[binding.id]?.values[1] ?? nil)
        XCTAssertNil(mutator.clip.macroLanes[binding.id]?.values[4] ?? nil)
        XCTAssertEqual(mutator.clip.macroLanes[binding.id]?.values[6] ?? nil, 0.4)
    }

    func test_pasteClipboardRoundTripsVelocityChanceAndMacroOverrideInOneMutationSkippingOutOfBounds() throws {
        let clipID = UUID()
        let binding = Self.makeBinding(kind: .sampleStart)
        let track = Self.makeTrack(macros: [binding])
        var sourceClip = Self.makeNoteClip(id: clipID, activeIndexes: [1, 4])
        Self.setNoteStep(in: &sourceClip, at: 1, velocity: 32, chance: 0.25)
        Self.setNoteStep(in: &sourceClip, at: 4, velocity: 96, chance: 0.85)
        sourceClip.macroLanes[binding.id] = MacroLane(values: [nil, 0.12, nil, nil, 0.88, nil, nil, nil])

        let sourceMutator = RecordingClipMutator(clip: sourceClip)
        let sourceCoordinator = StepGridCoordinator(clipID: clipID, clipMutator: sourceMutator)
        [1, 4].forEach { sourceCoordinator.toggleSelection(at: $0) }
        sourceCoordinator.copySelectedSteps(from: sourceMutator.clip, track: track)

        var clipboard = try XCTUnwrap(sourceCoordinator.clipboard)
        clipboard.steps[99] = try XCTUnwrap(clipboard.steps[1])

        let destinationMutator = RecordingClipMutator(clip: Self.makeNoteClip(id: clipID))
        let destinationCoordinator = StepGridCoordinator(clipID: clipID, clipMutator: destinationMutator)
        destinationCoordinator.clipboard = clipboard

        let didPaste = destinationCoordinator.pasteClipboard(track: track)

        XCTAssertTrue(didPaste)
        XCTAssertEqual(destinationMutator.mutationCount, 1)
        XCTAssertEqual(destinationMutator.impacts.count, 1)
        XCTAssertEqual(Self.activeIndexes(in: destinationMutator.clip), [1, 4])
        XCTAssertEqual(Self.velocities(in: destinationMutator.clip, at: [1, 4]), [32, 96])
        XCTAssertEqual(Self.chances(in: destinationMutator.clip, at: [1, 4]), [0.25, 0.85])
        let pastedLane = try XCTUnwrap(destinationMutator.clip.macroLanes[binding.id])
        XCTAssertEqual(try XCTUnwrap(pastedLane.values[1]), 0.12, accuracy: 0.0001)
        XCTAssertEqual(try XCTUnwrap(pastedLane.values[4]), 0.88, accuracy: 0.0001)
        XCTAssertEqual(pastedLane.values.count, 8)
    }

    func test_derivedFlagsMatchSelectionAndEditableLayerState() {
        let clipID = UUID()
        let mutator = RecordingClipMutator(clip: Self.makeNoteClip(id: clipID))
        let coordinator = StepGridCoordinator(clipID: clipID, clipMutator: mutator, editableLayers: [.velocity, .chance])

        XCTAssertFalse(coordinator.isSelectionActive)
        XCTAssertFalse(coordinator.shouldShowBatchActionBar)
        XCTAssertFalse(coordinator.shouldShowRotaryRow)

        coordinator.toggleSelection(at: 0)

        XCTAssertTrue(coordinator.isSelectionActive)
        XCTAssertTrue(coordinator.shouldShowBatchActionBar)
        XCTAssertTrue(coordinator.shouldShowRotaryRow)

        coordinator.editableLayers = []

        XCTAssertTrue(coordinator.isSelectionActive)
        XCTAssertTrue(coordinator.shouldShowBatchActionBar)
        XCTAssertFalse(coordinator.shouldShowRotaryRow)
    }

    func test_rotaryControlsInitializeFromLowestSelectedStep() throws {
        let clipID = UUID()
        var clip = Self.makeNoteClip(id: clipID, activeIndexes: [1, 4])
        Self.setNoteStep(in: &clip, at: 1, velocity: 32, chance: 0.25)
        Self.setNoteStep(in: &clip, at: 4, velocity: 96, chance: 0.85)
        let mutator = RecordingClipMutator(clip: clip)
        let coordinator = StepGridCoordinator(clipID: clipID, clipMutator: mutator, editableLayers: [.velocity, .chance])
        coordinator.toggleSelection(at: 4)
        coordinator.toggleSelection(at: 1)

        let controls = coordinator.rotaryControls(in: mutator.clip)

        XCTAssertEqual(coordinator.selectedRotarySeedStepIndex, 1)
        XCTAssertEqual(controls.map(\.layer), [.velocity, .chance])
        let velocity = try XCTUnwrap(controls.first(where: { $0.layer == .velocity }))
        let chance = try XCTUnwrap(controls.first(where: { $0.layer == .chance }))
        XCTAssertEqual(velocity.normalizedValue, 32.0 / 127.0, accuracy: 0.0001)
        XCTAssertEqual(velocity.displayValue, "32")
        XCTAssertEqual(chance.normalizedValue, 0.25, accuracy: 0.0001)
        XCTAssertEqual(chance.displayValue, "25%")
    }

    func test_rotaryAbsoluteWriteUsesOneMutationForSelectedSteps() {
        let clipID = UUID()
        let mutator = RecordingClipMutator(clip: Self.makeNoteClip(id: clipID, activeIndexes: [1, 4]))
        let coordinator = StepGridCoordinator(clipID: clipID, clipMutator: mutator, editableLayers: [.velocity, .chance])
        coordinator.toggleSelection(at: 4)
        coordinator.toggleSelection(at: 1)

        guard let seedStepIndex = coordinator.selectedRotarySeedStepIndex else {
            XCTFail("Expected selected rotary seed step")
            return
        }
        coordinator.writeAbsoluteValue(0.75, stepIndex: seedStepIndex, layer: .velocity)

        XCTAssertEqual(mutator.mutationCount, 1)
        XCTAssertEqual(Self.velocities(in: mutator.clip, at: [1, 4]), [95, 95])
    }

    func test_rotaryControlsAreEmptyWithoutSelectionOrEditableLayers() {
        let clipID = UUID()
        let mutator = RecordingClipMutator(clip: Self.makeNoteClip(id: clipID))
        let coordinator = StepGridCoordinator(clipID: clipID, clipMutator: mutator, editableLayers: [])

        XCTAssertEqual(coordinator.rotaryControls(in: mutator.clip), [])

        coordinator.toggleSelection(at: 0)

        XCTAssertFalse(coordinator.shouldShowRotaryRow)
        XCTAssertEqual(coordinator.rotaryControls(in: mutator.clip), [])
    }

    func test_triggerLayerRotaryControlsPreferVelocityAndChance() {
        let clipID = UUID()
        let binding = Self.makeBinding(kind: .sampleStart)
        let track = Self.makeTrack(macros: [binding])
        let mutator = RecordingClipMutator(clip: Self.makeNoteClip(id: clipID, activeIndexes: [0]))
        let coordinator = StepGridCoordinator(
            clipID: clipID,
            clipMutator: mutator,
            activeLayer: .trigger,
            editableLayers: [.velocity, .macro(index: 0), .chance]
        )
        coordinator.toggleSelection(at: 0)

        XCTAssertEqual(coordinator.rotaryControls(in: mutator.clip, track: track).map(\.layer), [.velocity, .chance])

        coordinator.updateEditableLayers([.macro(index: 0)])

        XCTAssertEqual(coordinator.rotaryControls(in: mutator.clip, track: track).map(\.layer), [.macro(index: 0)])
    }

    func test_stepCellContentConvertsSupportedLayers() {
        let clipID = UUID()
        let binding = Self.makeBinding(kind: .sampleStart)
        let track = Self.makeTrack(macros: [binding])
        var clip = Self.makeNoteClip(id: clipID, activeIndexes: [0])
        clip.macroLanes[binding.id] = MacroLane(values: [0.5, nil, nil, nil, nil, nil, nil, nil])
        let mutator = RecordingClipMutator(clip: clip)
        let coordinator = StepGridCoordinator(clipID: clipID, clipMutator: mutator)

        XCTAssertEqual(coordinator.cellContent(for: 0, in: mutator.clip, layer: .trigger), .toggle)
        XCTAssertEqual(coordinator.cellContent(for: 0, in: mutator.clip, layer: .velocity), .valueBar(fraction: 100.0 / 127.0))
        XCTAssertEqual(coordinator.cellContent(for: 0, in: mutator.clip, layer: .chance), .valueBar(fraction: 0.5))
        XCTAssertEqual(coordinator.cellContent(for: 0, in: mutator.clip, layer: .macro(index: 0), track: track), .valueBar(fraction: 0.5))
        XCTAssertEqual(coordinator.cellContent(for: 1, in: mutator.clip, layer: .chord), .chordLabel(name: "\u{2014}"))
    }

    func test_chordGeneratorTriggerLayerReturnsPitchClassChordLabel() {
        let clipID = UUID()
        var clip = Self.makeNoteClip(id: clipID, activeIndexes: [0], trackType: .polyMelodic)
        Self.setNoteStep(in: &clip, at: 0, velocity: 96, chance: 0.8, pitch: 66)
        let mutator = RecordingClipMutator(clip: clip)
        let coordinator = StepGridCoordinator(clipID: clipID, clipMutator: mutator)

        let content = coordinator.cellContent(for: 0, in: mutator.clip, layer: .trigger)

        XCTAssertEqual(content, .chordLabel(name: "F#"))
        guard case let .chordLabel(name) = content else {
            XCTFail("Expected chord label content")
            return
        }
        XCTAssertFalse(name.isEmpty)
    }

    func test_chordGeneratorTriggerLayerUsesDefaultLabelForEmptyNoteGridStep() {
        let clipID = UUID()
        let mutator = RecordingClipMutator(clip: Self.makeNoteClip(id: clipID, trackType: .polyMelodic))
        let coordinator = StepGridCoordinator(clipID: clipID, clipMutator: mutator)

        XCTAssertEqual(coordinator.cellContent(for: 0, in: mutator.clip, layer: .trigger), .chordLabel(name: "\u{2014}"))
    }

    func test_slicerStepCellContentConvertsSupportedLayers() {
        let clipID = UUID()
        let parameters = SliceTriggerStepParameters(gain: -6)
        let mutator = RecordingClipMutator(
            clip: Self.makeSliceClip(
                id: clipID,
                stepPattern: [true, false, true, false],
                sliceIndexes: [2, 0, 5, 1],
                stepModes: [.runFromHere, .single, .single, .runFromHere],
                stepParameters: [parameters, .default, .default, .default]
            )
        )
        let coordinator = StepGridCoordinator(clipID: clipID, clipMutator: mutator)

        XCTAssertEqual(coordinator.cellContent(for: 0, in: mutator.clip, layer: .trigger), .sliceLabel(index: 2, label: "S3"))
        XCTAssertEqual(coordinator.cellContent(for: 0, in: mutator.clip, layer: .sliceIndex), .sliceLabel(index: 2, label: "S3"))
        XCTAssertEqual(coordinator.cellContent(for: 0, in: mutator.clip, layer: .sliceMode), .optionLabel(text: "Run"))
        XCTAssertEqual(coordinator.cellContent(for: 1, in: mutator.clip, layer: .sliceMode), .optionLabel(text: "One"))
        XCTAssertEqual(coordinator.cellContent(for: 0, in: mutator.clip, layer: .velocity), .valueBar(fraction: 0.5))
        XCTAssertEqual(coordinator.cellContent(for: 1, in: mutator.clip, layer: .velocity), .valueBar(fraction: 0))
        XCTAssertEqual(coordinator.cellContent(for: 0, in: mutator.clip, layer: .chance), .valueBar(fraction: 1))
        XCTAssertEqual(coordinator.cellContent(for: 1, in: mutator.clip, layer: .chance), .valueBar(fraction: 0))
    }

    func test_slicerVelocityLayerReturnsValueBarForClipStep() {
        let clipID = UUID()
        let parameters = SliceTriggerStepParameters(gain: 3)
        let mutator = RecordingClipMutator(
            clip: Self.makeSliceClip(
                id: clipID,
                stepPattern: [true, false, false, false],
                stepParameters: [parameters, .default, .default, .default]
            )
        )
        let coordinator = StepGridCoordinator(clipID: clipID, clipMutator: mutator, activeLayer: .velocity)

        let content = coordinator.cellContent(for: 0, in: mutator.clip)

        XCTAssertEqual(content, .valueBar(fraction: 0.75))
    }

    func test_selectedSlicerWritesUseOneMutationAndPreserveParallelArrays() {
        let clipID = UUID()
        let mutator = RecordingClipMutator(clip: Self.makeSliceClip(id: clipID))
        let coordinator = StepGridCoordinator(clipID: clipID, clipMutator: mutator)
        [1, 3].forEach { coordinator.toggleSelection(at: $0) }

        coordinator.writeAbsoluteValue(7, stepIndex: 1, layer: .sliceIndex)

        XCTAssertEqual(mutator.mutationCount, 1)
        XCTAssertEqual(Self.sliceStepPattern(in: mutator.clip), [true, false, true, false])
        XCTAssertEqual(Self.sliceIndexes(in: mutator.clip), [0, 7, 2, 7])
        XCTAssertEqual(Self.sliceStepModes(in: mutator.clip), [.single, .runFromHere, .single, .single])

        coordinator.writeAbsoluteValue(1, stepIndex: 3, layer: .sliceMode)

        XCTAssertEqual(mutator.mutationCount, 2)
        XCTAssertEqual(Self.sliceStepPattern(in: mutator.clip), [true, false, true, false])
        XCTAssertEqual(Self.sliceIndexes(in: mutator.clip), [0, 7, 2, 7])
        XCTAssertEqual(Self.sliceStepModes(in: mutator.clip), [.single, .runFromHere, .single, .runFromHere])

        coordinator.writeAbsoluteValue(0.75, stepIndex: 1, layer: .velocity)

        XCTAssertEqual(mutator.mutationCount, 3)
        XCTAssertEqual(Self.sliceStepPattern(in: mutator.clip), [true, true, true, true])
        XCTAssertEqual(Self.sliceIndexes(in: mutator.clip), [0, 7, 2, 7])
        XCTAssertEqual(Self.sliceStepModes(in: mutator.clip), [.single, .runFromHere, .single, .runFromHere])
        XCTAssertEqual(Self.sliceGains(in: mutator.clip, at: [1, 3]), [3, 3])

        coordinator.writeAbsoluteValue(0.25, stepIndex: 3, layer: .chance)

        XCTAssertEqual(mutator.mutationCount, 4)
        XCTAssertEqual(Self.sliceStepPattern(in: mutator.clip), [true, false, true, false])
        XCTAssertEqual(Self.sliceIndexes(in: mutator.clip), [0, 7, 2, 7])
        XCTAssertEqual(Self.sliceStepModes(in: mutator.clip), [.single, .runFromHere, .single, .runFromHere])
        XCTAssertEqual(Self.sliceGains(in: mutator.clip, at: [1, 3]), [3, 3])
    }

    func test_slicerCopyClearPastePreservesSliceIndexAndMode() throws {
        let clipID = UUID()
        let track = Self.makeTrack()
        let mutator = RecordingClipMutator(
            clip: Self.makeSliceClip(
                id: clipID,
                stepPattern: [true, false, true, false],
                sliceIndexes: [3, 1, 6, 2],
                stepModes: [.runFromHere, .single, .single, .runFromHere]
            )
        )
        let coordinator = StepGridCoordinator(clipID: clipID, clipMutator: mutator)
        [0, 3].forEach { coordinator.toggleSelection(at: $0) }

        coordinator.copySelectedSteps(from: mutator.clip, track: track)

        let clipboard = try XCTUnwrap(coordinator.clipboard)
        let first = try XCTUnwrap(clipboard.steps[0])
        XCTAssertTrue(first.active)
        XCTAssertEqual(first.sliceIndex, 3)
        XCTAssertEqual(first.sliceMode, 1)
        let second = try XCTUnwrap(clipboard.steps[3])
        XCTAssertFalse(second.active)
        XCTAssertEqual(second.sliceIndex, 2)
        XCTAssertEqual(second.sliceMode, 1)

        coordinator.clearSelectedSteps(track: track)

        XCTAssertEqual(mutator.mutationCount, 1)
        XCTAssertEqual(Self.sliceStepPattern(in: mutator.clip), [false, false, true, false])
        XCTAssertFalse(coordinator.isSelectionActive)

        coordinator.pasteClipboard(track: track)

        XCTAssertEqual(mutator.mutationCount, 2)
        XCTAssertEqual(Self.sliceStepPattern(in: mutator.clip), [true, false, true, false])
        XCTAssertEqual(Self.sliceIndexes(in: mutator.clip), [3, 1, 6, 2])
        XCTAssertEqual(Self.sliceStepModes(in: mutator.clip), [.runFromHere, .single, .single, .runFromHere])
    }

    func test_workspaceCoordinatorClearsSelectionButKeepsClipboardOnActiveClipChange() {
        let firstClipID = UUID()
        let secondClipID = UUID()
        let track = Self.makeTrack()
        let mutator = RecordingClipMutator(clip: Self.makeNoteClip(id: firstClipID, activeIndexes: [1]))
        let workspace = TrackStepGridWorkspaceModel()
        let coordinator = workspace.coordinator(for: firstClipID, clipMutator: mutator, editableLayers: [.velocity, .chance])
        coordinator.toggleSelection(at: 1)
        coordinator.copySelectedSteps(from: mutator.clip, track: track)

        let sameCoordinator = workspace.coordinator(for: secondClipID, clipMutator: mutator, editableLayers: [.velocity])

        XCTAssertTrue(coordinator === sameCoordinator)
        XCTAssertEqual(coordinator.selection.clipID, secondClipID)
        XCTAssertFalse(coordinator.isSelectionActive)
        XCTAssertNotNil(coordinator.clipboard)
        XCTAssertEqual(coordinator.editableLayers, [.velocity])
    }

    func test_workspaceResetDiscardsCoordinatorSelectionAndClipboard() {
        let clipID = UUID()
        let track = Self.makeTrack()
        let mutator = RecordingClipMutator(clip: Self.makeNoteClip(id: clipID, activeIndexes: [1]))
        let workspace = TrackStepGridWorkspaceModel()
        let coordinator = workspace.coordinator(for: clipID, clipMutator: mutator, editableLayers: [.velocity, .chance])
        coordinator.toggleSelection(at: 1)
        coordinator.copySelectedSteps(from: mutator.clip, track: track)

        workspace.reset()

        XCTAssertNil(workspace.coordinator)
    }

    func test_transientStepGridTypesAreNotCodable() {
        XCTAssertFalse(Self.typeConformsToCodable(StepSelectionModel.self))
        XCTAssertFalse(Self.typeConformsToCodable(StepClipboard.self))
        XCTAssertFalse(Self.typeConformsToCodable(StepClipboardEntry.self))
        XCTAssertFalse(Self.typeConformsToCodable(StepCellContent.self))
        XCTAssertFalse(Self.typeConformsToCodable(StepGridCoordinator.self))
    }

    private static func typeConformsToCodable<T>(_ type: T.Type) -> Bool {
        type is any Codable.Type
    }

    private static func makeNoteClip(
        id: UUID,
        activeIndexes: Set<Int> = [],
        trackType: TrackType = .monoMelodic
    ) -> ClipPoolEntry {
        let steps = (0..<8).map { index in
            activeIndexes.contains(index)
                ? ClipStep(
                    main: ClipLane(
                        chance: 0.5,
                        notes: [ClipStepNote(pitch: 60, velocity: 100, lengthSteps: 4)]
                    ),
                    fill: nil
                )
                : .empty
        }
        return ClipPoolEntry(
            id: id,
            name: "Test Clip",
            trackType: trackType,
            content: .noteGrid(lengthSteps: steps.count, steps: steps)
        )
    }

    private static func makeSliceClip(
        id: UUID,
        stepPattern: [Bool] = [true, false, true, false],
        sliceIndexes: [Int] = [0, 1, 2, 3],
        stepModes: [SliceTriggerStepMode] = [.single, .runFromHere, .single, .single],
        stepParameters: [SliceTriggerStepParameters] = Array(repeating: .default, count: 4)
    ) -> ClipPoolEntry {
        ClipPoolEntry(
            id: id,
            name: "Slice Clip",
            trackType: .slice,
            content: .sliceTriggers(
                stepPattern: stepPattern,
                sliceIndexes: sliceIndexes,
                stepModes: stepModes,
                stepParameters: stepParameters
            )
        )
    }

    private static func activeIndexes(in clip: ClipPoolEntry) -> [Int] {
        guard case let .noteGrid(_, steps) = clip.content.normalized else { return [] }
        return steps.enumerated().compactMap { index, step in
            step.main == nil ? nil : index
        }
    }

    private static func velocities(in clip: ClipPoolEntry, at indexes: [Int]) -> [Int] {
        guard case let .noteGrid(_, steps) = clip.content.normalized else { return [] }
        return indexes.compactMap { steps[$0].main?.notes.first?.velocity }
    }

    private static func chances(in clip: ClipPoolEntry, at indexes: [Int]) -> [Double] {
        guard case let .noteGrid(_, steps) = clip.content.normalized else { return [] }
        return indexes.compactMap { steps[$0].main?.chance }
    }

    private static func setNoteStep(
        in clip: inout ClipPoolEntry,
        at index: Int,
        velocity: Int?,
        chance: Double?,
        pitch: Int = 60
    ) {
        guard case let .noteGrid(lengthSteps, steps) = clip.content.normalized else {
            XCTFail("Expected note-grid clip")
            return
        }
        var updated = steps
        guard updated.indices.contains(index) else {
            XCTFail("Expected valid note step index")
            return
        }
        if let velocity, let chance {
            updated[index].main = ClipLane(
                chance: chance,
                notes: [ClipStepNote(pitch: pitch, velocity: velocity, lengthSteps: 4)]
            )
        } else {
            updated[index].main = nil
        }
        clip.content = .noteGrid(lengthSteps: lengthSteps, steps: updated)
    }

    private static func sliceStepPattern(in clip: ClipPoolEntry) -> [Bool] {
        guard case let .sliceTriggers(stepPattern, _, _, _) = clip.content.normalized else { return [] }
        return stepPattern
    }

    private static func sliceIndexes(in clip: ClipPoolEntry) -> [Int] {
        guard case let .sliceTriggers(_, sliceIndexes, _, _) = clip.content.normalized else { return [] }
        return sliceIndexes
    }

    private static func sliceStepModes(in clip: ClipPoolEntry) -> [SliceTriggerStepMode] {
        guard case let .sliceTriggers(_, _, stepModes, _) = clip.content.normalized else { return [] }
        return stepModes
    }

    private static func sliceGains(in clip: ClipPoolEntry, at indexes: [Int]) -> [Double] {
        guard case let .sliceTriggers(_, _, _, stepParameters) = clip.content.normalized else { return [] }
        return indexes.compactMap { stepParameters[$0].gain }
    }

    private static func makeTrack(macros: [TrackMacroBinding] = []) -> StepSequenceTrack {
        StepSequenceTrack(
            id: UUID(),
            name: "Track",
            pitches: [60],
            stepPattern: Array(repeating: false, count: 8),
            velocity: 100,
            gateLength: 4,
            macros: macros
        )
    }

    private static func makeBinding(kind: BuiltinMacroKind, slotIndex: Int = 0) -> TrackMacroBinding {
        TrackMacroBinding(
            descriptor: TrackMacroDescriptor.builtin(trackID: UUID(), kind: kind),
            slotIndex: slotIndex
        )
    }
}

@MainActor
private final class RecordingClipMutator: StepGridClipMutating {
    var clip: ClipPoolEntry
    private(set) var mutationCount = 0
    private(set) var impacts: [LiveMutationImpact] = []

    init(clip: ClipPoolEntry) {
        self.clip = clip
    }

    func mutateClip(
        id: UUID,
        impact: LiveMutationImpact,
        _ update: (inout ClipPoolEntry) -> Void
    ) -> Bool {
        XCTAssertEqual(id, clip.id)
        mutationCount += 1
        impacts.append(impact)
        update(&clip)
        return true
    }
}
