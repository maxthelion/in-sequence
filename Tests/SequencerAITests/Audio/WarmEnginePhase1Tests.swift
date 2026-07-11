import AVFoundation
import XCTest
@testable import SequencerAI

/// PHASE 1 — WARM ENGINE + VALID RENDER ORIGIN rail (frozen; authored from the
/// SPEC `docs/plans/2026-06-30-precompute-lookahead-recording.md` Phase 1,
/// never from the implementation). Builders make these GREEN with the smallest
/// change; they may NOT edit, weaken, skip, or stub this file.
///
/// # The three Phase-1 invariants this gate encodes (verbatim from the spec)
///
/// 1. **Warm engine across a transport stop/start.** "keep `AVAudioEngine`
///    running (outputting silence) while a document session is active; stop only
///    on shutdown / device change / explicit rebuild." So a transport `stop()`
///    must NOT stop the underlying engine — only `shutdown()` (and the other
///    sanctioned events) may. Today `EngineController.stop()` →
///    `sampleEngine.stop()` → `MainAudioGraph.stop()` → `engine.stop()`, so the
///    engine dies on every transport stop: this test is RED.
///
/// 2. **Render origin is render-derived before the first event is stamped.**
///    "Capture the master-clock render origin only once `lastRenderTime` is valid
///    — do not set `hasOrigin=true` on the provisional `systemUptime` fallback
///    for AU stamping." With a warm engine the render origin is established
///    (render-derived) BEFORE step 0 is stamped, so the controller must record
///    that the first stamp used a render-derived origin
///    (`firstEventOriginWasRenderDerived == true`), never the provisional
///    fallback (`false`) and never "no stamp happened" (`nil`). Today nothing
///    establishes that guarantee, so the flag stays `nil`: RED.
///
/// 3. **Stop prevents new events being scheduled by an in-flight tick.** A tick
///    already dispatched by the wall-clock pump can land on the tick queue AFTER
///    `stop()` has torn the transport down. Such a late tick must schedule ZERO
///    events — it must not stamp/dispatch notes into a stopped transport. Today
///    `processTick`/`processTickMarked` has no running-state guard, so a tick
///    that arrives after `stop()` still bootstraps + dispatches a step: RED.
///
/// # Why these are deterministic (no device, no flakiness)
///
/// Like `OfflineFrameAccuracyTests`, this drives a real `EngineController` over a
/// real `MainAudioGraph` in offline manual-rendering mode and pumps `processTick`
/// on a synthetic timeline. The engine's running state and the dispatched-event
/// stream are read directly — no onset detection, no timers.
final class WarmEnginePhase1Tests: XCTestCase {

    // MARK: - Fixtures

    private var libraryRoot: URL!

    override func setUpWithError() throws {
        MainAudioGraph.useManualRenderingForAutomation = true
        libraryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(
            at: libraryRoot.appendingPathComponent("kick"),
            withIntermediateDirectories: true
        )
        try writeSilentWAV(to: libraryRoot.appendingPathComponent("kick/test-kick.wav"), sampleRate: 48_000)
    }

    override func tearDownWithError() throws {
        MainAudioGraph.useManualRenderingForAutomation = false
        try? FileManager.default.removeItem(at: libraryRoot)
    }

    private func writeSilentWAV(to url: URL, sampleRate: Double) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let frameCount = AVAudioFrameCount(sampleRate * 0.1)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    private func makeAlwaysOnGenerator(id: UUID, trackType: TrackType) -> GeneratorPoolEntry {
        GeneratorPoolEntry(
            id: id,
            name: "Always On",
            trackType: trackType,
            kind: .monoGenerator,
            params: .mono(
                trigger: .native(.euclidean(pulses: 1, steps: 1, offset: 0)),
                pitch: .native(.manual(pitches: [DrumKitNoteMap.baselineNote], pickMode: .sequential)),
                shape: NoteShape(velocity: 100, gateLength: 4, accent: false)
            )
        )
    }

    /// A one-sample-per-step drum project that fires a sample trigger every step.
    private func makeProject(stepsPerBar: Int) throws -> (Project, AudioSampleLibrary) {
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        let kick = try XCTUnwrap(library.firstSample(in: .kick))

        let track = StepSequenceTrack(
            name: "K",
            pitches: [DrumKitNoteMap.baselineNote],
            stepPattern: [true],
            destination: .sample(sampleID: kick.id, settings: .default),
            velocity: 100,
            gateLength: 4
        )
        let generator = makeAlwaysOnGenerator(id: UUID(), trackType: track.trackType)
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let phrase = PhraseModel.default(tracks: [track], layers: layers)
        let project = Project(
            version: 1,
            tracks: [track],
            generatorPool: [generator],
            layers: layers,
            patternBanks: [
                TrackPatternBank(
                    trackID: track.id,
                    slots: (0..<stepsPerBar).map {
                        TrackPatternSlot(slotIndex: $0, sourceRef: .generator(generator.id))
                    }
                )
            ],
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )
        return (project, library)
    }

