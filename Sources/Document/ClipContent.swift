import Foundation

struct ClipNote: Codable, Equatable, Hashable, Sendable, Identifiable {
    var pitch: Int
    var startStep: Int
    var lengthSteps: Int
    var velocity: Int

    var id: String {
        "\(pitch):\(startStep):\(lengthSteps):\(velocity)"
    }
}

enum ClipContent: Codable, Equatable, Hashable, Sendable {
    case stepSequence(stepPattern: [Bool], pitches: [Int])
    case pianoRoll(lengthBars: Int, stepsPerBar: Int, notes: [ClipNote])
    case sliceTriggers(stepPattern: [Bool], sliceIndexes: [Int])
}
