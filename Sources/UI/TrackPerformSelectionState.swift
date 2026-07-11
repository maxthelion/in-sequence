import Foundation

struct TrackPerformSelectionState: Equatable {
    private(set) var selectedTrackIDs: Set<UUID>

    init(selectedTrackIDs: Set<UUID> = []) {
        self.selectedTrackIDs = selectedTrackIDs
    }

    var count: Int {
        selectedTrackIDs.count
    }

    var isEmpty: Bool {
        selectedTrackIDs.isEmpty
    }

    func contains(_ trackID: UUID) -> Bool {
        selectedTrackIDs.contains(trackID)
    }

    mutating func add(_ trackID: UUID) {
        selectedTrackIDs.insert(trackID)
    }

    mutating func remove(_ trackID: UUID) {
        selectedTrackIDs.remove(trackID)
    }

    mutating func toggle(_ trackID: UUID) {
        if selectedTrackIDs.contains(trackID) {
            selectedTrackIDs.remove(trackID)
        } else {
            selectedTrackIDs.insert(trackID)
        }
    }

    mutating func clear() {
        selectedTrackIDs.removeAll()
    }

    mutating func reconcile(availableTrackIDs: [UUID]) {
        selectedTrackIDs.formIntersection(Set(availableTrackIDs))
    }
}

enum TrackPerformAuthoredEdit {
    static func recipientTrackIDs(
        sourceTrackID: UUID,
        orderedTrackIDs: [UUID],
        selection: TrackPerformSelectionState
    ) -> [UUID] {
        guard selection.count >= 2, selection.contains(sourceTrackID) else {
            return [sourceTrackID]
        }

        let recipients = orderedTrackIDs.filter { selection.contains($0) }
        return recipients.isEmpty ? [sourceTrackID] : recipients
    }
}

enum TrackPerformPatternMiniCellInteraction {
    static func selectedSlotAfterMiniCellClick(
        requestedSlotIndex: Int,
        slotCount: Int = TrackPatternBank.slotCount
    ) -> Int? {
        guard (0..<slotCount).contains(requestedSlotIndex) else {
            return nil
        }
        return requestedSlotIndex
    }

    static func shouldCycleFromCardBackground(layer: PhraseLayerDefinition) -> Bool {
        layer.valueType != .patternIndex
    }
}

enum TrackPerformLatchMode: String, CaseIterable, Equatable, Identifiable {
    case momentary
    case latched

    var id: String { rawValue }

    var label: String {
        switch self {
        case .momentary:
            return "Momentary"
        case .latched:
            return "Latch"
        }
    }
}

enum TrackPerformLayerMode: String, CaseIterable, Equatable, Hashable, Identifiable {
    case mute
    case pattern
    case fill
    case noteRepeat
    case stepOrder
    case volume
    case pan

    var id: String { rawValue }

    var label: String {
        switch self {
        case .mute:
            return "Mute"
        case .pattern:
            return "Pattern"
        case .fill:
            return "Fill"
        case .noteRepeat:
            return "Note Repeat"
        case .stepOrder:
            return "Step Order"
        case .volume:
            return "Volume"
        case .pan:
            return "Pan"
        }
    }

    var subtitle: String {
        switch self {
        case .mute:
            return "track mute"
        case .pattern:
            return "pattern slot"
        case .fill:
            return "runtime fill"
        case .noteRepeat:
            return "runtime repeat"
        case .stepOrder:
            return "step remap"
        case .volume:
            return "track volume"
        case .pan:
            return "track pan"
        }
    }

    var symbolName: String {
        switch self {
        case .mute:
            return "speaker.slash.fill"
        case .pattern:
            return "square.grid.2x2"
        case .fill:
            return "sparkles"
        case .noteRepeat:
            return "repeat"
        case .stepOrder:
            return "arrow.triangle.swap"
        case .volume:
            return "slider.horizontal.3"
        case .pan:
            return "dot.radiowaves.left.and.right"
        }
    }

    var phraseLayerID: String? {
        switch self {
        case .mute:
            return "mute"
        case .pattern:
            return "pattern"
        case .fill:
            return "fill-flag"
        case .noteRepeat, .stepOrder, .volume, .pan:
            return nil
        }
    }

    var binaryControl: TrackPerformBinaryControl? {
        switch self {
        case .mute, .pattern, .volume, .stepOrder, .pan:
            return nil
        case .fill:
            return .fill
        case .noteRepeat:
            return .noteRepeat
        }
    }

    var inlineVariantLabels: [String] {
        switch self {
        case .noteRepeat:
            // Mirrors NoteRepeatInterval — every variant here is engine-backed.
            return NoteRepeatInterval.allCases.map(\.rawValue)
        case .stepOrder:
            return ["Identity", "Break Fold", "Back Half", "Reverse", "Skip 4", "Repeat 3", "Custom"]
        case .mute, .pattern, .fill, .volume, .pan:
            return []
        }
    }

