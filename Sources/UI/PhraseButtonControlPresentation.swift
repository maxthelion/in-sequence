import Foundation

struct PhraseButtonControlsState: Equatable {
    private(set) var openPhraseID: UUID?

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
}
