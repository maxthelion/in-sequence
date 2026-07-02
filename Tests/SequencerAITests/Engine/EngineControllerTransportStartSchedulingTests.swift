import AVFoundation
import XCTest
@testable import SequencerAI

/// Transport-start step-0 scheduling — G2 startup-anchor model (owner-approved
/// 2026-07-02: anchor = 50 ms, rail cap = 60 ms; evidence in
/// `docs/plans/engine-timing-recovery-evidence/2026-07-02-lookahead-clock-skew/note.md`).
///
/// # The model being pinned
///
/// Transport start anchors musical second 0 a fixed
/// `AudioMasterClock.startupAnchorLeadSeconds` AFTER the start render position,
/// so step 0's due stamp is born schedulable (anchor 50 ms > visibility ~23 ms
/// + cold dispatch ~20 ms) and lands ON the grid like every other step:
///
/// 1. On a NORMAL start, step 0's stamp equals musical zero (the anchored
///    origin) EXACTLY — the `liveDispatchSchedulingFloorSeconds` last-resort
///    floor must NOT fire (it would lift step 0 a couple ms off-grid).
/// 2. AU and sample step-0 stamps still agree (parity latch): both land the
///    SAME unified-clock frame — the musical-zero frame.
/// 3. The floor STILL rescues a pathologically late dispatch (cold dispatch
///    delay > anchor − floor): the stamp is lifted to
///    `renderNow + floor` — slightly late but sounding, never an
///    unschedulable knife-edge stamp.
/// 4. Steady-state stamps far beyond the floor stay EXACT musical due times.
///
/// (The pre-anchor model — step-0 stamps lifted BY the floor on every start,
/// landing grid +41 ms ± 1 quantum — is superseded; the floor is now a rescue,
/// not the first-hit mechanism.)
final class EngineControllerTransportStartSchedulingTests: XCTestCase {

    // MARK: - Sinks

    private final class SpySamplePlaybackSink: SamplePlaybackSink {
        private(set) var playCalls: [(URL, SamplerSettings, UUID, AVAudioTime?)] = []
        func start() throws {}
        func stop() {}
        func prepareTrack(trackID: UUID) {}
        func play(sampleURL: URL, settings: SamplerSettings, trackID: UUID, at when: AVAudioTime?) -> VoiceHandle? {
            playCalls.append((sampleURL, settings, trackID, when))
            return nil
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
            playCalls.append((sampleURL, SamplerSettings.default, trackID, when))
            return nil
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

    /// Fake AU host capturing the sample-accurate note stamp handed to the AU
    /// note path (no real AU — unattended tier).
    private final class CapturingAUNoteSink: TrackPlaybackSink {
        let displayName = "Capturing AU Sink"
        var isAvailable = true
        let availableInstruments = [AudioInstrumentChoice.builtInSynth, .testInstrument]
        private(set) var selectedInstrument: AudioInstrumentChoice = .builtInSynth
        var currentAudioUnit: AVAudioUnit? { nil }
        private(set) var stampedNoteOns: [(sampleTime: AVAudioFramePosition?, sampleRate: Double)] = []

        func prepareIfNeeded() {}
        func startIfNeeded() {}
        func stop() {}
        func shutdown() {}
        func setMix(_ mix: TrackMixSettings) {}
        func setDestination(_ destination: Destination) {}
        func selectInstrument(_ choice: AudioInstrumentChoice) { selectedInstrument = choice }
        func captureStateBlob() throws -> Data? { nil }
        func play(noteEvents: [NoteEvent], bpm: Double, stepsPerBar: Int) {
            stampedNoteOns.append((nil, 0))
        }
        func play(
            noteEvents: [NoteEvent],
            bpm: Double,
            stepsPerBar: Int,
            noteOnSampleTime: AVAudioFramePosition?,
            sampleRate: Double
        ) {
            stampedNoteOns.append((noteOnSampleTime, sampleRate))
        }
    }

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

    private func makeSampleProject(kickID: UUID) -> (Project, StepSequenceTrack) {
        let track = StepSequenceTrack(
            name: "K",
            pitches: [DrumKitNoteMap.baselineNote],
            stepPattern: [true],
            destination: .sample(sampleID: kickID, settings: .default),
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
                    slots: (0..<16).map { TrackPatternSlot(slotIndex: $0, sourceRef: .generator(generator.id)) }
                )
            ],
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )
        return (project, track)
    }

