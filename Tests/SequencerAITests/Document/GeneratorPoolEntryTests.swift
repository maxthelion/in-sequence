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

    func test_default_pool_includes_progression_chord_generator() {
        let progressionEntry = GeneratorPoolEntry.defaultPool.first(where: { $0.kind == .progressionChordGenerator })

        XCTAssertEqual(progressionEntry?.trackType, .polyMelodic)
        XCTAssertEqual(progressionEntry?.name, "Progression Chords")
    }

    func test_default_poly_generator_has_active_steps() {
        guard let polyEntry = GeneratorPoolEntry.defaultPool.first(where: { $0.trackType == .polyMelodic }),
              case let .poly(trigger, _, _) = polyEntry.params,
              case let .euclidean(pulses, steps, _) = trigger.stepStage.algo
        else {
            return XCTFail("expected an euclidean default poly generator")
        }

        XCTAssertGreaterThan(pulses, 0)
        XCTAssertGreaterThan(steps, 0)
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
                trigger: .native(.euclidean(pulses: 5, steps: 16, offset: 0)),
                pitches: [.native(.manual(pitches: [60, 64, 67], pickMode: .random))],
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
            name: "Default Slice",
            kind: .sliceGenerator,
            trackType: .slice
        )

        XCTAssertEqual(
            entry.params,
            .slice(trigger: .native(.euclidean(pulses: 4, steps: 16, offset: 0)), sliceIndexes: [])
        )
    }

    func test_switching_kind_preserves_identity_and_shared_settings() throws {
        let entryID = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        let trigger = TriggerStageNode.native(.euclidean(pulses: 5, steps: 16, offset: 3))
        let entry = GeneratorPoolEntry(
            id: entryID,
            name: "Shared Generator",
            trackType: .polyMelodic,
            kind: .polyGenerator,
            params: .poly(
                trigger: trigger,
                pitches: [.native(.randomInScale(root: 65, scale: .dorian, spread: 17))],
                shape: NoteShape(velocity: 88, gateLength: 6, accent: true)
            )
        )

        let progression = entry.switchingKind(to: .progressionChordGenerator)

        XCTAssertEqual(progression.id, entryID)
        XCTAssertEqual(progression.name, "Shared Generator")
        XCTAssertEqual(progression.kind, .progressionChordGenerator)
        XCTAssertEqual(progression.trackType, .polyMelodic)
        guard case let .progressionChords(params) = progression.params else {
            return XCTFail("expected progression params")
        }
        XCTAssertEqual(params.rootMIDI, 65)
        XCTAssertEqual(params.mode, .minor)
        XCTAssertEqual(params.velocity, 88)

        let poly = progression.switchingKind(to: .polyGenerator)
        XCTAssertEqual(poly.id, entryID)
        XCTAssertEqual(poly.name, "Shared Generator")
        XCTAssertEqual(poly.kind, .polyGenerator)
        XCTAssertEqual(poly.trackType, .polyMelodic)
        guard case let .poly(roundTripTrigger, pitches, shape) = poly.params else {
            return XCTFail("expected poly params")
        }
        XCTAssertEqual(roundTripTrigger, .native(.defaultMono))
        XCTAssertEqual(pitches, [.native(.randomInScale(root: 65, scale: .naturalMinor, spread: 12))])
        XCTAssertEqual(shape.velocity, 88)
    }
}
