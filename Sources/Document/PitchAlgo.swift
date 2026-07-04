import Foundation

enum PickMode: String, Codable, Equatable, Hashable, Sendable {
    case sequential
    case random
}

enum HoldMode: String, Codable, Equatable, Hashable, Sendable {
    case pool
    case latest
}

struct PitchSelectionSettings: Codable, Equatable, Hashable, Sendable {
    /// -1 is uniform, 0 is balanced, 1 is closest-to-last memory.
    var memory: Double

    static let uniform = PitchSelectionSettings(memory: -1)
    static let balanced = PitchSelectionSettings(memory: 0)
    static let lastNote = PitchSelectionSettings(memory: 1)

    var normalized: PitchSelectionSettings {
        PitchSelectionSettings(memory: min(max(memory, -1), 1))
    }
}

struct PitchDeviationSettings: Codable, Equatable, Hashable, Sendable {
    var accidentalChance: Double
    var octaveSpan: Int
    var leadingChance: Double

    static let none = PitchDeviationSettings(accidentalChance: 0, octaveSpan: 0, leadingChance: 0)

    var normalized: PitchDeviationSettings {
        PitchDeviationSettings(
            accidentalChance: min(max(accidentalChance, 0), 1),
            octaveSpan: min(max(octaveSpan, 0), 3),
            leadingChance: min(max(leadingChance, 0), 1)
        )
    }
}

enum PitchAlgo: Codable, Equatable, Hashable, Sendable {
    case manual(pitches: [Int], pickMode: PickMode)
    case pool(root: Int, scale: ScaleID, spread: Int, selection: PitchSelectionSettings, deviation: PitchDeviationSettings)
    case randomInScale(root: Int, scale: ScaleID, spread: Int)
    case randomInChord(root: Int, chord: ChordID, inverted: Bool, spread: Int)
    case intervalProb(root: Int, scale: ScaleID, degreeWeights: [Double])
    case markov(root: Int, scale: ScaleID, styleID: StyleProfileID, leap: Double, color: Double)
    case fromClipPitches(clipID: UUID, pickMode: PickMode)
    case external(port: String, channel: Int, holdMode: HoldMode)

    func pick<R: RandomNumberGenerator>(
        context: PitchContext,
        rng: inout R
    ) -> Int {
        switch self {
        case let .manual(pitches, pickMode):
            guard !pitches.isEmpty else {
                return context.scaleRoot
            }

            switch pickMode {
            case .sequential:
                let index = positiveModulo(context.stepIndex, pitches.count)
                return pitches[index]
            case .random:
                return pitches.randomElement(using: &rng) ?? context.scaleRoot
            }

        case let .pool(root, scale, spread, selection, deviation):
            return pickFromPool(
                root: root,
                scaleID: scale,
                spread: spread,
                selection: selection.normalized,
                deviation: deviation.normalized,
                context: context,
                rng: &rng
            )

        case let .randomInScale(root, scale, spread):
            let pool = scalePool(root: root, scaleID: scale, spread: spread)
            return pool.randomElement(using: &rng) ?? context.scaleRoot

        case let .randomInChord(root, chord, inverted, spread):
            let pool = chordPool(root: root, chordID: chord, inverted: inverted, spread: spread)
            return pool.randomElement(using: &rng) ?? context.scaleRoot

        case let .intervalProb(root, scale, degreeWeights):
            guard let scale = Scale.for(id: scale), !scale.intervals.isEmpty else {
                return context.scaleRoot
            }

            let weights = alignedWeights(degreeWeights, count: scale.intervals.count)
            guard let degreeIndex = weightedIndex(from: weights, rng: &rng) else {
                return root
            }
            return root + scale.intervals[degreeIndex]

        case let .markov(root, scaleID, styleID, leap, color):
            let pool = scalePool(root: root, scaleID: scaleID, spread: 24)
            guard !pool.isEmpty else {
                return context.scaleRoot
            }

            guard let style = StyleProfile.for(id: styleID), let lastPitch = context.lastPitch else {
                return pool.randomElement(using: &rng) ?? context.scaleRoot
            }

            let lastScaleStep = scaleStepIndex(of: lastPitch, root: root, scaleID: scaleID)
            let baseCandidates = pool.filter { $0 != lastPitch }

            var weightedCandidates: [(pitch: Int, weight: Double)] = pool.map { candidate in
                let distance = scaleStepDistance(
                    from: lastPitch,
                    to: candidate,
                    lastScaleStep: lastScaleStep,
                    root: root,
                    scaleID: scaleID
                )
                let baseWeight = baseDistanceWeight(distance: distance, style: style)
                let directionBias = directionMultiplier(candidate: candidate, relativeTo: lastPitch, style: style)
                let leapMultiplier = leapMultiplier(distance: distance, leap: leap, style: style)
                return (candidate, baseWeight * directionBias * leapMultiplier)
            }

            if color > 0, let baseCandidate = baseCandidates.randomElement(using: &rng) {
                let direction = baseCandidate >= lastPitch ? 1 : -1
                let chromaticCandidate = min(max(baseCandidate + direction, 0), 127)
                if !pool.contains(chromaticCandidate) {
                    weightedCandidates.append((chromaticCandidate, min(max(color, 0), 1)))
                }
            }

            let weights = weightedCandidates.map(\.weight)
            guard let candidateIndex = weightedIndex(from: weights, rng: &rng) else {
                return context.scaleRoot
            }
            return weightedCandidates[candidateIndex].pitch

        case .fromClipPitches, .external:
            return context.scaleRoot
        }
    }
}

