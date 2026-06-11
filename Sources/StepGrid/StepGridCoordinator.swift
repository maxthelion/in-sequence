import Foundation
import Observation

enum StepGridLayer: Equatable, Sendable {
    case trigger
    case velocity
    case chance
    case macro(index: Int)
    case sliceIndex
    case sliceMode
    case chord

    var isEditableValueLayer: Bool {
        switch self {
        case .velocity, .chance, .macro, .sliceIndex, .sliceMode, .chord:
            return true
        case .trigger:
            return false
        }
    }
}

struct StepGridRotaryControl: Equatable, Identifiable, Sendable {
    let layer: StepGridLayer
    let title: String
    let normalizedValue: Double
    let displayValue: String

    var id: String {
        switch layer {
        case .trigger:
            return "trigger"
        case .velocity:
            return "velocity"
        case .chance:
            return "chance"
        case let .macro(index):
            return "macro-\(index)"
        case .sliceIndex:
            return "slice-index"
        case .sliceMode:
            return "slice-mode"
        case .chord:
            return "chord"
        }
    }
}

enum StepGridNoteLane: Equatable, Sendable {
    case main
    case fill

    func lane(in step: ClipStep) -> ClipLane? {
        switch self {
        case .main:
            return step.main
        case .fill:
            return step.fill
        }
    }

    func setLane(_ lane: ClipLane?, on step: inout ClipStep) {
        switch self {
        case .main:
            step.main = lane
        case .fill:
            step.fill = lane
        }
    }
}

@MainActor
protocol StepGridClipMutating: AnyObject {
    @discardableResult
    func mutateClip(id: UUID, impact: LiveMutationImpact, _ update: (inout ClipPoolEntry) -> Void) -> Bool
}

extension SequencerDocumentSession: StepGridClipMutating {}

@MainActor
@Observable
final class StepGridCoordinator {
    var selection: StepSelectionModel
    var clipboard: StepClipboard?
    var activeLayer: StepGridLayer
    var editableLayers: [StepGridLayer]

    @ObservationIgnored
    private let clipMutator: any StepGridClipMutating

    init(
        clipID: ClipID,
        clipMutator: any StepGridClipMutating,
        activeLayer: StepGridLayer = .trigger,
        editableLayers: [StepGridLayer] = [.velocity, .chance]
    ) {
        selection = StepSelectionModel(clipID: clipID)
        self.clipMutator = clipMutator
        self.activeLayer = activeLayer
        self.editableLayers = editableLayers
    }

    var isSelectionActive: Bool {
        !selection.selectedStepIndexes.isEmpty
    }

    var shouldShowBatchActionBar: Bool {
        isSelectionActive
    }

    var shouldShowRotaryRow: Bool {
        isSelectionActive && editableLayers.contains(where: \.isEditableValueLayer)
    }

    var selectedRotarySeedStepIndex: Int? {
        selection.selectedStepIndexes.min()
    }

    var rotaryEditableLayers: [StepGridLayer] {
        let editableValueLayers = editableLayers.filter(\.isEditableValueLayer)
        guard activeLayer == .trigger else {
            return editableValueLayers
        }

        let triggerLayerRotaries = editableValueLayers.filter { layer in
            layer == .velocity || layer == .chance
        }
        return triggerLayerRotaries.isEmpty ? editableValueLayers : triggerLayerRotaries
    }

    func updateActiveClip(_ clipID: ClipID) {
        selection.updateActiveClip(clipID)
    }

    func updateActiveLayer(_ layer: StepGridLayer) {
        activeLayer = layer
    }

    func updateEditableLayers(_ layers: [StepGridLayer]) {
        editableLayers = layers
    }

    func clearSelection() {
        selection.clear()
    }

    func toggleSelection(at stepIndex: Int) {
        selection.toggleStep(stepIndex)
    }

    func isStepSelected(_ stepIndex: Int) -> Bool {
        selection.selectedStepIndexes.contains(stepIndex)
    }

