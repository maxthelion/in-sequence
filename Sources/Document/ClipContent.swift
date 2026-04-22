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

    /// Number of steps in the clip — used to size macro lane values arrays.
    var stepCount: Int {
        switch self {
        case let .stepSequence(stepPattern, _):
            return stepPattern.count
        case let .pianoRoll(lengthBars, stepsPerBar, _):
            return max(1, lengthBars) * max(1, stepsPerBar)
        case let .sliceTriggers(stepPattern, _):
            return stepPattern.count
        }
    }
}

// MARK: - MacroLane

/// Per-step macro value overrides inside a clip.
///
/// A `nil` value at index N means "no override at this step — defer to the
/// phrase-layer value or descriptor default."
///
/// `values` is parallel to the clip's step count; use `synced(stepCount:)` to
/// keep them in sync when the clip length changes.
struct MacroLane: Codable, Equatable, Sendable {
    var values: [Double?]

    init(stepCount: Int) {
        values = Array(repeating: nil, count: max(0, stepCount))
    }

    init(values: [Double?]) {
        self.values = values
    }

    /// Returns a lane resized to `stepCount`, padding with `nil` or truncating.
    func synced(stepCount: Int) -> MacroLane {
        let count = max(0, stepCount)
        if values.count == count { return self }
        if values.count < count {
            return MacroLane(values: values + Array(repeating: nil, count: count - values.count))
        }
        return MacroLane(values: Array(values.prefix(count)))
    }
}

