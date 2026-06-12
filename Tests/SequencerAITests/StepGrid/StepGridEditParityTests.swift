import XCTest
@testable import SequencerAI

// MARK: - Step-grid edit-semantics parity (abstraction audit F1/F2)
//
// The note-grid step-edit semantics historically existed twice: once in
// `ClipNoteGridStepEditing` (the grid surfaces: single-track clip editor and
// drum kit matrix) and once in `StepGridCoordinator`'s private statics (the
// rotary / batch surface). These tests pin both call paths to byte-identical
// output on the same inputs, so the two surfaces cannot drift again.
//
// Divergences found while writing these tests (resolved deliberately, see
// each test's comment):
//
// 1. Velocity overshoot clamping — the coordinator clamped the incoming
//    fraction to 0...1 before mapping to 0–127, while
//    `ClipNoteGridStepEditing.updatingLaneVelocities` wrote the raw value
//    (e.g. fraction 1.5 → velocity 191) and relied on a later
//    `ClipContent.normalized` pass to clamp. Resolved: the shared
//    implementation clamps to 0...127 at the edit (spec: velocity is 0–127;
//    `UnifiedStepCell` already clamps drag fractions, so this was latent).
//
// 2. Macro-layer tap — `ClipContentPreview` cycles the tapped step through
//    the binding's quantized allowed values (boolean / patternIndex /
//    8-division scalar) with a fallback seed, while the coordinator's
//    (production-uncalled) `onTap` toggled between the descriptor default
//    and nil. Resolved: tap cycles (the shipped grid behaviour, per the
//    option-cycle rule in docs/roadmap/step-sequencer/spec.md §4c); the
//    toggle behaviour is gone.
//
// 3. Macro lane sync breadth — the grid path replaced the whole
//    `macroLanes` dict with every lane re-synced to the view's step count;
//    the coordinator syncs only the touched lane. Resolved in favour of the
//    coordinator's narrow write (other lanes are `.synced(stepCount:)` on
//    every read, so display is unaffected).
@MainActor
final class StepGridEditParityTests: XCTestCase {
    private let defaultNote = ClipStepNote(pitch: 60, velocity: 100, lengthSteps: 4)

    // MARK: - Trigger taps

    func test_triggerTap_noteGrid_matchesGridToggleTransform() {
        for activeIndexes: Set<Int> in [[], [2]] {
            let clipID = UUID()
            let mutator = ParityClipMutator(clip: Self.makeNoteClip(id: clipID, activeIndexes: activeIndexes))
            let coordinator = StepGridCoordinator(clipID: clipID, clipMutator: mutator)

            // Grid path: the transform ClipContentPreview / DrumKitMatrix commit.
            guard case let .noteGrid(lengthSteps, steps) = mutator.clip.content.normalized else {
                return XCTFail("Expected note grid")
            }
            let expected = ClipNoteGridStepEditing.togglingStep(
                at: 2,
                lengthSteps: lengthSteps,
                steps: steps,
                lane: .main,
                defaultNote: defaultNote
            )

            // Rotary/coordinator path.
            coordinator.onTap(stepIndex: 2, layer: .trigger, defaultNote: defaultNote)

            XCTAssertEqual(mutator.clip.content.normalized, expected.normalized, "active=\(activeIndexes)")
        }
    }

    func test_triggerTap_multiSelect_matchesGridLoopedToggleTransform() {
        let clipID = UUID()
        let mutator = ParityClipMutator(clip: Self.makeNoteClip(id: clipID, activeIndexes: [3]))
        let coordinator = StepGridCoordinator(clipID: clipID, clipMutator: mutator)
        [1, 3, 5].forEach { coordinator.toggleSelection(at: $0) }

        // Grid path: ClipContentPreview loops the sorted affected indexes
        // through togglingStep, each toggle seeing the previous result.
        guard case let .noteGrid(lengthSteps, steps) = mutator.clip.content.normalized else {
            return XCTFail("Expected note grid")
        }
        var expected = ClipContent.noteGrid(lengthSteps: lengthSteps, steps: steps)
        for index in [1, 3, 5] {
            guard case let .noteGrid(currentLength, currentSteps) = expected else { break }
            expected = ClipNoteGridStepEditing.togglingStep(
                at: index,
                lengthSteps: currentLength,
                steps: currentSteps,
                lane: .main,
                defaultNote: defaultNote
            )
        }

        coordinator.onTap(stepIndex: 3, layer: .trigger, defaultNote: defaultNote)

        XCTAssertEqual(mutator.mutationCount, 1)
        XCTAssertEqual(mutator.clip.content.normalized, expected.normalized)
    }

