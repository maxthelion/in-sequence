import Foundation
import XCTest
@testable import SequencerAI

final class StepAlgoTests: XCTestCase {
    func test_euclidean_three_against_eight_uses_expected_distribution() {
        let algo = StepAlgo.euclidean(pulses: 3, steps: 8, offset: 0)
        var rng = SplitMix64(seed: 1)
        let activeSteps = (0..<8).filter { algo.fires(at: $0, totalSteps: 8, rng: &rng) }

        XCTAssertEqual(activeSteps, [0, 3, 6])
    }

    func test_euclidean_offset_rotates_distribution() {
        let algo = StepAlgo.euclidean(pulses: 3, steps: 8, offset: 2)
        var rng = SplitMix64(seed: 2)
        let activeSteps = (0..<8).filter { algo.fires(at: $0, totalSteps: 8, rng: &rng) }

        XCTAssertEqual(activeSteps, [0, 2, 5])
    }

    func test_euclidean_zero_pulses_never_fires() {
        let algo = StepAlgo.euclidean(pulses: 0, steps: 8, offset: 0)
        var rng = SplitMix64(seed: 3)

        XCTAssertTrue((0..<16).allSatisfy { !algo.fires(at: $0, totalSteps: 8, rng: &rng) })
    }

    func test_euclidean_full_pulses_always_fires() {
        let algo = StepAlgo.euclidean(pulses: 8, steps: 8, offset: 0)
        var rng = SplitMix64(seed: 4)

        XCTAssertTrue((0..<16).allSatisfy { algo.fires(at: $0, totalSteps: 8, rng: &rng) })
    }

    func test_step_algo_round_trips_through_codable() throws {
        let algorithms: [StepAlgo] = [
            .euclidean(pulses: 5, steps: 16, offset: 3),
            .euclidean(pulses: 0, steps: 16, offset: 0),
            .euclidean(pulses: 16, steps: 16, offset: 7)
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
