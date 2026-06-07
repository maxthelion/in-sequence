import Foundation

struct PhraseButtonControlsState: Equatable {
    private(set) var openPhraseID: UUID?

    mutating func openControls(for phraseID: UUID) {
        openPhraseID = phraseID
    }

    mutating func toggleControls(for phraseID: UUID) {
        openPhraseID = openPhraseID == phraseID ? nil : phraseID
    }

    mutating func close() {
        openPhraseID = nil
    }

    mutating func reconcile(availablePhraseIDs: some Collection<UUID>) {
        guard let openPhraseID,
              !availablePhraseIDs.contains(openPhraseID)
        else { return }

        self.openPhraseID = nil
    }
}

struct PhraseButtonControlPresentation: Equatable {
    let name: String
    let barCountSummary: String
    let repeatSummary: String
    let collapsedSummary: String
    let loopStatusLabel: String
    let repeatValueLabel: String
    let effectivePlaybackSummary: String
    let accessibilityLabel: String

    init(
        phrase: PhraseModel,
        isSelected: Bool,
        isPlaying: Bool,
        isQueued: Bool,
        isOpen: Bool
    ) {
        name = phrase.name
        barCountSummary = Self.barCountSummary(phrase.lengthBars)
        repeatSummary = Self.repeatSummary(repeatCount: phrase.repeatCount, loopEnabled: phrase.loopEnabled)
        collapsedSummary = "\(barCountSummary) | \(repeatSummary)"
        loopStatusLabel = phrase.loopEnabled ? "Loop on" : "Loop off"
        repeatValueLabel = Self.repeatValueLabel(phrase.repeatCount)
        effectivePlaybackSummary = Self.effectivePlaybackSummary(
            repeatCount: phrase.repeatCount,
            loopEnabled: phrase.loopEnabled,
            isQueued: isQueued
        )

        var states: [String] = []
        if isSelected { states.append("selected") }
        if isPlaying { states.append("playing") }
        if isQueued { states.append("queued") }
        states.append(phrase.loopEnabled ? "loop on" : "loop off")
        states.append(isOpen ? "controls open" : "controls closed")

        accessibilityLabel = "\(phrase.name), \(barCountSummary), \(repeatSummary), \(states.joined(separator: ", "))"
    }

    static func barCountSummary(_ barCount: Int) -> String {
        let clamped = PhraseModel.clampedLengthBars(barCount)
        return clamped == 1 ? "1 bar" : "\(clamped) bars"
    }

    static func repeatValueLabel(_ repeatCount: Int) -> String {
        let clamped = PhraseModel.clampedRepeatCount(repeatCount)
        return clamped == 0 ? "Unlimited" : "\(clamped)"
    }

    static func repeatSummary(repeatCount: Int, loopEnabled: Bool) -> String {
        let repeatLabel = repeatValueLabel(repeatCount)
        if loopEnabled {
            return "Loop overrides \(repeatLabel) repeat"
        }
        if PhraseModel.clampedRepeatCount(repeatCount) == 0 {
            return "Unlimited repeat"
        }
        return "\(repeatLabel)x repeat"
    }

    static func effectivePlaybackSummary(repeatCount: Int, loopEnabled: Bool, isQueued: Bool) -> String {
        let queuePrefix = isQueued
            ? "Queued: starts at the next phrase boundary, then "
            : ""

        if loopEnabled {
            return "\(queuePrefix)loop stays on this phrase. Stored repeat \(repeatValueLabel(repeatCount)) is preserved for when loop is off."
        }

        let clampedRepeatCount = PhraseModel.clampedRepeatCount(repeatCount)
        if clampedRepeatCount == 0 {
            return "\(queuePrefix)unlimited repeat keeps this phrase playing until another phrase is chosen."
        }
        if clampedRepeatCount == 1 {
            return "\(queuePrefix)plays once, then advances to the next phrase."
        }
        return "\(queuePrefix)plays \(clampedRepeatCount) times, then advances to the next phrase."
    }

    static func isPlayingBadgeVisible(
        phraseID: UUID,
        engineIsRunning: Bool,
        currentPhraseID: UUID?
    ) -> Bool {
        engineIsRunning && currentPhraseID == phraseID
    }
}

enum StepOrderPhraseSurfaceStatus: Equatable {
    case unassigned
    case unavailable(String)
    case invalid(String)
    case off
    case on
    case pendingOn
    case pendingOff
}

struct StepOrderPhraseSurfacePresentation: Equatable {
    let status: StepOrderPhraseSurfaceStatus
    let statusLabel: String
    let statusSummary: String
    let scopeLabel = "Phrase"
    let activeMapName: String
    let activeMapDetail: String
    let assignedMapID: StepOrderMapID?
    let editorMapID: StepOrderMapID?
    let canToggle: Bool
    let nextToggleValue: Bool
    let toggleAccessibilityLabel: String

    init(
        phrase: PhraseModel,
        maps: [StepOrderMap],
        toggleState: StepOrderToggleState
    ) {
        let assignedMap = phrase.stepOrderAssignment.flatMap { assignment in
            maps.first { $0.id == assignment.mapID }
        }
        assignedMapID = phrase.stepOrderAssignment?.mapID
        editorMapID = assignedMap?.id ?? maps.first?.id
        activeMapName = assignedMap?.name ?? "No map assigned"

        if phrase.stepCount != StepOrderMap.stepCount {
            status = .unavailable("16-step phrases only")
        } else if phrase.stepOrderAssignment == nil {
            status = .unassigned
        } else if let assignedMap, let issue = assignedMap.validationIssue {
            status = .invalid(Self.validationIssueLabel(issue))
        } else if assignedMap == nil {
            status = .invalid("Assigned map is missing")
        } else {
            switch toggleState {
            case .unavailable:
                status = .unavailable("Step Order is unavailable")
            case .off:
                status = .off
            case .on:
                status = .on
            case .pendingOn:
                status = .pendingOn
            case .pendingOff:
                status = .pendingOff
            }
        }

        statusLabel = Self.statusLabel(for: status)
        statusSummary = Self.statusSummary(for: status, mapName: assignedMap?.name)
        activeMapDetail = Self.mapDetail(for: assignedMap)
        canToggle = Self.canToggle(status)
        nextToggleValue = Self.nextToggleValue(for: status)
        toggleAccessibilityLabel = "Step Order \(statusLabel), scope Phrase, active map \(activeMapName)"
    }

