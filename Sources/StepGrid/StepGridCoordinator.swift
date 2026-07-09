import Foundation
import Observation

enum StepGridLayer: Equatable, Sendable {
    case trigger
    case pitch
    case velocity
    case length
    case chance
    case macro(index: Int)
    case sliceIndex
    case sliceMode
    case chord

    var isEditableValueLayer: Bool {
        switch self {
        case .pitch, .velocity, .length, .chance, .macro, .sliceIndex, .sliceMode, .chord:
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
        case .pitch:
            return "pitch"
        case .velocity:
            return "velocity"
        case .length:
            return "length"
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
        editableLayers: [StepGridLayer] = [.velocity, .length, .chance]
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
            layer == .velocity || layer == .length || layer == .chance
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

        case .length:
            return .optionLabel(text: Self.lengthDisplayValue(at: stepIndex, in: clip.content, noteLane: noteLane))

        case .pitch:
            return Self.pitchContent(at: stepIndex, in: clip.content, noteLane: noteLane)

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

    /// The single clip-write entry for every step-grid surface (audit
    /// F1/F3). Rotary/batch writes and the grid surfaces' tap/drag commits
    /// all land here: one in-place transform of the live store entry, keyed
    /// by the coordinator's clip ID. Surfaces must never write a whole
    /// `ClipContent` (or `macroLanes` dict) computed from a view copy —
    /// expressing every edit as a transform of current store truth is what
    /// makes interleaved writes from different surfaces compose instead of
    /// losing updates.
    @discardableResult
    func commitEdit(_ edit: (inout ClipPoolEntry) -> Void) -> Bool {
        clipMutator.mutateClip(id: selection.clipID, impact: .snapshotOnly, edit)
    }

    @discardableResult
    func onTap(
        stepIndex: Int,
        layer: StepGridLayer? = nil,
        track: StepSequenceTrack? = nil,
        noteLane: StepGridNoteLane = .main,
        defaultNote: ClipStepNote = ClipStepNote(pitch: 60, velocity: 100, lengthSteps: 4)
    ) -> Bool {
        let indexes = affectedIndexes(for: stepIndex)
        let resolvedLayer = layer ?? activeLayer
        let resolvedBindings = track?.macros
        let normalizedDefaultNote = defaultNote.normalized

        return commitEdit { entry in
            ClipNoteGridStepEditing.applyTap(
                tappedIndex: stepIndex,
                indexes: indexes,
                layer: resolvedLayer,
                entry: &entry,
                macroBindings: resolvedBindings,
                noteLane: noteLane,
                defaultNote: normalizedDefaultNote
            )
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
        let indexes = affectedIndexes(for: stepIndex)
        let resolvedLayer = layer ?? activeLayer
        let resolvedBindings = macroBindings ?? track?.macros
        let normalizedDefaultNote = defaultNote.normalized

        return commitEdit { entry in
            ClipNoteGridStepEditing.applyAbsoluteValue(
                value,
                indexes: indexes,
                layer: resolvedLayer,
                entry: &entry,
                macroBindings: resolvedBindings,
                noteLane: noteLane,
                defaultNote: normalizedDefaultNote
            )
        }
    }

    func copySelectedSteps(from clip: ClipPoolEntry, track: StepSequenceTrack) {
        let sourceClipID = selection.clipID
        let indexes = selection.selectedStepIndexes.sorted()
        let macroBindings = track.macros
        let steps = Dictionary(uniqueKeysWithValues: indexes.map { index in
            (index, ClipNoteGridStepEditing.clipboardEntry(at: index, in: clip, macroBindings: macroBindings))
        })
        clipboard = StepClipboard(sourceClipID: sourceClipID, steps: steps)
    }

    @discardableResult
    func clearSelectedSteps(track: StepSequenceTrack) -> Bool {
        let indexes = selection.selectedStepIndexes.sorted()
        let macroBindings = track.macros

        let didMutate = commitEdit { entry in
            for index in indexes {
                ClipNoteGridStepEditing.clearStep(at: index, entry: &entry, macroBindings: macroBindings)
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
        let entries = clipboard.steps
        let macroBindings = track.macros
        let normalizedDefaultNote = defaultNote.normalized

        return commitEdit { entry in
            for (index, clipboardEntry) in entries {
                ClipNoteGridStepEditing.paste(
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

// Presentation-only statics: rotary row models and cell labels. All layer
// value reads and edits delegate to `ClipNoteGridStepEditing` — the one
// step-editing implementation.
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

    static func velocityFraction(at index: Int, in content: ClipContent, noteLane: StepGridNoteLane = .main) -> Double {
        ClipNoteGridStepEditing.velocityFraction(at: index, in: content, noteLane: noteLane)
    }

    static func chanceFraction(at index: Int, in content: ClipContent, noteLane: StepGridNoteLane = .main) -> Double {
        ClipNoteGridStepEditing.chanceFraction(at: index, in: content, noteLane: noteLane)
    }

    static func lengthFraction(at index: Int, in content: ClipContent, noteLane: StepGridNoteLane = .main) -> Double {
        ClipNoteGridStepEditing.lengthFraction(at: index, in: content, noteLane: noteLane)
    }

    static func lengthDisplayValue(at index: Int, in content: ClipContent, noteLane: StepGridNoteLane = .main) -> String {
        ClipNoteGridStepEditing.lengthDisplayValue(at: index, in: content, noteLane: noteLane)
    }

    static func pitchFraction(at index: Int, in content: ClipContent, noteLane: StepGridNoteLane = .main) -> Double {
        ClipNoteGridStepEditing.pitchFraction(at: index, in: content, noteLane: noteLane)
    }

    static func pitchContent(at index: Int, in content: ClipContent, noteLane: StepGridNoteLane = .main) -> StepCellContent {
        ClipNoteGridStepEditing.pitchContent(at: index, in: content, noteLane: noteLane)
    }

    static func pitchDisplayValue(at index: Int, in content: ClipContent, noteLane: StepGridNoteLane = .main) -> String {
        ClipNoteGridStepEditing.pitchDisplayValue(at: index, in: content, noteLane: noteLane)
    }

    static func chordLabel(at index: Int, in content: ClipContent, noteLane: StepGridNoteLane = .main) -> String {
        ClipNoteGridStepEditing.chordLabel(at: index, in: content, noteLane: noteLane)
    }

    static func macroFraction(at index: Int, in clip: ClipPoolEntry, binding: TrackMacroBinding) -> Double {
        ClipNoteGridStepEditing.macroFraction(at: index, in: clip, binding: binding)
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
        case .length:
            return lengthFraction(at: index, in: clip.content, noteLane: noteLane)
        case .pitch:
            return pitchFraction(at: index, in: clip.content, noteLane: noteLane)
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
        case .pitch:
            return "Pitch"
        case .velocity:
            return "Velocity"
        case .length:
            return "Length"
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
        case .pitch:
            return pitchDisplayValue(at: seedStepIndex, in: clip.content, noteLane: noteLane)
        case .velocity:
            return "\(Int((clampedUnit(normalizedValue) * 127).rounded()))"
        case .length:
            return lengthDisplayValue(at: seedStepIndex, in: clip.content, noteLane: noteLane)
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
        ClipNoteGridStepEditing.clampedUnit(value)
    }
}

private extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
