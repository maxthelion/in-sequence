import XCTest
@testable import SequencerAI

// MARK: - Single clip-write path (abstraction audit F1/F3)
//
// Every step-grid surface commits through `StepGridCoordinator.commitEdit`
// (→ `mutateClip(id:)`) as an in-place transform of the live store entry.
// Before this seam existed, the grid surfaces replaced the whole
// `ClipContent` (and the whole `macroLanes` dict) with values built from the
// view's own copy of the steps, so a rotary write that landed between the
// view copy and the grid commit was silently overwritten (lost update).
//
// These tests pin the compositional property: edits prepared independently
// (as both surfaces do) land together, regardless of interleaving.
@MainActor
final class StepGridSingleWritePathTests: XCTestCase {
    private let defaultNote = ClipStepNote(pitch: 60, velocity: 100, lengthSteps: 4)

    /// Rotary chance write interleaved with a grid velocity commit: both
    /// edits were "prepared" against the same starting content, the rotary
    /// lands first, the grid commit lands second — and must not undo it.
    func test_interleavedRotaryAndGridWrites_bothLand() throws {
        let clipID = UUID()
        let mutator = SingleWritePathClipMutator(clip: Self.makeNoteClip(id: clipID, activeIndexes: [0, 3]))
        let coordinator = StepGridCoordinator(clipID: clipID, clipMutator: mutator)

        // Grid edit prepared first (captures only indexes + target value,
        // never a content snapshot — that is the point of the transform API).
        let gridEdit: (inout ClipPoolEntry) -> Void = { entry in
            ClipNoteGridStepEditing.applyAbsoluteValue(
                0.75,
                indexes: [0],
                layer: .velocity,
                entry: &entry,
                macroBindings: nil,
                noteLane: .main,
                defaultNote: self.defaultNote
            )
        }

        // Rotary write lands before the grid commit.
        coordinator.writeAbsoluteValue(0.8, stepIndex: 3, layer: .chance, defaultNote: defaultNote)
        coordinator.commitEdit(gridEdit)

        guard case let .noteGrid(_, steps) = mutator.clip.content.normalized else {
            return XCTFail("Expected note grid")
        }
        // Grid velocity write landed.
        XCTAssertEqual(steps[0].main?.notes.first?.velocity, Int((0.75 * 127).rounded()))
        // Rotary chance write survived the grid commit.
        XCTAssertEqual(try XCTUnwrap(steps[3].main?.chance), 0.8, accuracy: 0.000001)
        XCTAssertEqual(mutator.mutationCount, 2)
    }

    /// A rotary macro write to lane B must survive a grid macro edit to
    /// lane A. The old grid path replaced the entire `macroLanes` dict from
    /// a view snapshot, which clobbered any concurrent lane write; the
    /// transform path touches only the edited lane.
    func test_macroLaneWritesFromTwoSurfaces_doNotClobberOtherLanes() throws {
        let clipID = UUID()
        let bindingA = Self.makeBinding(kind: .sampleStart, slotIndex: 0)
        let bindingB = Self.makeBinding(kind: .sampleGain, slotIndex: 1)
        let mutator = SingleWritePathClipMutator(clip: Self.makeNoteClip(id: clipID, activeIndexes: [0]))
        let coordinator = StepGridCoordinator(clipID: clipID, clipMutator: mutator)
        let bindings = [bindingA, bindingB]

        // Grid edit for lane A prepared up front.
        let gridEdit: (inout ClipPoolEntry) -> Void = { entry in
            ClipNoteGridStepEditing.applyAbsoluteValue(
                0.25,
                indexes: [0],
                layer: .macro(index: 0),
                entry: &entry,
                macroBindings: bindings,
                noteLane: .main,
                defaultNote: self.defaultNote
            )
        }

        // Rotary writes lane B first, then the grid commit lands.
        coordinator.writeAbsoluteValue(1.0, stepIndex: 2, layer: .macro(index: 1), macroBindings: bindings)
        coordinator.commitEdit(gridEdit)

        let laneB = try XCTUnwrap(mutator.clip.macroLanes[bindingB.id], "Rotary lane-B write was lost")
        XCTAssertEqual(
            try XCTUnwrap(laneB.values[2]),
            bindingB.descriptor.maxValue,
            accuracy: 0.000001
        )
        let laneA = try XCTUnwrap(mutator.clip.macroLanes[bindingA.id])
        let expectedA = bindingA.descriptor.minValue
            + 0.25 * (bindingA.descriptor.maxValue - bindingA.descriptor.minValue)
        XCTAssertEqual(try XCTUnwrap(laneA.values[0]), expectedA, accuracy: 0.000001)
    }

    /// `commitEdit` is keyed by the coordinator's current clip; it follows
    /// `updateActiveClip` so a slot reassignment cannot write to a stale clip.
    func test_commitEdit_followsActiveClip() {
        let firstClipID = UUID()
        let secondClipID = UUID()
        let mutator = SingleWritePathClipMutator(clip: Self.makeNoteClip(id: secondClipID, activeIndexes: []))
        let coordinator = StepGridCoordinator(clipID: firstClipID, clipMutator: mutator)
        coordinator.updateActiveClip(secondClipID)

        let didMutate = coordinator.commitEdit { entry in
            ClipNoteGridStepEditing.toggleActive(at: 1, entry: &entry, noteLane: .main, defaultNote: defaultNote)
        }

        XCTAssertTrue(didMutate)
        XCTAssertEqual(mutator.requestedClipIDs, [secondClipID])
    }

    // MARK: - Fixtures

    private static func makeNoteClip(id: UUID, activeIndexes: Set<Int>) -> ClipPoolEntry {
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
            name: "Single Write Path Clip",
            trackType: .monoMelodic,
            content: .noteGrid(lengthSteps: steps.count, steps: steps)
        )
    }

    private static func makeBinding(kind: BuiltinMacroKind, slotIndex: Int) -> TrackMacroBinding {
        TrackMacroBinding(
            descriptor: TrackMacroDescriptor.builtin(trackID: UUID(), kind: kind),
            slotIndex: slotIndex
        )
    }
}

@MainActor
private final class SingleWritePathClipMutator: StepGridClipMutating {
    var clip: ClipPoolEntry
    private(set) var mutationCount = 0
    private(set) var requestedClipIDs: [UUID] = []

    init(clip: ClipPoolEntry) {
        self.clip = clip
    }

    func mutateClip(
        id: UUID,
        impact: LiveMutationImpact,
        _ update: (inout ClipPoolEntry) -> Void
    ) -> Bool {
        requestedClipIDs.append(id)
        mutationCount += 1
        update(&clip)
        return true
    }
}