extension PitchAlgo {
    var normalizedForPitchGrammar: PitchAlgo {
        let defaultPool = PitchStage.defaultMono.algo

        switch self {
        case let .pool(root, scale, spread, selection, deviation):
            return .pool(
                root: root,
                scale: scale,
                spread: spread,
                selection: selection.normalized,
                deviation: deviation.normalized
            )
        case let .randomInScale(root, scale, spread):
            return .pool(
                root: root,
                scale: scale,
                spread: spread,
                selection: .balanced,
                deviation: .none
            )
        case let .intervalProb(root, scale, _),
             let .markov(root, scale, _, _, _):
            return .pool(
                root: root,
                scale: scale,
                spread: 12,
                selection: .balanced,
                deviation: .none
            )
        case let .randomInChord(root, _, _, spread):
            return .pool(
                root: root,
                scale: .major,
                spread: spread,
                selection: .balanced,
                deviation: .none
            )
        case .manual, .fromClipPitches, .external:
            return defaultPool
        }
    }
}

private func pickFromPool<R: RandomNumberGenerator>(
    root: Int,
    scaleID: ScaleID,
    spread: Int,
    selection: PitchSelectionSettings,
    deviation: PitchDeviationSettings,
    context: PitchContext,
    rng: inout R
) -> Int {
    // POOL = scale INTERSECT chord filter (synthesis vocabulary): a chord
    // sidechain narrows the available notes to chord tones; it never adds
    // notes and never touches triggers. When the intersection would be empty
    // the scale pool stands (a filter cannot silence the pitch stage).
    var pool = scalePool(root: root, scaleID: scaleID, spread: spread)
    if let chord = context.currentChord,
       let chordID = ChordID(rawValue: chord.chordType),
       let definition = ChordDefinition.for(id: chordID)
    {
        let chordClasses = Set(definition.intervals.map { positiveModulo(Int(chord.root) + $0, 12) })
        let filtered = pool.filter { chordClasses.contains(positiveModulo($0, 12)) }
        if !filtered.isEmpty {
            pool = filtered
        }
    }
    guard !pool.isEmpty else {
        return context.scaleRoot
    }

    // Sequence-aware chromatic leading (synthesis vocabulary: approach tones
    // RESOLVE stepwise into a pool note): when the previous emitted pitch was
    // an out-of-pool approach tone, this step resolves into the adjacent pool
    // note instead of making a fresh pick.
    if deviation.leadingChance > 0,
       let last = context.lastPitch,
       !pool.contains(last),
       let resolution = nearestPoolPitch(to: last, in: pool),
       abs(resolution - last) == 1
    {
        return resolution
    }

    var picked = poolWeightedByMemory(pool: pool, lastPitch: context.lastPitch, memory: selection.memory, rng: &rng)

    if deviation.octaveSpan > 0 {
        let octaveOffsets = (-deviation.octaveSpan...deviation.octaveSpan).map { $0 * 12 }
        let candidates = octaveOffsets
            .map { picked + $0 }
            .filter { (0...127).contains($0) }
        if let candidate = candidates.randomElement(using: &rng) {
            picked = candidate
        }
    }

    if deviation.leadingChance > 0,
       Double.random(in: 0..<1, using: &rng) < deviation.leadingChance,
       let leading = leadingTone(around: picked, pool: pool, rng: &rng)
    {
        picked = leading
    }

    if deviation.accidentalChance > 0,
       Double.random(in: 0..<1, using: &rng) < deviation.accidentalChance
    {
        let direction = Bool.random(using: &rng) ? 1 : -1
        let accidental = min(max(picked + direction, 0), 127)
        if !pool.contains(accidental) {
            picked = accidental
        }
    }

    return min(max(picked, 0), 127)
}

private func poolWeightedByMemory<R: RandomNumberGenerator>(
    pool: [Int],
    lastPitch: Int?,
    memory: Double,
    rng: inout R
) -> Int {
    guard let lastPitch, memory > 0 else {
        return pool.randomElement(using: &rng) ?? 60
    }

    let weights = pool.map { candidate -> Double in
        let distance = abs(candidate - lastPitch)
        let closeness = 1 / Double(distance + 1)
        return 1 + closeness * memory * 12
    }
    guard let index = weightedIndex(from: weights, rng: &rng) else {
        return pool.randomElement(using: &rng) ?? 60
    }
    return pool[index]
}