    func test_triggerTap_sliceTriggers_matchesGridPatternToggle() {
        let clipID = UUID()
        let mutator = ParityClipMutator(clip: Self.makeSliceClip(id: clipID))
        let coordinator = StepGridCoordinator(clipID: clipID, clipMutator: mutator)

        // Grid path: ClipContentPreview's slice trigger tap toggles the
        // pattern bool and keeps the parallel arrays.
        guard case let .sliceTriggers(stepPattern, sliceIndexes, stepModes, stepParameters) =
            mutator.clip.content.normalized
        else {
            return XCTFail("Expected slice triggers")
        }
        var expectedPattern = stepPattern
        expectedPattern[1].toggle()
        let expected = ClipContent.sliceTriggers(
            stepPattern: expectedPattern,
            sliceIndexes: sliceIndexes,
            stepModes: stepModes,
            stepParameters: stepParameters
        )

        coordinator.onTap(stepIndex: 1, layer: .trigger, defaultNote: defaultNote)

        XCTAssertEqual(mutator.clip.content.normalized, expected.normalized)
    }

    // MARK: - Velocity writes

    func test_velocityAbsoluteWrite_matchesGridDragTransform() {
        for fraction in [0.0, 0.25, 0.5, 1.0] {
            for activeIndexes: Set<Int> in [[2], []] {
                let clipID = UUID()
                let mutator = ParityClipMutator(clip: Self.makeNoteClip(id: clipID, activeIndexes: activeIndexes))
                let coordinator = StepGridCoordinator(clipID: clipID, clipMutator: mutator)

                guard case let .noteGrid(lengthSteps, steps) = mutator.clip.content.normalized else {
                    return XCTFail("Expected note grid")
                }
                let expected = ClipNoteGridStepEditing.updatingLaneVelocities(
                    lane: .main,
                    values: [fraction * 127.0],
                    visibleIndices: [2],
                    lengthSteps: lengthSteps,
                    steps: steps,
                    defaultNote: defaultNote
                )

                coordinator.writeAbsoluteValue(fraction, stepIndex: 2, layer: .velocity, defaultNote: defaultNote)

                XCTAssertEqual(
                    mutator.clip.content.normalized,
                    expected.normalized,
                    "fraction=\(fraction) active=\(activeIndexes)"
                )
            }
        }
    }

    /// Divergence 1 (see header): both paths must clamp velocity to 127 at
    /// the edit itself, byte-identically, without relying on a later
    /// normalization pass.
    func test_velocityAbsoluteWrite_overshootClampsIdenticallyInBothPaths() {
        let clipID = UUID()
        let mutator = ParityClipMutator(clip: Self.makeNoteClip(id: clipID, activeIndexes: [2]))
        let coordinator = StepGridCoordinator(clipID: clipID, clipMutator: mutator)

        guard case let .noteGrid(lengthSteps, steps) = mutator.clip.content.normalized else {
            return XCTFail("Expected note grid")
        }
        let gridResult = ClipNoteGridStepEditing.updatingLaneVelocities(
            lane: .main,
            values: [1.5 * 127.0],
            visibleIndices: [2],
            lengthSteps: lengthSteps,
            steps: steps,
            defaultNote: defaultNote
        )

        coordinator.writeAbsoluteValue(1.5, stepIndex: 2, layer: .velocity, defaultNote: defaultNote)

        // Raw (pre-normalization) parity: both must already hold 127.
        XCTAssertEqual(mutator.clip.content, gridResult)
        guard case let .noteGrid(_, resultSteps) = gridResult else {
            return XCTFail("Expected note grid")
        }
        XCTAssertEqual(resultSteps[2].main?.notes.first?.velocity, 127)
    }

