import XCTest
@testable import SequencerAI

final class TrackSourceSourceDisplayStateTests: XCTestCase {
    func test_clipSourceWithClip_resolvesToOccupiedClip() {
        let state = TrackSourceSourceDisplayState.resolve(
            sourceMode: .clip,
            currentClip: ClipPoolEntry(
                id: UUID(),
                name: "Pattern Clip",
                trackType: .monoMelodic,
                content: .emptyNoteGrid(lengthSteps: 16)
            ),
            selectedGenerator: nil
        )

        XCTAssertEqual(state, .occupiedClip)
        XCTAssertEqual(state.badgeTitle, "Clip")
    }

    func test_clipSourceWithoutClip_resolvesToEmpty() {
        let state = TrackSourceSourceDisplayState.resolve(
            sourceMode: .clip,
            currentClip: nil,
            selectedGenerator: nil
        )

        XCTAssertEqual(state, .empty)
        XCTAssertEqual(state.badgeTitle, "Empty")
    }

    func test_generatorSourceWithGenerator_resolvesToOccupiedGenerator() {
        let state = TrackSourceSourceDisplayState.resolve(
            sourceMode: .generator,
            currentClip: nil,
            selectedGenerator: GeneratorPoolEntry(
                id: UUID(),
                name: "Euclidean Mono",
                trackType: .monoMelodic,
                kind: .monoGenerator,
                params: .defaultMono
            )
        )

        XCTAssertEqual(state, .occupiedGenerator)
        XCTAssertEqual(state.badgeTitle, "Gen")
    }

    func test_generatorSourceWithoutGenerator_resolvesToEmptyEvenWithRetainedClip() {
        let state = TrackSourceSourceDisplayState.resolve(
            sourceMode: .generator,
            currentClip: ClipPoolEntry(
                id: UUID(),
                name: "Retained Clip",
                trackType: .monoMelodic,
                content: .emptyNoteGrid(lengthSteps: 16)
            ),
            selectedGenerator: nil
        )

        XCTAssertEqual(state, .empty)
        XCTAssertEqual(state.badgeTitle, "Empty")
    }
}
