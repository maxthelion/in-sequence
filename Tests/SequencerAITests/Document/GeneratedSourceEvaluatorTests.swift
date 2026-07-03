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

    func test_progression_chord_generator_outputs_bar_start_chords_until_next_chord() {
        let params = GeneratorParams.progressionChords(.default)

        var rng = PreviewRNG()
        var state = GeneratedSourceEvaluationState()
        let firstStep = GeneratedSourceEvaluator.evaluateStep(
            for: params,
            stepIndex: 0,
            clipChoices: [],
            chordContext: nil,
            state: &state,
            rng: &rng
        )
        let secondStep = GeneratedSourceEvaluator.evaluateStep(
            for: params,
            stepIndex: 1,
            clipChoices: [],
            chordContext: nil,
            state: &state,
            rng: &rng
        )
        let nextBar = GeneratedSourceEvaluator.evaluateStep(
            for: params,
            stepIndex: 16,
            clipChoices: [],
            chordContext: nil,
            state: &state,
            rng: &rng
        )

        XCTAssertEqual(firstStep.map(\.pitch), [60, 63, 67])
        XCTAssertEqual(firstStep.map(\.velocity), [100, 100, 100])
        XCTAssertEqual(firstStep.map(\.length), [16, 16, 16])
        XCTAssertTrue(secondStep.isEmpty)
        XCTAssertEqual(nextBar.map(\.pitch), [70, 74, 77])
        XCTAssertEqual(nextBar.map(\.length), [16, 16, 16])
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

    func test_resolveClipStep_sliceTriggers_emitSliceVoiceTags() {
        let clip = ClipPoolEntry(
            id: UUID(),
            name: "Slices",
            trackType: .slice,
            content: .sliceTriggers(
                stepPattern: [true, true],
                sliceIndexes: [3, 4],
                stepModes: [.single, .runFromHere],
                stepParameters: [
                    SliceTriggerStepParameters(gain: 2),
                    SliceTriggerStepParameters(startTrim: 0.15, reverse: true)
                ]
            )
        )

        var rng = PreviewRNG()
        let first = GeneratedSourceEvaluator.resolveClipStep(
            for: clip,
            stepIndex: 0,
            fillEnabled: false,
            rng: &rng
        )
        let second = GeneratedSourceEvaluator.resolveClipStep(
            for: clip,
            stepIndex: 1,
            fillEnabled: false,
            rng: &rng
        )

        XCTAssertEqual(first.first?.voiceTag, "slice-3")
        XCTAssertEqual(first.first?.sliceParameters?.gain, 2)
        XCTAssertEqual(second.first?.voiceTag, "slice-run-4")
        XCTAssertEqual(second.first?.sliceParameters?.startTrim, 0.15)
        XCTAssertEqual(second.first?.sliceParameters?.reverse, true)
    }

    // MARK: - WS4 generator vocabulary (weighted/cluster trigger, pool pitch)

    func test_weightedClusterTrigger_isDeterministicWithFixedSeed() {
        let params = GeneratorParams.mono(
            trigger: .native(.weighted(weights: [1, 0.2, 0, 0.7, 0.4, 0, 0.9, 0.1], steps: 8, cluster: 0.65)),
            pitch: .native(.manual(pitches: [60], pickMode: .sequential)),
            shape: .default
        )

        let first = previewPitches(for: params, count: 32)
        let second = previewPitches(for: params, count: 32)

        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(first, second)
    }

    /// WS4 AC2 (evaluator level): the chord sidechain is a PITCH-POOL FILTER
    /// only — attaching it must leave the trigger stream untouched while the
    /// realized pitches move. The full mid-run chord-change stream fixture
    /// lives in `GeneratorVocabAcceptanceTests`.
    func test_chordSidechainChangesPitchButNotTriggerStream() {
        let trigger = TriggerStageNode.native(.weighted(weights: [1, 0.35, 0, 0.8], steps: 4, cluster: 0.4))
        let plain = GeneratorParams.mono(
            trigger: trigger,
            pitch: .native(.pool(root: 60, scale: .major, spread: 12, selection: .uniform, deviation: .none)),
            shape: .default
        )
        let following = GeneratorParams.mono(
            trigger: trigger,
            pitch: .native(
                .pool(root: 60, scale: .major, spread: 12, selection: .uniform, deviation: .none),
                harmonicSidechain: .projectChordContext
            ),
            shape: .default
        )
        let chord = Chord(root: 65, chordType: ChordID.minorTriad.rawValue, scale: ScaleID.dorian.rawValue)

        XCTAssertEqual(sourceFirePattern(for: plain), sourceFirePattern(for: following))
        XCTAssertNotEqual(previewPitches(for: plain, count: 32), previewPitches(for: following, count: 32, chord: chord))
    }

    /// WS4 AC4: deviation controls. Accidentals only leave the pool when the
    /// factor is > 0; the octave span bounds the register jumps; chromatic
    /// leading emits approach tones that RESOLVE STEPWISE into a pool note on
    /// the following fire (synthesis taxonomy).
    func test_pitchPoolDeviationControlsBoundOutOfPoolAndRegisterBehavior() {
        let noDeviation = poolParams(deviation: .none)
        let accidental = poolParams(
            deviation: PitchDeviationSettings(accidentalChance: 1, octaveSpan: 0, leadingChance: 0)
        )
        let octaves = poolParams(
            spread: 0,
            deviation: PitchDeviationSettings(accidentalChance: 0, octaveSpan: 1, leadingChance: 0)
        )
        let leading = poolParams(
            deviation: PitchDeviationSettings(accidentalChance: 0, octaveSpan: 0, leadingChance: 1)
        )

        let pool = majorPool(root: 60, spread: 12)

        // Accidentals gate: zero factor never leaves the pool; full factor does.
        XCTAssertTrue(previewPitches(for: noDeviation, count: 48).allSatisfy { pool.contains($0) })
        XCTAssertTrue(previewPitches(for: accidental, count: 48).contains { !pool.contains($0) })

        // Octave span bounds: a one-note pool (spread 0) with span 1 may only
        // visit the root and its +/-1 octave registers.
        XCTAssertTrue(previewPitches(for: octaves, count: 48).allSatisfy { [48, 60, 72].contains($0) })

        // Chromatic leading resolves stepwise: every out-of-pool approach tone
        // is followed by an in-pool note exactly one semitone away.
        let leadingPitches = previewPitches(for: leading, count: 48)
        XCTAssertTrue(leadingPitches.contains { !pool.contains($0) }, "leading=1 must emit approach tones")
        for (index, pitch) in leadingPitches.enumerated() where !pool.contains(pitch) {
            guard index + 1 < leadingPitches.count else { continue }
            let next = leadingPitches[index + 1]
            XCTAssertTrue(
                pool.contains(next) && abs(next - pitch) == 1,
                "approach tone \(pitch) at \(index) must resolve stepwise into a pool note, got \(next)"
            )
        }
    }

    // MARK: - WS5 density transform

    /// WS5 AC1: same (pattern, density) → identical ghosts, and the ghost set
    /// is loop-stable — evaluating step indexes a full loop apart lands on the
    /// same normalized positions.
    func test_densityTransform_isDeterministicForSamePatternAndDensity() {
        let patternID = UUID(uuidString: "12121212-3434-5656-7878-909090909090")!
        let first = densityGhostSteps(patternID: patternID, density: 0.6, cluster: 0)
        let second = densityGhostSteps(patternID: patternID, density: 0.6, cluster: 0)
        let secondLoop = densityGhostSteps(patternID: patternID, density: 0.6, cluster: 0, stepOffset: 16)

        XCTAssertFalse(first.isEmpty)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first, secondLoop, "ghosts must land on the same positions every loop")
    }

    /// WS5 AC2: higher density strictly adds — a ghost admitted at a lower
    /// density is still admitted at every higher density. Property-style
    /// across several density pairs.
    func test_densityTransform_isMonotonicAsDensityRises() {
        let patternID = UUID(uuidString: "aaaaaaaa-1111-2222-3333-bbbbbbbbbbbb")!
        let densities: [Double] = [0.1, 0.3, 0.5, 0.7, 0.9, 1.0]
        for (lower, higher) in zip(densities, densities.dropFirst()) {
            let lowerGhosts = Set(densityGhostSteps(patternID: patternID, density: lower, cluster: 0))
            let higherGhosts = Set(densityGhostSteps(patternID: patternID, density: higher, cluster: 0))
            XCTAssertTrue(
                lowerGhosts.isSubset(of: higherGhosts),
                "ghosts(\(lower)) must be a subset of ghosts(\(higher))"
            )
        }
        XCTAssertFalse(densityGhostSteps(patternID: patternID, density: 1, cluster: 0).isEmpty)
    }

    /// WS5 AC3: cluster=attraction admits only adjacent-to-hit ghosts;
    /// repulsion maximizes spacing from every hit (distribution assertions
    /// under the deterministic hash — no seeds involved).
    func test_densityTransform_clusterControlsCandidateDistribution() {
        let patternID = UUID(uuidString: "cccccccc-1111-2222-3333-dddddddddddd")!
        let attraction = densityGhostSteps(patternID: patternID, density: 1, cluster: 1)
        let repulsion = densityGhostSteps(patternID: patternID, density: 1, cluster: -1)

        XCTAssertFalse(attraction.isEmpty)
        XCTAssertFalse(repulsion.isEmpty)
        XCTAssertTrue(attraction.allSatisfy { circularDistance(from: $0, toNearestOf: [0, 8], in: 16) <= 3 })
        XCTAssertTrue(repulsion.allSatisfy { circularDistance(from: $0, toNearestOf: [0, 8], in: 16) >= 4 })
    }

    /// WS5 ghost policy: velocity is scaled from the neighbouring hits (mean
    /// of nearest preceding/following, scaled down) and pitch repeats the
    /// nearest preceding hit (repeat-last for clips; a realized pool-policy
    /// note for generators).
    func test_densityGhosts_velocityScaledFromNeighboursAndPitchRepeatsPreceding() {
        let patternID = UUID(uuidString: "eeeeeeee-1111-2222-3333-ffffffffffff")!
        let hits = [
            DensitySourceHit(step: 0, pitch: 60, velocity: 100, voiceTag: nil),
            DensitySourceHit(step: 8, pitch: 67, velocity: 60, voiceTag: nil)
        ]
        var sawGhost = false
        for step in 0..<16 {
            let notes = GeneratedSourceEvaluator.applyingDensityTransform(
                to: [],
                stepIndex: step,
                stepCount: 16,
                patternID: patternID,
                density: 1,
                cluster: 0,
                sourceHits: hits,
                fallbackPitch: 48
            )
            guard let ghost = notes.first else { continue }
            sawGhost = true
            let expectedPitch = (1...7).contains(step) ? 60 : 67
            XCTAssertEqual(ghost.pitch, expectedPitch, "step \(step): ghost must repeat the nearest preceding hit's pitch")
            XCTAssertEqual(ghost.velocity, 52, "step \(step): ghost velocity must be the scaled neighbour mean (80 * 0.65)")
            XCTAssertLessThan(ghost.velocity, 60, "ghosts must sit below their neighbours")
        }
        XCTAssertTrue(sawGhost)
    }

    /// Density 0 is a byte-identical pass-through (the pre-WS5 stream).
    func test_densityTransform_zeroDensityIsPassThrough() {
        let notes = [GeneratedNote(pitch: 61, velocity: 90, length: 2, voiceTag: nil)]
        let result = GeneratedSourceEvaluator.applyingDensityTransform(
            to: notes,
            stepIndex: 3,
            stepCount: 16,
            patternID: UUID(),
            density: 0,
            cluster: 0,
            sourceHits: [DensitySourceHit(step: 0, pitch: 60, velocity: 100, voiceTag: nil)],
            fallbackPitch: 60
        )
        XCTAssertEqual(result, notes)
    }

    private func densityGhostSteps(
        patternID: UUID,
        density: Double,
        cluster: Double,
        stepOffset: Int = 0
    ) -> [Int] {
        let hits = [
            DensitySourceHit(step: 0, pitch: 60, velocity: 100, voiceTag: nil),
            DensitySourceHit(step: 8, pitch: 67, velocity: 100, voiceTag: nil)
        ]
        return (0..<16).compactMap { step in
            let notes = GeneratedSourceEvaluator.applyingDensityTransform(
                to: [],
                stepIndex: step + stepOffset,
                stepCount: 16,
                patternID: patternID,
                density: density,
                cluster: cluster,
                sourceHits: hits,
                fallbackPitch: 60
            )
            return notes.isEmpty ? nil : step
        }
    }

    private func circularDistance(from step: Int, toNearestOf hits: [Int], in stepCount: Int) -> Int {
        hits.map { hit in
            let raw = abs(step - hit)
            return min(raw, stepCount - raw)
        }.min() ?? stepCount
    }

    private func poolParams(spread: Int = 12, deviation: PitchDeviationSettings) -> GeneratorParams {
        .mono(
            trigger: .native(.euclidean(pulses: 1, steps: 1, offset: 0)),
            pitch: .native(.pool(root: 60, scale: .major, spread: spread, selection: .uniform, deviation: deviation)),
            shape: .default
        )
    }

    private func previewPitches(for params: GeneratorParams, count: Int, chord: Chord? = nil) -> [Int] {
        GeneratedSourceEvaluator.previewNotes(for: params, clipChoices: [], count: count, chordContext: chord)
            .flatMap { $0.map(\.pitch) }
    }

    private func sourceFirePattern(for params: GeneratorParams) -> [Bool] {
        var rng = PreviewRNG()
        return (0..<32).map { step in
            !GeneratedSourceEvaluator.evaluateSourceStep(
                for: params,
                stepIndex: step,
                clipChoices: [],
                rng: &rng
            ).isEmpty
        }
    }

    private func majorPool(root: Int, spread: Int) -> Set<Int> {
        let intervals = Set(Scale.for(id: .major)?.intervals ?? [])
        return Set((max(0, root - spread)...min(127, root + spread)).filter {
            intervals.contains((($0 - root) % 12 + 12) % 12)
        })
    }
}