    func test_velocityTapCycle_gridCycleMatchesRotaryAbsoluteWrite() {
        // The grid's tap cycle writes the cycled 0–127 value through
        // updatingLaneVelocities; the rotary writes the equivalent fraction.
        // Same gesture class on two surfaces — must land identical bytes.
        for startActive in [true, false] {
            let clipID = UUID()
            let activeIndexes: Set<Int> = startActive ? [2] : []
            let gridMutator = ParityClipMutator(clip: Self.makeNoteClip(id: clipID, activeIndexes: activeIndexes))
            let rotaryMutator = ParityClipMutator(clip: Self.makeNoteClip(id: clipID, activeIndexes: activeIndexes))
            let coordinator = StepGridCoordinator(clipID: clipID, clipMutator: rotaryMutator)

            guard case let .noteGrid(lengthSteps, steps) = gridMutator.clip.content.normalized else {
                return XCTFail("Expected note grid")
            }
            let nextValue = ClipNoteGridStepEditing.cycledValue(
                after: ClipNoteGridStepEditing.velocityValue(for: steps[2], lane: .main),
                allowedValues: ClipNoteGridStepEditing.velocityCycleValues
            )
            gridMutator.clip.content = ClipNoteGridStepEditing.updatingLaneVelocities(
                lane: .main,
                values: [nextValue],
                visibleIndices: [2],
                lengthSteps: lengthSteps,
                steps: steps,
                defaultNote: defaultNote
            )

            coordinator.writeAbsoluteValue(nextValue / 127.0, stepIndex: 2, layer: .velocity, defaultNote: defaultNote)

            XCTAssertEqual(
                rotaryMutator.clip.content.normalized,
                gridMutator.clip.content.normalized,
                "startActive=\(startActive)"
            )
        }
    }

    // MARK: - Chance writes

    func test_chanceAbsoluteWrite_matchesGridDragTransform() {
        for fraction in [0.0, 0.3, 1.0] {
            for activeIndexes: Set<Int> in [[2], []] {
                let clipID = UUID()
                let mutator = ParityClipMutator(clip: Self.makeNoteClip(id: clipID, activeIndexes: activeIndexes))
                let coordinator = StepGridCoordinator(clipID: clipID, clipMutator: mutator)

                guard case let .noteGrid(lengthSteps, steps) = mutator.clip.content.normalized else {
                    return XCTFail("Expected note grid")
                }
                let expected = ClipNoteGridStepEditing.updatingLaneChances(
                    lane: .main,
                    values: [fraction],
                    visibleIndices: [2],
                    lengthSteps: lengthSteps,
                    steps: steps,
                    defaultNote: defaultNote
                )

                coordinator.writeAbsoluteValue(fraction, stepIndex: 2, layer: .chance, defaultNote: defaultNote)

                XCTAssertEqual(
                    mutator.clip.content.normalized,
                    expected.normalized,
                    "fraction=\(fraction) active=\(activeIndexes)"
                )
            }
        }
    }

    func test_chanceTapCycle_gridCycleMatchesRotaryAbsoluteWrite() {
        let clipID = UUID()
        let gridMutator = ParityClipMutator(clip: Self.makeNoteClip(id: clipID, activeIndexes: [2]))
        let rotaryMutator = ParityClipMutator(clip: Self.makeNoteClip(id: clipID, activeIndexes: [2]))
        let coordinator = StepGridCoordinator(clipID: clipID, clipMutator: rotaryMutator)

        guard case let .noteGrid(lengthSteps, steps) = gridMutator.clip.content.normalized else {
            return XCTFail("Expected note grid")
        }
        let nextValue = ClipNoteGridStepEditing.cycledValue(
            after: ClipNoteGridStepEditing.chanceValue(for: steps[2], lane: .main),
            allowedValues: ClipNoteGridStepEditing.chanceCycleValues
        )
        gridMutator.clip.content = ClipNoteGridStepEditing.updatingLaneChances(
            lane: .main,
            values: [nextValue],
            visibleIndices: [2],
            lengthSteps: lengthSteps,
            steps: steps,
            defaultNote: defaultNote
        )

        coordinator.writeAbsoluteValue(nextValue, stepIndex: 2, layer: .chance, defaultNote: defaultNote)

        XCTAssertEqual(rotaryMutator.clip.content.normalized, gridMutator.clip.content.normalized)
    }

