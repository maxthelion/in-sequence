import Foundation
import XCTest
@testable import SequencerAI

final class GeneratorParamsTests: XCTestCase {
    func test_variants_round_trip_through_codable() throws {
        let values: [GeneratorParams] = [
            .mono(
                trigger: .native(.manual(pattern: [true, false])),
                pitch: .native(.manual(pitches: [60, 64], pickMode: .sequential)),
                shape: .default
            ),
            .poly(
                trigger: .native(.euclidean(pulses: 3, steps: 8, offset: 0)),
                pitches: [
                    .native(.manual(pitches: [60, 64, 67], pickMode: .random)),
                    .native(.randomInScale(root: 60, scale: .major, spread: 12)),
                ],
                shape: NoteShape(velocity: 96, gateLength: 6, accent: true)
            ),
            .drum(
                triggers: [
                    "kick": .native(.manual(pattern: [true, false, true, false]), basePitch: 36),
                    "hat": .native(.perStepProbability(probs: [1, 0.5, 1, 0.5]), basePitch: 42),
                ],
                shape: .default
            ),
            .template(templateID: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!),
            .slice(trigger: .native(.randomWeighted(density: 0.25)), sliceIndexes: [0, 3, 7]),
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
                trigger: .native(.manual(pattern: Array(repeating: false, count: 16))),
                pitch: .native(.manual(pitches: [60, 62, 64, 67], pickMode: .random)),
                shape: .default
            )
        )
    }

    func test_default_drum_kit_contains_kick_snare_and_hat() {
        guard case let .drum(triggers, shape) = GeneratorParams.defaultDrumKit else {
            XCTFail("defaultDrumKit should be a drum variant")
            return
        }

        XCTAssertEqual(shape, .default)
        XCTAssertEqual(triggers.count, 3)
        XCTAssertNotNil(triggers["kick"])
        XCTAssertNotNil(triggers["snare"])
        XCTAssertNotNil(triggers["hat"])
    }

    func test_mono_variants_compare_step_algo_in_equality() {
        let first = GeneratorParams.mono(
            trigger: .native(.manual(pattern: [true, false])),
            pitch: .native(.manual(pitches: [60], pickMode: .sequential)),
            shape: .default
        )
        let second = GeneratorParams.mono(
            trigger: .native(.manual(pattern: [false, true])),
            pitch: .native(.manual(pitches: [60], pickMode: .sequential)),
            shape: .default
        )

        XCTAssertNotEqual(first, second)
    }

    func test_harmonic_sidechain_source_round_trips_through_codable() throws {
        let values: [HarmonicSidechainSource] = [
            .none,
            .projectChordContext,
            .clip(UUID(uuidString: "77777777-7777-7777-7777-777777777777")!)
        ]

        for value in values {
            let data = try JSONEncoder().encode(value)
            let decoded = try JSONDecoder().decode(HarmonicSidechainSource.self, from: data)
            XCTAssertEqual(decoded, value)
        }
    }

    func test_generatedSourcePipeline_covers_all_generator_variants() {
        let templateID = UUID(uuidString: "12121212-3434-5656-7878-909090909090")!
        let values: [GeneratorParams] = [
            .mono(
                trigger: .native(.manual(pattern: [true, false]), basePitch: 60),
                pitch: .native(.manual(pitches: [60, 64], pickMode: .sequential)),
                shape: .default
            ),
            .poly(
                trigger: .native(.manual(pattern: [true, false]), basePitch: 60),
                pitches: [
                    .native(.manual(pitches: [60], pickMode: .sequential)),
                    .native(.manual(pitches: [67], pickMode: .sequential)),
                ],
                shape: .default
            ),
            .drum(
                triggers: [
                    "kick": .native(.manual(pattern: [true]), basePitch: 36),
                    "hat": .native(.manual(pattern: [false, true]), basePitch: 42),
                ],
                shape: .default
            ),
            .slice(
                trigger: .native(.manual(pattern: [true, false]), basePitch: 60),
                sliceIndexes: [0, 2, 4]
            ),
            .template(templateID: templateID),
        ]

        for value in values {
            switch (value, value.generatedSourcePipeline.content) {
            case let (.mono(trigger, pitch, shape), .melodic(pitches, pipelineShape)):
                XCTAssertEqual(value.generatedSourcePipeline.trigger, trigger)
                XCTAssertEqual(pitches, [pitch])
                XCTAssertEqual(pipelineShape, shape)

            case let (.poly(trigger, pitches, shape), .melodic(pipelinePitches, pipelineShape)):
                XCTAssertEqual(value.generatedSourcePipeline.trigger, trigger)
                XCTAssertEqual(pipelinePitches, pitches)
                XCTAssertEqual(pipelineShape, shape)

            case let (.drum(triggers, shape), .drum(pipelineTriggers, pipelineShape)):
                XCTAssertNil(value.generatedSourcePipeline.trigger)
                XCTAssertEqual(pipelineTriggers, triggers)
                XCTAssertEqual(pipelineShape, shape)

            case let (.slice(trigger, indexes), .slice(pipelineIndexes)):
                XCTAssertEqual(value.generatedSourcePipeline.trigger, trigger)
                XCTAssertEqual(pipelineIndexes, indexes)

            case let (.template(id), .template(pipelineID)):
                XCTAssertNil(value.generatedSourcePipeline.trigger)
                XCTAssertEqual(pipelineID, id)

            default:
                XCTFail("generatedSourcePipeline should preserve the generator variant shape")
            }
        }
    }
}