    var hasInlineVariants: Bool {
        !inlineVariantLabels.isEmpty
    }
}

enum PhrasePerformTimingPolicy {
    static func usesQuantisedLayerArming(
        layerID: String,
        latchMode: TrackPerformLatchMode,
        sessionArmingActive: Bool
    ) -> Bool {
        latchMode == .latched
            && sessionArmingActive
            && (
                layerID == TrackPerformLayerMode.mute.phraseLayerID
                || layerID == TrackPerformLayerMode.fill.phraseLayerID
                || layerID == TrackPerformLayerMode.pattern.phraseLayerID
            )
    }

}

/// One selectable cell in the performance layer matrix. Plain layers are one
/// cell each; variant layers (note repeat, step order) contribute one cell per
/// variant so every option is a full-size toggle.
struct PerformanceLayerOption: Identifiable, Equatable {
    let mode: TrackPerformLayerMode
    let variantLabel: String?
    let isAvailable: Bool
    let unavailableReason: String?

    init(
        mode: TrackPerformLayerMode,
        variantLabel: String?,
        isAvailable: Bool = true,
        unavailableReason: String? = nil
    ) {
        self.mode = mode
        self.variantLabel = variantLabel
        self.isAvailable = isAvailable
        self.unavailableReason = unavailableReason
    }

    var id: String { "\(mode.rawValue):\(variantLabel ?? "-")" }

    var title: String {
        variantLabel ?? mode.label
    }

    static var patternValues: [PerformanceLayerOption] {
        (0..<TrackPatternBank.slotCount).map {
            PerformanceLayerOption(mode: .pattern, variantLabel: "P\($0 + 1)")
        }
    }

    var patternSlotIndex: Int? {
        guard mode == .pattern,
              let variantLabel,
              variantLabel.first == "P",
              let oneBased = Int(variantLabel.dropFirst()),
              (1...TrackPatternBank.slotCount).contains(oneBased)
        else { return nil }
        return oneBased - 1
    }

    static let implicitIdentityStepOrder = PerformanceLayerOption(
        mode: .stepOrder,
        variantLabel: "Identity"
    )

    static let unavailableStepOrder = PerformanceLayerOption(
        mode: .stepOrder,
        variantLabel: nil,
        isAvailable: false,
        unavailableReason: "16 steps only"
    )

    func resolvedStepOrderMap(in maps: [StepOrderMap]) -> StepOrderMap? {
        guard mode == .stepOrder, let variantLabel else { return nil }
        return maps.first { $0.name == variantLabel && $0.isValid }
    }

    /// Step Order remains usable before a project has any saved maps. The
    /// first tap materializes the visible Identity option as a normal pooled
    /// map; subsequent rendering resolves it through the same path as every
    /// user-authored map.
    func materializedStepOrderMap(in maps: [StepOrderMap]) -> StepOrderMap? {
        if let existing = resolvedStepOrderMap(in: maps) {
            return existing
        }
        guard self == Self.implicitIdentityStepOrder else { return nil }
        return StepOrderMap(name: "Identity")
    }

    static var all: [PerformanceLayerOption] {
        TrackPerformLayerMode.allCases.flatMap { mode -> [PerformanceLayerOption] in
            if mode.hasInlineVariants {
                return mode.inlineVariantLabels.map { PerformanceLayerOption(mode: mode, variantLabel: $0) }
            }
            return [PerformanceLayerOption(mode: mode, variantLabel: nil)]
        }
    }

    /// Phrase performance only advertises options with a real interaction
    /// path. Document layers are available when present, note repeat is an
    /// engine-backed per-track gesture, and step order is backed by the
    /// document's valid maps for a 16-step phrase.
    static func phraseOptions(
        availableLayerIDs: Set<String>,
        stepOrderMaps: [StepOrderMap],
        phraseStepCount: Int
    ) -> [PerformanceLayerOption] {
        TrackPerformLayerMode.allCases.flatMap { mode -> [PerformanceLayerOption] in
            if let layerID = mode.phraseLayerID {
                return availableLayerIDs.contains(layerID)
                    ? [PerformanceLayerOption(mode: mode, variantLabel: nil)]
                    : []
            }

            switch mode {
            case .noteRepeat:
                return mode.inlineVariantLabels.map {
                    PerformanceLayerOption(mode: mode, variantLabel: $0)
                }
            case .stepOrder:
                guard phraseStepCount == StepOrderMap.stepCount else {
                    return [Self.unavailableStepOrder]
                }
                let validMaps = stepOrderMaps.filter(\.isValid)
                guard !validMaps.isEmpty else {
                    return [Self.implicitIdentityStepOrder]
                }
                return validMaps.map {
                    PerformanceLayerOption(mode: mode, variantLabel: $0.name)
                }
            case .mute, .pattern, .fill, .volume, .pan:
                return []
            }
        }
    }
}