    func rotaryControls(
        in clip: ClipPoolEntry,
        track: StepSequenceTrack? = nil,
        macroBindings: [TrackMacroBinding]? = nil,
        noteLane: StepGridNoteLane = .main
    ) -> [StepGridRotaryControl] {
        guard let seedStepIndex = selectedRotarySeedStepIndex else {
            return []
        }

        return rotaryEditableLayers.map { layer in
            Self.rotaryControl(
                for: layer,
                seedStepIndex: seedStepIndex,
                clip: clip,
                macroBindings: macroBindings ?? track?.macros,
                noteLane: noteLane
            )
        }
    }

    func cellContent(
        for stepIndex: Int,
        in clip: ClipPoolEntry,
        layer: StepGridLayer? = nil,
        track: StepSequenceTrack? = nil,
        macroBindings: [TrackMacroBinding]? = nil,
        noteLane: StepGridNoteLane = .main
    ) -> StepCellContent {
        Self.cellContent(
            for: stepIndex,
            in: clip,
            layer: layer ?? activeLayer,
            track: track,
            macroBindings: macroBindings,
            noteLane: noteLane
        )
    }

    static func cellContent(
        for stepIndex: Int,
        in clip: ClipPoolEntry,
        layer: StepGridLayer,
        track: StepSequenceTrack? = nil,
        macroBindings: [TrackMacroBinding]? = nil,
        noteLane: StepGridNoteLane = .main
    ) -> StepCellContent {
        switch layer {
        case .trigger:
            if clip.trackType == .polyMelodic {
                return .chordLabel(name: Self.chordLabel(at: stepIndex, in: clip.content, noteLane: noteLane))
            }
            if case let .sliceTriggers(_, sliceIndexes, _, _) = clip.content.normalized,
               let sliceIndex = sliceIndexes[safe: stepIndex] {
                return .sliceLabel(index: sliceIndex, label: "S\(sliceIndex + 1)")
            }
            return .toggle

        case .velocity:
            return .valueBar(fraction: Self.velocityFraction(at: stepIndex, in: clip.content, noteLane: noteLane))

        case .chance:
            return .valueBar(fraction: Self.chanceFraction(at: stepIndex, in: clip.content, noteLane: noteLane))

        case let .macro(index):
            guard let binding = (macroBindings ?? track?.macros)?[safe: index] else {
                return .valueBar(fraction: 0)
            }
            return .valueBar(fraction: Self.macroFraction(at: stepIndex, in: clip, binding: binding))

        case .sliceIndex:
            guard case let .sliceTriggers(_, sliceIndexes, _, _) = clip.content.normalized,
                  let sliceIndex = sliceIndexes[safe: stepIndex]
            else {
                return .optionLabel(text: "-")
            }
            return .sliceLabel(index: sliceIndex, label: "S\(sliceIndex + 1)")

        case .sliceMode:
            guard case let .sliceTriggers(_, _, stepModes, _) = clip.content.normalized,
                  let stepMode = stepModes[safe: stepIndex]
            else {
                return .optionLabel(text: "One")
            }
            return .optionLabel(text: stepMode == .runFromHere ? "Run" : "One")

        case .chord:
            return .chordLabel(name: Self.chordLabel(at: stepIndex, in: clip.content, noteLane: noteLane))
        }
    }

    @discardableResult
    func onTap(
        stepIndex: Int,
        layer: StepGridLayer? = nil,
        track: StepSequenceTrack? = nil,
        noteLane: StepGridNoteLane = .main,
        defaultNote: ClipStepNote = ClipStepNote(pitch: 60, velocity: 100, lengthSteps: 4)
    ) -> Bool {
        let clipID = selection.clipID
        let indexes = affectedIndexes(for: stepIndex)
        let resolvedLayer = layer ?? activeLayer
        let resolvedTrack = track
        let normalizedDefaultNote = defaultNote.normalized

        return clipMutator.mutateClip(id: clipID, impact: .snapshotOnly) { entry in
            for index in indexes {
                Self.applyTap(
                    at: index,
                    layer: resolvedLayer,
                    entry: &entry,
                    track: resolvedTrack,
                    noteLane: noteLane,
                    defaultNote: normalizedDefaultNote
                )
            }
        }
    }

