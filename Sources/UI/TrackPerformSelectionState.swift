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
    case latch

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
        case .latch:
            return "Latch"
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
        case .latch:
            return "hold overrides"
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
        case .latch:
            return "lock.fill"
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
        case .volume:
            return "volume"
        case .noteRepeat, .stepOrder, .pan, .latch:
            return nil
        }
    }

    var binaryControl: TrackPerformBinaryControl? {
        switch self {
        case .mute, .pattern, .volume, .stepOrder, .pan, .latch:
            return nil
        case .fill:
            return .fill
        case .noteRepeat:
            return .noteRepeat
        }
    }

    var inlineVariantLabels: [String] {
        switch self {
        case .pattern:
            return (1...16).map { "P\($0)" }
        case .noteRepeat:
            return ["Off", "1/4", "1/8", "1/16", "1/32", "Trip", "Roll", "Hold"]
        case .stepOrder:
            return ["Off", "Identity", "Break Fold", "Back Half", "Reverse", "Skip 4", "Repeat 3", "Custom"]
        case .mute, .fill, .volume, .pan, .latch:
            return []
        }
    }

    var hasInlineVariants: Bool {
        !inlineVariantLabels.isEmpty
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
