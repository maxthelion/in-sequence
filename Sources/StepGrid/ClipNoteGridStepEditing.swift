import Foundation

/// The one note-grid step-editing implementation shared by every step-grid
/// surface: the single-track clip editor (`ClipContentPreview`) and the drum
/// kit matrix. Both build new `ClipContent` values through these helpers and
/// commit through the same typed session mutation
/// (`SequencerDocumentSession.ensureClipAndMutate`), so a matrix edit is
/// byte-for-byte the same mutation as a single-track edit.
enum ClipNoteGridStepEditing {
    /// Velocity values cycled by tapping a cell in the velocity layer.
    static let velocityCycleValues: [Double] = [0, 24, 48, 72, 96, 127]

    /// Chance values cycled by tapping a cell in the chance layer.
    static let chanceCycleValues: [Double] = [0, 0.25, 0.5, 0.75, 1]

    // MARK: - Reads

    static func visualState(
        for step: ClipStep,
        lane: StepGridNoteLane,
        activeState: StepVisualState = .on
    ) -> StepVisualState {
        lane.lane(in: step) == nil ? .off : activeState
    }

    /// Velocity of the first note in the lane (0–127); 0 when the lane is off.
    static func velocityValue(for step: ClipStep, lane: StepGridNoteLane) -> Double {
        Double(lane.lane(in: step)?.notes.first?.velocity ?? 0)
    }

    /// Lane chance (0–1); 0 when the lane is off.
    static func chanceValue(for step: ClipStep, lane: StepGridNoteLane) -> Double {
        lane.lane(in: step)?.chance ?? 0
    }

    static func cycledValue(after value: Double, allowedValues: [Double]) -> Double {
        guard !allowedValues.isEmpty else { return value }
        let currentIndex = allowedValues.firstIndex { abs($0 - value) < 0.01 } ?? 0
        return allowedValues[(currentIndex + 1) % allowedValues.count]
    }

    // MARK: - Edits (pure ClipContent transforms)

    static func togglingStep(
        at index: Int,
        lengthSteps: Int,
        steps: [ClipStep],
        lane: StepGridNoteLane,
        defaultNote: ClipStepNote
    ) -> ClipContent {
        var updated = steps
        guard updated.indices.contains(index) else {
            return .noteGrid(lengthSteps: lengthSteps, steps: steps)
        }

        if lane.lane(in: updated[index]) == nil {
            lane.setLane(ClipLane(chance: 1, notes: [defaultNote]), on: &updated[index])
        } else {
            lane.setLane(nil, on: &updated[index])
        }

        return .noteGrid(lengthSteps: lengthSteps, steps: updated)
    }

    static func updatingLaneVelocities(
        lane: StepGridNoteLane,
        values: [Double],
        visibleIndices: [Int],
        lengthSteps: Int,
        steps: [ClipStep],
        defaultNote: ClipStepNote
    ) -> ClipContent {
        var updated = steps
        for (stepIndex, velocity) in zip(visibleIndices, values) where updated.indices.contains(stepIndex) {
            let resolvedVelocity = Int(velocity.rounded())
            guard resolvedVelocity > 0 else {
                lane.setLane(nil, on: &updated[stepIndex])
                continue
            }

            if var existingLane = lane.lane(in: updated[stepIndex]) {
                let notes = existingLane.notes.isEmpty ? [defaultNote] : existingLane.notes
                existingLane.notes = notes.map { note in
                    var updatedNote = note
                    updatedNote.velocity = resolvedVelocity
                    return updatedNote
                }
                lane.setLane(existingLane, on: &updated[stepIndex])
            } else {
                var note = defaultNote
                note.velocity = resolvedVelocity
                lane.setLane(ClipLane(chance: 1, notes: [note]), on: &updated[stepIndex])
            }
        }
        return .noteGrid(lengthSteps: lengthSteps, steps: updated)
    }

    static func updatingLaneChances(
        lane: StepGridNoteLane,
        values: [Double],
        visibleIndices: [Int],
        lengthSteps: Int,
        steps: [ClipStep],
        defaultNote: ClipStepNote
    ) -> ClipContent {
        var updated = steps
        for (stepIndex, chance) in zip(visibleIndices, values) where updated.indices.contains(stepIndex) {
            if var existingLane = lane.lane(in: updated[stepIndex]) {
                existingLane.chance = min(max(chance, 0), 1)
                lane.setLane(existingLane, on: &updated[stepIndex])
            } else if chance > 0 {
                lane.setLane(ClipLane(chance: min(max(chance, 0), 1), notes: [defaultNote]), on: &updated[stepIndex])
            }
        }
        return .noteGrid(lengthSteps: lengthSteps, steps: updated)
    }
}
