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

struct ClipStepNote: Codable, Equatable, Hashable, Sendable, Identifiable {
    var pitch: Int
    var velocity: Int
    var lengthSteps: Int

    var id: String {
        "\(pitch):\(velocity):\(lengthSteps)"
    }

    var normalized: ClipStepNote {
        ClipStepNote(
            pitch: min(max(pitch, 0), 127),
            velocity: min(max(velocity, 1), 127),
            lengthSteps: max(1, lengthSteps)
        )
    }
}

struct ClipLane: Codable, Equatable, Hashable, Sendable {
    var chance: Double
    var notes: [ClipStepNote]

    var normalized: ClipLane? {
        let normalizedNotes = notes.map(\.normalized)
        guard !normalizedNotes.isEmpty else {
            return nil
        }
        return ClipLane(chance: min(max(chance, 0), 1), notes: normalizedNotes)
    }
}

struct ClipStep: Codable, Equatable, Hashable, Sendable {
    var main: ClipLane?
    var fill: ClipLane?

    static let empty = ClipStep(main: nil, fill: nil)

    var normalized: ClipStep {
        ClipStep(
            main: main?.normalized,
            fill: fill?.normalized
        )
    }

    var isEmpty: Bool {
        main == nil && fill == nil
    }
}

enum ClipContent: Equatable, Hashable, Sendable {
    case noteGrid(lengthSteps: Int, steps: [ClipStep])
    case sliceTriggers(stepPattern: [Bool], sliceIndexes: [Int])
}

extension ClipContent {
    static func emptyNoteGrid(lengthSteps: Int) -> ClipContent {
        let resolvedLength = max(1, lengthSteps)
        return .noteGrid(
            lengthSteps: resolvedLength,
            steps: Array(repeating: .empty, count: resolvedLength)
        )
    }

    static func stepSequence(stepPattern: [Bool], pitches: [Int]) -> ClipContent {
        let resolvedLength = max(1, stepPattern.count)
        let resolvedPitches = pitches.isEmpty ? [60] : pitches
        let steps = (0..<resolvedLength).map { stepIndex -> ClipStep in
            guard stepPattern.indices.contains(stepIndex), stepPattern[stepIndex] else {
                return .empty
            }
            let note = ClipStepNote(
                pitch: resolvedPitches[stepIndex % resolvedPitches.count],
                velocity: 100,
                lengthSteps: 4
            )
            return ClipStep(
                main: ClipLane(chance: 1, notes: [note]),
                fill: nil
            )
        }
        return .noteGrid(lengthSteps: resolvedLength, steps: steps)
    }

    static func pianoRoll(lengthBars: Int, stepsPerBar: Int, notes: [ClipNote]) -> ClipContent {
        let resolvedLength = max(1, lengthBars * stepsPerBar)
        var steps = Array(repeating: ClipStep.empty, count: resolvedLength)

        for note in notes {
            let clampedStart = min(max(note.startStep, 0), resolvedLength - 1)
            let normalizedNote = ClipStepNote(
                pitch: note.pitch,
                velocity: note.velocity,
                lengthSteps: note.lengthSteps
            ).normalized
            let existingNotes = steps[clampedStart].main?.notes ?? []
            steps[clampedStart].main = ClipLane(
                chance: 1,
                notes: existingNotes + [normalizedNote]
            )
        }

        return .noteGrid(lengthSteps: resolvedLength, steps: steps)
    }

    var cycleLength: Int {
        switch self {
        case let .noteGrid(lengthSteps, _):
            return max(1, lengthSteps)
        case let .sliceTriggers(stepPattern, _):
            return max(1, stepPattern.count)
        }
    }

    var normalized: ClipContent {
        switch self {
        case let .noteGrid(lengthSteps, steps):
            let resolvedLength = max(1, lengthSteps)
            let normalizedSteps = (0..<resolvedLength).map { index in
                if steps.indices.contains(index) {
                    return steps[index].normalized
                }
                return .empty
            }
            return .noteGrid(lengthSteps: resolvedLength, steps: normalizedSteps)
        case let .sliceTriggers(stepPattern, sliceIndexes):
            let resolvedPattern = stepPattern.isEmpty ? [false] : stepPattern
            return .sliceTriggers(stepPattern: resolvedPattern, sliceIndexes: sliceIndexes)
        }
    }

