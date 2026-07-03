import XCTest
@testable import SequencerAI

/// WS4 acceptance coverage (pattern-generator-foundations spec, "Generator
/// editor + vocabulary + identity"):
///
/// - **AC2** — the chord sidechain is a PITCH-POOL FILTER only (synthesis
///   semantics correction): with a chord that CHANGES MID-RUN, the realized
///   trigger stream is byte-identical with and without the sidechain, while
///   the pitch stream moves — proven over the offline realized-stream seam
///   (`EngineController.resolvedStepNotes`, the same evaluation the live tick
///   and the precompute route consume; the event-recorder proper is not yet
///   on main).
/// - **AC3** — the new trigger/pitch vocabulary (weighted + cluster, pool /
///   selection / deviation) is deterministic under fixed seeds AND keeps the
///   Phase-2 precompute equivalence contract. This EXTENDS the frozen
///   `PrecomputeBarEquivalenceTests` rail to the new algo kinds without
///   editing the frozen file.
/// - **AC5** — the generator editor's result strip renders the SAME realized
///   bar the precompute route publishes for a deterministic generator: the
///   strip is fed by `GeneratorResultStrip.barContent` (the shared evaluator),
///   never a separate simulation.
final class GeneratorVocabAcceptanceTests: XCTestCase {

    // MARK: - Deterministic seeded RNG (mirrors the frozen rail's splitmix64)

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
    private let baseSeed: UInt64 = 0x5EED_4AC2

    private func seed(forStep step: Int) -> UInt64 {
        baseSeed ^ (UInt64(bitPattern: Int64(step)) &* 0x100000001B3)
    }

    // MARK: - Fixture

