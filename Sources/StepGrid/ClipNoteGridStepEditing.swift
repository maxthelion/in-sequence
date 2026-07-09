import Foundation

/// The one step-editing implementation shared by every step-grid surface:
/// the single-track clip editor (`ClipContentPreview`), the drum kit matrix,
/// the slicer workspace, and the rotary/batch path (`StepGridCoordinator`).
/// All of them express edits through these helpers and commit through the
/// same in-place clip mutation, so the same gesture is byte-for-byte the
/// same mutation on every surface (audit 2026-06-12 F1/F2).
enum ClipNoteGridStepEditing {
    /// Velocity values cycled by tapping a cell in the velocity layer.
    static let velocityCycleValues: [Double] = [0, 24, 48, 72, 96, 127]

    /// Chance values cycled by tapping a cell in the chance layer.
    static let chanceCycleValues: [Double] = [0, 0.25, 0.5, 0.75, 1]

    /// Musical gate lengths offered by a step-cell tap. Slicer steps include
    /// an additional natural/full-slice state before this numeric cycle.
    static let lengthCycleValues: [Int] = [1, 2, 4, 8, 16]

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

    static func lengthSteps(
        at index: Int,
        in content: ClipContent,
        noteLane: StepGridNoteLane = .main
    ) -> Int? {
        switch content.normalized {
        case let .noteGrid(_, steps):
            return steps[safe: index]
                .flatMap { noteLane.lane(in: $0) }?
                .notes.first?
                .lengthSteps
        case let .sliceTriggers(_, _, _, stepParameters):
            return stepParameters[safe: index]?.lengthSteps
        case let .chordReferences(_, _, _, _, _, lengthSteps):
            return lengthSteps[safe: index]
        }
    }

    static func lengthFraction(
        at index: Int,
        in content: ClipContent,
        noteLane: StepGridNoteLane = .main
    ) -> Double {
        guard let length = lengthSteps(at: index, in: content, noteLane: noteLane) else {
            return 0
        }
        return clampedUnit(Double(length) / 16)
    }

    static func lengthDisplayValue(
        at index: Int,
        in content: ClipContent,
        noteLane: StepGridNoteLane = .main
    ) -> String {
        switch content.normalized {
        case let .noteGrid(_, steps):
            guard let step = steps[safe: index], noteLane.lane(in: step) != nil else { return "" }
        case let .sliceTriggers(stepPattern, _, _, _):
            guard stepPattern[safe: index] == true else { return "" }
        case let .chordReferences(stepPattern, _, _, _, _, _):
            guard stepPattern[safe: index] == true else { return "" }
        }
        return lengthSteps(at: index, in: content, noteLane: noteLane).map(String.init) ?? "Full"
    }

    static func nextLength(after current: Int?, allowsNatural: Bool) -> Int? {
        guard let current else { return lengthCycleValues[0] }
        guard let index = lengthCycleValues.firstIndex(of: current) else {
            return lengthCycleValues.first { $0 > current } ?? (allowsNatural ? nil : lengthCycleValues[0])
        }
        let nextIndex = index + 1
        if nextIndex < lengthCycleValues.count {
            return lengthCycleValues[nextIndex]
        }
        return allowsNatural ? nil : lengthCycleValues[0]
    }

    static func cycledValue(after value: Double, allowedValues: [Double]) -> Double {
        guard !allowedValues.isEmpty else { return value }
        let currentIndex = allowedValues.firstIndex { abs($0 - value) < 0.01 } ?? 0
        return allowedValues[(currentIndex + 1) % allowedValues.count]
    }