    @discardableResult
    func writeAbsoluteValue(
        _ value: Double,
        stepIndex: Int,
        layer: StepGridLayer? = nil,
        track: StepSequenceTrack? = nil,
        macroBindings: [TrackMacroBinding]? = nil,
        noteLane: StepGridNoteLane = .main,
        defaultNote: ClipStepNote = ClipStepNote(pitch: 60, velocity: 100, lengthSteps: 4)
    ) -> Bool {
        let clipID = selection.clipID
        let indexes = affectedIndexes(for: stepIndex)
        let resolvedLayer = layer ?? activeLayer
        let resolvedBindings = macroBindings ?? track?.macros
        let normalizedDefaultNote = defaultNote.normalized

        return clipMutator.mutateClip(id: clipID, impact: .snapshotOnly) { entry in
            for index in indexes {
                Self.applyAbsoluteValue(
                    value,
                    at: index,
                    layer: resolvedLayer,
                    entry: &entry,
                    macroBindings: resolvedBindings,
                    noteLane: noteLane,
                    defaultNote: normalizedDefaultNote
                )
            }
        }
    }

    func copySelectedSteps(from clip: ClipPoolEntry, track: StepSequenceTrack) {
        let sourceClipID = selection.clipID
        let indexes = selection.selectedStepIndexes.sorted()
        let macroBindings = track.macros
        let steps = Dictionary(uniqueKeysWithValues: indexes.map { index in
            (index, Self.clipboardEntry(at: index, in: clip, macroBindings: macroBindings))
        })
        clipboard = StepClipboard(sourceClipID: sourceClipID, steps: steps)
    }

    @discardableResult
    func clearSelectedSteps(track: StepSequenceTrack) -> Bool {
        let clipID = selection.clipID
        let indexes = selection.selectedStepIndexes.sorted()
        let macroBindings = track.macros

        let didMutate = clipMutator.mutateClip(id: clipID, impact: .snapshotOnly) { entry in
            for index in indexes {
                Self.clearStep(at: index, entry: &entry, macroBindings: macroBindings)
            }
        }
        if didMutate {
            clearSelection()
        }
        return didMutate
    }

    @discardableResult
    func pasteClipboard(
        track: StepSequenceTrack,
        defaultNote: ClipStepNote = ClipStepNote(pitch: 60, velocity: 100, lengthSteps: 4)
    ) -> Bool {
        guard let clipboard else { return false }
        let clipID = selection.clipID
        let entries = clipboard.steps
        let macroBindings = track.macros
        let normalizedDefaultNote = defaultNote.normalized

        return clipMutator.mutateClip(id: clipID, impact: .snapshotOnly) { entry in
            for (index, clipboardEntry) in entries {
                Self.paste(
                    clipboardEntry,
                    at: index,
                    entry: &entry,
                    macroBindings: macroBindings,
                    defaultNote: normalizedDefaultNote
                )
            }
        }
    }

    private func affectedIndexes(for stepIndex: Int) -> [Int] {
        if selection.selectedStepIndexes.contains(stepIndex) {
            return selection.selectedStepIndexes.sorted()
        }
        return [stepIndex]
    }
}

@MainActor
@Observable
final class TrackStepGridWorkspaceModel {
    var coordinator: StepGridCoordinator?

    func coordinator(
        for clipID: ClipID,
        clipMutator: any StepGridClipMutating,
        editableLayers: [StepGridLayer]
    ) -> StepGridCoordinator {
        if let coordinator {
            coordinator.updateActiveClip(clipID)
            coordinator.updateEditableLayers(editableLayers)
            return coordinator
        }

        let coordinator = StepGridCoordinator(
            clipID: clipID,
            clipMutator: clipMutator,
            editableLayers: editableLayers
        )
        self.coordinator = coordinator
        return coordinator
    }

