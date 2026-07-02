import AVFoundation
import XCTest
@testable import SequencerAI

/// ROUND-2 PHASE-2 RAIL — the tick path CONSUMES a precomputed bar; it does NOT
/// generate live.
///
/// Authored from the SPEC only
/// (`docs/plans/2026-07-01-round2-integration-spec.md`, "P2 — generation
/// genuinely off the tick path", and `docs/plans/2026-06-30-precompute-lookahead-recording.md`,
/// Phase 2), never from the implementation. FROZEN: builders may not edit,
/// weaken, skip, or stub this file (fleet brief's frozen-rails rule).
///
/// # Why this rail exists (round-1 was ceremonial)
///
/// Round-1's `PrecomputeBarEquivalenceTests` tested `BarPrecomputeEvaluator`
/// as a PURE FUNCTION and never drove `EngineController`. So it stayed GREEN
/// while `prepareTick` still called `BarPrecomputeEvaluator.resolveStep(...)`
/// synchronously per track per step (the hollow tick path,
/// `EngineController.swift:2288`). Generation was RENAMED, not moved off-thread.
///
/// This rail closes that hole. It drives ticks through a live `EngineController`
/// and asserts the two things the spec requires (round-2 spec, P2 rail):
///
///   (a) "a bar's realized notes equal the precomputed buffer" — the notes the
///       engine actually dispatches over a bar equal `BarPrecomputeEvaluator.
///       precompute(...)` for the same compiled snapshot (the buffer the tick
///       path is supposed to consume);
///   (b) "a test seam counting live per-step generator evaluations during a tick
///       reads 0" — `LiveTickGeneratorProbe.liveEvaluationCount` is 0 across a
///       pumped bar, i.e. `prepareTick` did NOT evaluate the live per-step
///       generator (`resolveStep`) during the tick.
///
/// # Adversarial audit (frozen-rail non-negotiable)
///
/// The KNOWN-HOLLOW implementation — today's `prepareTick`, which calls
/// `BarPrecomputeEvaluator.resolveStep(...)` synchronously per track per step —
/// MUST make this rail RED. It does: every such call increments
/// `LiveTickGeneratorProbe` (the seam lives inside `resolveStep`), so (b) reads
/// > 0 and fails. Reverting a real Phase-2 fix back to the synchronous
/// `resolveStep` form re-introduces the increment and turns the rail RED again.
/// The rail can only pass when the tick path genuinely consumes a precomputed
/// bar and never reaches the live per-step generator during a tick.
///
/// # Why it is deterministic (no device, no RNG dependence)
///
/// The fixture is a euclidean-16/16 trigger with `.manual(..., pickMode:
/// .sequential)` — every step fires, and the pitch is a deterministic function
/// of the step (NOT the RNG). So the live engine's realized bar is deterministic
/// run-to-run, byte-comparable against `precompute(...)`, with no `AVAudioEngine`
/// and no audio device. A `CountingAudioSink` captures the realized dispatch
/// stream; manual `processTick` pumping drives the real tick path.
final class TickConsumesPrecomputeRailTests: XCTestCase {

    private let stepsPerBar = 16
    private let pitches = [60, 62, 64, 65, 67, 69, 71, 72]

    override func setUp() {
        super.setUp()
        MainAudioGraph.simulateAudioInputConnectionForTesting = true
        LiveTickGeneratorProbe.reset()
    }

    override func tearDown() {
        MainAudioGraph.simulateAudioInputConnectionForTesting = false
        LiveTickGeneratorProbe.reset()
        super.tearDown()
    }

    // MARK: - Fixture

