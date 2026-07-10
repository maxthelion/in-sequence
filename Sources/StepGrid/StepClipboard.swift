import Foundation

enum StepLengthClipboardValue: Equatable, Sendable {
    case natural
    case steps(Int)
}

struct StepClipboardEntry: Equatable, Sendable {
    var active: Bool
    var velocity: Double?
    var length: StepLengthClipboardValue?
    var chance: Double?
    var macroOverrides: [UUID: Double?]
    var sliceIndex: Int?
    var sliceMode: Int?
}

struct StepClipboard: Equatable, Sendable {
    enum ContentKind: Equatable, Sendable {
        case noteGrid
        case chordReferences
        case sliceTriggers
    }

    var sourceClipID: ClipID
    var sourceTrackType: TrackType
    var sourceContentKind: ContentKind
    var steps: [Int: StepClipboardEntry]

    init(
        sourceClipID: ClipID,
        sourceTrackType: TrackType = .monoMelodic,
        sourceContentKind: ContentKind = .noteGrid,
        steps: [Int: StepClipboardEntry]
    ) {
        self.sourceClipID = sourceClipID
        self.sourceTrackType = sourceTrackType
        self.sourceContentKind = sourceContentKind
        self.steps = steps
    }
}
