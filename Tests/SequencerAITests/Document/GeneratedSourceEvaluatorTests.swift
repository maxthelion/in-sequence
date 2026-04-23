import XCTest
@testable import SequencerAI

final class GeneratedSourceEvaluatorTests: XCTestCase {
    func test_randomInScale_expands_middleC_seed_within_scale_and_spread() {
        let params = GeneratorParams.mono(
            trigger: .native(.euclidean(pulses: 1, steps: 1, offset: 0), basePitch: 60),
            pitch: .native(.randomInScale(root: 60, scale: .major, spread: 12)),
            shape: .default
        )

        var rng = PreviewRNG()
        var state = GeneratedSourceEvaluationState()
        let results = (0..<64).flatMap { step in
            GeneratedSourceEvaluator.evaluateStep(
                for: params,
                stepIndex: step,
                clipChoices: [],
                chordContext: nil,
                state: &state,
                rng: &rng
            )
        }

        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { (48...72).contains($0.pitch) })
        XCTAssertTrue(results.allSatisfy { Scale.for(id: .major)?.intervals.contains(($0.pitch - 60 + 120) % 12) == true })
    }

    func test_randomInChord_uses_project_chord_context_sidechain() {
        let params = GeneratorParams.mono(
            trigger: .native(.euclidean(pulses: 1, steps: 1, offset: 0), basePitch: 60),
            pitch: .native(
                .randomInChord(root: 60, chord: .majorTriad, inverted: false, spread: 12),
                harmonicSidechain: .projectChordContext
            ),
            shape: .default
        )
        let chordContext = Chord(root: 65, chordType: ChordID.minorTriad.rawValue, scale: ScaleID.dorian.rawValue)

        var rng = PreviewRNG()
        var state = GeneratedSourceEvaluationState()
        let results = (0..<64).flatMap { step in
            GeneratedSourceEvaluator.evaluateStep(
                for: params,
                stepIndex: step,
                clipChoices: [],
                chordContext: chordContext,
                state: &state,
                rng: &rng
            )
        }
        let allowed = Set([53, 56, 60, 65, 68, 72, 77])

        XCTAssertFalse(results.isEmpty)
        XCTAssertTrue(results.allSatisfy { allowed.contains($0.pitch) })
        XCTAssertTrue(results.contains(where: { $0.pitch == 68 }))
    }

    func test_fromClipPitches_uses_referenced_clip_pitch_pool() {
        let clip = ClipPoolEntry(
            id: UUID(uuidString: "99999999-9999-9999-9999-999999999999")!,
            name: "Pitch Pool",
            trackType: .monoMelodic,
            content: .stepSequence(
                stepPattern: [true, true, true, true],
                pitches: [65, 67]
            )
        )
        let params = GeneratorParams.mono(
            trigger: .native(.euclidean(pulses: 1, steps: 1, offset: 0)),
            pitch: .native(.fromClipPitches(clipID: clip.id, pickMode: .sequential)),
            shape: .default
        )

        var rng = PreviewRNG()
        var state = GeneratedSourceEvaluationState()
        let results = (0..<3).flatMap { step in
            GeneratedSourceEvaluator.evaluateStep(
                for: params,
                stepIndex: step,
                clipChoices: [clip],
                chordContext: nil,
                state: &state,
                rng: &rng
            )
        }

        XCTAssertEqual(results.map(\.pitch), [65, 67, 65])
    }

    func test_poly_generator_outputs_all_pitch_lanes_from_one_trigger_stream() {
        let params = GeneratorParams.poly(
            trigger: .native(.euclidean(pulses: 1, steps: 1, offset: 0)),
            pitches: [
                .native(.manual(pitches: [60], pickMode: .sequential)),
                .native(.manual(pitches: [67], pickMode: .sequential)),
            ],
            shape: .default
        )

        var rng = PreviewRNG()
        var state = GeneratedSourceEvaluationState()
        let results = GeneratedSourceEvaluator.evaluateStep(
            for: params,
            stepIndex: 0,
            clipChoices: [],
            chordContext: nil,
            state: &state,
            rng: &rng
        )

        XCTAssertEqual(results.map(\.pitch), [60, 67])
    }

    func test_drum_generator_stays_trigger_only_and_uses_voice_base_pitches() {
        let params = GeneratorParams.drum(
            triggers: [
                "hat": .native(.euclidean(pulses: 1, steps: 1, offset: 0), basePitch: 42),
                "kick": .native(.euclidean(pulses: 1, steps: 1, offset: 0), basePitch: 36),
            ],
            shape: .default
        )

        var rng = PreviewRNG()
        var state = GeneratedSourceEvaluationState()
        let results = GeneratedSourceEvaluator.evaluateStep(
            for: params,
            stepIndex: 0,
            clipChoices: [],
            chordContext: nil,
            state: &state,
            rng: &rng
        )

        XCTAssertEqual(results.map(\.voiceTag), ["hat", "kick"])
        XCTAssertEqual(results.map(\.pitch), [42, 36])
    }

    func test_previewNotes_matches_direct_evaluator_loop_for_deterministic_fixture() {
        let params = GeneratorParams.mono(
            trigger: .native(.euclidean(pulses: 2, steps: 4, offset: 0)),
            pitch: .native(.manual(pitches: [60, 64], pickMode: .sequential)),
            shape: .default
        )

        let preview = GeneratedSourceEvaluator.previewNotes(for: params, clipChoices: [], count: 4)

        var rng = PreviewRNG()
        var state = GeneratedSourceEvaluationState()
        let direct = (0..<4).map { step in
            GeneratedSourceEvaluator.evaluateStep(
                for: params,
                stepIndex: step,
                clipChoices: [],
                chordContext: nil,
                state: &state,
                rng: &rng
            )
        }

        XCTAssertEqual(preview, direct)
    }

    func test_resolveClipStep_fillLane_falls_back_to_main_when_fill_does_not_hit() {
        let clip = ClipPoolEntry(
            id: UUID(),
            name: "Fill",
            trackType: .monoMelodic,
            content: .noteGrid(
                lengthSteps: 1,
                steps: [
                    ClipStep(
                        main: ClipLane(chance: 1, notes: [ClipStepNote(pitch: 60, velocity: 80, lengthSteps: 2)]),
                        fill: ClipLane(chance: 0, notes: [ClipStepNote(pitch: 72, velocity: 120, lengthSteps: 4)])
                    )
                ]
            )
        )

        var rng = PreviewRNG()
        let notes = GeneratedSourceEvaluator.resolveClipStep(
            for: clip,
            stepIndex: 0,
            fillEnabled: true,
            rng: &rng
        )

        XCTAssertEqual(notes.map(\.pitch), [60])
        XCTAssertEqual(notes.map(\.velocity), [80])
        XCTAssertEqual(notes.map(\.length), [2])
    }
}
