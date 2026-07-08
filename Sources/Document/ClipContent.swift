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

struct ClipRandomizeSettings: Codable, Equatable, Hashable, Sendable {
    var density: Double
    var scaleID: ScaleID
    var rootPitchClass: Int
    var octaveCenter: Int
    var octaveSpan: Int
    var velocityVariance: Double
    var gateVariance: Double
    var lastSeed: UInt64?

    init(
        density: Double = 0.45,
        scaleID: ScaleID = .minorPentatonic,
        rootPitchClass: Int = 0,
        octaveCenter: Int = 4,
        octaveSpan: Int = 1,
        velocityVariance: Double = 0.2,
        gateVariance: Double = 0.2,
        lastSeed: UInt64? = nil
    ) {
        self.density = min(max(density, 0), 1)
        self.scaleID = scaleID
        self.rootPitchClass = ((rootPitchClass % 12) + 12) % 12
        self.octaveCenter = min(max(octaveCenter, 0), 9)
        self.octaveSpan = min(max(octaveSpan, 0), 4)
        self.velocityVariance = min(max(velocityVariance, 0), 1)
        self.gateVariance = min(max(gateVariance, 0), 1)
        self.lastSeed = lastSeed
    }

    var normalized: ClipRandomizeSettings {
        ClipRandomizeSettings(
            density: density,
            scaleID: scaleID,
            rootPitchClass: rootPitchClass,
            octaveCenter: octaveCenter,
            octaveSpan: octaveSpan,
            velocityVariance: velocityVariance,
            gateVariance: gateVariance,
            lastSeed: lastSeed
        )
    }
}

enum ClipRandomizeBaker {
    static func bake(source: ClipContent, settings: ClipRandomizeSettings, seed: UInt64) -> ClipContent {
        let resolved = settings.normalized
        switch source.normalized {
        case let .noteGrid(lengthSteps, _):
            return .noteGrid(
                lengthSteps: lengthSteps,
                steps: (0..<lengthSteps).map { stepIndex in
                    guard fraction(seed: seed, step: stepIndex, salt: 0) < resolved.density else {
                        return .empty
                    }
                    let note = ClipStepNote(
                        pitch: pitch(settings: resolved, seed: seed, step: stepIndex),
                        velocity: velocity(settings: resolved, seed: seed, step: stepIndex),
                        lengthSteps: gateLength(settings: resolved, seed: seed, step: stepIndex)
                    )
                    return ClipStep(main: ClipLane(chance: 1, notes: [note]), fill: nil)
                }
            )
            .normalized
        case let .chordReferences(stepPattern, slotIDs, inversions, chordIDs, velocities, lengthSteps):
            let stepCount = max(1, stepPattern.count)
            let sourceSlotIDs = slotIDs.isEmpty ? Array(repeating: ChordPalette.default.slots.first?.id, count: stepCount) : slotIDs
            let bakedPattern = (0..<stepCount).map { stepIndex in
                fraction(seed: seed, step: stepIndex, salt: 0) < resolved.density
            }
            let bakedSlotIDs: [UUID?] = (0..<stepCount).map { stepIndex in
                sourceSlotIDs[index(seed: seed, step: stepIndex, salt: 1, upperBound: sourceSlotIDs.count)]
            }
            let bakedInversions = (0..<stepCount).map { stepIndex in
                inversions.indices.contains(stepIndex) ? inversions[stepIndex] : 0
            }
            let bakedVelocities = (0..<stepCount).map { stepIndex in
                velocities.indices.contains(stepIndex) ? velocities[stepIndex] : 96
            }
            let bakedLengths = (0..<stepCount).map { stepIndex in
                lengthSteps.indices.contains(stepIndex) ? lengthSteps[stepIndex] : 4
            }
            return ClipContent.chordReferences(
                stepPattern: bakedPattern,
                slotIDs: bakedSlotIDs,
                inversions: bakedInversions,
                chordIDs: chordIDs.isEmpty ? Array(repeating: nil, count: stepCount) : (0..<stepCount).map { stepIndex in
                    chordIDs.indices.contains(stepIndex) ? chordIDs[stepIndex] : nil
                },
                velocities: bakedVelocities,
                lengthSteps: bakedLengths
            )
            .normalized
        case let .sliceTriggers(stepPattern, sliceIndexes, _, _):
            let stepCount = max(1, stepPattern.count)
            let sourceIndexes = sliceIndexes.isEmpty ? [0] : sliceIndexes.map { max(0, $0) }
            let bakedPattern = (0..<stepCount).map { stepIndex in
                fraction(seed: seed, step: stepIndex, salt: 0) < resolved.density
            }
            let bakedIndexes = (0..<stepCount).map { stepIndex in
                sourceIndexes[index(seed: seed, step: stepIndex, salt: 1, upperBound: sourceIndexes.count)]
            }
            return .sliceTriggers(
                stepPattern: bakedPattern,
                sliceIndexes: bakedIndexes,
                stepModes: Array(repeating: .single, count: stepCount),
                stepParameters: Array(repeating: .default, count: stepCount)
            )
            .normalized
        }
    }

