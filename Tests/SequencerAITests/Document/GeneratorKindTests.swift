import Foundation
import XCTest
@testable import SequencerAI

final class GeneratorKindTests: XCTestCase {
    func test_generator_kind_has_five_serialized_cases_and_four_creatable_cases() {
        XCTAssertEqual(GeneratorKind.allCases.count, 5)
        XCTAssertEqual(GeneratorKind.creatableKinds.count, 4)
        XCTAssertFalse(GeneratorKind.progressionChordGenerator.isCreatable)
    }

    func test_every_kind_has_label_and_default_params() {
        for kind in GeneratorKind.allCases {
            XCTAssertFalse(kind.label.isEmpty)

            switch kind.defaultParams {
            case .mono, .poly, .chordGenerator, .progressionChords, .drum, .template, .slice:
                XCTAssertTrue(true)
            }
        }
    }

    func test_mono_generator_is_compatible_with_mono_tracks() {
        XCTAssertTrue(GeneratorKind.monoGenerator.compatibleWith.contains(.monoMelodic))
    }

    func test_slice_generator_targets_slice_tracks() {
        XCTAssertEqual(GeneratorKind.sliceGenerator.compatibleWith, [.slice])
    }

    func test_progression_chord_generator_targets_poly_tracks() {
        XCTAssertEqual(GeneratorKind.progressionChordGenerator.compatibleWith, [.polyMelodic])
    }

    func test_chord_generator_targets_only_chord_tracks() {
        XCTAssertEqual(GeneratorKind.chordGenerator.compatibleWith, [.chord])
        XCTAssertTrue(GeneratorKind.chordGenerator.isCreatable)
    }

    func test_new_values_round_trip() throws {
        for kind in GeneratorKind.allCases {
            let data = try JSONEncoder().encode(kind)
            let decoded = try JSONDecoder().decode(GeneratorKind.self, from: data)
            XCTAssertEqual(decoded, kind)
        }
    }
}