    func reset() {
        coordinator = nil
    }
}

private extension StepGridCoordinator {
    static func rotaryControl(
        for layer: StepGridLayer,
        seedStepIndex: Int,
        clip: ClipPoolEntry,
        macroBindings: [TrackMacroBinding]?,
        noteLane: StepGridNoteLane
    ) -> StepGridRotaryControl {
        let value = rotaryFraction(
            at: seedStepIndex,
            layer: layer,
            in: clip,
            macroBindings: macroBindings,
            noteLane: noteLane
        )
        return StepGridRotaryControl(
            layer: layer,
            title: rotaryTitle(for: layer, macroBindings: macroBindings),
            normalizedValue: value,
            displayValue: rotaryDisplayValue(
                for: layer,
                normalizedValue: value,
                seedStepIndex: seedStepIndex,
                clip: clip,
                noteLane: noteLane
            )
        )
    }

    static func applyTap(
        at index: Int,
        layer: StepGridLayer,
        entry: inout ClipPoolEntry,
        track: StepSequenceTrack?,
        noteLane: StepGridNoteLane,
        defaultNote: ClipStepNote
    ) {
        switch layer {
        case .trigger:
            toggleActive(at: index, entry: &entry, noteLane: noteLane, defaultNote: defaultNote)
        case .sliceIndex:
            cycleSliceIndex(at: index, entry: &entry)
        case .sliceMode:
            cycleSliceMode(at: index, entry: &entry)
        case let .macro(macroIndex):
            guard let binding = track?.macros[safe: macroIndex] else { return }
            let current = entry.macroLanes[binding.id]?.synced(stepCount: entry.content.stepCount).values[safe: index] ?? nil
            setMacroValue(current == nil ? binding.descriptor.defaultValue : nil, at: index, entry: &entry, binding: binding)
        case .velocity, .chance, .chord:
            break
        }
    }

