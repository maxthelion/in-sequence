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

    mutating func releaseMomentary(
        control: TrackPerformBinaryControl,
        sourceTrackID: UUID
    ) {
        let key = TrackPerformMomentaryPressKey(control: control, sourceTrackID: sourceTrackID)
        momentaryRecipientsByPress.removeValue(forKey: key)
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
