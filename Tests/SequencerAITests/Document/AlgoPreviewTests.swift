import XCTest
@testable import SequencerAI

final class AlgoPreviewTests: XCTestCase {
    func test_preview_rng_is_stable_for_same_seed() {
        var lhs = PreviewRNG()
        var rhs = PreviewRNG()

        let lhsValues = (0..<8).map { _ in lhs.next() }
        let rhsValues = (0..<8).map { _ in rhs.next() }

        XCTAssertEqual(lhsValues, rhsValues)
    }

    func test_preview_steps_matches_canonical_mono_reference() {
        let params = GeneratorParams.mono(
            trigger: .native(.euclidean(pulses: 2, steps: 4, offset: 0)),
            pitch: .native(.manual(pitches: [60, 64], pickMode: .sequential)),
            shape: .default
        )

        let preview = previewSteps(for: params, clipChoices: [], count: 8)

        XCTAssertEqual(
            preview,
            [
                ["60"], [],
                ["60"], [],
                ["60"], [],
                ["60"], []
            ]
        )
    }

    func test_preview_steps_reads_clip_backed_pitches() {
        let clip = ClipPoolEntry(
            id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
            name: "Preview Clip",
            trackType: .monoMelodic,
            content: .noteGrid(
                lengthSteps: 2,
                steps: [
                    ClipStep(main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 65, velocity: 100, lengthSteps: 1)]), fill: nil),
                    ClipStep(main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 67, velocity: 100, lengthSteps: 1)]), fill: nil)
                ]
            )
        )
        let params = GeneratorParams.mono(
            trigger: .native(.euclidean(pulses: 4, steps: 4, offset: 0)),
            pitch: .native(.fromClipPitches(clipID: clip.id, pickMode: .sequential)),
            shape: .default
        )

        let preview = previewSteps(for: params, clipChoices: [clip], count: 4)

        XCTAssertEqual(preview, [["65"], ["67"], ["65"], ["67"]])
    }
}
