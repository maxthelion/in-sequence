import Foundation
import XCTest
@testable import SequencerAI

final class GeneratorParamsTests: XCTestCase {
    func test_variants_round_trip_through_codable() throws {
        let values: [GeneratorParams] = [
            .mono(
                step: .manual(pattern: [true, false]),
                pitch: .manual(pitches: [60, 64], pickMode: .sequential),
                shape: .default
            ),
            .poly(
                step: .euclidean(pulses: 3, steps: 8, offset: 0),
                pitches: [
                    .manual(pitches: [60, 64, 67], pickMode: .random),
                    .randomInScale(root: 60, scale: .major, spread: 12),
                ],
                shape: NoteShape(velocity: 96, gateLength: 6, accent: true)
            ),
            .drum(
                steps: [
                    "kick": .manual(pattern: [true, false, true, false]),
                    "hat": .perStepProbability(probs: [1, 0.5, 1, 0.5]),
                ],
                shape: .default
            ),
            .template(templateID: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!),
            .slice(step: .randomWeighted(density: 0.25), sliceIndexes: [0, 3, 7]),
        ]

        for value in values {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(GeneratorParams.self, from: data)
            XCTAssertEqual(decoded, value)
        }
    }

    func test_default_mono_matches_freshly_constructed_value() {
        XCTAssertEqual(
            GeneratorParams.defaultMono,
            .mono(
                step: .manual(pattern: Array(repeating: false, count: 16)),
                pitch: .manual(pitches: [60, 62, 64, 67], pickMode: .random),
                shape: .default
            )
        )
    }

    func test_default_drum_kit_contains_kick_snare_and_hat() {
        guard case let .drum(steps, shape) = GeneratorParams.defaultDrumKit else {
            XCTFail("defaultDrumKit should be a drum variant")
            return
        }

        XCTAssertEqual(shape, .default)
        XCTAssertEqual(steps.count, 3)
        XCTAssertNotNil(steps["kick"])
        XCTAssertNotNil(steps["snare"])
        XCTAssertNotNil(steps["hat"])
    }

    func test_mono_variants_compare_step_algo_in_equality() {
        let first = GeneratorParams.mono(
            step: .manual(pattern: [true, false]),
            pitch: .manual(pitches: [60], pickMode: .sequential),
            shape: .default
        )
        let second = GeneratorParams.mono(
            step: .manual(pattern: [false, true]),
            pitch: .manual(pitches: [60], pickMode: .sequential),
            shape: .default
        )

        XCTAssertNotEqual(first, second)
    }
}
