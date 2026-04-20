import Foundation
import XCTest
@testable import SequencerAI

final class GeneratorKindTests: XCTestCase {
    func test_generator_kind_has_three_cases() {
        XCTAssertEqual(GeneratorKind.allCases.count, 3)
    }

    func test_every_kind_has_label_and_default_params() {
        for kind in GeneratorKind.allCases {
            XCTAssertFalse(kind.label.isEmpty)

            switch kind.defaultParams {
            case .mono, .poly, .drum, .template, .slice:
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

    func test_new_values_round_trip() throws {
        for kind in GeneratorKind.allCases {
            let data = try JSONEncoder().encode(kind)
            let decoded = try JSONDecoder().decode(GeneratorKind.self, from: data)
            XCTAssertEqual(decoded, kind)
        }
    }
}