    // MARK: - Invariant 1: warm engine across transport stop/start

    /// The document/session owner must warm the shared `MainAudioGraph` before
    /// the first transport run. Loading a sample kit must not be the side effect
    /// that makes AU playback possible.
    func test_sessionWarmStart_startsAudioGraphBeforeTransport() throws {
        let graph = MainAudioGraph()
        let controller = EngineController(
            client: nil,
            endpoint: nil,
            stepsPerBar: 16,
            mainAudioGraph: graph,
            sampleEngine: SamplePlaybackEngine(audioGraph: graph)
        )

        XCTAssertFalse(
            graph.isEngineRunning,
            "sanity: MainAudioGraph construction prepares the graph but does not start it"
        )

        controller.startSessionAudioGraph()

        XCTAssertTrue(
            graph.isEngineRunning,
            "Phase-1 warm engine: the document session must start the shared audio graph " +
            "before transport, so AU-only first play does not depend on loading a sample kit."
        )

        controller.shutdown()
        XCTAssertFalse(
            graph.isEngineRunning,
            "shutdown remains the sanctioned graph teardown point after session warm-start"
        )
    }

    /// Source-specific playback engines must not become accidental graph owners.
    /// AU and sample hosts may attach/connect/arm their own nodes, but session
    /// lifetime owns `MainAudioGraph.start/stop`.
    func test_sourcePlaybackEnginesDoNotStartOrStopSharedAudioGraph() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let guardedFiles = [
            repoRoot.appendingPathComponent("Sources/Audio/AudioInstrumentHost.swift"),
            repoRoot.appendingPathComponent("Sources/Audio/SamplePlaybackEngine.swift")
        ]