struct GlobalApplyValueVisibilityState: Equatable {
    private(set) var expandedModes: Set<TrackPerformLayerMode> = []
    private(set) var pinnedOptionIDs: Set<String> = []

    func isExpanded(_ mode: TrackPerformLayerMode) -> Bool {
        expandedModes.contains(mode)
    }

    func isPinned(_ option: PerformanceLayerOption) -> Bool {
        pinnedOptionIDs.contains(option.id)
    }

    mutating func toggleExpanded(_ mode: TrackPerformLayerMode) {
        if expandedModes.contains(mode) {
            expandedModes.remove(mode)
        } else {
            expandedModes.insert(mode)
        }
    }

    mutating func togglePinned(_ option: PerformanceLayerOption) {
        guard option.isAvailable else { return }
        if pinnedOptionIDs.contains(option.id) {
            pinnedOptionIDs.remove(option.id)
        } else {
            pinnedOptionIDs.insert(option.id)
        }
    }

    func visibleOptions(
        for mode: TrackPerformLayerMode,
        allOptions: [PerformanceLayerOption],
        currentOption: PerformanceLayerOption?
    ) -> [PerformanceLayerOption] {
        guard !allOptions.isEmpty else { return [] }
        if isExpanded(mode) {
            return allOptions
        }

        let current = currentOption.flatMap { candidate in
            allOptions.first { $0.id == candidate.id }
        } ?? allOptions[0]
        return [current] + allOptions.filter {
            $0.id != current.id && pinnedOptionIDs.contains($0.id)
        }
    }
}

struct PerformanceLayerSelectionState: Equatable {
    private(set) var mode: TrackPerformLayerMode
    private(set) var variantLabel: String?

    init(mode: TrackPerformLayerMode = .pattern, variantLabel: String? = nil) {
        self.mode = mode
        self.variantLabel = mode.inlineVariantLabels.contains(variantLabel ?? "") ? variantLabel : nil
    }

    var activeLabel: String {
        let suffix = variantLabel.map { " - \($0)" } ?? ""
        return "\(mode.label)\(suffix)"
    }

    mutating func select(
        _ mode: TrackPerformLayerMode,
        variantLabel: String?,
        availableVariantLabels: [String]? = nil
    ) {
        self.mode = mode
        let validLabels = availableVariantLabels ?? mode.inlineVariantLabels
        self.variantLabel = validLabels.contains(variantLabel ?? "") ? variantLabel : nil
    }

    mutating func reconcileVariant(availableVariantLabels: [String]? = nil) {
        let validLabels = availableVariantLabels ?? mode.inlineVariantLabels
        if !validLabels.contains(variantLabel ?? "") {
            variantLabel = nil
        }
    }
}

enum TrackPerformBinaryControl: String, CaseIterable, Equatable, Hashable, Identifiable {
    case fill
    case noteRepeat

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fill:
            return "Fill"
        case .noteRepeat:
            return "Repeat"
        }
    }

    var symbolName: String {
        switch self {
        case .fill:
            return "sparkles"
        case .noteRepeat:
            return "repeat"
        }
    }

    init?(layer: PhraseLayerDefinition) {
        switch layer.id {
        case "fill-flag":
            self = .fill
        case "note-repeat", "note-repeat-flag":
            self = .noteRepeat
        default:
            return nil
        }
    }
}

struct TrackPerformMomentaryPressKey: Equatable, Hashable {
    var control: TrackPerformBinaryControl
    var sourceTrackID: UUID
}

struct TrackPerformRuntimeOverlayState: Equatable {
    var latchMode: TrackPerformLatchMode
    private(set) var latchedTrackIDsByControl: [TrackPerformBinaryControl: Set<UUID>]
    private(set) var momentaryRecipientsByPress: [TrackPerformMomentaryPressKey: Set<UUID>]

    init(
        latchMode: TrackPerformLatchMode = .momentary,
        latchedTrackIDsByControl: [TrackPerformBinaryControl: Set<UUID>] = [:],
        momentaryRecipientsByPress: [TrackPerformMomentaryPressKey: Set<UUID>] = [:]
    ) {
        self.latchMode = latchMode
        self.latchedTrackIDsByControl = latchedTrackIDsByControl
        self.momentaryRecipientsByPress = momentaryRecipientsByPress
    }

    func isActive(_ control: TrackPerformBinaryControl, trackID: UUID) -> Bool {
        isLatched(control, trackID: trackID) || isMomentaryPressed(control, trackID: trackID)
    }