    // MARK: - Multi-select application

    func test_multiSelectVelocityWrite_matchesGridBatchDragTransform() {
        let clipID = UUID()
        let gridMutator = ParityClipMutator(clip: Self.makeNoteClip(id: clipID, activeIndexes: [0, 5]))
        let rotaryMutator = ParityClipMutator(clip: Self.makeNoteClip(id: clipID, activeIndexes: [0, 5]))
        let coordinator = StepGridCoordinator(clipID: clipID, clipMutator: rotaryMutator)
        [0, 2, 5].forEach { coordinator.toggleSelection(at: $0) }

        // Grid path: one updatingLaneVelocities call over the sorted
        // affected indexes (ClipContentPreview's selection batch contract).
        guard case let .noteGrid(lengthSteps, steps) = gridMutator.clip.content.normalized else {
            return XCTFail("Expected note grid")
        }
        gridMutator.clip.content = ClipNoteGridStepEditing.updatingLaneVelocities(
            lane: .main,
            values: Array(repeating: 0.75 * 127.0, count: 3),
            visibleIndices: [0, 2, 5],
            lengthSteps: lengthSteps,
            steps: steps,
            defaultNote: defaultNote
        )

        coordinator.writeAbsoluteValue(0.75, stepIndex: 2, layer: .velocity, defaultNote: defaultNote)

        XCTAssertEqual(rotaryMutator.mutationCount, 1)
        XCTAssertEqual(rotaryMutator.clip.content.normalized, gridMutator.clip.content.normalized)
    }

    // MARK: - Macro writes

    func test_macroAbsoluteWrite_targetLaneMatchesGridFractionTransform() throws {
        let clipID = UUID()
        let binding = Self.makeBinding(kind: .sampleStart)
        let mutator = ParityClipMutator(clip: Self.makeNoteClip(id: clipID, activeIndexes: [1]))
        let coordinator = StepGridCoordinator(clipID: clipID, clipMutator: mutator)

        // Grid path semantics (ClipContentPreview.updateMacroLaneFraction):
        // resolve the fraction against the descriptor range, clamp, store by
        // binding ID at the step index.
        let fraction = 0.42
        let range = binding.descriptor.maxValue - binding.descriptor.minValue
        let resolved = binding.descriptor.minValue + (min(max(fraction, 0), 1) * range)
        let expectedValue = min(max(resolved, binding.descriptor.minValue), binding.descriptor.maxValue)

        coordinator.writeAbsoluteValue(fraction, stepIndex: 1, layer: .macro(index: 0), macroBindings: [binding])

        let lane = try XCTUnwrap(mutator.clip.macroLanes[binding.id])
        XCTAssertEqual(lane.values.count, mutator.clip.content.stepCount)
        XCTAssertEqual(try XCTUnwrap(lane.values[1]), expectedValue, accuracy: 0.000001)
        XCTAssertNil(lane.values[0] ?? nil)
    }