    /// A euclidean-16/16 (fires every step) SEQUENTIAL-pitch generator track.
    /// `.manual(pickMode: .sequential)` walks the pitch pool deterministically —
    /// no RNG dependence — so the realized bar through the live engine is
    /// reproducible and byte-comparable against the precomputed buffer.
    private func makeSequentialGeneratorProject() -> (Project, UUID, BlockID) {
        let trackID = UUID(uuidString: "55555555-5555-5555-5555-555555555555")!
        let generatorID = UUID(uuidString: "66666666-6666-6666-6666-666666666666")!

        let generator = GeneratorPoolEntry(
            id: generatorID,
            name: "Sequential Lead",
            trackType: .monoMelodic,
            kind: .monoGenerator,
            params: .mono(
                trigger: .native(.euclidean(pulses: 16, steps: 16, offset: 0)),
                pitch: .native(.manual(pitches: pitches, pickMode: .sequential)),
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

    /// A deterministic order for a multiset of `NoteEvent`s (which is only
    /// `Equatable`, not `Hashable`), so two runs are comparable independent of
    /// cross-step / cross-block dispatch order.
    private func sortedMultiset(_ events: [NoteEvent]) -> [NoteEvent] {
        events.sorted { lhs, rhs in
            if lhs.pitch != rhs.pitch { return lhs.pitch < rhs.pitch }
            if lhs.velocity != rhs.velocity { return lhs.velocity < rhs.velocity }
            if lhs.length != rhs.length { return lhs.length < rhs.length }
            if lhs.gate != rhs.gate { return !lhs.gate && rhs.gate }
            return (lhs.voiceTag ?? "") < (rhs.voiceTag ?? "")
        }
    }

    /// Pump steps 0..<count through the live engine, returning the flattened
    /// note stream the sink actually played (the realized dispatch stream) as a
    /// deterministically-ordered multiset.
    @discardableResult
    private func pumpRealizedMultiset(
        _ controller: EngineController,
        sink: CountingAudioSink,
        steps: Int
    ) -> [NoteEvent] {
        sink.resetPlayedEvents()
        for step in 0..<steps {
            controller.processTick(tickIndex: UInt64(step), now: Double(step))
        }
        return sortedMultiset(sink.playedEvents.flatMap { $0 })
    }

    /// The precomputed buffer for the bar — the buffer the tick path is supposed
    /// to consume — over steps 0..<stepsPerBar, flattened to a deterministically
    /// ordered multiset. Sequential pitch → RNG-independent, seed is irrelevant.
    private func precomputedMultiset(
        snapshot: PlaybackSnapshot,
        phraseID: UUID,
        trackID: UUID,
        blockID: BlockID
    ) -> [NoteEvent] {
        let bar = BarPrecomputeEvaluator.precompute(
            snapshot: snapshot,
            phraseID: phraseID,
            trackIDs: [trackID],
            blockIDForTrack: { EngineController.generatorBlockID(for: $0) },
            startStep: 0,
            stepCount: stepsPerBar,
            chordContext: nil,
            seedForStep: { _ in 0 }
        )
        var events: [NoteEvent] = []
        for step in 0..<stepsPerBar {
            for (_, stepEvents) in bar.preparedNotesByBlockID(forStep: step) {
                events.append(contentsOf: stepEvents)
            }
        }
        return sortedMultiset(events)
    }

    // MARK: - (a) the realized bar equals the precomputed buffer

    /// The notes the engine dispatches over a bar equal the precomputed buffer
    /// for the same compiled snapshot. This is the "realized notes equal the
    /// precomputed buffer" half of the spec's P2 rail: whatever the tick path
    /// consumes, it must be the precomputed bar's notes (not an empty / divergent
    /// stream).
    func test_realizedBar_equalsPrecomputedBuffer() {
        let sink = CountingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: sink)
        let (project, trackID, blockID) = makeSequentialGeneratorProject()
        controller.apply(documentModel: project)

        let snapshot = SequencerSnapshotCompiler.compile(project: project)
        let phraseID = snapshot.selectedPhraseID
        let precomputed = precomputedMultiset(
            snapshot: snapshot,
            phraseID: phraseID,
            trackID: trackID,
            blockID: blockID
        )

        // Sanity: the precomputed buffer is a NON-EMPTY bar (every step fires) —
        // so the equality below is a real comparison, not "[:] == [:]".
        XCTAssertFalse(
            precomputed.isEmpty,
            "fixture must precompute a non-empty bar (euclidean 16/16 fires every step)"
        )

        controller.start()
        let realized = pumpRealizedMultiset(controller, sink: sink, steps: stepsPerBar)
        controller.stop()

        // The engine must have dispatched a non-empty realized bar ...
        XCTAssertFalse(
            realized.isEmpty,
            "the engine must dispatch a non-empty realized bar — an empty realized stream would " +
            "mean generation was disabled rather than moved off-thread"
        )
        // ... carrying EXACTLY the precomputed buffer's notes. The engine's
        // look-ahead double-pump legitimately prepares one step beyond the bar
        // (step 16 wraps to the bar's step 0), so the realized stream is a
        // SUPERSET of the bar by at most that one wrap step — never a subset and
        // never a divergent stream. So: every precomputed note must appear in the
        // realized stream (the tick path consumed the precomputed bar), and every
        // realized note must be one the precomputed bar carries (no divergent /
        // spurious note the buffer did not contain).
        XCTAssertTrue(
            isSubMultiset(precomputed, of: realized),
            "every precomputed note must be dispatched by the engine — the tick path must consume " +
            "the precomputed bar (a missing note means the realized stream diverged from the buffer). " +
            "precomputed=\(precomputed.count) realized=\(realized.count)"
        )
        // No realized note may be outside the precomputed bar's note pool — the
        // engine dispatched only notes the buffer carries (a divergent stream,
        // e.g. a different pitch, fails here).
        let precomputedPool = Set(precomputed.map(noteKey))
        for event in realized {
            XCTAssertTrue(
                precomputedPool.contains(noteKey(event)),
                "the engine dispatched a note the precomputed buffer never carried (\(event)) — the " +
                "realized bar must equal the precomputed buffer, not a divergent stream"
            )
        }
        // And the realized bar exceeds the precomputed bar by at most the single
        // look-ahead wrap step (defensive: a wildly larger realized stream would
        // mean double-dispatch or live re-generation).
        XCTAssertLessThanOrEqual(
            realized.count - precomputed.count, 1,
            "the realized bar must equal the precomputed buffer up to at most one look-ahead wrap " +
            "step — a larger surplus means the tick path dispatched notes the buffer did not carry"
        )
    }

    /// A stable comparable key for a `NoteEvent` (which is only `Equatable`).
    private func noteKey(_ event: NoteEvent) -> String {
        "\(event.pitch)-\(event.velocity)-\(event.length)-\(event.gate)-\(event.voiceTag ?? "")"
    }

    /// True iff `subset` is a sub-multiset of `superset` (every element,
    /// counting multiplicity, appears in `superset`).
    private func isSubMultiset(_ subset: [NoteEvent], of superset: [NoteEvent]) -> Bool {
        var remaining = superset
        for event in subset {
            guard let idx = remaining.firstIndex(of: event) else { return false }
            remaining.remove(at: idx)
        }
        return true
    }

    // MARK: - (b) zero live per-step generator evaluations during a tick

    /// The load-bearing anti-hollowness assertion. Across a pumped bar, the live
    /// per-step generator seam (`BarPrecomputeEvaluator.resolveStep`) must run
    /// ZERO times: generation is precomputed off the tick path, so the tick path
    /// never evaluates the generator live. On the KNOWN-HOLLOW code (today's
    /// `prepareTick`, which calls `resolveStep` per track per step) this reads
    /// > 0 → RED. This is the adversarial-audit invariant: the synchronous
    /// `resolveStep` in prepareTick MUST make the rail RED.
    func test_noLivePerStepGeneratorEvaluationsDuringTick() {
        let sink = CountingAudioSink()
        let controller = EngineController(client: nil, endpoint: nil, audioOutput: sink)
        let (project, _, _) = makeSequentialGeneratorProject()
        controller.apply(documentModel: project)

        controller.start()
        LiveTickGeneratorProbe.reset()
        _ = pumpRealizedMultiset(controller, sink: sink, steps: stepsPerBar)
        let liveEvaluations = LiveTickGeneratorProbe.liveEvaluationCount
        controller.stop()

        XCTAssertEqual(
            liveEvaluations, 0,
            "the tick path must NOT evaluate the live per-step generator during a tick — generation " +
            "is precomputed off-thread and the tick path consumes the precomputed bar. A non-zero " +
            "count means generation is still running live on the tick path (RENAMED, not moved). " +
            "observed live per-step evaluations across the bar = \(liveEvaluations)"
        )
    }

    // MARK: - Adversarial audit (in-suite): the hollow seam DOES increment

    /// Proves the probe seam is wired to the live per-step generator, so (b) is
    /// not vacuous: a direct call into `BarPrecomputeEvaluator.resolveStep` (the
    /// hollow tick-path seam) increments the counter. If a builder ever severed
    /// the probe from `resolveStep` (to make (b) pass while still generating
    /// live), this assertion fails — the seam must genuinely observe live
    /// generation.
    func test_adversarial_liveResolveStepSeam_incrementsProbe() {
        let (project, trackID, _) = makeSequentialGeneratorProject()
        let snapshot = SequencerSnapshotCompiler.compile(project: project)
        let phraseID = snapshot.selectedPhraseID

        LiveTickGeneratorProbe.reset()
        var state = GeneratedSourceEvaluationState()
        _ = BarPrecomputeEvaluator.resolveStep(
            trackID: trackID,
            in: snapshot,
            phraseID: phraseID,
            stepInPhrase: 0,
            chordContext: nil,
            trackFillPreview: .inactive,
            quantisedFillFlagOverrides: [:],
            quantisedPatternSlotOverrides: [:],
            quantisedFillCueTrackIDs: [],
            auditionOverride: nil,
            trackType: .monoMelodic,
            state: &state
        )
        XCTAssertEqual(
            LiveTickGeneratorProbe.liveEvaluationCount, 1,
            "the live per-step generator seam (resolveStep) MUST increment the probe — otherwise the " +
            "zero-live-evaluations gate would be vacuous (it could pass while generation still ran live)"
        )
    }
}
