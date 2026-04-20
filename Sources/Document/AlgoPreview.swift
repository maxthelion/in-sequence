import Foundation

// Preview-only dry run of step/pitch algos. DUPLICATES ENGINE LOGIC — keep in sync with Sources/Engine/Blocks/*. Tracked for consolidation in a follow-up plan.

struct PreviewRNG: RandomNumberGenerator {
    private var state: UInt64 = 0x5EEDC0DE

    mutating func next() -> UInt64 {
        state = 2862933555777941757 &* state &+ 3037000493
        return state
    }
}

func previewSteps(for params: GeneratorParams, clipChoices: [ClipPoolEntry], count: Int = 16) -> [[String]] {
    var rng = PreviewRNG()

    switch params {
    case let .mono(step, pitch, _):
        var lastPitch: Int?
        return (0..<count).map { stepIndex in
            guard stepFiresPreview(step, stepIndex: stepIndex, clipChoices: clipChoices, rng: &rng) else {
                return []
            }
            let picked = pickPitchPreview(pitch, stepIndex: stepIndex, lastPitch: lastPitch, clipChoices: clipChoices, rng: &rng)
            lastPitch = picked
            return ["\(picked)"]
        }
    case let .poly(step, pitches, _):
        return (0..<count).map { stepIndex in
            guard stepFiresPreview(step, stepIndex: stepIndex, clipChoices: clipChoices, rng: &rng) else {
                return []
            }
            return pitches.map { "\(pickPitchPreview($0, stepIndex: stepIndex, lastPitch: nil, clipChoices: clipChoices, rng: &rng))" }
        }
    case let .drum(steps, _):
        let keys = steps.keys.sorted()
        return (0..<count).map { stepIndex in
            keys.compactMap { key in
                guard let step = steps[key],
                      stepFiresPreview(step, stepIndex: stepIndex, clipChoices: clipChoices, rng: &rng) else {
                    return nil
                }
                return key
            }
        }
    case .template:
        return Array(repeating: ["Template"], count: count)
    case let .slice(step, sliceIndexes):
        let slices = sliceIndexes.isEmpty ? [0] : sliceIndexes
        var nextSlice = 0
        return (0..<count).map { stepIndex in
            guard stepFiresPreview(step, stepIndex: stepIndex, clipChoices: clipChoices, rng: &rng) else {
                return []
            }
            let label = "S\(slices[nextSlice % slices.count])"
            nextSlice += 1
            return [label]
        }
    }
}

func stepFiresPreview<R: RandomNumberGenerator>(_ step: StepAlgo, stepIndex: Int, clipChoices: [ClipPoolEntry], rng: inout R) -> Bool {
    switch step {
    case let .fromClipSteps(clipID):
        guard let clip = clipChoices.first(where: { $0.id == clipID }) else { return false }
        switch clip.content {
        case let .stepSequence(stepPattern, _):
            return stepPattern[stepIndex % max(1, stepPattern.count)]
        case let .pianoRoll(_, _, notes):
            return notes.contains(where: { $0.startStep == stepIndex })
        case let .sliceTriggers(stepPattern, _):
            return stepPattern[stepIndex % max(1, stepPattern.count)]
        }
    default:
        return step.fires(at: stepIndex, totalSteps: 16, rng: &rng)
    }
}

func pickPitchPreview<R: RandomNumberGenerator>(_ pitch: PitchAlgo, stepIndex: Int, lastPitch: Int?, clipChoices: [ClipPoolEntry], rng: inout R) -> Int {
    switch pitch {
    case let .fromClipPitches(clipID, pickMode):
        guard let clip = clipChoices.first(where: { $0.id == clipID }) else { return 60 }
        let pitches = clipPitches(for: clip)
        guard !pitches.isEmpty else { return 60 }
        switch pickMode {
        case .sequential:
            return pitches[stepIndex % pitches.count]
        case .random:
            return pitches.randomElement(using: &rng) ?? 60
        }
    case .external:
        return 60
    default:
        return pitch.pick(
            context: PitchContext(lastPitch: lastPitch, scaleRoot: 60, scaleID: .major, currentChord: nil, stepIndex: stepIndex),
            rng: &rng
        )
    }
}

func clipPitches(for clip: ClipPoolEntry) -> [Int] {
    switch clip.content {
    case let .stepSequence(_, pitches):
        return pitches
    case let .pianoRoll(_, _, notes):
        return Array(Set(notes.map(\.pitch))).sorted()
    case .sliceTriggers:
        return [60]
    }
}
