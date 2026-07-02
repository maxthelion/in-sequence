import XCTest
@testable import SequencerAI

/// PHASE 2 RAIL — off-thread next-bar precompute equivalence.
///
/// Authored from the SPEC only
/// (`docs/plans/2026-06-30-precompute-lookahead-recording.md`, Phase 2), never
/// from the implementation. FROZEN: builders may not edit, weaken, skip, or stub
/// this file (see the fleet brief's frozen-rails rule).
///
/// # The invariant this gate encodes (spec, Phase 2)
///
/// 1. "move generative evaluation to a background queue ... Publish the
///    precomputed bar's notes (tempo-independent) via the existing snapshot
///    lock-swap." → generation runs OFF the realtime tick path; the tick path
///    consumes a `PrecomputedBar` with a pure dictionary read (no RNG, no
///    generator evaluation).
/// 2. Executable gate (HEADLINE): "a recorded run *with* precompute == a
///    recorded run *without* (same notes — equivalence)." The precomputed bar
///    must carry the byte-identical `preparedNotesByBlockID` dispatch map a live
///    per-step evaluation produces for the same inputs.
/// 3. "Invalidate + regenerate on any generation-input change" — a precompute
///    fed a CHANGED snapshot must produce the changed stream (so a stale bar
///    can't be the equivalence cheat).
///
/// # Why it is deterministic (no engine, no device)
///
/// Per the fleet brief, the rail prefers deterministic unit tests over
/// device-dependent ones. Generation is a pure function of (snapshot, phrase,
/// step, chord, evaluation-state, RNG): `EngineController.resolvedStepNotes`.
/// The live tick path uses a FRESH RNG per (track, step); to make a
/// deterministic, byte-comparable test we inject the SAME deterministic per-step
/// seed into both routes. The LIVE reference is built by calling
/// `resolvedStepNotes` step-by-step (exactly as `prepareTick` does), threading
/// `GeneratedSourceEvaluationState` across the bar; the PRECOMPUTE route is
/// `BarPrecomputeEvaluator.precompute` over the whole bar. The two dispatch maps
/// must be byte-identical — pure data, no `AVAudioEngine`.
///
/// # Why it starts RED (TDD)
///
/// On current code `BarPrecomputeEvaluator.precompute` is a no-op stub
/// (`Sources/Engine/BarPrecompute.swift`) that returns `PrecomputedBar.empty`.
/// So every precomputed step yields an empty dispatch map `[:]`, which does NOT
/// equal the live, non-empty per-step map — every equivalence assertion FAILS.
/// The adversarial audit (`test_adversarial_emptyPrecomputedBar_...`) pins this:
/// an empty bar (a precompute that does not generate) CANNOT satisfy the gate,
/// so the gate is not ceremonial.
final class PrecomputeBarEquivalenceTests: XCTestCase {

    // MARK: - Deterministic seeded RNG (test-only)