    // MARK: - Step 0 on a normal start: musical zero, UNLIFTED

    /// THE PIN: at live transport start, the FIRST hit's sample stamp is
    /// EXACTLY musical zero — the anchored origin
    /// (`renderPositionAtStart + startupAnchorLeadSeconds`) — with NO floor
    /// lift. The anchor makes the stamp schedulable by construction; a lifted
    /// stamp here would mean the floor fired on a normal start and moved the
    /// first hit off-grid.
    func test_transportStart_step0SampleStamp_isMusicalZero_unlifted() throws {
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        let kick = try XCTUnwrap(library.firstSample(in: .kick))
        let spy = SpySamplePlaybackSink()
        let (project, _) = makeSampleProject(kickID: kick.id)

        let controller = EngineController(
            client: nil,
            endpoint: nil,
            sampleEngine: spy,
            sampleLibrary: library
        )
        controller.apply(documentModel: project)
        controller.setBPM(120)

        controller.startTransportWithoutClockForTesting(now: ProcessInfo.processInfo.systemUptime)
        defer { controller.stop() }

        let correlation = controller.audioMasterClock.capturedOriginCorrelation()
        XCTAssertTrue(
            correlation.isRenderDerived,
            "fixture: offline manual rendering must give a render-derived origin, " +
            "otherwise the cold-fallback (immediate) path is being tested instead"
        )

        _ = controller.processLookAheadPumpForTesting(now: correlation.hostSeconds)

        let when = try XCTUnwrap(
            spy.playCalls.first?.3,
            "step 0 must be handed a real AVAudioTime stamp (not nil/immediate) once a render-derived origin exists"
        )
        XCTAssertTrue(when.isHostTimeValid)
        let stampSeconds = AVAudioTime.seconds(forHostTime: when.hostTime)
        let expectedMusicalZero = controller.audioMasterClock.hostSeconds(atMusicalSeconds: 0)

        XCTAssertEqual(
            stampSeconds, expectedMusicalZero, accuracy: 0.000_001,
            "step 0's stamp must be EXACTLY musical zero (the anchored origin) — an excess is the " +
            "last-resort floor firing on a normal start, lifting the first hit off-grid; a deficit " +
            "means the stamp bypassed the unified clock."
        )
        // The stamp is genuinely schedulable: born startupAnchorLeadSeconds
        // ahead of the start render position, it is still in the FUTURE when
        // the sample engine's immediate-clamp inspects it.
        XCTAssertNotNil(
            SamplePlaybackEngine.effectivePlaybackTime(for: when, now: ProcessInfo.processInfo.systemUptime),
            "the anchored step-0 stamp must not clamp to immediate at receipt"
        )
    }

    // MARK: - The floor still rescues a pathologically late dispatch

