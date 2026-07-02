import AVFoundation
import XCTest
@testable import SequencerAI

/// PHASE D RAIL — cross-bar generator-state continuity in the bar-precompute
/// path (`docs/plans/2026-07-01-engine-timing-recovery-implementation.md`,
/// Phase D: "Fix generator-state continuity across bars. The current risk is
/// per-bar reset changing Markov/last-note behavior.").
///
/// # The defect this pins (RED on pre-fix code)
///
/// The LIVE tick path threads `GeneratedSourceEvaluationState` (e.g.
/// `lastPitchesByLane` for Markov / last-pitch generators) across steps AND
/// bars: `prepareTick` copies the tick-state's generated states, mutates them
/// per track, and commits them back, so the next tick continues from them.
///
/// The PRECOMPUTE path does not: `BarPrecomputeEvaluator.precompute` starts
/// each track's state EMPTY for every bar, so every precomputed bar restarts
/// stateful generators from scratch. Consequently:
///
///   1. a Markov/last-pitch generator behaves differently under precompute
///      than under the live path (bar boundaries "forget" the walk);
///   2. after consuming a precomputed bar, the tick-state's generated states
///      for those tracks are stale, so a later cold-boundary fallback
///      (`BarPrecomputeScheduler.resolveStepFallback`) would evaluate from
///      stale state.
///
/// `PrecomputeBarEquivalenceTests` (frozen) does not catch this because its
/// live reference ALSO resets state per bar — its equivalence is intra-bar
/// only. This rail's live reference threads ONE state continuously across
/// 2 consecutive bars, exactly as the live tick path would.
///
/// # Determinism
///
/// Same pattern as the frozen equivalence rail: a deterministic splitmix64
/// seed per step is injected into both routes, so the two streams are
/// byte-comparable; the only free variable is the cross-bar state threading
/// under test. The engine-level test uses the sequential-pitch fixture
/// (RNG-independent) so the adopted state value is an exact expectation.
final class PrecomputeStateContinuityTests: XCTestCase {

    // MARK: - Deterministic seeded RNG (test-only; same constants as the
    // equivalence rail's SeededRNG and the scheduler's PrecomputeSplitMix64)

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
    private let baseSeed: UInt64 = 0xC0117141117

    /// Deterministic per-step seed shared by both routes.
    private func seed(forStep step: Int) -> UInt64 {
        baseSeed ^ (UInt64(bitPattern: Int64(step)) &* 0x100000001B3)
    }

    override func setUp() {
        super.setUp()
        MainAudioGraph.simulateAudioInputConnectionForTesting = true
    }

    override func tearDown() {
        MainAudioGraph.simulateAudioInputConnectionForTesting = false
        super.tearDown()
    }

    // MARK: - Fixtures

