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
            case .velocity:
                setVelocityFraction(value, at: index, entry: &entry, noteLane: noteLane, defaultNote: defaultNote)
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
        }
    }

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
                chance: lane?.chance,
                macroOverrides: macroOverrides,
                sliceIndex: nil,
                sliceMode: nil
            )

        case let .sliceTriggers(stepPattern, sliceIndexes, stepModes, _):
            return StepClipboardEntry(
                active: stepPattern[safe: index] ?? false,
                velocity: nil,
                chance: nil,
                macroOverrides: macroOverrides,
                sliceIndex: sliceIndexes[safe: index],
                sliceMode: stepModes[safe: index].map { $0 == .runFromHere ? 1 : 0 }
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
        }
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
