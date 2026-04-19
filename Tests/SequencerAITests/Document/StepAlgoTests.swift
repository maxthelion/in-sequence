import Foundation
import XCTest
@testable import SequencerAI

final class StepAlgoTests: XCTestCase {
    func test_manual_pattern_reads_values_and_bounds_checks() {
        let algo = StepAlgo.manual(pattern: [true, false, true, false])
        var rng = SplitMix64(seed: 1)

        XCTAssertTrue(algo.fires(at: 0, totalSteps: 4, rng: &rng))
        XCTAssertFalse(algo.fires(at: 1, totalSteps: 4, rng: &rng))
        XCTAssertTrue(algo.fires(at: 2, totalSteps: 4, rng: &rng))
        XCTAssertFalse(algo.fires(at: 4, totalSteps: 4, rng: &rng))
    }

    func test_random_weighted_one_always_fires() {
        let algo = StepAlgo.randomWeighted(density: 1.0)
        var rng = SplitMix64(seed: 2)

        XCTAssertTrue((0..<64).allSatisfy { _ in algo.fires(at: 0, totalSteps: 16, rng: &rng) })
    }

    func test_random_weighted_zero_never_fires() {
        let algo = StepAlgo.randomWeighted(density: 0.0)
        var rng = SplitMix64(seed: 3)

        XCTAssertTrue((0..<64).allSatisfy { _ in !algo.fires(at: 0, totalSteps: 16, rng: &rng) })
    }

    func test_random_weighted_half_fires_roughly_half_the_time() {
        let algo = StepAlgo.randomWeighted(density: 0.5)
        var rng = SplitMix64(seed: 4)

        let fireCount = (0..<1_000).reduce(into: 0) { count, _ in
            if algo.fires(at: 0, totalSteps: 16, rng: &rng) {
                count += 1
            }
        }

        XCTAssertGreaterThanOrEqual(fireCount, 450)
        XCTAssertLessThanOrEqual(fireCount, 550)
    }

    func test_euclidean_three_against_eight_uses_expected_distribution() {
        let algo = StepAlgo.euclidean(pulses: 3, steps: 8, offset: 0)
        var rng = SplitMix64(seed: 5)
        let activeSteps = (0..<8).filter { algo.fires(at: $0, totalSteps: 8, rng: &rng) }

        XCTAssertEqual(activeSteps, [0, 3, 6])
    }

    func test_euclidean_offset_rotates_distribution() {
        let algo = StepAlgo.euclidean(pulses: 3, steps: 8, offset: 2)
        var rng = SplitMix64(seed: 6)
        let activeSteps = (0..<8).filter { algo.fires(at: $0, totalSteps: 8, rng: &rng) }

        XCTAssertEqual(activeSteps, [0, 2, 5])
    }

    func test_per_step_probability_uses_per_step_thresholds() {
        let algo = StepAlgo.perStepProbability(probs: [1.0, 0.0, 1.0])
        var rng = SplitMix64(seed: 7)

        XCTAssertTrue(algo.fires(at: 0, totalSteps: 3, rng: &rng))
        XCTAssertFalse(algo.fires(at: 1, totalSteps: 3, rng: &rng))
        XCTAssertTrue(algo.fires(at: 2, totalSteps: 3, rng: &rng))
    }

    func test_from_clip_steps_is_stubbed_false_until_clip_pool_arrives() {
        let algo = StepAlgo.fromClipSteps(clipID: UUID())
        var rng = SplitMix64(seed: 8)

        XCTAssertFalse(algo.fires(at: 0, totalSteps: 16, rng: &rng))
        XCTAssertFalse(algo.fires(at: 15, totalSteps: 16, rng: &rng))
    }

    func test_step_algo_round_trips_through_codable() throws {
        let algorithms: [StepAlgo] = [
            .manual(pattern: [true, false, true]),
            .randomWeighted(density: 0.25),
            .euclidean(pulses: 5, steps: 16, offset: 3),
            .perStepProbability(probs: [0.1, 0.2, 0.3]),
            .fromClipSteps(clipID: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!)
        ]

        for algorithm in algorithms {
            let data = try JSONEncoder().encode(algorithm)
            let decoded = try JSONDecoder().decode(StepAlgo.self, from: data)
            XCTAssertEqual(decoded, algorithm)
        }
    }
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
