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

enum SliceTriggerStepMode: String, Codable, Equatable, Hashable, Sendable, CaseIterable {
    case single
    case runFromHere
}

struct SliceTriggerStepParameters: Codable, Equatable, Hashable, Sendable {
    var gain: Double
    var pitch: Double
    var startTrim: Double
    var endTrim: Double
    var pan: Double
    var filter: Double
    var attackMs: Double
    var releaseMs: Double
    var reverse: Bool
    var choke: Bool

    init(
        gain: Double = 0,
        pitch: Double = 0,
        startTrim: Double = 0,
        endTrim: Double = 0,
        pan: Double = 0,
        filter: Double = 1,
        attackMs: Double = 0,
        releaseMs: Double = 0,
        reverse: Bool = false,
        choke: Bool = true
    ) {
        self.gain = gain
        self.pitch = pitch
        self.startTrim = startTrim
        self.endTrim = endTrim
        self.pan = pan
        self.filter = filter
        self.attackMs = attackMs
        self.releaseMs = releaseMs
        self.reverse = reverse
        self.choke = choke
    }

    static let `default` = SliceTriggerStepParameters()

    var clamped: SliceTriggerStepParameters {
        SliceTriggerStepParameters(
            gain: min(max(gain, -24), 12),
            pitch: min(max(pitch, -12), 12),
            startTrim: min(max(startTrim, 0), 0.99),
            endTrim: min(max(endTrim, 0), 0.99),
            pan: min(max(pan, -1), 1),
            filter: min(max(filter, 0), 1),
            attackMs: min(max(attackMs, 0), 100),
            releaseMs: min(max(releaseMs, 0), 200),
            reverse: reverse,
            choke: choke
        )
    }

    private enum CodingKeys: String, CodingKey {
        case gain
        case pitch
        case startTrim
        case endTrim
        case pan
        case filter
        case attackMs
        case releaseMs
        case reverse
        case choke
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        gain = try container.decodeIfPresent(Double.self, forKey: .gain) ?? 0
        pitch = try container.decodeIfPresent(Double.self, forKey: .pitch) ?? 0
        startTrim = try container.decodeIfPresent(Double.self, forKey: .startTrim) ?? 0
        endTrim = try container.decodeIfPresent(Double.self, forKey: .endTrim) ?? 0
        pan = try container.decodeIfPresent(Double.self, forKey: .pan) ?? 0
        filter = try container.decodeIfPresent(Double.self, forKey: .filter) ?? 1
        attackMs = try container.decodeIfPresent(Double.self, forKey: .attackMs) ?? 0
        releaseMs = try container.decodeIfPresent(Double.self, forKey: .releaseMs) ?? 0
        reverse = try container.decodeIfPresent(Bool.self, forKey: .reverse) ?? false
        choke = try container.decodeIfPresent(Bool.self, forKey: .choke) ?? true
    }
}

enum ClipContent: Equatable, Hashable, Sendable {
    case noteGrid(lengthSteps: Int, steps: [ClipStep])
    case sliceTriggers(
        stepPattern: [Bool],
        sliceIndexes: [Int],
        stepModes: [SliceTriggerStepMode],
        stepParameters: [SliceTriggerStepParameters] = []
    )

    /// Number of steps in the clip — used to size macro lane values arrays.
    var stepCount: Int {
        switch self {
        case let .noteGrid(lengthSteps, _):
            return max(1, lengthSteps)
        case let .sliceTriggers(stepPattern, _, _, _):
            return max(1, stepPattern.count)
        }
    }
}

extension ClipContent {
    static func emptyNoteGrid(lengthSteps: Int) -> ClipContent {
        let resolvedLength = max(1, lengthSteps)
        return .noteGrid(
            lengthSteps: resolvedLength,
            steps: Array(repeating: .empty, count: resolvedLength)
        )
    }

    static func emptySliceTriggers(lengthSteps: Int) -> ClipContent {
        let resolvedLength = max(1, lengthSteps)
        return .sliceTriggers(
            stepPattern: Array(repeating: false, count: resolvedLength),
            sliceIndexes: Array(repeating: 0, count: resolvedLength),
            stepModes: Array(repeating: .single, count: resolvedLength),
            stepParameters: Array(repeating: .default, count: resolvedLength)
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
        case let .sliceTriggers(stepPattern, _, _, _):
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
        case let .sliceTriggers(stepPattern, sliceIndexes, stepModes, stepParameters):
            let resolvedPattern = stepPattern.isEmpty ? [false] : stepPattern
            let resolvedIndexes = Self.syncedSliceIndexes(sliceIndexes, stepCount: resolvedPattern.count)
            let resolvedModes = Self.syncedSliceModes(stepModes, stepCount: resolvedPattern.count)
            let resolvedParameters = Self.syncedSliceParameters(stepParameters, stepCount: resolvedPattern.count)
            return .sliceTriggers(
                stepPattern: resolvedPattern,
                sliceIndexes: resolvedIndexes,
                stepModes: resolvedModes,
                stepParameters: resolvedParameters
            )
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
        case stepModes
        case stepParameters
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
                sliceIndexes: try nested.decode([Int].self, forKey: .sliceIndexes),
                stepModes: try nested.decodeIfPresent([SliceTriggerStepMode].self, forKey: .stepModes) ?? [],
                stepParameters: try nested.decodeIfPresent([SliceTriggerStepParameters].self, forKey: .stepParameters) ?? []
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
        case let .sliceTriggers(stepPattern, sliceIndexes, stepModes, stepParameters):
            var nested = container.nestedContainer(keyedBy: SliceTriggersCodingKeys.self, forKey: DynamicCodingKey("sliceTriggers"))
            try nested.encode(stepPattern, forKey: .stepPattern)
            try nested.encode(sliceIndexes, forKey: .sliceIndexes)
            try nested.encode(stepModes, forKey: .stepModes)
            try nested.encode(stepParameters, forKey: .stepParameters)
        }
    }

    private static func syncedSliceIndexes(_ indexes: [Int], stepCount: Int) -> [Int] {
        let count = max(1, stepCount)
        if indexes.count == count { return indexes.map { max(0, $0) } }
        if indexes.count < count {
            return (indexes + Array(repeating: 0, count: count - indexes.count)).map { max(0, $0) }
        }
        return Array(indexes.prefix(count)).map { max(0, $0) }
    }

    private static func syncedSliceModes(_ modes: [SliceTriggerStepMode], stepCount: Int) -> [SliceTriggerStepMode] {
        let count = max(1, stepCount)
        if modes.count == count { return modes }
        if modes.count < count {
            return modes + Array(repeating: .single, count: count - modes.count)
        }
        return Array(modes.prefix(count))
    }

    private static func syncedSliceParameters(
        _ parameters: [SliceTriggerStepParameters],
        stepCount: Int
    ) -> [SliceTriggerStepParameters] {
        let count = max(1, stepCount)
        let clamped = parameters.map(\.clamped)
        if clamped.count == count { return clamped }
        if clamped.count < count {
            return clamped + Array(repeating: .default, count: count - clamped.count)
        }
        return Array(clamped.prefix(count))
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
