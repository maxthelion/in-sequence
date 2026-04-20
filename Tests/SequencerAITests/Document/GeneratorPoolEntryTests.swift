import Foundation
import XCTest
@testable import SequencerAI

final class GeneratorPoolEntryTests: XCTestCase {
    func test_default_pool_has_four_entries_with_compatible_track_types() {
        XCTAssertEqual(GeneratorPoolEntry.defaultPool.count, 4)
        XCTAssertTrue(
            GeneratorPoolEntry.defaultPool.allSatisfy { entry in
                entry.kind.compatibleWith.contains(entry.trackType)
            }
        )
    }

    func test_default_pool_includes_poly_generator() {
        let polyEntry = GeneratorPoolEntry.defaultPool.first(where: { $0.trackType == .polyMelodic })

        XCTAssertEqual(polyEntry?.kind, .polyGenerator)
    }

    func test_default_poly_generator_has_active_steps() {
        guard let polyEntry = GeneratorPoolEntry.defaultPool.first(where: { $0.trackType == .polyMelodic }),
              case let .poly(step, _, _) = polyEntry.params,
              case let .manual(pattern) = step
        else {
            return XCTFail("expected a manual default poly generator")
        }

        XCTAssertTrue(pattern.contains(true))
    }

    func test_default_pool_uses_kind_default_params() {
        for entry in GeneratorPoolEntry.defaultPool {
            XCTAssertEqual(entry.params, entry.kind.defaultParams)
        }
    }

    func test_generator_pool_entry_round_trips_new_shape() throws {
        let entry = GeneratorPoolEntry(
            id: UUID(uuidString: "88888888-8888-8888-8888-888888888888")!,
            name: "Poly Motion",
            trackType: .polyMelodic,
            kind: .polyGenerator,
            params: .poly(
                step: .euclidean(pulses: 5, steps: 16, offset: 0),
                pitches: [.manual(pitches: [60, 64, 67], pickMode: .random)],
                shape: .default
            )
        )

        let data = try JSONEncoder().encode(entry)
        let decoded = try JSONDecoder().decode(GeneratorPoolEntry.self, from: data)
        XCTAssertEqual(decoded, entry)
    }

    func test_make_default_seeds_params_from_kind() {
        let entry = GeneratorPoolEntry.makeDefault(
            id: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!,
            name: "Default Drum",
            kind: .drumKit,
            trackType: .monoMelodic
        )

        XCTAssertEqual(entry.params, .defaultDrumKit)
    }
}