    /// LAST-RESORT RESCUE PIN: when dispatch is pathologically late (the render
    /// position has advanced past `due − floor`, i.e. the cold dispatch delay
    /// exceeds `startupAnchorLeadSeconds − liveDispatchSchedulingFloorSeconds`),
    /// the stamp must be LIFTED to the earliest reliably-schedulable time
    /// (`renderNow + floor`) instead of being handed to the sink as an
    /// unschedulable past/knife-edge time. Slightly late but sounding.
    ///
    /// Offline manual rendering pairs the static render frame with a LIVE
    /// mach host time, so sleeping past the rescue threshold between origin
    /// capture and the pump wake deterministically models the late dispatch.
    func test_transportStart_pathologicallyLateDispatch_isRescuedByFloor() throws {
        let anchor = AudioMasterClock.startupAnchorLeadSeconds
        let floor = AudioMasterClock.liveDispatchSchedulingFloorSeconds
        XCTAssertLessThan(
            floor, anchor,
            "fixture: the rescue threshold (anchor − floor) must be positive — a floor >= the anchor " +
            "would fire on EVERY normal start"
        )

        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        let kick = try XCTUnwrap(library.firstSample(in: .kick))
        let spy = SpySamplePlaybackSink()
        let (project, _) = makeSampleProject(kickID: kick.id)

        let controller = EngineController(
            client: nil,
            endpoint: nil,
            sampleEngine: spy,
            sampleLibrary: library
        )
        controller.apply(documentModel: project)
        controller.setBPM(120)

        controller.startTransportWithoutClockForTesting(now: ProcessInfo.processInfo.systemUptime)
        defer { controller.stop() }
        let correlation = controller.audioMasterClock.capturedOriginCorrelation()
        XCTAssertTrue(correlation.isRenderDerived)

        // Model the pathological cold start: dispatch delayed beyond the rescue
        // threshold (anchor − floor), with margin for timer coarseness.
        let simulatedDelay = (anchor - floor) + 0.020
        Thread.sleep(forTimeInterval: simulatedDelay)

        _ = controller.processLookAheadPumpForTesting(now: correlation.hostSeconds + simulatedDelay)

        let when = try XCTUnwrap(
            spy.playCalls.first?.3,
            "a rescued step 0 must still carry a real AVAudioTime stamp (scheduled, not immediate)"
        )
        XCTAssertTrue(when.isHostTimeValid)
        let stampSeconds = AVAudioTime.seconds(forHostTime: when.hostTime)
        let lift = stampSeconds - correlation.hostSeconds

        XCTAssertGreaterThan(
            lift, 0.005,
            "a dispatch \(simulatedDelay * 1000) ms late must be rescued: the stamp must be lifted " +
            "above the (already-unschedulable) musical-zero due time to renderNow + floor. " +
            "Zero lift hands the sink a stamp inside the schedule-visibility horizon — the " +
            "non-deterministic +41 ms first-hit defect."
        )
        // Bounded: a rescue is renderNow + floor — never the look-ahead lead in
        // stamp clothing.
        XCTAssertLessThanOrEqual(
            lift, simulatedDelay + floor + 0.050,
            "the rescue lift must stay near renderNow + floor; \(lift * 1000) ms looks like the " +
            "look-ahead lead leaked into the stamp."
        )
        // Still sounding: the rescued stamp is in the future at receipt.
        XCTAssertNotNil(
            SamplePlaybackEngine.effectivePlaybackTime(for: when, now: ProcessInfo.processInfo.systemUptime),
            "the rescued step-0 stamp must not clamp to immediate at receipt"
        )
    }