    private static func pitch(settings: ClipRandomizeSettings, seed: UInt64, step: Int) -> Int {
        let scale = Scales.table[settings.scaleID] ?? Scales.table[.minorPentatonic]
        let intervals = {
            guard let scale, !scale.intervals.isEmpty else { return [0] }
            return scale.intervals
        }()
        var pool: [Int] = []
        let lowOctave = max(0, settings.octaveCenter - settings.octaveSpan)
        let highOctave = min(9, settings.octaveCenter + settings.octaveSpan)
        for octave in lowOctave...highOctave {
            let octaveBase = (octave + 1) * 12
            for interval in intervals {
                let midiNote = octaveBase + settings.rootPitchClass + interval
                if (0...127).contains(midiNote) {
                    pool.append(midiNote)
                }
            }
        }
        guard !pool.isEmpty else { return 60 }
        return pool[index(seed: seed, step: step, salt: 2, upperBound: pool.count)]
    }

    private static func velocity(settings: ClipRandomizeSettings, seed: UInt64, step: Int) -> Int {
        let variance = Int((settings.velocityVariance * 32).rounded())
        guard variance > 0 else { return 96 }
        let offset = index(seed: seed, step: step, salt: 3, upperBound: variance * 2 + 1) - variance
        return min(max(96 + offset, 1), 127)
    }

    private static func gateLength(settings: ClipRandomizeSettings, seed: UInt64, step: Int) -> Int {
        let maxExtra = Int((settings.gateVariance * 7).rounded())
        guard maxExtra > 0 else { return 1 }
        return 1 + index(seed: seed, step: step, salt: 4, upperBound: maxExtra + 1)
    }

    private static func fraction(seed: UInt64, step: Int, salt: UInt64) -> Double {
        let value = hash(seed: seed, step: step, salt: salt)
        return Double(value >> 11) / Double(1 << 53)
    }

    private static func index(seed: UInt64, step: Int, salt: UInt64, upperBound: Int) -> Int {
        guard upperBound > 1 else { return 0 }
        return Int(hash(seed: seed, step: step, salt: salt) % UInt64(upperBound))
    }

