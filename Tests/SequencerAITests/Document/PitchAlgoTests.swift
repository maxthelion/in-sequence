import Foundation
import XCTest
@testable import SequencerAI

final class PitchAlgoTests: XCTestCase {
    func test_manual_sequential_cycles_through_pitches() {
        let algo = PitchAlgo.manual(pitches: [60, 62, 64], pickMode: .sequential)
        var rng = SplitMix64(seed: 10)

        XCTAssertEqual(algo.pick(context: context(stepIndex: 0), rng: &rng), 60)
        XCTAssertEqual(algo.pick(context: context(stepIndex: 1), rng: &rng), 62)
        XCTAssertEqual(algo.pick(context: context(stepIndex: 2), rng: &rng), 64)
        XCTAssertEqual(algo.pick(context: context(stepIndex: 3), rng: &rng), 60)
    }

    func test_manual_random_emits_both_values_regularly() {
        let algo = PitchAlgo.manual(pitches: [60, 62], pickMode: .random)
        var rng = SplitMix64(seed: 11)

        let picks = (0..<1_000).map { _ in algo.pick(context: context(), rng: &rng) }
        XCTAssertGreaterThanOrEqual(picks.filter { $0 == 60 }.count, 400)
        XCTAssertGreaterThanOrEqual(picks.filter { $0 == 62 }.count, 400)
    }

    func test_manual_random_falls_back_to_scale_root_when_empty() {
        let algo = PitchAlgo.manual(pitches: [], pickMode: .random)
        var rng = SplitMix64(seed: 12)

        XCTAssertEqual(algo.pick(context: context(scaleRoot: 65), rng: &rng), 65)
    }

    func test_random_in_scale_stays_inside_scale_and_spread() {
        let algo = PitchAlgo.randomInScale(root: 60, scale: .major, spread: 12)
        var rng = SplitMix64(seed: 13)

        let results = (0..<128).map { _ in algo.pick(context: context(), rng: &rng) }
        XCTAssertTrue(results.allSatisfy { (48...72).contains($0) })
        XCTAssertTrue(results.allSatisfy { Scale.for(id: .major)?.intervals.contains(($0 - 60 + 120) % 12) == true })
    }

    func test_random_in_chord_stays_inside_chord_pool() {
        let algo = PitchAlgo.randomInChord(root: 60, chord: .majorTriad, inverted: false, spread: 12)
        var rng = SplitMix64(seed: 14)

        let allowed = Set([48, 52, 55, 60, 64, 67, 72])
        let results = (0..<128).map { _ in algo.pick(context: context(), rng: &rng) }
        XCTAssertTrue(results.allSatisfy { allowed.contains($0) })
    }

    func test_interval_prob_can_force_specific_scale_degree() {
        let algo = PitchAlgo.intervalProb(root: 60, scale: .major, degreeWeights: [0, 0, 1, 0, 0, 0, 0])
        var rng = SplitMix64(seed: 15)

        XCTAssertEqual(algo.pick(context: context(), rng: &rng), 64)
    }

    func test_markov_distribution_tracks_style_weights() {
        let algo = PitchAlgo.markov(root: 60, scale: .major, styleID: .balanced, leap: 0, color: 0)
        let profile = StyleProfile.for(id: .balanced)!
        var rng = SplitMix64(seed: 16)

        let observedDistances = (0..<1_000).map { _ in
            algo.pick(context: context(lastPitch: 60), rng: &rng)
        }.compactMap {
            scaleStepDistance(from: 60, to: $0, root: 60, scaleID: .major)
        }

        let maxDistance = 7
        let observedDistribution = normalizedDistribution(distances: observedDistances, maxDistance: maxDistance)
        let expectedDistribution = normalizedWeights(
            (0...maxDistance).map { distance in
                if distance == 0 {
                    return profile.distanceWeights[0] * profile.repeatBias
                }
                let base = profile.distanceWeights[distance]
                return distance >= 3 ? base * profile.leapPenalty : base
            }
        )

        for distance in 0...maxDistance {
            XCTAssertEqual(observedDistribution[distance], expectedDistribution[distance], accuracy: 0.06)
        }
    }

    func test_from_clip_pitches_is_stubbed_to_scale_root() {
        let algo = PitchAlgo.fromClipPitches(
            clipID: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            pickMode: .random
        )
        var rng = SplitMix64(seed: 17)

        XCTAssertEqual(algo.pick(context: context(scaleRoot: 63), rng: &rng), 63)
    }

    func test_external_is_stubbed_to_scale_root() {
        let algo = PitchAlgo.external(port: "Port A", channel: 1, holdMode: .latest)
        var rng = SplitMix64(seed: 18)

        XCTAssertEqual(algo.pick(context: context(scaleRoot: 67), rng: &rng), 67)
    }

    func test_pitch_algo_round_trips_through_codable() throws {
        let algorithms: [PitchAlgo] = [
            .manual(pitches: [60, 62], pickMode: .random),
            .randomInScale(root: 60, scale: .major, spread: 12),
            .randomInChord(root: 60, chord: .minor7th, inverted: true, spread: 12),
            .intervalProb(root: 60, scale: .dorian, degreeWeights: [0.1, 0.2, 0.7]),
            .markov(root: 60, scale: .major, styleID: .vocal, leap: 0.2, color: 0.3),
            .fromClipPitches(clipID: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!, pickMode: .sequential),
            .external(port: "Port B", channel: 2, holdMode: .pool)
        ]

        for algorithm in algorithms {
            let data = try JSONEncoder().encode(algorithm)
            let decoded = try JSONDecoder().decode(PitchAlgo.self, from: data)
            XCTAssertEqual(decoded, algorithm)
        }
    }
}

private func context(
    lastPitch: Int? = nil,
    scaleRoot: Int = 60,
    stepIndex: Int = 0
) -> PitchContext {
    PitchContext(
        lastPitch: lastPitch,
        scaleRoot: scaleRoot,
        scaleID: .major,
        currentChord: nil,
        stepIndex: stepIndex
    )
}

private func scaleStepDistance(from source: Int, to destination: Int, root: Int, scaleID: ScaleID) -> Int? {
    guard let sourceIndex = scaleStepIndex(of: source, root: root, scaleID: scaleID),
          let destinationIndex = scaleStepIndex(of: destination, root: root, scaleID: scaleID)
    else {
        return nil
    }

    return abs(sourceIndex - destinationIndex)
}

private func scaleStepIndex(of pitch: Int, root: Int, scaleID: ScaleID) -> Int? {
    guard let scale = Scale.for(id: scaleID) else {
        return nil
    }

    let relative = pitch - root
    let octave = Int(floor(Double(relative) / 12.0))
    let pitchClass = ((relative % 12) + 12) % 12
    guard let degreeIndex = scale.intervals.firstIndex(of: pitchClass) else {
        return nil
    }

    return octave * scale.intervals.count + degreeIndex
}

private func normalizedDistribution(distances: [Int], maxDistance: Int) -> [Double] {
    let counts = (0...maxDistance).map { distance in
        Double(distances.filter { $0 == distance }.count)
    }
    return normalizedWeights(counts)
}

private func normalizedWeights(_ weights: [Double]) -> [Double] {
    let total = weights.reduce(0, +)
    guard total > 0 else {
        return Array(repeating: 0, count: weights.count)
    }
    return weights.map { $0 / total }
}

private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58476D1CE4E5B9
        value = (value ^ (value >> 27)) &* 0x94D049BB133111EB
        return value ^ (value >> 31)
    }
}