    static func newMapName(existingMaps: [StepOrderMap]) -> String {
        let existingNames = Set(existingMaps.map(\.name))
        var index = existingMaps.count + 1
        while existingNames.contains("Step Order \(index)") {
            index += 1
        }
        return "Step Order \(index)"
    }

    static func mapDetail(for map: StepOrderMap?) -> String {
        guard let map else {
            return "Unassigned"
        }
        if let issue = map.validationIssue {
            return validationIssueLabel(issue)
        }
        return map.values == StepOrderMap.identityValues ? "Pass-through / no remap" : "Remap active"
    }

    static func deletionReasonLabel(_ reason: StepOrderMapDeletionBlockReason?) -> String? {
        switch reason {
        case .assignedToPhrases(let count):
            return count == 1 ? "Assigned to 1 phrase" : "Assigned to \(count) phrases"
        case nil:
            return nil
        }
    }

    static func validationIssueLabel(_ issue: StepOrderMapValidationIssue) -> String {
        switch issue {
        case .wrongLength(let actual):
            return "Invalid: \(actual) steps saved"
        case .outOfRange:
            return "Invalid: source step outside 1-16"
        }
    }

    static func outputStepAccessibilityLabel(outputIndex: Int, sourceIndex: Int) -> String {
        "Output step \(outputIndex + 1) reads source step \(sourceIndex + 1)"
    }

    static func sourceStepAccessibilityLabel(sourceIndex: Int, selectedOutputIndex: Int) -> String {
        "Assign source step \(sourceIndex + 1) to output step \(selectedOutputIndex + 1)"
    }

    static func stepCandidateValues() -> [Int] {
        Array(0..<StepOrderMap.stepCount)
    }

    static func advancedOutputIndex(after outputIndex: Int) -> Int {
        (outputIndex + 1) % StepOrderMap.stepCount
    }

    static func didWrapAfterEditing(outputIndex: Int) -> Bool {
        outputIndex == StepOrderMap.stepCount - 1
    }

    private static func statusLabel(for status: StepOrderPhraseSurfaceStatus) -> String {
        switch status {
        case .unassigned:
            return "Unassigned"
        case .unavailable:
            return "Unavailable"
        case .invalid:
            return "Invalid"
        case .off:
            return "Off"
        case .on:
            return "On"
        case .pendingOn:
            return "Pending On"
        case .pendingOff:
            return "Pending Off"
        }
    }

    private static func statusSummary(for status: StepOrderPhraseSurfaceStatus, mapName: String?) -> String {
        switch status {
        case .unassigned:
            return "Assign a named 16-step map to this phrase."
        case .unavailable(let reason), .invalid(let reason):
            return reason
        case .off:
            return "\(mapName ?? "Assigned map") is assigned and ready."
        case .on:
            return "\(mapName ?? "Assigned map") remaps source-step reads for this phrase."
        case .pendingOn:
            return "Will turn on at the next phrase boundary."
        case .pendingOff:
            return "Will turn off at the next phrase boundary."
        }
    }

    private static func canToggle(_ status: StepOrderPhraseSurfaceStatus) -> Bool {
        switch status {
        case .off, .on, .pendingOn, .pendingOff:
            return true
        case .unassigned, .unavailable, .invalid:
            return false
        }
    }

    private static func nextToggleValue(for status: StepOrderPhraseSurfaceStatus) -> Bool {
        switch status {
        case .off, .pendingOff, .unassigned, .unavailable, .invalid:
            return true
        case .on, .pendingOn:
            return false
        }
    }
}

struct StepOrderMapRowPresentation: Equatable, Identifiable {
    let id: StepOrderMapID
    let name: String
    let usageLabel: String
    let detailLabel: String
    let isAssignedToCurrentPhrase: Bool
    let canDelete: Bool
    let deleteBlockedReason: String?
    let accessibilityLabel: String

    init(
        map: StepOrderMap,
        deletionStatus: StepOrderMapDeletionStatus,
        currentPhraseAssignment: StepOrderAssignment?
    ) {
        id = map.id
        name = map.name
        usageLabel = deletionStatus.assignmentCount == 1
            ? "1 phrase"
            : "\(deletionStatus.assignmentCount) phrases"
        detailLabel = StepOrderPhraseSurfacePresentation.mapDetail(for: map)
        isAssignedToCurrentPhrase = currentPhraseAssignment?.mapID == map.id
        canDelete = deletionStatus.canDelete
        deleteBlockedReason = StepOrderPhraseSurfacePresentation.deletionReasonLabel(deletionStatus.blockedReason)

        let assignmentLabel = isAssignedToCurrentPhrase ? "assigned to current phrase" : "not assigned to current phrase"
        let deleteLabel = canDelete ? "delete available" : "delete blocked, \(deleteBlockedReason ?? "in use")"
        accessibilityLabel = "\(name), \(usageLabel), \(detailLabel), \(assignmentLabel), \(deleteLabel)"
    }
}