    /// A small splitmix64 so each step's evaluation is reproducible and the two
    /// routes are byte-comparable. (Mirrors the seeded RNG used elsewhere in the
    /// suite, e.g. `StepAlgoTests`.)
    private struct SeededRNG: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed &+ 0x9E3779B97F4A7C15 }
        mutating func next() -> UInt64 {
            state = state &+ 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    private let stepsPerBar = 16
    private let baseSeed: UInt64 = 0xA11CE5

    /// Deterministic per-step seed shared by both routes.
    private func seed(forStep step: Int) -> UInt64 {
        baseSeed ^ (UInt64(bitPattern: Int64(step)) &* 0x100000001B3)
    }

    // MARK: - Fixtures

    /// A RANDOM-pitch mono generator track. `.manual(pickMode: .random)` draws a
    /// pitch from the pool using the RNG every step it fires, so the realized
    /// stream genuinely depends on the RNG (and on state threading across the
    /// bar): a precompute that doesn't reproduce the live RNG stream diverges,
    /// which is exactly what the equivalence gate must catch.
    private func makeRandomPitchGeneratorProject(
        pitches: [Int] = [60, 62, 64, 65, 67, 69, 71, 72]
    ) -> (Project, UUID, BlockID) {
        let trackID = UUID(uuidString: "33333333-3333-3333-3333-333333333333")!
        let generatorID = UUID(uuidString: "44444444-4444-4444-4444-444444444444")!

        let generator = GeneratorPoolEntry(
            id: generatorID,
            name: "Random Lead",
            trackType: .monoMelodic,
            kind: .monoGenerator,
            params: .mono(
                // Fires every step (euclidean 16/16) so every step draws a pitch.
                trigger: .native(.euclidean(pulses: 16, steps: 16, offset: 0)),
                pitch: .native(.manual(pitches: pitches, pickMode: .random)),
                shape: NoteShape(velocity: 100, gateLength: 4, accent: false)
            )
        )
        let track = StepSequenceTrack(
            id: trackID,
            name: "Lead",
            pitches: [60],
            stepPattern: Array(repeating: true, count: 16),
            destination: .auInstrument(
                componentID: AudioInstrumentChoice.builtInSynth.audioComponentID,
                stateBlob: nil
            ),
            velocity: 100,
            gateLength: 4
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let phrase = PhraseModel.default(tracks: [track], layers: layers)
        let patternBank = TrackPatternBank(
            trackID: track.id,
            slots: (0..<stepsPerBar).map {
                TrackPatternSlot(slotIndex: $0, sourceRef: .generator(generator.id))
            }
        )
        let project = Project(
            version: 1,
            tracks: [track],
            generatorPool: [generator],
            layers: layers,
            patternBanks: [patternBank],
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )
        return (project, trackID, EngineController.generatorBlockID(for: trackID))
    }

    /// The LIVE reference dispatch map for a whole bar: evaluate each output step
    /// one-at-a-time exactly as `EngineController.prepareTick` does — fresh
    /// per-step RNG seeded deterministically, `GeneratedSourceEvaluationState`
    /// threaded across the bar in step order — keyed by generator block id.
    /// This is "a recorded run WITHOUT precompute."
    private func liveReferenceBar(
        snapshot: PlaybackSnapshot,
        phraseID: UUID,
        trackID: UUID,
        blockID: BlockID,
        startStep: Int,
        stepCount: Int,
        chordContext: Chord?
    ) -> [Int: [BlockID: [NoteEvent]]] {
        var state = GeneratedSourceEvaluationState()
        var byStep: [Int: [BlockID: [NoteEvent]]] = [:]
        for step in startStep..<(startStep + stepCount) {
            var rng = SeededRNG(seed: seed(forStep: step))
            let notes = EngineController.resolvedStepNotes(
                for: trackID,
                in: snapshot,
                phraseID: phraseID,
                stepIndex: step,
                chordContext: chordContext,
                state: &state,
                rng: &rng
            )
            let events = notes.map(EngineController.noteEvent(from:))
            if !events.isEmpty {
                byStep[step] = [blockID: events]
            }
        }
        return byStep
    }

    /// The PRECOMPUTE route over the whole bar — "a recorded run WITH precompute."
    private func precomputeBar(
        snapshot: PlaybackSnapshot,
        phraseID: UUID,
        trackID: UUID,
        startStep: Int,
        stepCount: Int,
        chordContext: Chord?
    ) -> PrecomputedBar {
        BarPrecomputeEvaluator.precompute(
            snapshot: snapshot,
            phraseID: phraseID,
            trackIDs: [trackID],
            blockIDForTrack: { EngineController.generatorBlockID(for: $0) },
            startStep: startStep,
            stepCount: stepCount,
            chordContext: chordContext,
            seedForStep: { self.seed(forStep: $0) }
        )
    }

    // MARK: - Gate 1 (HEADLINE): with-precompute == without-precompute

    /// THE EQUIVALENCE GATE. A precomputed bar must carry the byte-identical
    /// per-step dispatch map a live per-step evaluation produces — same notes,
    /// same order, same block-id keying. This is the spec's load-bearing Phase-2
    /// gate ("a recorded run *with* precompute == a recorded run *without*").
    func test_precomputedBar_equalsLivePerStepEvaluation_sameNotes() {
        let (project, trackID, blockID) = makeRandomPitchGeneratorProject()
        let snapshot = SequencerSnapshotCompiler.compile(project: project)
        let phraseID = snapshot.selectedPhraseID

        let live = liveReferenceBar(
            snapshot: snapshot,
            phraseID: phraseID,
            trackID: trackID,
            blockID: blockID,
            startStep: 0,
            stepCount: stepsPerBar,
            chordContext: nil
        )

        // Sanity: the live reference is a NON-EMPTY, RNG-dependent stream — so
        // the equivalence below is a real comparison, not "[:] == [:]".
        XCTAssertFalse(
            live.isEmpty,
            "fixture must realize a non-empty bar (every step fires a random-pitch note)"
        )
        let livePitches = (0..<stepsPerBar).compactMap { live[$0]?[blockID]?.first?.pitch }
        XCTAssertTrue(
            Set(livePitches).count > 1,
            "fixture must actually depend on the RNG (random-pitch draws should vary across the bar)"
        )

        let precomputed = precomputeBar(
            snapshot: snapshot,
            phraseID: phraseID,
            trackID: trackID,
            startStep: 0,
            stepCount: stepsPerBar,
            chordContext: nil
        )

        for step in 0..<stepsPerBar {
            XCTAssertEqual(
                precomputed.preparedNotesByBlockID(forStep: step),
                live[step] ?? [:],
                "step \(step): the precomputed bar must carry the byte-identical dispatch map the " +
                "live per-step evaluation produces — a recorded run WITH precompute must equal a " +
                "recorded run WITHOUT (same notes). (Precompute did not reproduce the live stream.)"
            )
        }
    }

    // MARK: - Gate 2: state threaded across the bar (in-order generation)

    /// The precompute must thread `GeneratedSourceEvaluationState` across the bar
    /// IN STEP ORDER, just like the live sequential tick path — so an order- or
    /// state-dependent generator matches. We prove the bar is order-sensitive by
    /// showing the realized pitch sequence is not constant, then assert the
    /// precompute reproduces that exact sequence step-for-step. A precompute that
    /// evaluated steps out of order, or reset state per step, would diverge here.
    func test_precomputedBar_threadsEvaluationStateInStepOrder() {
        let (project, trackID, blockID) = makeRandomPitchGeneratorProject()
        let snapshot = SequencerSnapshotCompiler.compile(project: project)
        let phraseID = snapshot.selectedPhraseID

        let live = liveReferenceBar(
            snapshot: snapshot,
            phraseID: phraseID,
            trackID: trackID,
            blockID: blockID,
            startStep: 0,
            stepCount: stepsPerBar,
            chordContext: nil
        )
        let precomputed = precomputeBar(
            snapshot: snapshot,
            phraseID: phraseID,
            trackID: trackID,
            startStep: 0,
            stepCount: stepsPerBar,
            chordContext: nil
        )

        let liveSeq = (0..<stepsPerBar).map { live[$0]?[blockID] ?? [] }
        let precomputedSeq = (0..<stepsPerBar).map { precomputed.preparedNotesByBlockID(forStep: $0)[blockID] ?? [] }

        XCTAssertEqual(
            precomputedSeq, liveSeq,
            "the precomputed bar's per-step note sequence must match the live sequential evaluation " +
            "step-for-step (evaluation state threaded across the bar IN ORDER)."
        )
    }

    // MARK: - Gate 3: consumption is pure (no RNG/generation on read)

    /// Consuming the precomputed bar is a pure read: the same step read twice
    /// returns the same map, and a step OUTSIDE the bar returns an empty map (no
    /// spurious triggers, no re-generation). This is what lets the tick path
    /// dispatch from the bar WITHOUT any RNG/alloc (the spec's other Phase-2
    /// requirement, also guarded by realtime-path-lint).
    func test_precomputedBar_consumptionIsPureAndStable() {
        let (project, trackID, blockID) = makeRandomPitchGeneratorProject()
        let snapshot = SequencerSnapshotCompiler.compile(project: project)
        let phraseID = snapshot.selectedPhraseID

        // A bar covering steps 0..<16 must carry SOME notes (the fixture fires
        // every step) — proven against the live reference so this isn't vacuous.
        let live = liveReferenceBar(
            snapshot: snapshot,
            phraseID: phraseID,
            trackID: trackID,
            blockID: blockID,
            startStep: 0,
            stepCount: stepsPerBar,
            chordContext: nil
        )
        XCTAssertFalse(live.isEmpty, "fixture sanity: live bar is non-empty")

        let precomputed = precomputeBar(
            snapshot: snapshot,
            phraseID: phraseID,
            trackID: trackID,
            startStep: 0,
            stepCount: stepsPerBar,
            chordContext: nil
        )

        // The bar must actually carry the realized notes (not be empty) ...
        XCTAssertEqual(
            precomputed.preparedNotesByBlockID(forStep: 0),
            live[0] ?? [:],
            "the precomputed bar must carry step 0's realized notes for pure consumption"
        )
        // ... reading the same step twice is stable (immutable, no re-generation) ...
        XCTAssertEqual(
            precomputed.preparedNotesByBlockID(forStep: 5),
            precomputed.preparedNotesByBlockID(forStep: 5),
            "reading a step twice must return the identical map — consumption does no RNG/generation"
        )
        // ... and a step outside the bar yields an empty map.
        XCTAssertEqual(
            precomputed.preparedNotesByBlockID(forStep: stepsPerBar + 1), [:],
            "a step outside the precomputed bar must yield an empty dispatch map (no spurious triggers)"
        )
    }

    // MARK: - Gate 4: invalidation — a changed snapshot regenerates

    /// A precompute fed a CHANGED snapshot (different pitch pool) must produce
    /// the changed stream — equal to the live evaluation of the CHANGED snapshot,
    /// and NOT equal to the original. This pins the spec's "invalidate +
    /// regenerate on any generation-input change," and forecloses a cheat where
    /// precompute returns a stale or hardcoded bar.
    func test_precomputedBar_changedSnapshot_regeneratesNewStream() {
        let (projectA, trackID, blockID) = makeRandomPitchGeneratorProject(
            pitches: [60, 62, 64, 65, 67, 69, 71, 72]
        )
        // A disjoint pitch pool (an octave up) — the realized pitches must move.
        let (projectB, _, _) = makeRandomPitchGeneratorProject(
            pitches: [72, 74, 76, 77, 79, 81, 83, 84]
        )
        let snapshotA = SequencerSnapshotCompiler.compile(project: projectA)
        let snapshotB = SequencerSnapshotCompiler.compile(project: projectB)
        let phraseID = snapshotA.selectedPhraseID

        let liveB = liveReferenceBar(
            snapshot: snapshotB,
            phraseID: phraseID,
            trackID: trackID,
            blockID: blockID,
            startStep: 0,
            stepCount: stepsPerBar,
            chordContext: nil
        )
        let precomputedB = precomputeBar(
            snapshot: snapshotB,
            phraseID: phraseID,
            trackID: trackID,
            startStep: 0,
            stepCount: stepsPerBar,
            chordContext: nil
        )

        // Precompute on the changed snapshot equals the live changed stream ...
        for step in 0..<stepsPerBar {
            XCTAssertEqual(
                precomputedB.preparedNotesByBlockID(forStep: step),
                liveB[step] ?? [:],
                "step \(step): precompute on the changed snapshot must equal the live evaluation of " +
                "that changed snapshot (invalidate + regenerate on a generation-input change)"
            )
        }

        // ... and differs from the ORIGINAL snapshot's stream (no stale cheat).
        let precomputedA = precomputeBar(
            snapshot: snapshotA,
            phraseID: phraseID,
            trackID: trackID,
            startStep: 0,
            stepCount: stepsPerBar,
            chordContext: nil
        )
        let seqA = (0..<stepsPerBar).map { precomputedA.preparedNotesByBlockID(forStep: $0)[blockID] ?? [] }
        let seqB = (0..<stepsPerBar).map { precomputedB.preparedNotesByBlockID(forStep: $0)[blockID] ?? [] }
        XCTAssertNotEqual(
            seqA, seqB,
            "a generation-input change (disjoint pitch pool) must change the precomputed stream — " +
            "a precompute that returns a stale/hardcoded bar would fail this"
        )
    }

    // MARK: - Adversarial audit: an empty (no-op) precompute MUST fail the gate

    /// ADVERSARIAL AUDIT (frozen-rail non-negotiable): if precompute does not
    /// actually generate (the no-op stub returns `PrecomputedBar.empty`, i.e.
    /// the feature reverted), the equivalence CANNOT hold — every step's
    /// dispatch map is empty, which does not equal the live, non-empty bar. This
    /// proves the gate is load-bearing: it can only pass when precompute
    /// genuinely reproduces the live note stream.
    ///
    /// Phrased as a property over an explicitly-empty `PrecomputedBar` so it
    /// stays a meaningful guard regardless of how the builder implements the
    /// evaluator.
    func test_adversarial_emptyPrecomputedBar_cannotEqualLiveBar() {
        let (project, trackID, blockID) = makeRandomPitchGeneratorProject()
        let snapshot = SequencerSnapshotCompiler.compile(project: project)
        let phraseID = snapshot.selectedPhraseID

        let live = liveReferenceBar(
            snapshot: snapshot,
            phraseID: phraseID,
            trackID: trackID,
            blockID: blockID,
            startStep: 0,
            stepCount: stepsPerBar,
            chordContext: nil
        )
        XCTAssertFalse(live.isEmpty, "fixture must be a non-empty live bar")

        // An empty precomputed bar (what a no-op precompute produces) feeds
        // nothing to the dispatch path, so it can never equal the live stream.
        let emptyBar = PrecomputedBar.empty(startStep: 0, stepCount: stepsPerBar)
        var matchedAnyRealizedStep = false
        for step in 0..<stepsPerBar where (live[step] ?? [:]).isEmpty == false {
            if emptyBar.preparedNotesByBlockID(forStep: step) == live[step] {
                matchedAnyRealizedStep = true
            }
            XCTAssertEqual(
                emptyBar.preparedNotesByBlockID(forStep: step), [:],
                "an empty (no-op) precomputed bar must feed nothing to the dispatch path"
            )
        }
        XCTAssertFalse(
            matchedAnyRealizedStep,
            "a no-op / empty precomputed bar must NOT reproduce any realized live step — otherwise the " +
            "equivalence gate would pass without the feature (ceremonial). blockID=\(blockID)"
        )
    }
}