    func activeTrackIDs(_ control: TrackPerformBinaryControl, orderedTrackIDs: [UUID]) -> [UUID] {
        orderedTrackIDs.filter { isActive(control, trackID: $0) }
    }

    func momentaryRecipientTrackIDs(control: TrackPerformBinaryControl, sourceTrackID: UUID) -> [UUID] {
        let key = TrackPerformMomentaryPressKey(control: control, sourceTrackID: sourceTrackID)
        return Array(momentaryRecipientsByPress[key] ?? [])
    }

    func isLatched(_ control: TrackPerformBinaryControl, trackID: UUID) -> Bool {
        latchedTrackIDsByControl[control]?.contains(trackID) == true
    }

    func isMomentaryPressed(_ control: TrackPerformBinaryControl, trackID: UUID) -> Bool {
        momentaryRecipientsByPress.contains { key, trackIDs in
            key.control == control && trackIDs.contains(trackID)
        }
    }

    mutating func setRuntime(
        _ isActive: Bool,
        control: TrackPerformBinaryControl,
        trackIDs: [UUID]
    ) {
        if isActive {
            latchedTrackIDsByControl[control, default: []].formUnion(trackIDs)
        } else {
            latchedTrackIDsByControl[control, default: []].subtract(trackIDs)
            removeEmptyLatchedSet(for: control)
        }
    }

    mutating func clearRuntime(control: TrackPerformBinaryControl, trackIDs: [UUID]) {
        setRuntime(false, control: control, trackIDs: trackIDs)
    }

    mutating func activate(
        control: TrackPerformBinaryControl,
        sourceTrackID: UUID,
        orderedTrackIDs: [UUID],
        selection: TrackPerformSelectionState
    ) {
        let recipientTrackIDs = TrackPerformAuthoredEdit.recipientTrackIDs(
            sourceTrackID: sourceTrackID,
            orderedTrackIDs: orderedTrackIDs,
            selection: selection
        )

        switch latchMode {
        case .momentary:
            let key = TrackPerformMomentaryPressKey(control: control, sourceTrackID: sourceTrackID)
            if momentaryRecipientsByPress[key] == nil {
                momentaryRecipientsByPress[key] = Set(recipientTrackIDs)
            }
        case .latched:
            toggleRuntime(control: control, trackIDs: recipientTrackIDs)
        }
    }

    mutating func activate(
        control: TrackPerformBinaryControl,
        sourceTrackID: UUID,
        recipientTrackIDs: [UUID]
    ) {
        switch latchMode {
        case .momentary:
            let key = TrackPerformMomentaryPressKey(control: control, sourceTrackID: sourceTrackID)
            if momentaryRecipientsByPress[key] == nil {
                momentaryRecipientsByPress[key] = Set(recipientTrackIDs)
            }
        case .latched:
            toggleRuntime(control: control, trackIDs: recipientTrackIDs)
        }
    }

    mutating func releaseMomentary(
        control: TrackPerformBinaryControl,
        sourceTrackID: UUID
    ) {
        let key = TrackPerformMomentaryPressKey(control: control, sourceTrackID: sourceTrackID)
        momentaryRecipientsByPress.removeValue(forKey: key)
    }

    mutating func releaseAllMomentary(control: TrackPerformBinaryControl) {
        momentaryRecipientsByPress = momentaryRecipientsByPress.filter { key, _ in
            key.control != control
        }
    }

    mutating func cleanupRuntime() {
        latchedTrackIDsByControl.removeAll()
        momentaryRecipientsByPress.removeAll()
    }

    mutating func reconcile(availableTrackIDs: [UUID]) {
        let availableTrackIDs = Set(availableTrackIDs)

        for control in latchedTrackIDsByControl.keys {
            latchedTrackIDsByControl[control]?.formIntersection(availableTrackIDs)
            removeEmptyLatchedSet(for: control)
        }

        for key in momentaryRecipientsByPress.keys {
            momentaryRecipientsByPress[key]?.formIntersection(availableTrackIDs)
            if momentaryRecipientsByPress[key]?.isEmpty != false {
                momentaryRecipientsByPress.removeValue(forKey: key)
            }
        }
    }

    private mutating func toggleRuntime(
        control: TrackPerformBinaryControl,
        trackIDs: [UUID]
    ) {
        let allActive = trackIDs.allSatisfy { isLatched(control, trackID: $0) }
        setRuntime(!allActive, control: control, trackIDs: trackIDs)
    }

    private mutating func removeEmptyLatchedSet(for control: TrackPerformBinaryControl) {
        if latchedTrackIDsByControl[control]?.isEmpty != false {
            latchedTrackIDsByControl.removeValue(forKey: control)
        }
    }
}