        for url in guardedFiles {
            let source = try String(contentsOf: url, encoding: .utf8)
            XCTAssertFalse(
                source.contains("audioGraph.start()"),
                "\(url.lastPathComponent) must not start the shared graph; use EngineController.startSessionAudioGraph()"
            )
            XCTAssertFalse(
                source.contains("audioGraph.stop()"),
                "\(url.lastPathComponent) must not stop the shared graph; teardown belongs to EngineController.shutdown()"
            )
        }
    }

    /// THE WARM-ENGINE GATE. After a transport `stop()` the underlying
    /// `AVAudioEngine` must STILL be running (warm, outputting silence). Only
    /// `shutdown()` (negative control below) may stop it.
    ///
    /// Pre-P1 this failed because `EngineController.stop()` tore the engine down
    /// via `sampleEngine.stop()` → `MainAudioGraph.stop()` → `engine.stop()`.
    /// The graph is now warmed by the document/session owner before transport;
    /// this test pumps no ticks, so no sample buffers are scheduled on a player
    /// node (which on the real graph would raise an uncatchable
    /// AVAudioPlayerNode NSException).
    /// The engine-running lifecycle is exactly what this invariant is about; the
    /// note-dispatch path is covered by invariant 3.
    func test_transportStop_keepsAudioEngineWarm() throws {
        let graph = MainAudioGraph()
        let controller = EngineController(
            client: nil,
            endpoint: nil,
            stepsPerBar: 16,
            mainAudioGraph: graph,
            sampleEngine: SamplePlaybackEngine(audioGraph: graph)
        )
        // An empty document: a live session is active, but no firing tracks, so
        // starting the transport starts the engine without scheduling any voices.
        controller.apply(documentModel: .empty)
        controller.setBPM(120)
        controller.startSessionAudioGraph()

        controller.startTransportWithoutClockForTesting(now: 0)
        XCTAssertTrue(
            graph.isEngineRunning,
            "engine must be running while transport is active"
        )

        controller.stop()

        XCTAssertTrue(
            graph.isEngineRunning,
            "Phase-1 warm engine: a transport stop() must NOT stop the underlying " +
            "AVAudioEngine — it must keep running (outputting silence) for the active " +
            "document session, so look-ahead has a valid render origin and the next " +
            "start() is not a cold start. (Engine was stopped on transport stop.)"
        )
    }

    /// Audible silence must be requested before `TickClock.stop()` joins its
    /// serial queue. Otherwise a long-running tick turns scheduler cleanup into
    /// user-visible Stop-button latency.
    func test_transportStop_silencesVoicesBeforeJoiningClockQueue() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/Engine/EngineController.swift"),
            encoding: .utf8
        )
        let stopStart = try XCTUnwrap(source.range(of: "    func stop() {"))
        let stopTail = source[stopStart.lowerBound...]
        let nextFunction = stopTail.range(of: "\n    func ", options: [], range: stopTail.index(after: stopTail.startIndex)..<stopTail.endIndex)
        let stopBody = nextFunction.map { stopTail[..<$0.lowerBound] } ?? stopTail[...]

        let hostSilence = try XCTUnwrap(stopBody.range(of: "hosts.forEach { $0.stop() }"))
        let sampleSilence = try XCTUnwrap(stopBody.range(of: "sampleEngine.stopVoicesKeepingEngineWarm()"))
        let clockJoin = try XCTUnwrap(stopBody.range(of: "clock.stop()"))

        XCTAssertLessThan(hostSilence.lowerBound, clockJoin.lowerBound)
        XCTAssertLessThan(sampleSilence.lowerBound, clockJoin.lowerBound)
    }

    /// NEGATIVE CONTROL for invariant 1 (proves the warm-engine assertion is not
    /// "engine can never stop"): `shutdown()` IS a sanctioned stop point, so it
    /// must tear the engine down. If this passed even when stop() also kept the
    /// engine warm, the warm-engine gate would be vacuous.
    func test_shutdown_stopsAudioEngine() throws {
        let graph = MainAudioGraph()
        let controller = EngineController(
            client: nil,
            endpoint: nil,
            stepsPerBar: 16,
            mainAudioGraph: graph,
            sampleEngine: SamplePlaybackEngine(audioGraph: graph)
        )
        controller.apply(documentModel: .empty)
        controller.setBPM(120)
        controller.startSessionAudioGraph()

        controller.startTransportWithoutClockForTesting(now: 0)
        controller.shutdown()

        XCTAssertFalse(
            graph.isEngineRunning,
            "shutdown() is a sanctioned stop point and MUST stop the engine — " +
            "otherwise the warm-engine gate (stop keeps it running) would be vacuous."
        )
    }

    // MARK: - Invariant 2: render-derived origin before the first stamp

    /// THE RENDER-DERIVED-ORIGIN GATE. When the first event (step 0) is stamped,
    /// the `AudioMasterClock` origin in effect must already be the authoritative
    /// RENDER-DERIVED origin — never the provisional pre-render `systemUptime`
    /// fallback, and the stamp must actually have happened.
    ///
    /// The controller records this at the stamp site
    /// (`firstEventOriginWasRenderDerived`): `true` = render-derived (correct),
    /// `false` = stamped against the provisional fallback (the defect), `nil` =
    /// the controller never recorded a first stamp (defect — the guarantee was
    /// not wired). Pre-P1 the flag is `nil`. The test ALSO reads the real clock
    /// state so the flag cannot merely be hardcoded.
    func test_firstEventOrigin_isRenderDerived_notProvisionalFallback() throws {
        let (project, library) = try makeProject(stepsPerBar: 16)
        // Real MainAudioGraph in offline manual-rendering mode (renderPosition is
        // available, so a render-derived origin CAN be established), but a
        // capturing sample sink so dispatching step 0 does not schedule buffers
        // on a real player node.
        let graph = MainAudioGraph()
        let controller = EngineController(
            client: nil,
            endpoint: nil,
            stepsPerBar: 16,
            mainAudioGraph: graph,
            sampleEngine: CapturingPlaySink(),
            sampleLibrary: library
        )
        controller.apply(documentModel: project)
        controller.setBPM(120)
        controller.startSessionAudioGraph()

        controller.startTransportWithoutClockForTesting(now: 0)
        controller.processTick(tickIndex: 0, now: 0)

        let recorded = controller.firstEventOriginWasRenderDerived
        XCTAssertNotNil(
            recorded,
            "Phase-1: the controller must record, at the first event stamp, whether " +
            "the origin was render-derived. nil means the guarantee was never wired " +
            "(the first event was stamped without establishing a render-derived origin)."
        )
        XCTAssertEqual(
            recorded, true,
            "Phase-1: the first event must be stamped against the RENDER-DERIVED origin, " +
            "not the provisional systemUptime fallback (false). The warm engine must have " +
            "a valid render position before step 0 is stamped."
        )

        // Independent corroboration from the real clock — the flag must reflect
        // genuine clock state, not a constant.
        let correlation = controller.audioMasterClock.capturedOriginCorrelation()
        XCTAssertTrue(
            correlation.hasOrigin,
            "the master clock must have an origin once the first event is stamped"
        )
        XCTAssertTrue(
            correlation.isRenderDerived,
            "the master clock's captured origin must be render-derived at the first stamp"
        )
    }

    /// NEGATIVE CONTROL for invariant 2 (proves render-derived tracks REAL clock
    /// state, not a constant): an `AudioMasterClock` whose render position is
    /// unavailable, anchored only on the provisional fallback, must report its
    /// origin as NOT render-derived. If this were always `true`, invariant 2's
    /// gate would be meaningless.
    func test_clock_fallbackOnly_isNotRenderDerived() {
        let clock = AudioMasterClock(
            stepsPerBar: 16,
            renderPositionProvider: { nil }  // engine not rendering yet
        )
        clock.captureOrigin(fallbackHostSeconds: 123.456)

        let correlation = clock.capturedOriginCorrelation()
        XCTAssertTrue(
            correlation.hasOrigin,
            "the provisional fallback still establishes some origin (host-time scheduling)"
        )
        XCTAssertFalse(
            correlation.isRenderDerived,
            "an origin anchored only on the systemUptime fallback (no render position) " +
            "MUST report isRenderDerived == false — otherwise invariant 2's gate is vacuous"
        )
    }

    // MARK: - Invariant 3: stop prevents an in-flight tick from scheduling

    /// THE IN-FLIGHT-TICK GATE. A tick that lands AFTER `stop()` (a wake the
    /// pump already dispatched before the stop drained) must schedule ZERO
    /// events — it must not stamp/dispatch notes into a stopped transport.
    ///
    /// We use a capturing sample sink to count `play(...)` dispatches. After
    /// `stop()`, a late `processTick` must add no new triggers. Pre-P1
    /// `processTickMarked` has no running-state guard, so the late tick
    /// bootstraps + dispatches a step: RED.
    func test_inFlightTick_afterStop_schedulesNothing() throws {
        let (project, library) = try makeProject(stepsPerBar: 16)
        let sink = CapturingPlaySink()
        let controller = EngineController(
            client: nil,
            endpoint: nil,
            stepsPerBar: 16,
            sampleEngine: sink,
            sampleLibrary: library
        )
        controller.apply(documentModel: project)
        controller.setBPM(120)
        controller.startSessionAudioGraph()

        controller.startTransportWithoutClockForTesting(now: 0)
        controller.processTick(tickIndex: 0, now: 0)
        XCTAssertGreaterThan(
            sink.playCount, 0,
            "sanity: a running transport must dispatch sample triggers"
        )

        controller.stop()
        let countAtStop = sink.playCount

        // A pump-in-flight tick arrives after stop() drained the transport.
        controller.processTick(tickIndex: 1, now: 0.25)

        XCTAssertEqual(
            sink.playCount, countAtStop,
            "Phase-1: a tick that lands after stop() must schedule ZERO new events — " +
            "Stop must prevent an in-flight tick from stamping/dispatching notes into a " +
            "stopped transport. (\(sink.playCount - countAtStop) event(s) leaked through.)"
        )
    }

    /// Records every `play(...)` dispatch so the in-flight-tick gate can count
    /// triggers. All other sink surface is a no-op.
    private final class CapturingPlaySink: SamplePlaybackSink {
        private(set) var playCount = 0

        func start() throws {}
        func stop() {}
        func prepareTrack(trackID: UUID) {}
        func play(sampleURL: URL, settings: SamplerSettings, trackID: UUID, at when: AVAudioTime?) -> VoiceHandle? {
            playCount += 1; return nil
        }
        func play(sampleAsset: PreparedSampleAsset, settings: SamplerSettings, trackID: UUID, at when: AVAudioTime?) -> VoiceHandle? {
            playCount += 1; return nil
        }
        func playSlice(
            sampleURL: URL,
            startFrame: AVAudioFramePosition,
            endFrame: AVAudioFramePosition,
            settings: SlicerSettings,
            trackID: UUID,
            at when: AVAudioTime?,
            reverse: Bool,
            stepParameters: SliceTriggerStepParameters?
        ) -> VoiceHandle? {
            playCount += 1; return nil
        }
        func setTrackMix(trackID: UUID, level: Double, pan: Double) {}
        func setTrackMuteGain(trackID: UUID, muted: Bool, source: TrackMuteSource) {}
        func removeTrack(trackID: UUID) {}
        func audition(sampleURL: URL) {}
        func stopAudition() {}
        func setVoiceParam(trackID: UUID, kind: BuiltinMacroKind, value: Double) {}
        func applyFilter(_ settings: SamplerFilterSettings, trackID: UUID) {}
        func filterNode(for trackID: UUID) -> (any SamplerFilterControlling)? { nil }
    }
}