private func nearestPoolPitch(to pitch: Int, in pool: [Int]) -> Int? {
    pool.min { lhs, rhs in
        abs(lhs - pitch) < abs(rhs - pitch)
    }
}

private func leadingTone<R: RandomNumberGenerator>(around target: Int, pool: [Int], rng: inout R) -> Int? {
    var candidates: [Int] = []
    let lower = target - 1
    let upper = target + 1
    if lower >= 0, !pool.contains(lower) {
        candidates.append(lower)
    }
    if upper <= 127, !pool.contains(upper) {
        candidates.append(upper)
    }
    return candidates.randomElement(using: &rng)
}

private func positiveModulo(_ value: Int, _ modulus: Int) -> Int {
    ((value % modulus) + modulus) % modulus
}

private func scalePool(root: Int, scaleID: ScaleID, spread: Int) -> [Int] {
    guard let scale = Scale.for(id: scaleID) else {
        return []
    }

    let minimum = max(0, root - abs(spread))
    let maximum = min(127, root + abs(spread))
    return Array(minimum...maximum).filter { candidate in
        scale.intervals.contains(positiveModulo(candidate - root, 12))
    }
}

private func chordPool(root: Int, chordID: ChordID, inverted: Bool, spread: Int) -> [Int] {
    guard let chord = ChordDefinition.for(id: chordID) else {
        return []
    }

    var intervals = chord.intervals
    if inverted, !intervals.isEmpty {
        intervals[0] += 12
        intervals.sort()
    }

    let minimum = max(0, root - abs(spread))
    let maximum = min(127, root + abs(spread))
    var pool = Set<Int>()

    for candidate in minimum...maximum {
        let relative = candidate - root
        let pitchClass = positiveModulo(relative, 12)
        let interval = relative >= 0 ? pitchClass : relative % 12 == 0 ? 0 : pitchClass
        if intervals.map({ positiveModulo($0, 12) }).contains(interval) {
            pool.insert(candidate)
        }
    }

    return pool.sorted()
}

private func alignedWeights(_ weights: [Double], count: Int) -> [Double] {
    let normalized = Array(weights.prefix(count)).map { max($0, 0) }
    return normalized + Array(repeating: 0, count: max(0, count - normalized.count))
}

private func weightedIndex<R: RandomNumberGenerator>(
    from weights: [Double],
    rng: inout R
) -> Int? {
    let total = weights.reduce(0, +)
    guard total > 0 else {
        return nil
    }

    var threshold = Double.random(in: 0..<total, using: &rng)
    for (index, weight) in weights.enumerated() {
        threshold -= weight
        if threshold < 0 {
            return index
        }
    }

    return weights.indices.last
}

private func scaleStepIndex(of pitch: Int, root: Int, scaleID: ScaleID) -> Int? {
    guard let scale = Scale.for(id: scaleID) else {
        return nil
    }

    let relative = pitch - root
    let octave = Int(floor(Double(relative) / 12.0))
    let pitchClass = positiveModulo(relative, 12)
    guard let degreeIndex = scale.intervals.firstIndex(of: pitchClass) else {
        return nil
    }

    return octave * scale.intervals.count + degreeIndex
}

private func scaleStepDistance(
    from lastPitch: Int,
    to candidate: Int,
    lastScaleStep: Int?,
    root: Int,
    scaleID: ScaleID
) -> Int {
    if let lastScaleStep, let candidateScaleStep = scaleStepIndex(of: candidate, root: root, scaleID: scaleID) {
        return abs(candidateScaleStep - lastScaleStep)
    }

    return abs(candidate - lastPitch)
}

private func baseDistanceWeight(distance: Int, style: StyleProfile) -> Double {
    let clampedDistance = max(distance, 0)
    if clampedDistance == 0 {
        return (style.distanceWeights.first ?? 1) * style.repeatBias
    }

    if clampedDistance < style.distanceWeights.count {
        return style.distanceWeights[clampedDistance]
    }

    let tailExponent = clampedDistance - style.distanceWeights.count
    return style.tailBase * pow(style.tailDecay, Double(tailExponent))
}

private func directionMultiplier(candidate: Int, relativeTo lastPitch: Int, style: StyleProfile) -> Double {
    if candidate > lastPitch {
        return style.ascendBias
    }
    if candidate < lastPitch {
        return style.descendBias
    }
    return style.repeatBias
}

private func leapMultiplier(distance: Int, leap: Double, style: StyleProfile) -> Double {
    guard distance >= 3 else {
        return 1
    }

    let normalizedLeap = min(max(leap, 0), 1)
    let penalty = style.leapPenalty + normalizedLeap * (1 - style.leapPenalty)
    return penalty
}