    /// A MARKOV-pitch mono generator track. The Markov pitch stage conditions
    /// each draw on `lastPitch` (the `GeneratedSourceEvaluationState` lane
    /// state): with `lastPitch == nil` it draws uniformly from the scale pool,
    /// with `lastPitch` set it draws from the distance/direction-weighted
    /// distribution around it — a DIFFERENT RNG consumption pattern and a
    /// different stream. So a precompute that resets state at a bar boundary
    /// diverges from a live run that threads state across the boundary, which
    /// is exactly what this rail must catch.
    private func makeMarkovGeneratorProject() -> (Project, UUID, BlockID) {
        let trackID = UUID(uuidString: "77777777-7777-7777-7777-777777777777")!
        let generatorID = UUID(uuidString: "88888888-8888-8888-8888-888888888888")!

        let generator = GeneratorPoolEntry(
            id: generatorID,
            name: "Markov Lead",
            trackType: .monoMelodic,
            kind: .monoGenerator,
            params: .mono(
                // Fires every step (euclidean 16/16) so every step draws a pitch.
                trigger: .native(.euclidean(pulses: 16, steps: 16, offset: 0)),
                pitch: .native(.markov(root: 60, scale: .major, styleID: .balanced, leap: 0.35, color: 0)),
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

    /// The rail-fixture sequential-pitch generator (RNG-independent realized
    /// stream) for the engine-level state-adoption test. Pitch at step N is
    /// `pitches[N % 8]` deterministically, and every evaluated step writes the
    /// realized pitch into the evaluation state's lane 0 (`setLastPitch`).
    private let sequentialPitches = [60, 62, 64, 65, 67, 69, 71, 72]

    private func makeSequentialGeneratorProject() -> (Project, UUID, BlockID) {
        let trackID = UUID(uuidString: "99999999-9999-9999-9999-999999999999")!
        let generatorID = UUID(uuidString: "AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA")!

        let generator = GeneratorPoolEntry(
            id: generatorID,
            name: "Sequential Lead",
            trackType: .monoMelodic,
            kind: .monoGenerator,
            params: .mono(
                trigger: .native(.euclidean(pulses: 16, steps: 16, offset: 0)),
                pitch: .native(.manual(pitches: sequentialPitches, pickMode: .sequential)),
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

    // MARK: - Live continuous reference

    /// The LIVE reference dispatch map over an arbitrary step range: evaluate
    /// each output step one-at-a-time exactly as `EngineController.prepareTick`
    /// does on the live path — fresh per-step RNG seeded deterministically,
    /// with ONE `GeneratedSourceEvaluationState` threaded CONTINUOUSLY across
    /// the whole range (across bar boundaries). This is what the live tick
    /// path produces for consecutive bars.
    private func liveContinuousReference(
        snapshot: PlaybackSnapshot,
        phraseID: UUID,
        trackID: UUID,
        blockID: BlockID,
        startStep: Int,
        stepCount: Int
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
                chordContext: nil,
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

    // MARK: - THE CONTINUITY GATE (RED on pre-fix code)

    /// Two CONSECUTIVE precomputed bars, computed the way the production
    /// `BarPrecomputeScheduler` computes them (one `precompute` call per bar),
    /// must together reproduce the live reference stream that threads
    /// generator state CONTINUOUSLY across the bar boundary. On pre-fix code
    /// this FAILS at bar 1: the second bar restarts the Markov walk from empty
    /// state (`lastPitch == nil`), so its stream diverges from the live one.
    func test_consecutivePrecomputedBars_threadGeneratorStateAcrossBars() {
        let (project, trackID, blockID) = makeMarkovGeneratorProject()
        let snapshot = SequencerSnapshotCompiler.compile(project: project)
        let phraseID = snapshot.selectedPhraseID

        // The live path's stream over TWO consecutive bars, ONE state threaded
        // continuously across the boundary.
        let live = liveContinuousReference(
            snapshot: snapshot,
            phraseID: phraseID,
            trackID: trackID,
            blockID: blockID,
            startStep: 0,
            stepCount: 2 * stepsPerBar
        )

        // Sanity: a non-empty, genuinely RNG/state-dependent fixture — every
        // step fires and the Markov walk moves.
        XCTAssertEqual(
            live.count, 2 * stepsPerBar,
            "fixture must realize a note on every step of both bars"
        )
        let livePitches = (0..<(2 * stepsPerBar)).compactMap { live[$0]?[blockID]?.first?.pitch }
        XCTAssertTrue(
            Set(livePitches).count > 1,
            "fixture must actually walk (Markov draws should vary across the bars)"
        )

        // Bar 0, then bar 1, precomputed per bar exactly as the scheduler
        // does: bar 1 is SEEDED from bar 0's published end states (the Phase D
        // chain `BarPrecomputeScheduler.request` performs at compute time).
        let bar0 = BarPrecomputeEvaluator.precompute(
            snapshot: snapshot,
            phraseID: phraseID,
            trackIDs: [trackID],
            blockIDForTrack: { EngineController.generatorBlockID(for: $0) },
            startStep: 0,
            stepCount: stepsPerBar,
            chordContext: nil,
            seedForStep: { self.seed(forStep: $0) }
        )
        let bar1 = BarPrecomputeEvaluator.precompute(
            snapshot: snapshot,
            phraseID: phraseID,
            trackIDs: [trackID],
            blockIDForTrack: { EngineController.generatorBlockID(for: $0) },
            startStep: stepsPerBar,
            stepCount: stepsPerBar,
            chordContext: nil,
            initialStatesByTrackID: bar0.endStatesByTrackID,
            seedForStep: { self.seed(forStep: $0) }
        )

        // Bar 0 must match (intra-bar equivalence — already pinned elsewhere).
        for step in 0..<stepsPerBar {
            XCTAssertEqual(
                bar0.preparedNotesByBlockID(forStep: step),
                live[step] ?? [:],
                "bar 0 step \(step): precompute must reproduce the live stream"
            )
        }
        // Bar 1 must CONTINUE the stream — the bar boundary must not reset the
        // generator state. On pre-fix code this fails: the precompute restarts
        // the Markov walk from scratch every bar.
        for step in stepsPerBar..<(2 * stepsPerBar) {
            XCTAssertEqual(
                bar1.preparedNotesByBlockID(forStep: step),
                live[step] ?? [:],
                "bar 1 step \(step): a consecutive precomputed bar must CONTINUE the generator state " +
                "from the previous bar's end (Markov/last-pitch continuity across the bar boundary), " +
                "matching a live run that threads state continuously. (The precompute reset state at " +
                "the bar boundary.)"
            )
        }
    }

    // MARK: - Adversarial: an UNCHAINED second bar must diverge

    /// Proves the continuity gate above is load-bearing for this fixture and
    /// seed: a second bar precomputed WITHOUT the previous bar's end states
    /// (the pre-fix per-bar reset behavior) must NOT reproduce the continuous
    /// live stream. If this ever passed, the fixture would be insensitive to
    /// chaining and the gate ceremonial.
    func test_adversarial_unchainedSecondBar_divergesFromContinuousReference() {
        let (project, trackID, blockID) = makeMarkovGeneratorProject()
        let snapshot = SequencerSnapshotCompiler.compile(project: project)
        let phraseID = snapshot.selectedPhraseID

        let live = liveContinuousReference(
            snapshot: snapshot,
            phraseID: phraseID,
            trackID: trackID,
            blockID: blockID,
            startStep: 0,
            stepCount: 2 * stepsPerBar
        )
        // Bar 1 with EMPTY initial states — the per-bar reset this rail exists
        // to forbid on the chained path.
        let unchainedBar1 = BarPrecomputeEvaluator.precompute(
            snapshot: snapshot,
            phraseID: phraseID,
            trackIDs: [trackID],
            blockIDForTrack: { EngineController.generatorBlockID(for: $0) },
            startStep: stepsPerBar,
            stepCount: stepsPerBar,
            chordContext: nil,
            seedForStep: { self.seed(forStep: $0) }
        )
        let liveSeq = (stepsPerBar..<(2 * stepsPerBar)).map { live[$0]?[blockID] ?? [] }
        let unchainedSeq = (stepsPerBar..<(2 * stepsPerBar)).map {
            unchainedBar1.preparedNotesByBlockID(forStep: $0)[blockID] ?? []
        }
        XCTAssertNotEqual(
            unchainedSeq, liveSeq,
            "a second bar precomputed from EMPTY state must diverge from the continuous live " +
            "stream for this fixture/seed — otherwise the continuity gate would be ceremonial"
        )
    }

    // MARK: - Scheduler chaining (end-to-end through request/publish/consume)

    /// A sparse-trigger fixture (fires ONLY at source step 0 of a 32-step
    /// trigger cycle, deterministic euclidean, sequential pitch) makes the
    /// scheduler's chain seed directly observable with NO RNG dependence:
    /// bar 0 realizes exactly one note (pitch 60) and ends with lane-0 last
    /// pitch 60; bar 1 fires NO step, so its end states are exactly its
    /// INITIAL states — which must have been chained from bar 0's end states.
    private func makeSparseTriggerProject() -> (Project, UUID) {
        let trackID = UUID(uuidString: "BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB")!
        let generatorID = UUID(uuidString: "CCCCCCCC-CCCC-CCCC-CCCC-CCCCCCCCCCCC")!

        let generator = GeneratorPoolEntry(
            id: generatorID,
            name: "Sparse Lead",
            trackType: .monoMelodic,
            kind: .monoGenerator,
            params: .mono(
                // ONE pulse in a 32-step cycle: fires at source step 0 only —
                // bar 0 (steps 0..<16) fires once, bar 1 (steps 16..<32) never.
                trigger: .native(.euclidean(pulses: 1, steps: 32, offset: 0)),
                pitch: .native(.manual(pitches: sequentialPitches, pickMode: .sequential)),
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
        return (project, trackID)
    }

    /// End-to-end through the REAL scheduler (request → serial-queue compute →
    /// publish → consume): the next consecutive bar's precompute is seeded from
    /// the previous bar's published end states; a revision bump or a gap
    /// resets the chain to the caller-provided fallback states.
    func test_scheduler_seedsNextBarFromPreviousBarEndStates_andResetsOnRevisionBumpOrGap() {
        let (project, trackID) = makeSparseTriggerProject()
        let snapshot = SequencerSnapshotCompiler.compile(project: project)
        let phraseID = snapshot.selectedPhraseID
        let scheduler = BarPrecomputeScheduler()
        let waitSeconds: TimeInterval = 5

        func request(
            startStep: Int,
            revision: UInt64,
            fallback: [UUID: GeneratedSourceEvaluationState] = [:]
        ) {
            scheduler.request(
                snapshot: snapshot,
                phraseID: phraseID,
                trackIDs: [trackID],
                blockIDForTrack: { EngineController.generatorBlockID(for: $0) },
                startStep: startStep,
                stepCount: stepsPerBar,
                chordContext: nil,
                fallbackStatesByTrackID: fallback,
                revision: revision
            )
        }
        func consume(startStep: Int, revision: UInt64) -> PrecomputedBar? {
            scheduler.consume(
                phraseID: phraseID,
                startStep: startStep,
                stepCount: stepsPerBar,
                revision: revision,
                boundaryWaitSeconds: waitSeconds
            )
        }
        func lanePitch(_ bar: PrecomputedBar?) -> Int? {
            bar?.endStatesByTrackID[trackID]?.lastPitchesByLane.first ?? nil
        }

        // Bar 0: fires once at step 0 → end state lane-0 last pitch is 60.
        request(startStep: 0, revision: 7)
        let bar0 = consume(startStep: 0, revision: 7)
        XCTAssertNotNil(bar0, "bar 0 must publish within the bounded wait")
        XCTAssertEqual(
            lanePitch(bar0), sequentialPitches[0],
            "bar 0's end state must carry the realized pitch of its only fired step"
        )

        // Bar 1 (consecutive, same revision): fires NO step, so its end states
        // ARE its initial states — which must be bar 0's end states (chained).
        request(startStep: stepsPerBar, revision: 7)
        let bar1 = consume(startStep: stepsPerBar, revision: 7)
        XCTAssertNotNil(bar1, "bar 1 must publish within the bounded wait")
        XCTAssertEqual(
            lanePitch(bar1), sequentialPitches[0],
            "the scheduler must seed a consecutive bar's precompute from the previous bar's " +
            "published end states (cross-bar generator-state continuity)"
        )

        // Revision bump: the predecessor key no longer matches, so the chain
        // resets to the fallback (empty here) — no inherited last pitch.
        request(startStep: stepsPerBar, revision: 8)
        let bar1Bumped = consume(startStep: stepsPerBar, revision: 8)
        XCTAssertNotNil(bar1Bumped, "revision-8 bar must publish within the bounded wait")
        XCTAssertNil(
            lanePitch(bar1Bumped),
            "a generation-input revision bump must RESET the cross-bar chain (mirrors the live " +
            "path's generated-state reset on a structural change)"
        )

        // Gap: startStep 48 has no published predecessor (bar at 32 was never
        // requested), so the seed is the caller-provided fallback tick states.
        let fallbackState = GeneratedSourceEvaluationState(lastPitchesByLane: [99])
        request(startStep: 3 * stepsPerBar, revision: 7, fallback: [trackID: fallbackState])
        let bar3 = consume(startStep: 3 * stepsPerBar, revision: 7)
        XCTAssertNotNil(bar3, "gap bar must publish within the bounded wait")
        XCTAssertEqual(
            lanePitch(bar3), 99,
            "with no chainable predecessor, the precompute must seed from the caller-provided " +
            "tick-state generated states"
        )
    }

    // MARK: - Consume-side adoption (RED on pre-fix code)

    /// When the tick path consumes a precomputed bar, the tick-state's
    /// generated states must be brought in sync with the bar's realized
    /// content — otherwise a later cold-boundary fallback
    /// (`BarPrecomputeScheduler.resolveStepFallback`) evaluates from stale
    /// state. Deterministic expectation: the sequential-pitch fixture realizes
    /// `pitches[15 % 8] == 72` at the bar's last step and every evaluated step
    /// writes its realized pitch into lane 0 of the evaluation state, so after
    /// a pumped bar the tick-state's lane-0 last pitch must be 72. On pre-fix
    /// code the consumed bar never updates the tick-state (only the tick-0
    /// cold-start fallback wrote `pitches[0] == 60`), so this reads 60 — RED.
    /// Test-isolation teardown (bug 20260702-135500): a controller that is
    /// only `stop()`ped (or not even that) can leak TickClock timers and
    /// host-queue work that crash LATER suites via Swift exclusivity traps.
    /// Every controller a test creates registers a full `shutdown()` here.
    private func registerShutdownAtTeardown(_ controller: EngineController) {
        addTeardownBlock {
            controller.shutdown()
            XCTAssertFalse(controller.clock.isRunning,
                "no TickClock may survive test teardown")
        }
    }

    func test_tickState_adoptsGeneratorStateFromConsumedPrecomputedBar() {
        let sink = CountingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: sink)
        registerShutdownAtTeardown(controller)
        let (project, trackID, _) = makeSequentialGeneratorProject()
        controller.apply(documentModel: project)

        controller.start()
        for step in 0..<stepsPerBar {
            controller.processTick(tickIndex: UInt64(step), now: Double(step))
        }
        // Read BEFORE stop(): stop() resets the tick-state's runtime state.
        let states = controller.tickState.readPrepareInputs().generatedStates
        controller.stop()

        let lanePitch = states[trackID]?.lastPitchesByLane.first ?? nil
        XCTAssertEqual(
            lanePitch, sequentialPitches[(stepsPerBar - 1) % sequentialPitches.count],
            "after consuming a precomputed bar, the tick-state's generated state must reflect the " +
            "bar's realized content (last pitch of the bar), so a later cold-boundary fallback " +
            "does not evaluate from stale state. observed=\(String(describing: lanePitch))"
        )
    }

    /// `BarKey` carries no chord field, so a harmonic-sidechain follower's
    /// precomputed bar bakes in whatever chord was live when the bar was
    /// requested (up to a bar ahead of playback). A chord CHANGE must therefore
    /// bump the generation-input revision so stale bars become unmatchable —
    /// but only an actual value change may bump, because the broadcast re-fires
    /// every step and an unconditional bump would disable precompute entirely.
    func test_chordContextBroadcast_bumpsGenerationRevisionOnlyOnChordChange() {
        let sink = CountingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: sink)
        registerShutdownAtTeardown(controller)
        let (project, _, _) = makeSequentialGeneratorProject()
        controller.apply(documentModel: project)

        let cMajor = Chord(root: 60, chordType: "majorTriad", scale: "major")
        let fMajor = Chord(root: 65, chordType: "majorTriad", scale: "major")

        let initial = controller.tickState.readPrepareInputs().generationInputRevision

        controller.applyChordContextBroadcast(lane: "prog", chord: cMajor)
        let afterFirst = controller.tickState.readPrepareInputs().generationInputRevision
        XCTAssertEqual(
            afterFirst, initial &+ 1,
            "first chord on a lane is a change from nil — published bars baked without it are stale"
        )

        controller.applyChordContextBroadcast(lane: "prog", chord: cMajor)
        XCTAssertEqual(
            controller.tickState.readPrepareInputs().generationInputRevision, afterFirst,
            "re-broadcasting an unchanged chord fires every step and must NOT invalidate precompute"
        )

        controller.applyChordContextBroadcast(lane: "prog", chord: fMajor)
        XCTAssertEqual(
            controller.tickState.readPrepareInputs().generationInputRevision, afterFirst &+ 1,
            "a chord change must invalidate published bars that baked the previous chord"
        )

        controller.applyChordContextBroadcast(lane: "other", chord: fMajor)
        XCTAssertEqual(
            controller.tickState.readPrepareInputs().generationInputRevision, afterFirst &+ 2,
            "lanes are independent — a first chord on another lane is a change on that lane"
        )
    }
}