    /// AU/sample PARITY LATCH: an AU note and a sample trigger on step 0 must
    /// make the SAME scheduling decision and land on the SAME unified-clock
    /// frame — the musical-zero (anchored-origin) frame. Also pins the
    /// "compute the floor once per dispatch pass" requirement — per-event
    /// floors could straddle a render-position advance and split AU from
    /// drums on the first hit.
    func test_transportStart_step0_auNoteAndSample_shareMusicalZeroFrame() throws {
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        let kick = try XCTUnwrap(library.firstSample(in: .kick))
        let spy = SpySamplePlaybackSink()
        let auSink = CapturingAUNoteSink()

        let sampleTrack = StepSequenceTrack(
            name: "K",
            pitches: [DrumKitNoteMap.baselineNote],
            stepPattern: [true],
            destination: .sample(sampleID: kick.id, settings: .default),
            velocity: 100,
            gateLength: 4
        )
        let auTrack = StepSequenceTrack(
            name: "Lead",
            trackType: .monoMelodic,
            pitches: [60],
            stepPattern: [true],
            destination: .auInstrument(
                componentID: AudioInstrumentChoice.testInstrument.audioComponentID,
                stateBlob: nil
            ),
            velocity: 100,
            gateLength: 4
        )
        let sampleGen = makeAlwaysOnGenerator(id: UUID(), trackType: sampleTrack.trackType)
        let auGen = makeAlwaysOnGenerator(id: UUID(), trackType: auTrack.trackType)
        let tracks = [sampleTrack, auTrack]
        let layers = PhraseLayerDefinition.defaultSet(for: tracks)
        let phrase = PhraseModel.default(
            tracks: tracks,
            layers: layers,
            generatorPool: [sampleGen, auGen],
            clipPool: []
        )
        let project = Project(
            version: 1,
            tracks: tracks,
            generatorPool: [sampleGen, auGen],
            layers: layers,
            patternBanks: [
                TrackPatternBank(
                    trackID: sampleTrack.id,
                    slots: (0..<16).map { TrackPatternSlot(slotIndex: $0, sourceRef: .generator(sampleGen.id)) }
                ),
                TrackPatternBank(
                    trackID: auTrack.id,
                    slots: (0..<16).map { TrackPatternSlot(slotIndex: $0, sourceRef: .generator(auGen.id)) }
                )
            ],
            selectedTrackID: sampleTrack.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        let controller = EngineController(
            client: nil,
            endpoint: nil,
            audioOutput: auSink,
            sampleEngine: spy,
            sampleLibrary: library
        )
        controller.apply(documentModel: project)
        controller.setBPM(120)

        controller.startTransportWithoutClockForTesting(now: ProcessInfo.processInfo.systemUptime)
        defer { controller.stop() }
        let correlation = controller.audioMasterClock.capturedOriginCorrelation()
        XCTAssertTrue(correlation.isRenderDerived)

        _ = controller.processLookAheadPumpForTesting(now: correlation.hostSeconds)

        let sampleWhen = try XCTUnwrap(
            spy.playCalls.first?.3,
            "step 0 sample trigger must carry a stamp"
        )
        let auStamp = try XCTUnwrap(
            auSink.stampedNoteOns.first,
            "step 0 AU note must be dispatched to the AU sink"
        )
        let auFrame = try XCTUnwrap(
            auStamp.sampleTime,
            "step 0 AU note must be sample-stamped (render origin exists) — nil means the AU " +
            "path went immediate while the sample path scheduled: the cold/scheduled decision split"
        )

        // Same unified-clock frame through the captured origin correlation
        // (the same mapping the frozen offline zero-flam gate uses).
        let sampleFrame = correlation.frame(
            forHostSeconds: AVAudioTime.seconds(forHostTime: sampleWhen.hostTime)
        )
        XCTAssertLessThanOrEqual(
            abs(sampleFrame - auFrame), 1,
            "AU note-on frame (\(auFrame)) and sample stamp frame (\(sampleFrame)) on step 0 " +
            "must land on the same unified-clock frame — the scheduling decision must be identical " +
            "for both paths (parity latch)"
        )

        // And both are the MUSICAL-ZERO (anchored-origin) frame — unlifted on a
        // normal start, not the old floor-lifted frame and never a lead-shifted
        // one.
        XCTAssertEqual(
            auFrame, correlation.sampleTime,
            "the step-0 AU frame must be exactly the anchored-origin (musical zero) frame — " +
            "an offset means the last-resort floor fired on a normal start (off-grid first hit) " +
            "or the stamp bypassed the unified clock"
        )
        XCTAssertLessThanOrEqual(
            abs(sampleFrame - correlation.sampleTime), 1,
            "the step-0 sample frame must be the anchored-origin (musical zero) frame"
        )
    }

    /// Steady-state guard: an event dispatched with the normal look-ahead lead
    /// (due far beyond the floor) must keep its EXACT unified-clock stamp — the
    /// floor must never move on-grid events.
    func test_steadyStateStamp_pastTheFloor_isNotLifted() throws {
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        let kick = try XCTUnwrap(library.firstSample(in: .kick))
        let spy = SpySamplePlaybackSink()
        let (project, _) = makeSampleProject(kickID: kick.id)

        let controller = EngineController(
            client: nil,
            endpoint: nil,
            sampleEngine: spy,
            sampleLibrary: library
        )
        controller.apply(documentModel: project)
        controller.setBPM(120)

        controller.startTransportWithoutClockForTesting(now: ProcessInfo.processInfo.systemUptime)
        defer { controller.stop() }
        let correlation = controller.audioMasterClock.capturedOriginCorrelation()

        // First pump wake at the origin dispatches step 0 (musical zero,
        // anchored) and step 1 (due 125 ms — inside the lead+slack horizon,
        // far beyond the floor).
        _ = controller.processLookAheadPumpForTesting(now: correlation.hostSeconds)

        let stepSeconds = (60.0 / 120.0) * (4.0 / 16.0)
        let stamps = spy.playCalls.compactMap { call -> Double? in
            guard let when = call.3, when.isHostTimeValid else { return nil }
            return AVAudioTime.seconds(forHostTime: when.hostTime)
        }
        XCTAssertGreaterThanOrEqual(stamps.count, 2, "the first pump wake must dispatch steps 0 and 1")
        let expectedStep1 = controller.audioMasterClock.hostSeconds(atMusicalSeconds: stepSeconds)
        XCTAssertEqual(
            stamps[1], expectedStep1, accuracy: 0.000_001,
            "a steady-state stamp (due one full step out, beyond the scheduling floor) must be " +
            "EXACTLY the unified clock's musical due time — the floor must not lift on-grid events"
        )
    }
}