    var noteGridLengthSteps: Int? {
        guard case let .noteGrid(lengthSteps, _) = normalized else {
            return nil
        }
        return lengthSteps
    }

    var noteGridSteps: [ClipStep]? {
        guard case let .noteGrid(_, steps) = normalized else {
            return nil
        }
        return steps
    }

    func noteGridStep(at stepIndex: Int) -> ClipStep? {
        guard let lengthSteps = noteGridLengthSteps,
              let steps = noteGridSteps,
              !steps.isEmpty
        else {
            return nil
        }
        let normalizedIndex = ((stepIndex % lengthSteps) + lengthSteps) % lengthSteps
        return steps[normalizedIndex]
    }
}

extension ClipContent: Codable {
    private struct DynamicCodingKey: CodingKey {
        var stringValue: String
        var intValue: Int?

        init?(stringValue: String) {
            self.stringValue = stringValue
        }

        init?(intValue: Int) {
            self.stringValue = String(intValue)
            self.intValue = intValue
        }

        init(_ stringValue: String) {
            self.stringValue = stringValue
            self.intValue = nil
        }
    }

    private enum NoteGridCodingKeys: String, CodingKey {
        case lengthSteps
        case steps
    }

    private enum StepSequenceCodingKeys: String, CodingKey {
        case stepPattern
        case pitches
    }

    private enum PianoRollCodingKeys: String, CodingKey {
        case lengthBars
        case stepsPerBar
        case notes
    }

    private enum SliceTriggersCodingKeys: String, CodingKey {
        case stepPattern
        case sliceIndexes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        guard let key = container.allKeys.first else {
            self = .emptyNoteGrid(lengthSteps: 16)
            return
        }

        switch key.stringValue {
        case "noteGrid":
            let nested = try container.nestedContainer(keyedBy: NoteGridCodingKeys.self, forKey: key)
            self = .noteGrid(
                lengthSteps: try nested.decode(Int.self, forKey: .lengthSteps),
                steps: try nested.decode([ClipStep].self, forKey: .steps)
            ).normalized
        case "stepSequence":
            let nested = try container.nestedContainer(keyedBy: StepSequenceCodingKeys.self, forKey: key)
            self = ClipContent.stepSequence(
                stepPattern: try nested.decode([Bool].self, forKey: .stepPattern),
                pitches: try nested.decode([Int].self, forKey: .pitches)
            ).normalized
        case "pianoRoll":
            let nested = try container.nestedContainer(keyedBy: PianoRollCodingKeys.self, forKey: key)
            self = ClipContent.pianoRoll(
                lengthBars: try nested.decode(Int.self, forKey: .lengthBars),
                stepsPerBar: try nested.decode(Int.self, forKey: .stepsPerBar),
                notes: try nested.decode([ClipNote].self, forKey: .notes)
            ).normalized
        case "sliceTriggers":
            let nested = try container.nestedContainer(keyedBy: SliceTriggersCodingKeys.self, forKey: key)
            self = ClipContent.sliceTriggers(
                stepPattern: try nested.decode([Bool].self, forKey: .stepPattern),
                sliceIndexes: try nested.decode([Int].self, forKey: .sliceIndexes)
            ).normalized
        default:
            throw DecodingError.dataCorruptedError(
                forKey: key,
                in: container,
                debugDescription: "Unsupported ClipContent case: \(key.stringValue)"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: DynamicCodingKey.self)

        switch normalized {
        case let .noteGrid(lengthSteps, steps):
            var nested = container.nestedContainer(keyedBy: NoteGridCodingKeys.self, forKey: DynamicCodingKey("noteGrid"))
            try nested.encode(lengthSteps, forKey: .lengthSteps)
            try nested.encode(steps, forKey: .steps)
        case let .sliceTriggers(stepPattern, sliceIndexes):
            var nested = container.nestedContainer(keyedBy: SliceTriggersCodingKeys.self, forKey: DynamicCodingKey("sliceTriggers"))
            try nested.encode(stepPattern, forKey: .stepPattern)
            try nested.encode(sliceIndexes, forKey: .sliceIndexes)
        }
    }
}