    private static func hash(seed: UInt64, step: Int, salt: UInt64) -> UInt64 {
        var value = seed
        value &+= UInt64(truncatingIfNeeded: step) &* 0x9E3779B97F4A7C15
        value &+= salt &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
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

struct SliceTriggerStep: Equatable, Hashable, Sendable {
    var isOn: Bool
    var sliceIndex: Int
    var mode: SliceTriggerStepMode
    var parameters: SliceTriggerStepParameters

    init(
        isOn: Bool = false,
        sliceIndex: Int = 0,
        mode: SliceTriggerStepMode = .single,
        parameters: SliceTriggerStepParameters = .default
    ) {
        self.isOn = isOn
        self.sliceIndex = max(0, sliceIndex)
        self.mode = mode
        self.parameters = parameters.clamped
    }
}

struct SliceTriggerSteps: Equatable, Sendable {
    var steps: [SliceTriggerStep]

    init(steps: [SliceTriggerStep]) {
        self.steps = steps.isEmpty ? [SliceTriggerStep()] : steps
    }

    init(
        stepPattern: [Bool],
        sliceIndexes: [Int],
        stepModes: [SliceTriggerStepMode],
        stepParameters: [SliceTriggerStepParameters],
        defaultSliceIndex: Int = 0
    ) {
        let count = max(1, stepPattern.count)
        let fallbackIndex = max(0, defaultSliceIndex)
        steps = (0..<count).map { index in
            SliceTriggerStep(
                isOn: stepPattern.indices.contains(index) ? stepPattern[index] : false,
                sliceIndex: sliceIndexes.indices.contains(index) ? sliceIndexes[index] : fallbackIndex,
                mode: stepModes.indices.contains(index) ? stepModes[index] : .single,
                parameters: stepParameters.indices.contains(index) ? stepParameters[index] : .default
            )
        }
    }

    var count: Int { steps.count }

    var stepPattern: [Bool] { steps.map(\.isOn) }
    var sliceIndexes: [Int] { steps.map(\.sliceIndex) }
    var stepModes: [SliceTriggerStepMode] { steps.map(\.mode) }
    var stepParameters: [SliceTriggerStepParameters] { steps.map(\.parameters) }

    func resized(to stepCount: Int, defaultSliceIndex: Int = 0) -> SliceTriggerSteps {
        let resolvedCount = max(1, stepCount)
        if steps.count == resolvedCount {
            return self
        }
        if steps.count > resolvedCount {
            return SliceTriggerSteps(steps: Array(steps.prefix(resolvedCount)))
        }
        let padding = Array(
            repeating: SliceTriggerStep(sliceIndex: defaultSliceIndex),
            count: resolvedCount - steps.count
        )
        return SliceTriggerSteps(steps: steps + padding)
    }

    subscript(index: Int) -> SliceTriggerStep? {
        get {
            guard steps.indices.contains(index) else { return nil }
            return steps[index]
        }
        set {
            guard steps.indices.contains(index), let newValue else { return }
            steps[index] = newValue
        }
    }

    mutating func toggleStep(at index: Int, defaultSliceIndex: Int, selectedSliceIndex: Int) {
        guard steps.indices.contains(index) else { return }
        steps[index].isOn.toggle()
        if steps[index].isOn {
            steps[index].sliceIndex = max(defaultSliceIndex, selectedSliceIndex)
        }
    }

    mutating func assignSliceIndex(_ sliceIndex: Int, at index: Int) {
        guard steps.indices.contains(index) else { return }
        steps[index].sliceIndex = max(0, sliceIndex)
        steps[index].isOn = true
    }

    mutating func assignMode(_ mode: SliceTriggerStepMode, at index: Int) {
        guard steps.indices.contains(index) else { return }
        steps[index].mode = mode
    }

    mutating func assignParameters(_ parameters: SliceTriggerStepParameters, at index: Int) {
        guard steps.indices.contains(index) else { return }
        steps[index].parameters = parameters.clamped
    }
}

enum ClipContent: Equatable, Hashable, Sendable {
    case noteGrid(lengthSteps: Int, steps: [ClipStep])
    case chordReferences(
        stepPattern: [Bool],
        slotIDs: [UUID?],
        inversions: [Int],
        chordIDs: [ChordID?],
        velocities: [Int],
        lengthSteps: [Int]
    )
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
        case let .chordReferences(stepPattern, _, _, _, _, _):
            return max(1, stepPattern.count)
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

    static func emptyChordReferences(lengthSteps: Int, defaultSlotID: UUID? = ChordPalette.default.slots.first?.id) -> ClipContent {
        let resolvedLength = max(1, lengthSteps)
        return .chordReferences(
            stepPattern: Array(repeating: false, count: resolvedLength),
            slotIDs: Array(repeating: defaultSlotID, count: resolvedLength),
            inversions: Array(repeating: 0, count: resolvedLength),
            chordIDs: Array(repeating: nil, count: resolvedLength),
            velocities: Array(repeating: 96, count: resolvedLength),
            lengthSteps: Array(repeating: 4, count: resolvedLength)
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
        case let .chordReferences(stepPattern, _, _, _, _, _):
            return max(1, stepPattern.count)
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
        case let .chordReferences(stepPattern, slotIDs, inversions, chordIDs, velocities, lengthSteps):
            let resolvedPattern = stepPattern.isEmpty ? [false] : stepPattern
            let count = resolvedPattern.count
            return .chordReferences(
                stepPattern: resolvedPattern,
                slotIDs: Self.syncedChordSlotIDs(slotIDs, stepCount: count),
                inversions: Self.syncedChordInversions(inversions, stepCount: count),
                chordIDs: Self.syncedChordIDs(chordIDs, stepCount: count),
                velocities: Self.syncedChordVelocities(velocities, stepCount: count),
                lengthSteps: Self.syncedChordLengths(lengthSteps, stepCount: count)
            )
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

    func resolvedChordNoteGrid(palette: ChordPalette) -> ClipContent {
        switch normalized {
        case let .chordReferences(stepPattern, slotIDs, inversions, chordIDs, velocities, lengthSteps):
            let steps = stepPattern.indices.map { index -> ClipStep in
                guard stepPattern[index] else { return .empty }
                let pitches = palette.normalized.voicedPitches(
                    slotID: slotIDs.indices.contains(index) ? slotIDs[index] : nil,
                    inversion: inversions.indices.contains(index) ? inversions[index] : 0,
                    chordIDOverride: chordIDs.indices.contains(index) ? chordIDs[index] : nil
                )
                guard !pitches.isEmpty else { return .empty }
                let velocity = velocities.indices.contains(index) ? velocities[index] : 96
                let length = lengthSteps.indices.contains(index) ? lengthSteps[index] : 4
                return ClipStep(
                    main: ClipLane(
                        chance: 1,
                        notes: pitches.map {
                            ClipStepNote(pitch: $0, velocity: velocity, lengthSteps: length).normalized
                        }
                    ),
                    fill: nil
                )
            }
            return ClipContent.noteGrid(lengthSteps: max(1, stepPattern.count), steps: steps).normalized
        case .noteGrid, .sliceTriggers:
            return normalized
        }
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

    private enum ChordReferencesCodingKeys: String, CodingKey {
        case stepPattern
        case slotIDs
        case inversions
        case chordIDs
        case velocities
        case lengthSteps
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
        case "chordReferences":
            let nested = try container.nestedContainer(keyedBy: ChordReferencesCodingKeys.self, forKey: key)
            self = ClipContent.chordReferences(
                stepPattern: try nested.decode([Bool].self, forKey: .stepPattern),
                slotIDs: try nested.decodeIfPresent([UUID?].self, forKey: .slotIDs) ?? [],
                inversions: try nested.decodeIfPresent([Int].self, forKey: .inversions) ?? [],
                chordIDs: try nested.decodeIfPresent([ChordID?].self, forKey: .chordIDs) ?? [],
                velocities: try nested.decodeIfPresent([Int].self, forKey: .velocities) ?? [],
                lengthSteps: try nested.decodeIfPresent([Int].self, forKey: .lengthSteps) ?? []
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
        case let .chordReferences(stepPattern, slotIDs, inversions, chordIDs, velocities, lengthSteps):
            var nested = container.nestedContainer(keyedBy: ChordReferencesCodingKeys.self, forKey: DynamicCodingKey("chordReferences"))
            try nested.encode(stepPattern, forKey: .stepPattern)
            try nested.encode(slotIDs, forKey: .slotIDs)
            try nested.encode(inversions, forKey: .inversions)
            try nested.encode(chordIDs, forKey: .chordIDs)
            try nested.encode(velocities, forKey: .velocities)
            try nested.encode(lengthSteps, forKey: .lengthSteps)
        case let .sliceTriggers(stepPattern, sliceIndexes, stepModes, stepParameters):
            var nested = container.nestedContainer(keyedBy: SliceTriggersCodingKeys.self, forKey: DynamicCodingKey("sliceTriggers"))
            try nested.encode(stepPattern, forKey: .stepPattern)
            try nested.encode(sliceIndexes, forKey: .sliceIndexes)
            try nested.encode(stepModes, forKey: .stepModes)
            try nested.encode(stepParameters, forKey: .stepParameters)
        }
    }

    private static func syncedChordSlotIDs(_ slotIDs: [UUID?], stepCount: Int) -> [UUID?] {
        let count = max(1, stepCount)
        if slotIDs.count == count { return slotIDs }
        if slotIDs.count < count {
            let fallback = slotIDs.first ?? ChordPalette.default.slots.first?.id
            return slotIDs + Array(repeating: fallback, count: count - slotIDs.count)
        }
        return Array(slotIDs.prefix(count))
    }

    private static func syncedChordInversions(_ inversions: [Int], stepCount: Int) -> [Int] {
        let count = max(1, stepCount)
        let clamped = inversions.map { min(max($0, -4), 4) }
        if clamped.count == count { return clamped }
        if clamped.count < count {
            return clamped + Array(repeating: 0, count: count - clamped.count)
        }
        return Array(clamped.prefix(count))
    }

    private static func syncedChordIDs(_ chordIDs: [ChordID?], stepCount: Int) -> [ChordID?] {
        let count = max(1, stepCount)
        if chordIDs.count == count { return chordIDs }
        if chordIDs.count < count {
            return chordIDs + Array(repeating: nil, count: count - chordIDs.count)
        }
        return Array(chordIDs.prefix(count))
    }

    private static func syncedChordVelocities(_ velocities: [Int], stepCount: Int) -> [Int] {
        let count = max(1, stepCount)
        let clamped = velocities.map { min(max($0, 1), 127) }
        if clamped.count == count { return clamped }
        if clamped.count < count {
            return clamped + Array(repeating: 96, count: count - clamped.count)
        }
        return Array(clamped.prefix(count))
    }

    private static func syncedChordLengths(_ lengths: [Int], stepCount: Int) -> [Int] {
        let count = max(1, stepCount)
        let clamped = lengths.map { max(1, $0) }
        if clamped.count == count { return clamped }
        if clamped.count < count {
            return clamped + Array(repeating: 4, count: count - clamped.count)
        }
        return Array(clamped.prefix(count))
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