    private func makeGeneratorProject(
        params: GeneratorParams
    ) -> (project: Project, trackID: UUID, blockID: BlockID) {
        let trackID = UUID(uuidString: "AAAAAAAA-AAAA-4AAA-8AAA-AAAAAAAAAAAA")!
        let generatorID = UUID(uuidString: "BBBBBBBB-BBBB-4BBB-8BBB-BBBBBBBBBBBB")!

        let generator = GeneratorPoolEntry(
            id: generatorID,
            name: "Vocab Generator",
            trackType: .monoMelodic,
            kind: .monoGenerator,
            params: params
        )
        let track = StepSequenceTrack(
            id: trackID,
            name: "Vocab",
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

    /// Offline realized run: evaluate steps one-at-a-time exactly as the live
    /// tick path does (fresh deterministic per-step RNG, evaluation state
    /// threaded in step order), with a per-step chord context so the chord can
    /// change mid-run.
    private func realizedRun(
        project: Project,
        trackID: UUID,
        stepCount: Int,
        chordForStep: (Int) -> Chord?
    ) -> [[GeneratedNote]] {
        let snapshot = SequencerSnapshotCompiler.compile(project: project)
        let phraseID = snapshot.selectedPhraseID
        var state = GeneratedSourceEvaluationState()
        return (0..<stepCount).map { step in
            var rng = SeededRNG(seed: seed(forStep: step))
            return EngineController.resolvedStepNotes(
                for: trackID,
                in: snapshot,
                phraseID: phraseID,
                stepIndex: step,
                chordContext: chordForStep(step),
                state: &state,
                rng: &rng
            )
        }
    }

    /// The trigger-stream projection: everything about a realized step EXCEPT
    /// pitch (fire/rest, note count, velocity, length, voice tag). AC2 pins
    /// this byte-identical with/without the chord sidechain.
    private func triggerStream(_ run: [[GeneratedNote]]) -> [[String]] {
        run.map { notes in
            notes.map { "\($0.velocity):\($0.length):\($0.voiceTag ?? "-")" }
        }
    }

    private func pitchStream(_ run: [[GeneratedNote]]) -> [[Int]] {
        run.map { $0.map(\.pitch) }
    }

    // MARK: - AC2: chord sidechain = pitch-pool filter only (mid-run change)

    func test_chordSidechain_midRunChordChange_movesPitchStreamOnly() {
        let trigger = TriggerStageNode.native(
            .weighted(weights: [1, 0.35, 0, 0.8, 0.5, 0, 0.9, 0.15], steps: 8, cluster: 0.4)
        )
        let poolAlgo = PitchAlgo.pool(
            root: 60, scale: .major, spread: 12, selection: .uniform, deviation: .none
        )
        let shape = NoteShape(velocity: 96, gateLength: 3, accent: false)
        let plainParams = GeneratorParams.mono(
            trigger: trigger, pitch: .native(poolAlgo), shape: shape
        )
        let followingParams = GeneratorParams.mono(
            trigger: trigger,
            pitch: .native(poolAlgo, harmonicSidechain: .projectChordContext),
            shape: shape
        )

        // The chord changes mid-run: F minor for bar 1, A major for bar 2.
        let chordA = Chord(root: 65, chordType: ChordID.minorTriad.rawValue, scale: ScaleID.naturalMinor.rawValue)
        let chordB = Chord(root: 57, chordType: ChordID.majorTriad.rawValue, scale: ScaleID.major.rawValue)
        let chordForStep: (Int) -> Chord? = { $0 < self.stepsPerBar ? chordA : chordB }

        let (plainProject, plainTrackID, _) = makeGeneratorProject(params: plainParams)
        let (followingProject, followingTrackID, _) = makeGeneratorProject(params: followingParams)

        let plain = realizedRun(
            project: plainProject, trackID: plainTrackID,
            stepCount: stepsPerBar * 2, chordForStep: chordForStep
        )
        let following = realizedRun(
            project: followingProject, trackID: followingTrackID,
            stepCount: stepsPerBar * 2, chordForStep: chordForStep
        )

        // Non-vacuous: the probabilistic weighted trigger fires SOME steps and
        // rests on others, so trigger equality below is a real comparison.
        let firedSteps = plain.filter { !$0.isEmpty }.count
        XCTAssertGreaterThan(firedSteps, 0, "fixture must fire")
        XCTAssertLessThan(firedSteps, stepsPerBar * 2, "fixture must also rest")

        // Trigger stream byte-identical with vs without the sidechain — the
        // chord may NEVER touch the trigger stage.
        XCTAssertEqual(
            triggerStream(plain), triggerStream(following),
            "chord sidechain must be trigger-invariant (pitch-pool filter ONLY)"
        )

        // The pitch stream moves.
        XCTAssertNotEqual(
            pitchStream(plain), pitchStream(following),
            "attaching the chord sidechain must change realized pitches"
        )

        // The MID-RUN change lands in the pitch domain: bar 1's notes draw
        // from F-minor chord tones, bar 2's from A-major chord tones (the
        // pool = scale INTERSECT chord filter contract).
        let chordAClasses: Set<Int> = [5, 8, 0] // F minor triad
        let chordBClasses: Set<Int> = [9, 1, 4] // A major triad
        let bar1Classes = Set(following.prefix(stepsPerBar).flatMap { $0.map { $0.pitch % 12 } })
        let bar2Classes = Set(following.suffix(stepsPerBar).flatMap { $0.map { $0.pitch % 12 } })
        XCTAssertFalse(bar1Classes.isEmpty)
        XCTAssertFalse(bar2Classes.isEmpty)
        XCTAssertTrue(
            bar1Classes.isSubset(of: chordAClasses),
            "bar 1 must draw from the F-minor-filtered pool, got \(bar1Classes)"
        )
        XCTAssertTrue(
            bar2Classes.isSubset(of: chordBClasses),
            "bar 2 must draw from the A-major-filtered pool after the mid-run change, got \(bar2Classes)"
        )
    }

    // MARK: - AC3: precompute equivalence extended to the new algo kinds

    func test_precomputeEquivalence_weightedClusterTrigger() {
        assertPrecomputeMatchesLiveAndIsDeterministic(
            params: .mono(
                trigger: .native(
                    .weighted(weights: [1, 0.3, 0, 0.75, 0.5, 0, 0.9, 0.2], steps: 8, cluster: 0.6)
                ),
                pitch: .native(.pool(root: 62, scale: .dorian, spread: 12, selection: .balanced, deviation: .none)),
                shape: NoteShape(velocity: 92, gateLength: 3, accent: false)
            )
        )
    }

    func test_precomputeEquivalence_poolPitchWithDeviationAndMemory() {
        assertPrecomputeMatchesLiveAndIsDeterministic(
            params: .mono(
                trigger: .native(.euclidean(pulses: 16, steps: 16, offset: 0)),
                pitch: .native(.pool(
                    root: 60,
                    scale: .major,
                    spread: 12,
                    selection: PitchSelectionSettings(memory: 0.6),
                    deviation: PitchDeviationSettings(accidentalChance: 0.5, octaveSpan: 1, leadingChance: 0.3)
                )),
                shape: NoteShape(velocity: 100, gateLength: 4, accent: false)
            )
        )
    }

    func test_precomputeEquivalence_manualTriggerPattern() {
        assertPrecomputeMatchesLiveAndIsDeterministic(
            params: .mono(
                trigger: .native(.manual(pattern: [true, false, false, true, false, true, false, false])),
                pitch: .native(.pool(root: 57, scale: .naturalMinor, spread: 12, selection: .uniform, deviation: .none)),
                shape: NoteShape(velocity: 84, gateLength: 2, accent: false)
            )
        )
    }

    private func assertPrecomputeMatchesLiveAndIsDeterministic(
        params: GeneratorParams,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let (project, trackID, blockID) = makeGeneratorProject(params: params)
        let snapshot = SequencerSnapshotCompiler.compile(project: project)
        let phraseID = snapshot.selectedPhraseID

        // LIVE reference: sequential per-step evaluation, state threaded.
        var state = GeneratedSourceEvaluationState()
        var live: [Int: [BlockID: [NoteEvent]]] = [:]
        for step in 0..<stepsPerBar {
            var rng = SeededRNG(seed: seed(forStep: step))
            let notes = EngineController.resolvedStepNotes(
                for: trackID,
                in: snapshot,
                phraseID: phraseID,
                stepIndex: step,
                chordContext: nil,
                state: &state,
                rng: &rng
            )
            let events = notes.map(EngineController.noteEvent(from:))
            if !events.isEmpty {
                live[step] = [blockID: events]
            }
        }
        XCTAssertFalse(live.isEmpty, "fixture must realize a non-empty bar", file: file, line: line)

        let precompute: () -> PrecomputedBar = {
            BarPrecomputeEvaluator.precompute(
                snapshot: snapshot,
                phraseID: phraseID,
                trackIDs: [trackID],
                blockIDForTrack: { EngineController.generatorBlockID(for: $0) },
                startStep: 0,
                stepCount: self.stepsPerBar,
                chordContext: nil,
                seedForStep: { self.seed(forStep: $0) }
            )
        }
        let precomputed = precompute()

        for step in 0..<stepsPerBar {
            XCTAssertEqual(
                precomputed.preparedNotesByBlockID(forStep: step),
                live[step] ?? [:],
                "step \(step): precompute must reproduce the live stream for the new algo kinds",
                file: file, line: line
            )
        }

        // Deterministic under fixed seeds: the same inputs precompute the
        // byte-identical bar again.
        let second = precompute()
        for step in 0..<stepsPerBar {
            XCTAssertEqual(
                precomputed.preparedNotesByBlockID(forStep: step),
                second.preparedNotesByBlockID(forStep: step),
                "step \(step): fixed seeds must reproduce the identical bar",
                file: file, line: line
            )
        }
    }

    // MARK: - AC5: result strip == precomputed bar (no separate simulation)

    func test_resultStripContent_equalsPrecomputedBar_forDeterministicGenerator() {
        // Fully deterministic vocabulary: 0/1 weights (no trigger RNG draw)
        // and a single-note pool (spread 0), so the live/preview RNG streams
        // cannot diverge and byte-equality is exact.
        let params = GeneratorParams.mono(
            trigger: .native(.weighted(
                weights: [1, 0, 0, 1, 0, 0, 1, 0, 1, 0, 0, 1, 0, 0, 1, 1],
                steps: 16,
                cluster: 0
            )),
            pitch: .native(.pool(root: 60, scale: .major, spread: 0, selection: .uniform, deviation: .none)),
            shape: NoteShape(velocity: 88, gateLength: 2, accent: false)
        )
        let (project, trackID, blockID) = makeGeneratorProject(params: params)
        let snapshot = SequencerSnapshotCompiler.compile(project: project)

        let precomputed = BarPrecomputeEvaluator.precompute(
            snapshot: snapshot,
            phraseID: snapshot.selectedPhraseID,
            trackIDs: [trackID],
            blockIDForTrack: { EngineController.generatorBlockID(for: $0) },
            startStep: 0,
            stepCount: stepsPerBar,
            chordContext: nil,
            seedForStep: { self.seed(forStep: $0) }
        )

        // THE strip content function the editor view renders (AC5 seam).
        let strip = GeneratorResultStrip.barContent(for: params, clipChoices: [])
        XCTAssertEqual(strip.count, stepsPerBar)
        XCTAssertFalse(strip.allSatisfy(\.isEmpty), "fixture must realize a non-empty strip")

        for step in 0..<stepsPerBar {
            let stripEvents = strip[step].map(EngineController.noteEvent(from:))
            let precomputedEvents = precomputed.preparedNotesByBlockID(forStep: step)[blockID] ?? []
            XCTAssertEqual(
                stripEvents,
                precomputedEvents,
                "step \(step): the result strip must render the same realized bar the precompute " +
                "publishes — same evaluator source, no separate simulation drift"
            )
        }
    }
}