    static func applyAbsoluteValue(
        _ value: Double,
        at index: Int,
        layer: StepGridLayer,
        entry: inout ClipPoolEntry,
        macroBindings: [TrackMacroBinding]?,
        noteLane: StepGridNoteLane,
        defaultNote: ClipStepNote
    ) {
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
            break
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
            var updated = steps
            guard updated.indices.contains(index) else { return }
            let nextLane = noteLane.lane(in: updated[index]) == nil
                ? ClipLane(chance: 1, notes: [defaultNote])
                : nil
            noteLane.setLane(nextLane, on: &updated[index])
            entry.content = .noteGrid(lengthSteps: lengthSteps, steps: updated)

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
            var updated = steps
            guard updated.indices.contains(index) else { return }
            let velocity = Int((clampedUnit(value) * 127).rounded())
            if velocity <= 0 {
                noteLane.setLane(nil, on: &updated[index])
            } else if var lane = noteLane.lane(in: updated[index]) {
                let notes = lane.notes.isEmpty ? [defaultNote] : lane.notes
                lane.notes = notes.map { note in
                    var updatedNote = note
                    updatedNote.velocity = velocity
                    return updatedNote
                }
                noteLane.setLane(lane, on: &updated[index])
            } else {
                var note = defaultNote
                note.velocity = velocity
                noteLane.setLane(ClipLane(chance: 1, notes: [note]), on: &updated[index])
            }
            entry.content = .noteGrid(lengthSteps: lengthSteps, steps: updated)

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
            var updated = steps
            guard updated.indices.contains(index) else { return }
            let chance = clampedUnit(value)
            if var lane = noteLane.lane(in: updated[index]) {
                lane.chance = chance
                noteLane.setLane(lane, on: &updated[index])
            } else if chance > 0 {
                noteLane.setLane(ClipLane(chance: chance, notes: [defaultNote]), on: &updated[index])
            }
            entry.content = .noteGrid(lengthSteps: lengthSteps, steps: updated)

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

    static func cycleSliceIndex(at index: Int, entry: inout ClipPoolEntry) {
        guard case let .sliceTriggers(stepPattern, sliceIndexes, stepModes, stepParameters) = entry.content.normalized else { return }
        var updated = sliceIndexes
        guard updated.indices.contains(index) else { return }
        updated[index] = (updated[index] + 1) % 16
        entry.content = .sliceTriggers(
            stepPattern: stepPattern,
            sliceIndexes: updated,
            stepModes: stepModes,
            stepParameters: stepParameters
        )
    }

    static func cycleSliceMode(at index: Int, entry: inout ClipPoolEntry) {
        guard case let .sliceTriggers(stepPattern, sliceIndexes, stepModes, stepParameters) = entry.content.normalized else { return }
        var updated = stepModes
        guard updated.indices.contains(index) else { return }
        updated[index] = updated[index] == .single ? .runFromHere : .single
        entry.content = .sliceTriggers(
            stepPattern: stepPattern,
            sliceIndexes: sliceIndexes,
            stepModes: updated,
            stepParameters: stepParameters
        )
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

    static func rotaryFraction(
        at index: Int,
        layer: StepGridLayer,
        in clip: ClipPoolEntry,
        macroBindings: [TrackMacroBinding]?,
        noteLane: StepGridNoteLane
    ) -> Double {
        switch layer {
        case .velocity:
            return velocityFraction(at: index, in: clip.content, noteLane: noteLane)
        case .chance:
            return chanceFraction(at: index, in: clip.content, noteLane: noteLane)
        case let .macro(macroIndex):
            guard let binding = macroBindings?[safe: macroIndex] else {
                return 0
            }
            return macroFraction(at: index, in: clip, binding: binding)
        case .sliceIndex:
            guard case let .sliceTriggers(_, sliceIndexes, _, _) = clip.content.normalized,
                  let sliceIndex = sliceIndexes[safe: index]
            else {
                return 0
            }
            let maxIndex = max(sliceIndexes.max() ?? 0, 1)
            return clampedUnit(Double(sliceIndex) / Double(maxIndex))
        case .sliceMode:
            guard case let .sliceTriggers(_, _, stepModes, _) = clip.content.normalized,
                  let stepMode = stepModes[safe: index]
            else {
                return 0
            }
            return stepMode == .runFromHere ? 1 : 0
        case .chord, .trigger:
            return 0
        }
    }

    static func rotaryTitle(for layer: StepGridLayer, macroBindings: [TrackMacroBinding]?) -> String {
        switch layer {
        case .trigger:
            return "Steps"
        case .velocity:
            return "Velocity"
        case .chance:
            return "Chance"
        case let .macro(index):
            return macroBindings?[safe: index]?.displayName ?? "Macro \(index + 1)"
        case .sliceIndex:
            return "Slice"
        case .sliceMode:
            return "Mode"
        case .chord:
            return "Chord"
        }
    }

    static func rotaryDisplayValue(
        for layer: StepGridLayer,
        normalizedValue: Double,
        seedStepIndex: Int,
        clip: ClipPoolEntry,
        noteLane: StepGridNoteLane
    ) -> String {
        switch layer {
        case .velocity:
            return "\(Int((clampedUnit(normalizedValue) * 127).rounded()))"
        case .chance, .macro:
            return "\(Int((clampedUnit(normalizedValue) * 100).rounded()))%"
        case .sliceIndex:
            guard case let .sliceTriggers(_, sliceIndexes, _, _) = clip.content.normalized,
                  let sliceIndex = sliceIndexes[safe: seedStepIndex]
            else {
                return "-"
            }
            return "\(sliceIndex + 1)"
        case .sliceMode:
            guard case let .sliceTriggers(_, _, stepModes, _) = clip.content.normalized,
                  let stepMode = stepModes[safe: seedStepIndex]
            else {
                return "One"
            }
            return stepMode == .runFromHere ? "Run" : "One"
        case .chord:
            return chordLabel(at: seedStepIndex, in: clip.content, noteLane: noteLane)
        case .trigger:
            return ""
        }
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