    /// Quantized values a macro-layer cell tap cycles through: both ends for
    /// booleans, every index for pattern indexes, and 8 divisions for scalars.
    static func macroAllowedValues(for binding: TrackMacroBinding) -> [Double] {
        let descriptor = binding.descriptor
        switch descriptor.valueType {
        case .boolean:
            return [descriptor.minValue, descriptor.maxValue]
        case .patternIndex:
            let lower = Int(descriptor.minValue.rounded(.up))
            let upper = Int(descriptor.maxValue.rounded(.down))
            guard lower <= upper else {
                return [descriptor.minValue]
            }
            return (lower...upper).map(Double.init)
        case .scalar:
            let minValue = descriptor.minValue
            let maxValue = descriptor.maxValue
            guard maxValue > minValue else {
                return [minValue]
            }
            let divisionCount = 8
            return (0...divisionCount).map { index in
                minValue + ((maxValue - minValue) * Double(index) / Double(divisionCount))
            }
        }
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
            // Clamp at the edit (spec: velocity is 0–127). The rotary path
            // always clamped; relying on a later `.normalized` pass here let
            // the two implementations diverge on out-of-range input.
            let resolvedVelocity = min(Int(velocity.rounded()), 127)
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

    static func updatingLaneLengths(
        lane: StepGridNoteLane,
        values: [Int],
        visibleIndices: [Int],
        lengthSteps: Int,
        steps: [ClipStep],
        defaultNote: ClipStepNote
    ) -> ClipContent {
        var updated = steps
        for (stepIndex, value) in zip(visibleIndices, values) where updated.indices.contains(stepIndex) {
            let resolved = min(max(value, 1), 16)
            if var existingLane = lane.lane(in: updated[stepIndex]) {
                let notes = existingLane.notes.isEmpty ? [defaultNote] : existingLane.notes
                existingLane.notes = notes.map { note in
                    var updatedNote = note
                    updatedNote.lengthSteps = resolved
                    return updatedNote
                }
                lane.setLane(existingLane, on: &updated[stepIndex])
            } else {
                var note = defaultNote
                note.lengthSteps = resolved
                lane.setLane(ClipLane(chance: 1, notes: [note]), on: &updated[stepIndex])
            }
        }
        return .noteGrid(lengthSteps: lengthSteps, steps: updated)
    }

    // MARK: - Entry-level edits (in-place ClipPoolEntry transforms)
    //
    // Layer-dispatched edits applied directly to a clip-pool entry. These are
    // the commit-side counterparts of the pure ClipContent builders above and
    // are shared by the rotary/batch coordinator and the grid surfaces.

    /// Apply a tap gesture to every affected index. Trigger taps toggle each
    /// step independently; option/value cycles compute the target from the
    /// tapped step and apply that one target to all affected steps
    /// (spec §4c: "the cycle target index is applied to all selected steps").
    static func applyTap(
        tappedIndex: Int,
        indexes: [Int],
        layer: StepGridLayer,
        entry: inout ClipPoolEntry,
        macroBindings: [TrackMacroBinding]?,
        noteLane: StepGridNoteLane,
        defaultNote: ClipStepNote,
        macroFallbackValues: [UUID: Double] = [:]
    ) {
        switch layer {
        case .trigger:
            for index in indexes {
                toggleActive(at: index, entry: &entry, noteLane: noteLane, defaultNote: defaultNote)
            }

        case .pitch:
            let current = pitchValue(at: tappedIndex, in: entry.content, noteLane: noteLane) ?? defaultNote.pitch
            let target = nextScalePitch(after: current)
            for index in indexes {
                setPitch(target, at: index, entry: &entry, noteLane: noteLane, defaultNote: defaultNote)
            }

        case .sliceIndex:
            guard case let .sliceTriggers(_, sliceIndexes, _, _) = entry.content.normalized,
                  let current = sliceIndexes[safe: tappedIndex]
            else { return }
            let target = (current + 1) % 16
            for index in indexes {
                setSliceIndex(target, at: index, entry: &entry)
            }

        case .sliceMode:
            guard case let .sliceTriggers(_, _, stepModes, _) = entry.content.normalized,
                  let current = stepModes[safe: tappedIndex]
            else { return }
            let target = current == .single ? SliceTriggerStepMode.runFromHere : .single
            for index in indexes {
                setSliceMode(target == .runFromHere ? 1 : 0, at: index, entry: &entry)
            }

        case .length:
            let current = lengthSteps(at: tappedIndex, in: entry.content, noteLane: noteLane)
            let allowsNaturalLength: Bool
            if case .sliceTriggers = entry.content.normalized {
                allowsNaturalLength = true
            } else {
                allowsNaturalLength = false
            }
            let target = nextLength(after: current, allowsNatural: allowsNaturalLength)
            for index in indexes {
                setLengthSteps(target, at: index, entry: &entry, noteLane: noteLane, defaultNote: defaultNote)
            }

        case let .macro(macroIndex):
            guard let binding = macroBindings?[safe: macroIndex] else { return }
            // Cycle through the binding's quantized allowed values, seeded
            // from the tapped step (nil → fallback → descriptor default).
            // This is the shipped grid behaviour; the coordinator's earlier
            // default↔nil toggle is gone (parity divergence 2).
            let stepCount = entry.content.stepCount
            let current = entry.macroLanes[binding.id]?.synced(stepCount: stepCount).values[safe: tappedIndex] ?? nil
            let fallback = clampedMacroValue(
                macroFallbackValues[binding.id] ?? binding.descriptor.defaultValue,
                binding: binding
            )
            let next = cycledValue(after: current ?? fallback, allowedValues: macroAllowedValues(for: binding))
            for index in indexes {
                setMacroValue(next, at: index, entry: &entry, binding: binding)
            }

        case .velocity, .chance, .chord:
            break
        }
    }

    /// Apply an absolute (0–1 normalized) value write to every affected index.
    static func applyAbsoluteValue(
        _ value: Double,
        indexes: [Int],
        layer: StepGridLayer,
        entry: inout ClipPoolEntry,
        macroBindings: [TrackMacroBinding]?,
        noteLane: StepGridNoteLane,
        defaultNote: ClipStepNote
    ) {
        for index in indexes {
            switch layer {
            case .pitch:
                setPitchFraction(value, at: index, entry: &entry, noteLane: noteLane, defaultNote: defaultNote)
            case .velocity:
                setVelocityFraction(value, at: index, entry: &entry, noteLane: noteLane, defaultNote: defaultNote)
            case .length:
                let steps = 1 + Int((clampedUnit(value) * 15).rounded())
                setLengthSteps(steps, at: index, entry: &entry, noteLane: noteLane, defaultNote: defaultNote)
            case .chance:
                setChanceFraction(value, at: index, entry: &entry, noteLane: noteLane, defaultNote: defaultNote)
            case let .macro(macroIndex):
                guard let binding = macroBindings?[safe: macroIndex] else { return }
                let resolved = binding.descriptor.minValue + (clampedUnit(value) * (binding.descriptor.maxValue - binding.descriptor.minValue))
                setMacroValue(resolved, at: index, entry: &entry, binding: binding)
            case .sliceIndex:
                setSliceIndex(Int(value.rounded()), at: index, entry: &entry)
            case .sliceMode:
                setSliceMode(Int(value.rounded()), at: index, entry: &entry)
            case .trigger, .chord:
                return
            }
        }
    }

    static func toggleActive(
        at index: Int,
        entry: inout ClipPoolEntry,
        noteLane: StepGridNoteLane,
        defaultNote: ClipStepNote
    ) {
        switch entry.content.normalized {
        case let .noteGrid(lengthSteps, steps):
            guard steps.indices.contains(index) else { return }
            entry.content = togglingStep(
                at: index,
                lengthSteps: lengthSteps,
                steps: steps,
                lane: noteLane,
                defaultNote: defaultNote
            )

        case let .sliceTriggers(stepPattern, sliceIndexes, stepModes, stepParameters):
            var updated = stepPattern
            guard updated.indices.contains(index) else { return }
            updated[index].toggle()
            entry.content = .sliceTriggers(
                stepPattern: updated,
                sliceIndexes: sliceIndexes,
                stepModes: stepModes,
                stepParameters: stepParameters
            )

        case let .chordReferences(stepPattern, slotIDs, inversions, chordIDs, velocities, lengthSteps):
            var updated = stepPattern
            guard updated.indices.contains(index) else { return }
            updated[index].toggle()
            entry.content = .chordReferences(
                stepPattern: updated,
                slotIDs: slotIDs,
                inversions: inversions,
                chordIDs: chordIDs,
                velocities: velocities,
                lengthSteps: lengthSteps
            )
        }
    }

    static func setVelocityFraction(
        _ value: Double,
        at index: Int,
        entry: inout ClipPoolEntry,
        noteLane: StepGridNoteLane,
        defaultNote: ClipStepNote
    ) {
        switch entry.content.normalized {
        case let .noteGrid(lengthSteps, steps):
            guard steps.indices.contains(index) else { return }
            entry.content = updatingLaneVelocities(
                lane: noteLane,
                values: [clampedUnit(value) * 127],
                visibleIndices: [index],
                lengthSteps: lengthSteps,
                steps: steps,
                defaultNote: defaultNote
            )

        case let .sliceTriggers(stepPattern, sliceIndexes, stepModes, stepParameters):
            var updatedPattern = stepPattern
            var updatedParameters = stepParameters
            guard updatedPattern.indices.contains(index), updatedParameters.indices.contains(index) else { return }
            let fraction = clampedUnit(value)
            updatedPattern[index] = fraction > 0
            updatedParameters[index].gain = (fraction * 36) - 24
            entry.content = .sliceTriggers(
                stepPattern: updatedPattern,
                sliceIndexes: sliceIndexes,
                stepModes: stepModes,
                stepParameters: updatedParameters
            )

        case let .chordReferences(stepPattern, slotIDs, inversions, chordIDs, velocities, lengthSteps):
            var updatedPattern = stepPattern
            var updatedVelocities = velocities
            guard updatedPattern.indices.contains(index), updatedVelocities.indices.contains(index) else { return }
            let fraction = clampedUnit(value)
            updatedPattern[index] = fraction > 0
            updatedVelocities[index] = min(max(Int((fraction * 127).rounded()), 1), 127)
            entry.content = .chordReferences(
                stepPattern: updatedPattern,
                slotIDs: slotIDs,
                inversions: inversions,
                chordIDs: chordIDs,
                velocities: updatedVelocities,
                lengthSteps: lengthSteps
            )
        }
    }

    static func setLengthSteps(
        _ lengthSteps: Int?,
        at index: Int,
        entry: inout ClipPoolEntry,
        noteLane: StepGridNoteLane,
        defaultNote: ClipStepNote
    ) {
        let resolvedLength = lengthSteps.map { min(max($0, 1), 16) }
        switch entry.content.normalized {
        case let .noteGrid(clipLength, steps):
            var updated = steps
            guard updated.indices.contains(index) else { return }
            let numericLength = resolvedLength ?? 1
            if var lane = noteLane.lane(in: updated[index]) {
                let notes = lane.notes.isEmpty ? [defaultNote] : lane.notes
                lane.notes = notes.map { note in
                    var updatedNote = note
                    updatedNote.lengthSteps = numericLength
                    return updatedNote
                }
                noteLane.setLane(lane, on: &updated[index])
            } else {
                var note = defaultNote
                note.lengthSteps = numericLength
                noteLane.setLane(ClipLane(chance: 1, notes: [note]), on: &updated[index])
            }
            entry.content = .noteGrid(lengthSteps: clipLength, steps: updated)

        case let .sliceTriggers(stepPattern, sliceIndexes, stepModes, stepParameters):
            var updatedPattern = stepPattern
            var updatedParameters = stepParameters
            guard updatedPattern.indices.contains(index), updatedParameters.indices.contains(index) else { return }
            updatedPattern[index] = true
            updatedParameters[index].lengthSteps = resolvedLength
            entry.content = .sliceTriggers(
                stepPattern: updatedPattern,
                sliceIndexes: sliceIndexes,
                stepModes: stepModes,
                stepParameters: updatedParameters
            )

        case let .chordReferences(stepPattern, slotIDs, inversions, chordIDs, velocities, lengthSteps):
            var updatedPattern = stepPattern
            var updatedLengths = lengthSteps
            guard updatedPattern.indices.contains(index), updatedLengths.indices.contains(index) else { return }
            updatedPattern[index] = true
            updatedLengths[index] = resolvedLength ?? 1
            entry.content = .chordReferences(
                stepPattern: updatedPattern,
                slotIDs: slotIDs,
                inversions: inversions,
                chordIDs: chordIDs,
                velocities: velocities,
                lengthSteps: updatedLengths
            )
        }
    }

    static func setChanceFraction(
        _ value: Double,
        at index: Int,
        entry: inout ClipPoolEntry,
        noteLane: StepGridNoteLane,
        defaultNote: ClipStepNote
    ) {
        switch entry.content.normalized {
        case let .noteGrid(lengthSteps, steps):
            guard steps.indices.contains(index) else { return }
            entry.content = updatingLaneChances(
                lane: noteLane,
                values: [clampedUnit(value)],
                visibleIndices: [index],
                lengthSteps: lengthSteps,
                steps: steps,
                defaultNote: defaultNote
            )

        case let .sliceTriggers(stepPattern, sliceIndexes, stepModes, stepParameters):
            var updatedPattern = stepPattern
            guard updatedPattern.indices.contains(index) else { return }
            updatedPattern[index] = clampedUnit(value) >= 0.5
            entry.content = .sliceTriggers(
                stepPattern: updatedPattern,
                sliceIndexes: sliceIndexes,
                stepModes: stepModes,
                stepParameters: stepParameters
            )

        case let .chordReferences(stepPattern, slotIDs, inversions, chordIDs, velocities, lengthSteps):
            var updatedPattern = stepPattern
            guard updatedPattern.indices.contains(index) else { return }
            updatedPattern[index] = clampedUnit(value) >= 0.5
            entry.content = .chordReferences(
                stepPattern: updatedPattern,
                slotIDs: slotIDs,
                inversions: inversions,
                chordIDs: chordIDs,
                velocities: velocities,
                lengthSteps: lengthSteps
            )
        }
    }

    static func setPitchFraction(
        _ value: Double,
        at index: Int,
        entry: inout ClipPoolEntry,
        noteLane: StepGridNoteLane,
        defaultNote: ClipStepNote
    ) {
        let pitch = Int((clampedUnit(value) * 127).rounded())
        setPitch(pitch, at: index, entry: &entry, noteLane: noteLane, defaultNote: defaultNote)
    }

    static func setPitch(
        _ pitch: Int,
        at index: Int,
        entry: inout ClipPoolEntry,
        noteLane: StepGridNoteLane,
        defaultNote: ClipStepNote
    ) {
        guard case let .noteGrid(lengthSteps, steps) = entry.content.normalized else { return }
        var updated = steps
        guard updated.indices.contains(index) else { return }

        let resolvedPitch = min(max(pitch, 0), 127)
        if var existingLane = noteLane.lane(in: updated[index]) {
            let notes = existingLane.notes.isEmpty ? [defaultNote] : existingLane.notes
            existingLane.notes = notes.enumerated().map { offset, note in
                var updatedNote = note
                updatedNote.pitch = min(max(resolvedPitch + offset, 0), 127)
                return updatedNote
            }
            noteLane.setLane(existingLane, on: &updated[index])
        } else {
            var note = defaultNote
            note.pitch = resolvedPitch
            noteLane.setLane(ClipLane(chance: 1, notes: [note]), on: &updated[index])
        }
        entry.content = .noteGrid(lengthSteps: lengthSteps, steps: updated)
    }

    /// Octave-band tap on a pitch cell (prototype 11): cycle the tapped
    /// step's octave in place (+1, wrapping past +2 back to -2 around the
    /// centre octave), preserving each step's pitch class. Selection-aware:
    /// every affected step lands on the same target octave.
    static func applyOctaveTap(
        tappedIndex: Int,
        indexes: [Int],
        entry: inout ClipPoolEntry,
        noteLane: StepGridNoteLane,
        defaultNote: ClipStepNote
    ) {
        let currentPitch = pitchValue(at: tappedIndex, in: entry.content, noteLane: noteLane) ?? defaultNote.pitch
        let currentOffset = (currentPitch / 12) - centerOctave
        let targetOffset = currentOffset >= 2 ? -2 : currentOffset + 1
        let targetOctave = targetOffset + centerOctave

        for index in indexes {
            let stepPitch = pitchValue(at: index, in: entry.content, noteLane: noteLane) ?? defaultNote.pitch
            let pitchClass = ((stepPitch % 12) + 12) % 12
            let shifted = min(max(targetOctave * 12 + pitchClass, 0), 127)
            setPitch(shifted, at: index, entry: &entry, noteLane: noteLane, defaultNote: defaultNote)
        }
    }

    /// MIDI octave treated as the register centre for the pitch cell's
    /// 3-dot band (octave 4 = "mid"; C4=60 in the 0-based /12 convention).
    static let centerOctave = 4

    static func setMacroValue(_ value: Double?, at index: Int, entry: inout ClipPoolEntry, binding: TrackMacroBinding) {
        let stepCount = entry.content.stepCount
        var lane = entry.macroLanes[binding.id]?.synced(stepCount: stepCount) ?? MacroLane(stepCount: stepCount)
        guard lane.values.indices.contains(index) else { return }
        lane.values[index] = value.map { clampedMacroValue($0, binding: binding) }
        entry.macroLanes[binding.id] = lane
    }

    static func setSliceIndex(_ value: Int, at index: Int, entry: inout ClipPoolEntry) {
        guard case let .sliceTriggers(stepPattern, sliceIndexes, stepModes, stepParameters) = entry.content.normalized else { return }
        var updated = sliceIndexes
        guard updated.indices.contains(index) else { return }
        updated[index] = max(0, value)
        entry.content = .sliceTriggers(
            stepPattern: stepPattern,
            sliceIndexes: updated,
            stepModes: stepModes,
            stepParameters: stepParameters
        )
    }

    static func setSliceMode(_ value: Int, at index: Int, entry: inout ClipPoolEntry) {
        guard case let .sliceTriggers(stepPattern, sliceIndexes, stepModes, stepParameters) = entry.content.normalized else { return }
        var updated = stepModes
        guard updated.indices.contains(index) else { return }
        updated[index] = value <= 0 ? .single : .runFromHere
        entry.content = .sliceTriggers(
            stepPattern: stepPattern,
            sliceIndexes: sliceIndexes,
            stepModes: updated,
            stepParameters: stepParameters
        )
    }

    static func ensureActive(at index: Int, entry: inout ClipPoolEntry, defaultNote: ClipStepNote) {
        switch entry.content.normalized {
        case let .noteGrid(lengthSteps, steps):
            var updated = steps
            guard updated.indices.contains(index) else { return }
            if updated[index].main == nil {
                updated[index].main = ClipLane(chance: 1, notes: [defaultNote])
            }
            entry.content = .noteGrid(lengthSteps: lengthSteps, steps: updated)

        case let .sliceTriggers(stepPattern, sliceIndexes, stepModes, stepParameters):
            var updated = stepPattern
            guard updated.indices.contains(index) else { return }
            updated[index] = true
            entry.content = .sliceTriggers(
                stepPattern: updated,
                sliceIndexes: sliceIndexes,
                stepModes: stepModes,
                stepParameters: stepParameters
            )

        case let .chordReferences(stepPattern, slotIDs, inversions, chordIDs, velocities, lengthSteps):
            var updated = stepPattern
            guard updated.indices.contains(index) else { return }
            updated[index] = true
            entry.content = .chordReferences(
                stepPattern: updated,
                slotIDs: slotIDs,
                inversions: inversions,
                chordIDs: chordIDs,
                velocities: velocities,
                lengthSteps: lengthSteps
            )
        }
    }

    static func clearStep(at index: Int, entry: inout ClipPoolEntry, macroBindings: [TrackMacroBinding]) {
        switch entry.content.normalized {
        case let .noteGrid(lengthSteps, steps):
            var updated = steps
            if updated.indices.contains(index) {
                updated[index].main = nil
                entry.content = .noteGrid(lengthSteps: lengthSteps, steps: updated)
            }

        case let .sliceTriggers(stepPattern, sliceIndexes, stepModes, stepParameters):
            var updated = stepPattern
            if updated.indices.contains(index) {
                updated[index] = false
                entry.content = .sliceTriggers(
                    stepPattern: updated,
                    sliceIndexes: sliceIndexes,
                    stepModes: stepModes,
                    stepParameters: stepParameters
                )
            }

        case let .chordReferences(stepPattern, slotIDs, inversions, chordIDs, velocities, lengthSteps):
            var updated = stepPattern
            if updated.indices.contains(index) {
                updated[index] = false
                entry.content = .chordReferences(
                    stepPattern: updated,
                    slotIDs: slotIDs,
                    inversions: inversions,
                    chordIDs: chordIDs,
                    velocities: velocities,
                    lengthSteps: lengthSteps
                )
            }
        }

        for binding in macroBindings {
            setMacroValue(nil, at: index, entry: &entry, binding: binding)
        }
    }

    static func clipboardEntry(
        at index: Int,
        in clip: ClipPoolEntry,
        macroBindings: [TrackMacroBinding]
    ) -> StepClipboardEntry {
        var macroOverrides: [UUID: Double?] = [:]
        for binding in macroBindings {
            let value = clip.macroLanes[binding.id]?.synced(stepCount: clip.content.stepCount).values[safe: index] ?? nil
            macroOverrides[binding.id] = .some(value)
        }

        switch clip.content.normalized {
        case let .noteGrid(_, steps):
            let lane = steps[safe: index]?.main
            return StepClipboardEntry(
                active: lane != nil,
                velocity: lane?.notes.first.map { Double($0.velocity) / 127 },
                length: lane?.notes.first.map { .steps($0.lengthSteps) },
                chance: lane?.chance,
                macroOverrides: macroOverrides,
                sliceIndex: nil,
                sliceMode: nil
            )

        case let .sliceTriggers(stepPattern, sliceIndexes, stepModes, stepParameters):
            return StepClipboardEntry(
                active: stepPattern[safe: index] ?? false,
                velocity: nil,
                length: stepParameters[safe: index]?.lengthSteps.map { .steps($0) } ?? .natural,
                chance: nil,
                macroOverrides: macroOverrides,
                sliceIndex: sliceIndexes[safe: index],
                sliceMode: stepModes[safe: index].map { $0 == .runFromHere ? 1 : 0 }
            )

        case let .chordReferences(stepPattern, _, _, _, velocities, lengthSteps):
            return StepClipboardEntry(
                active: stepPattern[safe: index] ?? false,
                velocity: velocities[safe: index].map { Double($0) / 127 },
                length: lengthSteps[safe: index].map { .steps($0) },
                chance: stepPattern[safe: index] == true ? 1 : 0,
                macroOverrides: macroOverrides,
                sliceIndex: nil,
                sliceMode: nil
            )
        }
    }

    static func paste(
        _ clipboardEntry: StepClipboardEntry,
        at index: Int,
        entry: inout ClipPoolEntry,
        macroBindings: [TrackMacroBinding],
        defaultNote: ClipStepNote
    ) {
        if clipboardEntry.active {
            ensureActive(at: index, entry: &entry, defaultNote: defaultNote)
        } else {
            clearStep(at: index, entry: &entry, macroBindings: [])
        }

        if let velocity = clipboardEntry.velocity {
            setVelocityFraction(velocity, at: index, entry: &entry, noteLane: .main, defaultNote: defaultNote)
        }
        if clipboardEntry.active, let length = clipboardEntry.length {
            switch length {
            case .natural:
                setLengthSteps(nil, at: index, entry: &entry, noteLane: .main, defaultNote: defaultNote)
            case let .steps(value):
                setLengthSteps(value, at: index, entry: &entry, noteLane: .main, defaultNote: defaultNote)
            }
        }
        if let chance = clipboardEntry.chance {
            setChanceFraction(chance, at: index, entry: &entry, noteLane: .main, defaultNote: defaultNote)
        }
        if let sliceIndex = clipboardEntry.sliceIndex {
            setSliceIndex(sliceIndex, at: index, entry: &entry)
        }
        if let sliceMode = clipboardEntry.sliceMode {
            setSliceMode(sliceMode, at: index, entry: &entry)
        }

        for binding in macroBindings {
            guard let override = clipboardEntry.macroOverrides[binding.id] else { continue }
            setMacroValue(override, at: index, entry: &entry, binding: binding)
        }
    }

    // MARK: - Layer-value reads (shared by cells and rotaries)

    static func velocityFraction(at index: Int, in content: ClipContent, noteLane: StepGridNoteLane = .main) -> Double {
        switch content.normalized {
        case let .noteGrid(_, steps):
            guard let velocity = steps[safe: index].flatMap({ noteLane.lane(in: $0) })?.notes.first?.velocity else {
                return 0
            }
            return clampedUnit(Double(velocity) / 127)

        case let .sliceTriggers(stepPattern, _, _, stepParameters):
            guard stepPattern.indices.contains(index), stepPattern[index] else {
                return 0
            }
            let gain = stepParameters[safe: index]?.gain ?? 0
            return clampedUnit((gain + 24) / 36)

        case let .chordReferences(stepPattern, _, _, _, velocities, _):
            guard stepPattern.indices.contains(index), stepPattern[index] else {
                return 0
            }
            return clampedUnit(Double(velocities[safe: index] ?? 96) / 127)
        }
    }

    static func chanceFraction(at index: Int, in content: ClipContent, noteLane: StepGridNoteLane = .main) -> Double {
        switch content.normalized {
        case let .noteGrid(_, steps):
            return clampedUnit(steps[safe: index].flatMap { noteLane.lane(in: $0) }?.chance ?? 0)

        case let .sliceTriggers(stepPattern, _, _, _):
            guard stepPattern.indices.contains(index) else {
                return 0
            }
            return stepPattern[index] ? 1 : 0

        case let .chordReferences(stepPattern, _, _, _, _, _):
            guard stepPattern.indices.contains(index) else {
                return 0
            }
            return stepPattern[index] ? 1 : 0
        }
    }

    static func pitchValue(at index: Int, in content: ClipContent, noteLane: StepGridNoteLane = .main) -> Int? {
        guard case let .noteGrid(_, steps) = content.normalized else { return nil }
        return steps[safe: index].flatMap { noteLane.lane(in: $0) }?.notes.first?.pitch
    }

    static func pitchFraction(at index: Int, in content: ClipContent, noteLane: StepGridNoteLane = .main) -> Double {
        guard let pitch = pitchValue(at: index, in: content, noteLane: noteLane) else { return 0 }
        return clampedUnit(Double(pitch) / 127)
    }

    static func pitchContent(at index: Int, in content: ClipContent, noteLane: StepGridNoteLane = .main) -> StepCellContent {
        guard let pitch = pitchValue(at: index, in: content, noteLane: noteLane) else {
            return .pitchLabel(degree: "-", octaveBand: 1, badge: nil)
        }
        return pitchContent(for: pitch)
    }

    static func pitchDisplayValue(at index: Int, in content: ClipContent, noteLane: StepGridNoteLane = .main) -> String {
        guard let pitch = pitchValue(at: index, in: content, noteLane: noteLane) else { return "-" }
        let content = pitchContent(for: pitch)
        if case let .pitchLabel(degree, _, badge) = content {
            return "\(degree)\(badge ?? "")"
        }
        return "\(pitch)"
    }

    static func pitchContent(for pitch: Int) -> StepCellContent {
        let octave = pitch / 12
        let band: Int
        if octave <= 3 {
            band = 0
        } else if octave <= 5 {
            band = 1
        } else {
            band = 2
        }
        let centerOffset = octave - 4
        let badge = abs(centerOffset) > 2 ? (centerOffset > 0 ? "+\(centerOffset)" : "\(centerOffset)") : nil
        return .pitchLabel(degree: scaleDegreeLabel(for: pitch), octaveBand: band, badge: badge)
    }

    static func chordLabel(at index: Int, in content: ClipContent, noteLane: StepGridNoteLane = .main) -> String {
        guard case let .noteGrid(_, steps) = content.normalized,
              let pitch = steps[safe: index].flatMap({ noteLane.lane(in: $0) })?.notes.first?.pitch
        else {
            return "\u{2014}"
        }
        let names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
        return names[((pitch % 12) + 12) % 12]
    }

    static func macroFraction(at index: Int, in clip: ClipPoolEntry, binding: TrackMacroBinding) -> Double {
        let fallback = binding.descriptor.defaultValue
        let value = (clip.macroLanes[binding.id]?.synced(stepCount: clip.content.stepCount).values[safe: index] ?? nil) ?? fallback
        let range = binding.descriptor.maxValue - binding.descriptor.minValue
        guard range > 0 else {
            return 0
        }
        return clampedUnit((value - binding.descriptor.minValue) / range)
    }

    static func scaleDegreeLabel(for pitch: Int) -> String {
        switch ((pitch % 12) + 12) % 12 {
        case 0: return "1"
        case 1: return "b2"
        case 2: return "2"
        case 3: return "b3"
        case 4: return "3"
        case 5: return "4"
        case 6: return "#4"
        case 7: return "5"
        case 8: return "b6"
        case 9: return "6"
        case 10: return "b7"
        default: return "7"
        }
    }

    static func nextScalePitch(after pitch: Int) -> Int {
        let majorDegrees: Set<Int> = [0, 2, 4, 5, 7, 9, 11]
        guard pitch < 127 else { return 0 }
        for candidate in (pitch + 1)...127 where majorDegrees.contains(((candidate % 12) + 12) % 12) {
            return candidate
        }
        return 0
    }

    static func clampedUnit(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    static func clampedMacroValue(_ value: Double, binding: TrackMacroBinding) -> Double {
        min(max(value, binding.descriptor.minValue), binding.descriptor.maxValue)
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
