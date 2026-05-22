import Foundation

struct StepClipboardEntry: Equatable, Sendable {
    var active: Bool
    var velocity: Double?
    var chance: Double?
    var macroOverrides: [UUID: Double?]
    var sliceIndex: Int?
    var sliceMode: Int?
}

struct StepClipboard: Equatable, Sendable {
    var sourceClipID: ClipID
    var steps: [Int: StepClipboardEntry]
}
