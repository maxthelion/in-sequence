import Foundation

struct SeqAIDocumentModel: Codable, Equatable {
    var version: Int
    var primaryTrack: StepSequenceTrack

    static let empty = SeqAIDocumentModel(
        version: 1,
        primaryTrack: .default
    )
}

struct StepSequenceTrack: Codable, Equatable, Sendable {
    var name: String
    var pitches: [Int]
    var stepPattern: [Bool]
    var velocity: Int
    var gateLength: Int

    static let `default` = StepSequenceTrack(
        name: "Main Track",
        pitches: [60, 64, 67, 72],
        stepPattern: Array(repeating: true, count: 16),
        velocity: 100,
        gateLength: 4
    )
}
