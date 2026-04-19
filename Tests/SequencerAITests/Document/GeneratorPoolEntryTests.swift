import Foundation
import XCTest
@testable import SequencerAI

final class GeneratorPoolEntryTests: XCTestCase {
    func test_default_pool_has_three_entries_with_compatible_track_types() {
        XCTAssertEqual(GeneratorPoolEntry.defaultPool.count, 3)
        XCTAssertTrue(
            GeneratorPoolEntry.defaultPool.allSatisfy { entry in
                entry.kind.compatibleWith.contains(entry.trackType)
            }
        )
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