    /// Divergence 2 (see header): a macro-layer tap must cycle the tapped
    /// step through the binding's quantized allowed values — the shipped
    /// grid behaviour — on both paths. The coordinator's old default↔nil
    /// toggle is gone.
    func test_macroTapCycle_matchesGridQuantizedCycle() throws {
        let clipID = UUID()
        let binding = Self.makeBinding(kind: .sampleStart)
        let track = Self.makeTrack(macros: [binding])
        let mutator = ParityClipMutator(clip: Self.makeNoteClip(id: clipID, activeIndexes: [1]))
        let coordinator = StepGridCoordinator(clipID: clipID, clipMutator: mutator)

        // Grid path semantics (ClipContentPreview.cycleMacroLaneValue):
        // current value (nil → descriptor default fallback) advanced through
        // the quantized allowed values.
        let allowed = ClipNoteGridStepEditing.macroAllowedValues(for: binding)
        let expectedFirst = ClipNoteGridStepEditing.cycledValue(
            after: binding.descriptor.defaultValue,
            allowedValues: allowed
        )

        coordinator.onTap(stepIndex: 1, layer: .macro(index: 0), track: track)
        let firstLane = try XCTUnwrap(mutator.clip.macroLanes[binding.id])
        XCTAssertEqual(try XCTUnwrap(firstLane.values[1]), expectedFirst, accuracy: 0.000001)

        // Second tap advances from the stored value, not the fallback.
        let expectedSecond = ClipNoteGridStepEditing.cycledValue(after: expectedFirst, allowedValues: allowed)
        coordinator.onTap(stepIndex: 1, layer: .macro(index: 0), track: track)
        let secondLane = try XCTUnwrap(mutator.clip.macroLanes[binding.id])
        XCTAssertEqual(try XCTUnwrap(secondLane.values[1]), expectedSecond, accuracy: 0.000001)
    }

    // MARK: - Slice option layers

    func test_sliceModeAbsoluteWrite_matchesGridRunModeToggleSemantics() {
        let clipID = UUID()
        let mutator = ParityClipMutator(clip: Self.makeSliceClip(id: clipID))
        let coordinator = StepGridCoordinator(clipID: clipID, clipMutator: mutator)

        // Grid path semantics (ClipContentPreview.sliceStepModeEditor): the
        // run-mode button flips single ↔ runFromHere at the index.
        guard case let .sliceTriggers(stepPattern, sliceIndexes, stepModes, stepParameters) =
            mutator.clip.content.normalized
        else {
            return XCTFail("Expected slice triggers")
        }
        var expectedModes = stepModes
        expectedModes[0] = expectedModes[0] == .single ? .runFromHere : .single
        let expected = ClipContent.sliceTriggers(
            stepPattern: stepPattern,
            sliceIndexes: sliceIndexes,
            stepModes: expectedModes,
            stepParameters: stepParameters
        )

        coordinator.onTap(stepIndex: 0, layer: .sliceMode)

        XCTAssertEqual(mutator.clip.content.normalized, expected.normalized)
    }

    // MARK: - Fixtures

    private static func makeNoteClip(id: UUID, activeIndexes: Set<Int> = []) -> ClipPoolEntry {
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
            name: "Parity Clip",
            trackType: .monoMelodic,
            content: .noteGrid(lengthSteps: steps.count, steps: steps)
        )
    }

    private static func makeSliceClip(id: UUID) -> ClipPoolEntry {
        ClipPoolEntry(
            id: id,
            name: "Parity Slice Clip",
            trackType: .slice,
            content: .sliceTriggers(
                stepPattern: [true, false, true, false],
                sliceIndexes: [0, 1, 2, 3],
                stepModes: [.single, .runFromHere, .single, .single],
                stepParameters: Array(repeating: .default, count: 4)
            )
        )
    }

    private static func makeTrack(macros: [TrackMacroBinding]) -> StepSequenceTrack {
        StepSequenceTrack(
            id: UUID(),
            name: "Parity Track",
            pitches: [60],
            stepPattern: Array(repeating: false, count: 8),
            velocity: 100,
            gateLength: 4,
            macros: macros
        )
    }

    private static func makeBinding(kind: BuiltinMacroKind) -> TrackMacroBinding {
        TrackMacroBinding(
            descriptor: TrackMacroDescriptor.builtin(trackID: UUID(), kind: kind),
            slotIndex: 0
        )
    }
}

@MainActor
private final class ParityClipMutator: StepGridClipMutating {
    var clip: ClipPoolEntry
    private(set) var mutationCount = 0

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
        update(&clip)
        return true
    }
}
