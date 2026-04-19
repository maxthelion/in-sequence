import Foundation

enum PickMode: String, Codable, Equatable, Hashable, Sendable {
    case sequential
    case random
}

enum HoldMode: String, Codable, Equatable, Hashable, Sendable {
    case pool
    case latest
}

enum PitchAlgo: Codable, Equatable, Hashable, Sendable {
    case manual(pitches: [Int], pickMode: PickMode)
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
