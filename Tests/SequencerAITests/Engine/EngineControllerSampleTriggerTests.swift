import XCTest
import AVFoundation
@testable import SequencerAI

final class EngineControllerSampleTriggerTests: XCTestCase {
    private final class SpySamplePlaybackSink: SamplePlaybackSink {
        var playCalls: [(URL, SamplerSettings, UUID, AVAudioTime?)] = []
        var playSliceCalls: [(URL, AVAudioFramePosition, AVAudioFramePosition, SlicerSettings, UUID, AVAudioTime?, Bool, SliceTriggerStepParameters?)] = []
        var prepareTrackCalls: [UUID] = []
        var setTrackMixCalls: [(UUID, Double, Double)] = []
        var setTrackMuteGainCalls: [(UUID, Bool, TrackMuteSource)] = []
        var removeTrackCalls: [UUID] = []
        func start() throws {}
        func stop() {}
        func prepareTrack(trackID: UUID) {
            prepareTrackCalls.append(trackID)
        }
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
            playSliceCalls.append((sampleURL, startFrame, endFrame, settings, trackID, when, reverse, stepParameters))
            return nil
        }
        func setTrackMix(trackID: UUID, level: Double, pan: Double) {
            setTrackMixCalls.append((trackID, level, pan))
        }
        func setTrackMuteGain(trackID: UUID, muted: Bool, source: TrackMuteSource) {
            setTrackMuteGainCalls.append((trackID, muted, source))
        }
        func removeTrack(trackID: UUID) {
            removeTrackCalls.append(trackID)
        }
        func audition(sampleURL: URL) {}
        func stopAudition() {}
        func setVoiceParam(trackID: UUID, kind: BuiltinMacroKind, value: Double) {}
        func applyFilter(_ settings: SamplerFilterSettings, trackID: UUID) {}
        func filterNode(for trackID: UUID) -> (any SamplerFilterControlling)? { nil }
    }

    private var libraryRoot: URL!

    override func setUpWithError() throws {
        MainAudioGraph.useManualRenderingForAutomation = true
        libraryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: libraryRoot.appendingPathComponent("kick"), withIntermediateDirectories: true)
        try writeSilentWAV(to: libraryRoot.appendingPathComponent("kick/test-kick.wav"), sampleRate: 48_000)
    }

    override func tearDownWithError() throws {
        MainAudioGraph.useManualRenderingForAutomation = false
        try? FileManager.default.removeItem(at: libraryRoot)
    }

    // MARK: - Helpers

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

    private func writeSilentWAV(to url: URL, sampleRate: Double) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let frameCount = AVAudioFrameCount(sampleRate * 0.1)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        try file.write(from: buffer)
    }

    private func makeProject(
        track: StepSequenceTrack,
        generator: GeneratorPoolEntry,
        phrase: PhraseModel,
        layers: [PhraseLayerDefinition],
        clipPool: [ClipPoolEntry] = [],
        patternBank: TrackPatternBank? = nil,
        sliceSetPool: [SliceSet] = []
    ) -> Project {
        let resolvedPatternBank = patternBank ?? TrackPatternBank(
            trackID: track.id,
            slots: (0..<16).map { TrackPatternSlot(slotIndex: $0, sourceRef: .generator(generator.id)) }
        )
        return Project(
            version: 1,
            tracks: [track],
            generatorPool: [generator],
            clipPool: clipPool,
            layers: layers,
            patternBanks: [resolvedPatternBank],
            sliceSetPool: sliceSetPool,
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )
    }

    // MARK: - Tests

    func test_sampleDestination_firesPlayPerStep() {
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        guard let kick = library.firstSample(in: .kick) else {
            XCTFail("fixture missing"); return
        }
        let spy = SpySamplePlaybackSink()

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
        let project = makeProject(track: track, generator: generator, phrase: phrase, layers: layers)

        let controller = EngineController(
            client: nil, endpoint: nil,
            sampleEngine: spy, sampleLibrary: library
        )
        controller.apply(documentModel: project)
        let now = ProcessInfo.processInfo.systemUptime
        for step in 0..<4 {
            controller.processTick(tickIndex: UInt64(step), now: now + Double(step) * 0.125)
        }

        XCTAssertEqual(spy.playCalls.count, 4, "manual processTick driving should dispatch one sample trigger per fired step")
    }

    func test_liveLookAheadPump_dispatchesAllStepsInsideHorizonWithoutDuplicates() throws {
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        let kick = try XCTUnwrap(library.firstSample(in: .kick))
        let spy = SpySamplePlaybackSink()

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
        let project = makeProject(track: track, generator: generator, phrase: phrase, layers: layers)

        let controller = EngineController(
            client: nil,
            endpoint: nil,
            sampleEngine: spy,
            sampleLibrary: library
        )
        controller.apply(documentModel: project)
        controller.setBPM(300)

        let origin = 1_000.0
        controller.startTransportWithoutClockForTesting(now: origin)
        defer { controller.stop() }
        let pumpOrigin = controller.audioMasterClock.capturedOriginCorrelation().hostSeconds

        let firstPumpCount = controller.processLookAheadPumpForTesting(now: pumpOrigin)
        XCTAssertEqual(firstPumpCount, 3)
        XCTAssertEqual(
            spy.playCalls.count,
            3,
            "At 300 BPM, 16 steps/bar yields 50 ms per step. A 100 ms horizon should dispatch steps 0, 1, and 2 on the first pump wake."
        )

        let duplicatePumpCount = controller.processLookAheadPumpForTesting(now: pumpOrigin)
        XCTAssertEqual(duplicatePumpCount, 0)
        XCTAssertEqual(spy.playCalls.count, 3, "Repeating the same pump wake must not dispatch already-handed-off steps again.")

        let nextPumpCount = controller.processLookAheadPumpForTesting(now: pumpOrigin + 0.050)
        XCTAssertEqual(nextPumpCount, 1)
        XCTAssertEqual(spy.playCalls.count, 4, "The next pump wake should dispatch only the next newly eligible step.")
    }

    /// Regression for the 2026-07-02 capture-rig finding: the pump's wake
    /// deadlines come from `systemUptime` while the musical origin is the
    /// render-derived host time — different anchors in the same timebase,
    /// typically a render cycle (~11-14 ms) apart. TickClock fires wake k at
    /// `origin_wake + k*step - lead`, but measured against the RENDER origin
    /// that wake sits at `due(k) - lead - skew`. With a 1 µs horizon epsilon
    /// the next step was (lead + skew) away, missed every wake, and dispatched
    /// one wake later — ~14 ms past due, so EVERY steady-state trigger clamped
    /// to immediate (272 immediate vs 4 scheduled in the rig run, constant
    /// 12 ms render-quantum flams between coincident voices). The horizon must
    /// absorb cross-clock skew via `lookAheadClockSkewSlackSeconds`.
    func test_liveLookAheadPump_toleratesOriginVsWakeClockSkew() throws {
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        let kick = try XCTUnwrap(library.firstSample(in: .kick))
        let spy = SpySamplePlaybackSink()

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
        let project = makeProject(track: track, generator: generator, phrase: phrase, layers: layers)

        let controller = EngineController(
            client: nil,
            endpoint: nil,
            sampleEngine: spy,
            sampleLibrary: library
        )
        controller.apply(documentModel: project)
        // Default 120 BPM: 125 ms per 16th step, 100 ms lead.

        controller.startTransportWithoutClockForTesting(now: 1_000.0)
        defer { controller.stop() }
        let pumpOrigin = controller.audioMasterClock.capturedOriginCorrelation().hostSeconds

        // Tick-0 wake, then the production wake for step 1: TickClock fires it
        // at due(1) - lead against its OWN anchor, which is due(1) - lead - skew
        // against the render origin. Step 1 must be handed to the sink no later
        // than this wake; without skew slack it measured (lead + skew) away,
        // slipped a full wake, and dispatched past due (the immediate-clamp
        // flam). With the slack it dispatches at this wake or the one before.
        _ = controller.processLookAheadPumpForTesting(now: pumpOrigin)
        let measuredSkew = 0.014
        let wakeForStepOne = pumpOrigin + 0.125 - 0.100 - measuredSkew
        _ = controller.processLookAheadPumpForTesting(now: wakeForStepOne)
        XCTAssertGreaterThanOrEqual(
            spy.playCalls.count, 2,
            "steps 0 and 1 must both be handed off by step 1's lead-phased wake despite " +
            "origin-vs-wake clock skew; slipping past this wake dispatches past due and " +
            "clamps to immediate"
        )
    }

    func test_sampleDestination_opensSampleOnceDuringWarmupNotPerDispatch() throws {
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        let kick = try XCTUnwrap(library.firstSample(in: .kick))
        let spy = SpySamplePlaybackSink()
        var openedURLs: [URL] = []
        let cache = SampleAssetCache { url in
            openedURLs.append(url)
            return try AVAudioFile(forReading: url)
        }

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
        let project = makeProject(track: track, generator: generator, phrase: phrase, layers: layers)
        let controller = EngineController(
            client: nil,
            endpoint: nil,
            sampleEngine: spy,
            sampleAssetCache: cache,
            sampleLibrary: library
        )

        controller.apply(documentModel: project)
        XCTAssertEqual(openedURLs.count, 1)

        for step in 0..<4 {
            controller.processTick(tickIndex: UInt64(step), now: Double(step) * 0.125)
        }

        XCTAssertEqual(spy.playCalls.count, 4)
        XCTAssertEqual(openedURLs.count, 1, "dispatch should reuse the prepared asset instead of opening the sample per trigger")
    }

    func test_denseRepeatedSampleHitsUseWarmedAssetsWithoutAdditionalFileOpens() throws {
        for category in ["snare", "hatClosed"] {
            let directory = libraryRoot.appendingPathComponent(category)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try writeSilentWAV(to: directory.appendingPathComponent("\(category)-default.wav"), sampleRate: 48_000)
        }

        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        let fixtures: [(name: String, sample: AudioSample)] = [
            ("Kick", try XCTUnwrap(library.firstSample(in: .kick))),
            ("Snare", try XCTUnwrap(library.firstSample(in: .snare))),
            ("Hat", try XCTUnwrap(library.firstSample(in: .hatClosed)))
        ]
        let expectedURLs = try Set(fixtures.map { try $0.sample.fileRef.resolve(libraryRoot: library.libraryRoot) })
        let spy = SpySamplePlaybackSink()
        var openedURLs: [URL] = []
        let cache = SampleAssetCache { url in
            openedURLs.append(url)
            return try AVAudioFile(forReading: url)
        }

        let tracks = fixtures.map { fixture in
            StepSequenceTrack(
                name: fixture.name,
                pitches: [DrumKitNoteMap.baselineNote],
                stepPattern: [true],
                destination: .sample(sampleID: fixture.sample.id, settings: .default),
                velocity: 100,
                gateLength: 4
            )
        }
        let generators = tracks.map { makeAlwaysOnGenerator(id: UUID(), trackType: $0.trackType) }
        let layers = PhraseLayerDefinition.defaultSet(for: tracks)
        let phrase = PhraseModel.default(tracks: tracks, layers: layers, generatorPool: generators)
        let patternBanks = zip(tracks, generators).map { track, generator in
            TrackPatternBank(
                trackID: track.id,
                slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .generator(generator.id))]
            )
        }
        let project = Project(
            version: 1,
            tracks: tracks,
            generatorPool: generators,
            layers: layers,
            patternBanks: patternBanks,
            selectedTrackID: tracks[0].id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )
        let controller = EngineController(
            client: nil,
            endpoint: nil,
            sampleEngine: spy,
            sampleAssetCache: cache,
            sampleLibrary: library
        )

        controller.apply(documentModel: project)
        XCTAssertEqual(Set(openedURLs), expectedURLs)

        let tickCount = 64
        let now = ProcessInfo.processInfo.systemUptime
        for step in 0..<tickCount {
            controller.processTick(tickIndex: UInt64(step), now: now + Double(step) * 0.083_333_333)
        }

        XCTAssertEqual(spy.playCalls.count, tracks.count * tickCount)
        XCTAssertEqual(Set(spy.playCalls.map(\.0)), expectedURLs)
        XCTAssertEqual(openedURLs.count, expectedURLs.count, "dense repeated dispatch should stay on warmed cache assets instead of reopening files")
    }

    func test_denseDrumPlaybackForSixtySecondsAtMultipleBPMsUsesWarmedAssetsWithoutAdditionalFileOpens() throws {
        for category in ["snare", "hatClosed"] {
            let directory = libraryRoot.appendingPathComponent(category)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try writeSilentWAV(to: directory.appendingPathComponent("\(category)-default.wav"), sampleRate: 48_000)
        }

        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        let fixtures: [(name: String, sample: AudioSample)] = [
            ("Kick", try XCTUnwrap(library.firstSample(in: .kick))),
            ("Snare", try XCTUnwrap(library.firstSample(in: .snare))),
            ("Hat", try XCTUnwrap(library.firstSample(in: .hatClosed)))
        ]
        let expectedURLs = try Set(fixtures.map { try $0.sample.fileRef.resolve(libraryRoot: library.libraryRoot) })
        let spy = SpySamplePlaybackSink()
        var openedURLs: [URL] = []
        let cache = SampleAssetCache { url in
            openedURLs.append(url)
            return try AVAudioFile(forReading: url)
        }

        let tracks = fixtures.map { fixture in
            StepSequenceTrack(
                name: fixture.name,
                pitches: [DrumKitNoteMap.baselineNote],
                stepPattern: [true],
                destination: .sample(sampleID: fixture.sample.id, settings: .default),
                velocity: 100,
                gateLength: 4
            )
        }
        let generators = tracks.map { makeAlwaysOnGenerator(id: UUID(), trackType: $0.trackType) }
        let layers = PhraseLayerDefinition.defaultSet(for: tracks)
        let phrase = PhraseModel.default(tracks: tracks, layers: layers, generatorPool: generators)
        let patternBanks = zip(tracks, generators).map { track, generator in
            TrackPatternBank(
                trackID: track.id,
                slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .generator(generator.id))]
            )
        }
        let project = Project(
            version: 1,
            tracks: tracks,
            generatorPool: generators,
            layers: layers,
            patternBanks: patternBanks,
            selectedTrackID: tracks[0].id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )
        let controller = EngineController(
            client: nil,
            endpoint: nil,
            sampleEngine: spy,
            sampleAssetCache: cache,
            sampleLibrary: library
        )

        controller.apply(documentModel: project)
        XCTAssertEqual(Set(openedURLs), expectedURLs)

        let bpms = [120.0, 150.0, 180.0]
        var tickBase: UInt64 = 0
        var totalTickCount = 0
        var runStart = ProcessInfo.processInfo.systemUptime

        for bpm in bpms {
            controller.setBPM(bpm)
            let secondsPerStep = 60.0 / bpm / 4.0
            let tickCount = Int((60.0 / secondsPerStep).rounded())
            totalTickCount += tickCount
            for step in 0..<tickCount {
                controller.processTick(
                    tickIndex: tickBase + UInt64(step),
                    now: runStart + Double(step) * secondsPerStep
                )
            }
            tickBase += UInt64(tickCount)
            runStart += Double(tickCount) * secondsPerStep
        }

        XCTAssertEqual(spy.playCalls.count, tracks.count * totalTickCount)
        XCTAssertEqual(Set(spy.playCalls.map(\.0)), expectedURLs)
        XCTAssertEqual(
            openedURLs.count,
            expectedURLs.count,
            "60s dense drum runs at 120/150/180 BPM should reuse warmed assets and never reopen sample files per trigger"
        )
    }

    /// P0: each step's sample trigger is stamped at the step's MUSICAL position
    /// on the unified audio clock (`AVAudioTime(sampleTime:atRate:)`), NOT the
    /// pump's wall-clock `now`. Step 0 → musical second 0, step 1 → one step
    /// later (0.125 s at 120 BPM / 16 steps), regardless of the jittery `now`
    /// values driven in. The stamp is read back as `sampleTime / sampleRate`.
    func test_sampleDestination_schedulesPreparedNextStepAtMusicalPosition() throws {
        MainAudioGraph.useManualRenderingForAutomation = true
        defer { MainAudioGraph.useManualRenderingForAutomation = false }

        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        let kick = try XCTUnwrap(library.firstSample(in: .kick))
        let spy = SpySamplePlaybackSink()

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
        let project = makeProject(track: track, generator: generator, phrase: phrase, layers: layers)
        let controller = EngineController(
            client: nil,
            endpoint: nil,
            sampleEngine: spy,
            sampleLibrary: library
        )

        controller.apply(documentModel: project)
        // Pump `now` values are deliberately offset/jittered; they must NOT
        // affect the stamped (musical) frame under P0.
        controller.processTick(tickIndex: 0, now: 100)
        controller.processTick(tickIndex: 1, now: 100.125)

        // The live sink schedules against host time, so the stamps are host-time
        // AVAudioTimes. Each stamp's ABSOLUTE host seconds must equal the unified
        // clock's host time for that step's MUSICAL position — `origin + musical
        // seconds`, NOT the jittered pump `now` (100 / 100.125) we drove in.
        // Asserting the absolute value (not just the spacing) is what catches a
        // wrong unit: if a trigger were stamped from a wall-clock value (Defect 1)
        // its absolute host seconds would diverge from the clock's expected value.
        let hostSeconds = spy.playCalls.compactMap { call -> Double? in
            guard let when = call.3, when.isHostTimeValid else { return nil }
            return AVAudioTime.seconds(forHostTime: when.hostTime)
        }
        let stepSeconds = (60.0 / 120.0) * (4.0 / 16.0)
        // Expected absolute host seconds from the SAME production clock the engine
        // stamped against (exercises AudioMasterClock end to end, not a re-derive).
        let expectedStep0 = controller.audioMasterClock.hostSeconds(atMusicalSeconds: 0)
        let expectedStep1 = controller.audioMasterClock.hostSeconds(atMusicalSeconds: stepSeconds)
        XCTAssertEqual(hostSeconds.count, 2)
        XCTAssertEqual(hostSeconds[0], expectedStep0, accuracy: 0.000001)
        XCTAssertEqual(hostSeconds[1], expectedStep1, accuracy: 0.000001)
        // And the spacing is exactly one musical step (independent corroboration).
        XCTAssertEqual(hostSeconds[1] - hostSeconds[0], stepSeconds, accuracy: 0.000001)
    }

    /// REGRESSION GATE for Defect 1 (the audio-dispatch unit mismatch). An
    /// OWN-pattern slice trigger and a ROUTED slice trigger that fire on the SAME
    /// step must be stamped at the SAME sounding time (zero flam).
    ///
    /// Both audio events flow through the same dispatch seam
    /// (`scheduledAudioTime(for:)`), which interprets the queued value as MUSICAL
    /// seconds on the unified clock. Own-pattern events enqueue the unified
    /// clock's musical seconds; the routed audio path must enqueue the SAME unit.
    ///
    /// Pre-fix the routed path enqueued `routerDispatch.dispatchNow` — a WALL-CLOCK
    /// `systemUptime` seconds value (`now + stepDuration`). Fed into the
    /// musical-seconds seam that adds it to the render origin, the routed slice was
    /// stamped ~systemUptime (tens/hundreds of thousands of) seconds in the future
    /// — i.e. it would never sound. This test FAILS on the pre-fix code (the two
    /// stamps differ by ~`now`) and PASSES after routed audio carries musical
    /// seconds. Sample/slice sources only (unattended tier — no AU, no mic).
    func test_ownPatternAndRoutedSlice_onSameStep_landOnSameFrame_zeroFlam() throws {
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        let kick = try XCTUnwrap(library.firstSample(in: .kick))
        let spy = SpySamplePlaybackSink()

        // One slice set shared by both slicer tracks (the actual sample content is
        // irrelevant; we assert on the stamped time, not the audio).
        let sliceSet = SliceSet(
            sampleID: kick.id,
            markers: [SliceMarker(startFrame: 0, endFrame: 4_800)]
        )

        // OWN track: a slicer whose own clip fires a slice trigger on step 0 →
        // own-pattern slice (enqueued from the unified clock's musical seconds).
        let ownClip = ClipPoolEntry(
            id: UUID(),
            name: "Own Slice Clip",
            trackType: .slice,
            content: .sliceTriggers(stepPattern: [true], sliceIndexes: [0], stepModes: [.single])
        )
        let ownTrack = StepSequenceTrack(
            id: UUID(uuidString: "0A000000-0000-0000-0000-000000000001")!,
            name: "Own",
            trackType: .slice,
            pitches: [60],
            stepPattern: [true],
            destination: .slicer(sliceSetID: sliceSet.id, settings: .default),
            velocity: 100,
            gateLength: 4
        )
        // ROUTE TARGET: a slicer that does NOT fire its own pattern; it only
        // sounds via the route, so any slice stamped for it is the ROUTED one.
        let routeTarget = StepSequenceTrack(
            id: UUID(uuidString: "0A000000-0000-0000-0000-000000000002")!,
            name: "RouteTarget",
            trackType: .slice,
            pitches: [60],
            stepPattern: [false],
            destination: .slicer(sliceSetID: sliceSet.id, settings: .default),
            velocity: 100,
            gateLength: 4
        )
        // SOURCE: produces notes (own destination .none so it makes no audio of
        // its own) and routes them into the route target on the same step.
        let sourceGen = makeAlwaysOnGenerator(id: UUID(), trackType: .monoMelodic)
        let sourceTrack = StepSequenceTrack(
            id: UUID(uuidString: "0A000000-0000-0000-0000-000000000003")!,
            name: "Source",
            pitches: [60],
            stepPattern: [true],
            destination: .none,
            velocity: 100,
            gateLength: 4
        )

        let tracks = [ownTrack, routeTarget, sourceTrack]
        let layers = PhraseLayerDefinition.defaultSet(for: tracks)
        let phrase = PhraseModel.default(
            tracks: tracks,
            layers: layers,
            generatorPool: [sourceGen],
            clipPool: [ownClip]
        )
        let route = Route(
            source: .track(sourceTrack.id),
            destination: .trackInput(routeTarget.id, tag: nil)
        )
        let project = Project(
            version: 1,
            tracks: tracks,
            generatorPool: [sourceGen],
            clipPool: [ownClip],
            layers: layers,
            routes: [route],
            patternBanks: [
                TrackPatternBank(
                    trackID: ownTrack.id,
                    slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .clip(ownClip.id))]
                ),
                TrackPatternBank(
                    trackID: sourceTrack.id,
                    slots: (0..<16).map { TrackPatternSlot(slotIndex: $0, sourceRef: .generator(sourceGen.id)) }
                )
            ],
            sliceSetPool: [sliceSet],
            selectedTrackID: ownTrack.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        let controller = EngineController(
            client: nil,
            endpoint: nil,
            sampleEngine: spy,
            sampleLibrary: library
        )
        controller.apply(documentModel: project)
        // Drive a single step at a deliberately large wall-clock `now` — this is
        // what makes the pre-fix bug glaring: the routed path would carry ~`now`
        // into the musical seam. A correct implementation ignores it entirely.
        controller.processTick(tickIndex: 0, now: 100_000)

        // Stamps grouped by destination track.
        let ownStamps = spy.playSliceCalls
            .filter { $0.4 == ownTrack.id }
            .compactMap { $0.5 }
        let routedStamps = spy.playSliceCalls
            .filter { $0.4 == routeTarget.id }
            .compactMap { $0.5 }

        XCTAssertGreaterThanOrEqual(ownStamps.count, 1, "own-pattern slicer must fire on step 0")
        XCTAssertGreaterThanOrEqual(routedStamps.count, 1, "routed slicer must fire on step 0")

        let ownHostSeconds = try AVAudioTime.seconds(forHostTime: XCTUnwrap(ownStamps.first).hostTime)
        let routedHostSecondsAll = routedStamps.map { AVAudioTime.seconds(forHostTime: $0.hostTime) }

        // Zero flam: EVERY routed slice on this step is stamped at the IDENTICAL
        // sounding time as the own-pattern slice. (Pre-fix: the routed stamps were
        // ≈ ownHostSeconds + ~100_000 s, because the routed path carried wall-clock
        // seconds into the musical seam — so this asserts both that routed audio
        // sounds at all and that it shares the own-pattern frame.)
        for routedHostSeconds in routedHostSecondsAll {
            XCTAssertEqual(
                routedHostSeconds, ownHostSeconds, accuracy: 0.000001,
                "own-pattern and routed slices on the same step must land on the same frame (flam = " +
                "\(routedHostSeconds - ownHostSeconds) s)"
            )
        }
    }

    func test_factory808Kit_dispatchesKickAndHatWhenBothFireOnSameStep() throws {
        for category in ["snare", "hatClosed", "clap"] {
            let directory = libraryRoot.appendingPathComponent(category)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try writeSilentWAV(to: directory.appendingPathComponent("\(category)-default.wav"), sampleRate: 48_000)
        }
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        let kick = try XCTUnwrap(library.firstSample(in: .kick))
        let hat = try XCTUnwrap(library.firstSample(in: .hatClosed))
        let spy = SpySamplePlaybackSink()
        var project = Project.empty

        let groupID = try XCTUnwrap(project.addDrumGroup(
            plan: DrumKitFixtures.templatedPlan(named: "808"),
            library: library,
            templateLookup: DrumKitFixtures.factoryTemplateLookup
        ))
        let group = try XCTUnwrap(project.trackGroups.first(where: { $0.id == groupID }))
        let members = Dictionary(uniqueKeysWithValues: group.memberIDs.compactMap { memberID -> (VoiceTag, UUID)? in
            guard let track = project.tracks.first(where: { $0.id == memberID }),
                  let voiceTag = track.voiceTag
            else { return nil }
            return (voiceTag, track.id)
        })

        let controller = EngineController(
            client: nil,
            endpoint: nil,
            sampleEngine: spy,
            sampleLibrary: library
        )
        controller.apply(documentModel: project)
        controller.processTick(tickIndex: 0, now: ProcessInfo.processInfo.systemUptime)

        let triggeredTrackIDs = Set(spy.playCalls.map(\.2))
        let triggeredSampleIDs = Set(spy.playCalls.compactMap { call -> UUID? in
            library.samples.first { sample in
                (try? sample.fileRef.resolve(libraryRoot: library.libraryRoot)) == call.0
            }?.id
        })

        XCTAssertTrue(triggeredTrackIDs.contains(try XCTUnwrap(members["kick"])))
        XCTAssertTrue(triggeredTrackIDs.contains(try XCTUnwrap(members["hat-closed"])))
        XCTAssertTrue(triggeredSampleIDs.contains(kick.id))
        XCTAssertTrue(triggeredSampleIDs.contains(hat.id))
        XCTAssertEqual(spy.playCalls.count, 2, "808 step 0 should trigger kick and closed hat, not let one suppress the other")
    }

    func test_inheritedSampleDestination_preparesMixerAndDispatchesTrigger() throws {
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        let kick = try XCTUnwrap(library.firstSample(in: .kick))
        let spy = SpySamplePlaybackSink()
        let groupID = UUID(uuidString: "91919191-9191-9191-9191-919191919191")!
        let trackID = UUID(uuidString: "92929292-9292-9292-9292-929292929292")!
        let track = StepSequenceTrack(
            id: trackID,
            name: "Inherited Kick",
            voiceTag: "kick",
            pitches: [DrumKitNoteMap.baselineNote],
            stepPattern: [true],
            destination: .inheritGroup,
            groupID: groupID,
            velocity: 100,
            gateLength: 4
        )
        let generator = makeAlwaysOnGenerator(id: UUID(), trackType: track.trackType)
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let phrase = PhraseModel.default(tracks: [track], layers: layers)
        let project = Project(
            version: 1,
            tracks: [track],
            trackGroups: [
                TrackGroup(
                    id: groupID,
                    name: "Shared Sampler Kit",
                    memberIDs: [track.id],
                    sharedDestination: .sample(sampleID: kick.id, settings: .default)
                )
            ],
            generatorPool: [generator],
            layers: layers,
            patternBanks: [
                TrackPatternBank(
                    trackID: track.id,
                    slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .generator(generator.id))]
                )
            ],
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )

        let controller = EngineController(
            client: nil,
            endpoint: nil,
            sampleEngine: spy,
            sampleLibrary: library
        )
        controller.apply(documentModel: project)
        controller.processTick(tickIndex: 0, now: ProcessInfo.processInfo.systemUptime)

        XCTAssertTrue(spy.prepareTrackCalls.contains(track.id))
        XCTAssertEqual(spy.playCalls.map(\.2), [track.id])
        XCTAssertEqual(spy.playCalls.first?.0, try kick.fileRef.resolve(libraryRoot: library.libraryRoot))
    }

    func test_noteRepeatSampleDestinationPassesDistinctScheduledTimesForSixtyFourthRepeats() throws {
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        let kick = try XCTUnwrap(library.firstSample(in: .kick))
        let spy = SpySamplePlaybackSink()
        let trackID = UUID(uuidString: "51515151-6565-6565-6565-515151515151")!
        var track = StepSequenceTrack(
            id: trackID,
            name: "Repeat Sample",
            pitches: [DrumKitNoteMap.baselineNote],
            stepPattern: [false],
            destination: .sample(sampleID: kick.id, settings: .default),
            velocity: 100,
            gateLength: 4
        )
        track.noteRepeatInterval = .oneSixtyFourth
        let clip = ClipPoolEntry(
            id: UUID(uuidString: "62626262-6565-6565-6565-626262626262")!,
            name: "Sample Repeat Source",
            trackType: track.trackType,
            content: .noteGrid(
                lengthSteps: 1,
                steps: [
                    ClipStep(
                        main: ClipLane(
                            chance: 1,
                            notes: [ClipStepNote(pitch: DrumKitNoteMap.baselineNote, velocity: 100, lengthSteps: 1)]
                        ),
                        fill: nil
                    )
                ]
            )
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let phrase = PhraseModel.default(
            tracks: [track],
            layers: layers,
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: [clip]
        )
        let project = Project(
            version: 1,
            tracks: [track],
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: [clip],
            layers: layers,
            routes: [],
            patternBanks: [
                TrackPatternBank(
                    trackID: track.id,
                    slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .clip(clip.id))]
                )
            ],
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )
        let controller = EngineController(
            client: nil,
            endpoint: nil,
            sampleEngine: spy,
            sampleLibrary: library
        )

        controller.apply(documentModel: project)
        controller.processTick(tickIndex: 0, now: 0)
        spy.playCalls.removeAll()
        controller.engageNoteRepeat(trackID: track.id)
        controller.processTick(tickIndex: 1, now: 1)

        // P0: note-repeat sub-step stamps are anchored on the tick's MUSICAL
        // position (unified clock), not the pump's wall-clock `now`, and spaced
        // evenly by secondsPerStep/triggerCount. The live sink schedules against
        // host time. Assert each stamp's ABSOLUTE host seconds equals the unified
        // clock's host time for that sub-step's musical position — the absolute
        // check (not just spacing) is what would catch a wrong-unit stamp.
        let repeatTimes = spy.playCalls.map(\.3)
        XCTAssertEqual(repeatTimes.count, 4)
        XCTAssertTrue(repeatTimes.allSatisfy { $0 != nil && $0!.isHostTimeValid })
        let hostSeconds = repeatTimes.compactMap { when in
            when.map { AVAudioTime.seconds(forHostTime: $0.hostTime) }
        }
        let stepSeconds = (60.0 / 120.0) * (4.0 / 16.0)   // one musical step
        let spacing = stepSeconds / 4.0                     // 1/64 → 4 triggers per step
        // The tick-1 musical anchor, read from the SAME production clock.
        let anchorMusical = try XCTUnwrap(controller.audioMasterClock.musicalSeconds(forStep: 1))
        XCTAssertEqual(hostSeconds.count, 4)
        for index in 0..<hostSeconds.count {
            let expected = controller.audioMasterClock.hostSeconds(
                atMusicalSeconds: anchorMusical + Double(index) * spacing
            )
            XCTAssertEqual(
                hostSeconds[index], expected, accuracy: 0.000001,
                "sub-step \(index) must stamp at the unified clock's host time for its musical position"
            )
        }
        // Spacing corroboration: consecutive sub-steps are one 1/64 apart.
        for index in 1..<hostSeconds.count {
            XCTAssertEqual(hostSeconds[index] - hostSeconds[index - 1], spacing, accuracy: 0.000001)
        }
        XCTAssertEqual(Set(hostSeconds).count, 4, "1/64 repeats must not collapse into one dispatch time")
    }

    func test_trackMix_appliedToSampleEngineOnDocumentApply() {
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        guard let kick = library.firstSample(in: .kick) else {
            XCTFail("fixture missing"); return
        }
        let spy = SpySamplePlaybackSink()

        var track = StepSequenceTrack(
            name: "K",
            pitches: [DrumKitNoteMap.baselineNote],
            stepPattern: [true],
            destination: .sample(sampleID: kick.id, settings: .default),
            velocity: 100,
            gateLength: 4
        )
        track.mix.level = 0.25
        track.mix.pan = -0.5

        let generator = makeAlwaysOnGenerator(id: UUID(), trackType: track.trackType)
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let phrase = PhraseModel.default(tracks: [track], layers: layers)
        let project = makeProject(track: track, generator: generator, phrase: phrase, layers: layers)

        let controller = EngineController(
            client: nil, endpoint: nil,
            sampleEngine: spy, sampleLibrary: library
        )
        controller.apply(documentModel: project)

        let last = spy.setTrackMixCalls.last(where: { $0.0 == track.id })
        XCTAssertNotNil(last, "sample track should get a setTrackMix call")
        XCTAssertEqual(last?.1 ?? -1, 0.25, accuracy: 1e-9, "fader level should reach sample engine")
        XCTAssertEqual(last?.2 ?? 0, -0.5, accuracy: 1e-9, "pan should reach sample engine")
    }

    func test_documentApply_preparesSampleAndSlicerTracksBeforePlayback() {
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        guard let kick = library.firstSample(in: .kick) else {
            XCTFail("fixture missing"); return
        }
        let spy = SpySamplePlaybackSink()
        let sliceSet = SliceSet(
            sampleID: kick.id,
            markers: [
                SliceMarker(startFrame: 0, endFrame: 4_800),
                SliceMarker(startFrame: 0, endFrame: 2_400)
            ]
        )
        let drumTrack = StepSequenceTrack(
            name: "Drum",
            pitches: [DrumKitNoteMap.baselineNote],
            stepPattern: [true],
            destination: .sample(sampleID: kick.id, settings: .default),
            velocity: 100,
            gateLength: 4
        )
        let sliceTrack = StepSequenceTrack(
            name: "Slice",
            trackType: .slice,
            pitches: [60],
            stepPattern: [true],
            destination: .slicer(sliceSetID: sliceSet.id, settings: .default),
            velocity: 100,
            gateLength: 4
        )
        let layers = PhraseLayerDefinition.defaultSet(for: [drumTrack, sliceTrack])
        let phrase = PhraseModel.default(tracks: [drumTrack, sliceTrack], layers: layers)
        let project = Project(
            version: 1,
            tracks: [drumTrack, sliceTrack],
            layers: layers,
            sliceSetPool: [sliceSet],
            selectedTrackID: drumTrack.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )
        let controller = EngineController(
            client: nil,
            endpoint: nil,
            sampleEngine: spy,
            sampleLibrary: library
        )

        controller.apply(documentModel: project)

        XCTAssertEqual(Set(spy.prepareTrackCalls), [drumTrack.id, sliceTrack.id])
        XCTAssertEqual(Set(spy.setTrackMixCalls.map(\.0)), [drumTrack.id, sliceTrack.id])
    }

    func test_destinationChangedAwayFromSample_triggersRemoveTrack() {
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        guard let kick = library.firstSample(in: .kick) else {
            XCTFail("fixture missing"); return
        }
        let spy = SpySamplePlaybackSink()

        var track = StepSequenceTrack(
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
        var project = makeProject(track: track, generator: generator, phrase: phrase, layers: layers)

        let controller = EngineController(
            client: nil, endpoint: nil,
            sampleEngine: spy, sampleLibrary: library
        )
        controller.apply(documentModel: project)
        XCTAssertTrue(spy.removeTrackCalls.isEmpty, "no removals on first apply")

        // Flip the track's destination away from .sample — the sample engine should
        // be told to tear down its mixer for this track.
        track.destination = .midi(port: nil, channel: 0, noteOffset: 0)
        project.tracks = [track]
        controller.apply(documentModel: project)

        XCTAssertTrue(spy.removeTrackCalls.contains(track.id), "track leaving .sample should trigger removeTrack on sample engine")
    }

    // Layer (perform-cell) mute on a sample track is now a GAIN change, not a
    // trigger-gate (task #49): the track keeps triggering and the mute is
    // applied as ramped per-track gain. (Was: asserted zero dispatch.)
    func test_layerMute_appliesGain_doesNotSuppressSampleDispatch() {
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        guard let kick = library.firstSample(in: .kick) else { XCTFail(); return }
        let spy = SpySamplePlaybackSink()

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
        let muteLayer = layers.first(where: { $0.target == .mute })!
        var phrase = PhraseModel.default(tracks: [track], layers: layers)
        phrase.setCell(.single(.bool(true)), for: muteLayer.id, trackID: track.id)
        let project = makeProject(track: track, generator: generator, phrase: phrase, layers: layers)

        let controller = EngineController(
            client: nil, endpoint: nil,
            sampleEngine: spy, sampleLibrary: library
        )
        controller.apply(documentModel: project)
        controller.start()
        let now = ProcessInfo.processInfo.systemUptime
        for step in 0..<4 {
            controller.processTick(tickIndex: UInt64(step), now: now + Double(step) * 0.125)
        }
        controller.stop()

        XCTAssertGreaterThan(spy.playCalls.count, 0, "layer mute is a gain, not a gate — triggering continues")
        XCTAssertTrue(
            spy.setTrackMuteGainCalls.contains(where: { $0.0 == track.id && $0.1 }),
            "layer mute must drive the per-track mute-gain path"
        )
    }

    // Mixer mute on a sample track is now a GAIN change, not a trigger-gate.
    func test_mixMute_appliesGain_doesNotSuppressSampleDispatch() {
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        guard let kick = library.firstSample(in: .kick) else { XCTFail(); return }
        let spy = SpySamplePlaybackSink()

        var track = StepSequenceTrack(
            name: "K",
            pitches: [DrumKitNoteMap.baselineNote],
            stepPattern: [true],
            destination: .sample(sampleID: kick.id, settings: .default),
            velocity: 100,
            gateLength: 4
        )
        track.mix.isMuted = true

        let generator = makeAlwaysOnGenerator(id: UUID(), trackType: track.trackType)
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let phrase = PhraseModel.default(tracks: [track], layers: layers)
        let project = makeProject(track: track, generator: generator, phrase: phrase, layers: layers)

        let controller = EngineController(
            client: nil, endpoint: nil,
            sampleEngine: spy, sampleLibrary: library
        )
        controller.apply(documentModel: project)
        controller.start()
        let now = ProcessInfo.processInfo.systemUptime
        for step in 0..<4 {
            controller.processTick(tickIndex: UInt64(step), now: now + Double(step) * 0.125)
        }
        controller.stop()

        XCTAssertGreaterThan(spy.playCalls.count, 0, "mix mute is a gain, not a gate — triggering continues")
        XCTAssertTrue(
            spy.setTrackMuteGainCalls.contains(where: { $0.0 == track.id && $0.1 }),
            "mixer mute must drive the per-track mute-gain path"
        )
    }

    func test_orphanSampleID_noCrash() {
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        let spy = SpySamplePlaybackSink()

        let track = StepSequenceTrack(
            name: "K",
            pitches: [DrumKitNoteMap.baselineNote],
            stepPattern: [true],
            destination: .sample(sampleID: UUID(), settings: .default),   // not in library
            velocity: 100,
            gateLength: 4
        )
        let generator = makeAlwaysOnGenerator(id: UUID(), trackType: track.trackType)
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let phrase = PhraseModel.default(tracks: [track], layers: layers)
        let project = makeProject(track: track, generator: generator, phrase: phrase, layers: layers)

        let controller = EngineController(
            client: nil, endpoint: nil,
            sampleEngine: spy, sampleLibrary: library
        )
        controller.apply(documentModel: project)
        controller.start()
        controller.processTick(tickIndex: 0, now: 0)
        controller.stop()

        XCTAssertEqual(spy.playCalls.count, 0, "orphan sample ID should no-op cleanly")
    }

    func test_slicerDestination_dispatchesSliceRangeAndMergedGain() {
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        guard let sample = library.firstSample(in: .kick) else {
            XCTFail("fixture missing"); return
        }
        let spy = SpySamplePlaybackSink()
        let sliceSet = SliceSet(
            sampleID: sample.id,
            markers: [
                SliceMarker(startFrame: 0, endFrame: 44_100),
                SliceMarker(startFrame: 100, endFrame: 300, gain: 3, reverse: true)
            ]
        )
        let clip = ClipPoolEntry(
            id: UUID(),
            name: "Slice Clip",
            trackType: .slice,
            content: .sliceTriggers(stepPattern: [true], sliceIndexes: [1], stepModes: [.single])
        )
        let track = StepSequenceTrack(
            name: "Slice",
            trackType: .slice,
            pitches: [60],
            stepPattern: [true],
            destination: .slicer(sliceSetID: sliceSet.id, settings: SlicerSettings(gain: -2, transpose: 0, voiceMode: .mono)),
            velocity: 100,
            gateLength: 4
        )
        let generator = makeAlwaysOnGenerator(id: UUID(), trackType: track.trackType)
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let phrase = PhraseModel.default(tracks: [track], layers: layers, generatorPool: [generator], clipPool: [clip])
        let bank = TrackPatternBank(
            trackID: track.id,
            slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .clip(clip.id))]
        )
        let project = makeProject(
            track: track,
            generator: generator,
            phrase: phrase,
            layers: layers,
            clipPool: [clip],
            patternBank: bank,
            sliceSetPool: [sliceSet]
        )
        let controller = EngineController(client: nil, endpoint: nil, sampleEngine: spy, sampleLibrary: library)

        controller.apply(documentModel: project)
        controller.processTick(tickIndex: 0, now: ProcessInfo.processInfo.systemUptime)

        XCTAssertEqual(spy.playCalls.count, 0)
        let call = spy.playSliceCalls.first
        XCTAssertEqual(spy.playSliceCalls.count, 1)
        XCTAssertEqual(call?.1, 100)
        XCTAssertEqual(call?.2, 300)
        XCTAssertEqual(call?.3.gain ?? 0, 1, accuracy: 1e-9)
        XCTAssertEqual(call?.4, track.id)
        XCTAssertEqual(call?.6, true)
    }

    func test_slicerDestination_appliesPerStepSamplePlayerParameters() {
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        guard let sample = library.firstSample(in: .kick) else {
            XCTFail("fixture missing"); return
        }
        let spy = SpySamplePlaybackSink()
        let sliceSet = SliceSet(
            sampleID: sample.id,
            markers: [
                SliceMarker(startFrame: 0, endFrame: 44_100),
                SliceMarker(startFrame: 100, endFrame: 1_100, gain: 3)
            ]
        )
        let stepParameters = SliceTriggerStepParameters(
            gain: 4,
            pitch: 2,
            startTrim: 0.1,
            endTrim: 0.2,
            pan: -0.25,
            filter: 0.35,
            attackMs: 12,
            releaseMs: 80,
            reverse: true,
            choke: false
        )
        let clip = ClipPoolEntry(
            id: UUID(),
            name: "Slice Clip",
            trackType: .slice,
            content: .sliceTriggers(
                stepPattern: [true],
                sliceIndexes: [1],
                stepModes: [.single],
                stepParameters: [stepParameters]
            )
        )
        let track = StepSequenceTrack(
            name: "Slice",
            trackType: .slice,
            pitches: [60],
            stepPattern: [true],
            destination: .slicer(sliceSetID: sliceSet.id, settings: SlicerSettings(gain: -2, transpose: 1, voiceMode: .mono)),
            velocity: 100,
            gateLength: 4
        )
        let generator = makeAlwaysOnGenerator(id: UUID(), trackType: track.trackType)
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let phrase = PhraseModel.default(tracks: [track], layers: layers, generatorPool: [generator], clipPool: [clip])
        let bank = TrackPatternBank(
            trackID: track.id,
            slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .clip(clip.id))]
        )
        let project = makeProject(
            track: track,
            generator: generator,
            phrase: phrase,
            layers: layers,
            clipPool: [clip],
            patternBank: bank,
            sliceSetPool: [sliceSet]
        )
        let controller = EngineController(client: nil, endpoint: nil, sampleEngine: spy, sampleLibrary: library)

        controller.apply(documentModel: project)
        controller.processTick(tickIndex: 0, now: ProcessInfo.processInfo.systemUptime)

        let call = spy.playSliceCalls.first
        XCTAssertEqual(spy.playSliceCalls.count, 1)
        XCTAssertEqual(call?.1, 200)
        XCTAssertEqual(call?.2, 900)
        XCTAssertEqual(call?.3.gain ?? 0, 5, accuracy: 1e-9)
        XCTAssertEqual(call?.3.transpose, 3)
        XCTAssertEqual(call?.3.voiceMode, .polyphonic)
        XCTAssertEqual(call?.6, true)
        XCTAssertEqual(call?.7?.pan, -0.25)
        XCTAssertEqual(call?.7?.filter, 0.35)
        XCTAssertEqual(call?.7?.attackMs, 12)
        XCTAssertEqual(call?.7?.releaseMs, 80)
        XCTAssertEqual(call?.7?.choke, false)
    }

    func test_slicerRapidAlternatingSlicesUseWarmedAssetAndRemainMono() throws {
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        let sample = try XCTUnwrap(library.firstSample(in: .kick))
        let expectedURL = try sample.fileRef.resolve(libraryRoot: library.libraryRoot)
        let spy = SpySamplePlaybackSink()
        var openedURLs: [URL] = []
        let cache = SampleAssetCache { url in
            openedURLs.append(url)
            return try AVAudioFile(forReading: url)
        }

        let sliceSet = SliceSet(
            sampleID: sample.id,
            markers: [
                SliceMarker(startFrame: 0, endFrame: 1_200),
                SliceMarker(startFrame: 1_200, endFrame: 2_400, gain: 1),
                SliceMarker(startFrame: 2_400, endFrame: 3_600, reverse: true),
                SliceMarker(startFrame: 3_600, endFrame: 4_800, gain: -2)
            ]
        )
        let stepCount = 16
        let stepParameters = (0..<stepCount).map { index in
            SliceTriggerStepParameters(
                gain: Double((index % 5) - 2),
                pitch: Double((index % 3) - 1),
                startTrim: index.isMultiple(of: 3) ? 0.10 : 0,
                endTrim: index.isMultiple(of: 4) ? 0.15 : 0,
                pan: index.isMultiple(of: 2) ? -0.35 : 0.35,
                filter: Double(index % 10) / 10,
                attackMs: index.isMultiple(of: 5) ? 2 : 0,
                releaseMs: index.isMultiple(of: 6) ? 4 : 0,
                reverse: index.isMultiple(of: 7),
                choke: true
            )
        }
        let clip = ClipPoolEntry(
            id: UUID(),
            name: "Rapid Slice Clip",
            trackType: .slice,
            content: .sliceTriggers(
                stepPattern: Array(repeating: true, count: stepCount),
                sliceIndexes: (0..<stepCount).map { $0 % sliceSet.markers.count },
                stepModes: Array(repeating: .single, count: stepCount),
                stepParameters: stepParameters
            )
        )
        let track = StepSequenceTrack(
            name: "Slice",
            trackType: .slice,
            pitches: [60],
            stepPattern: Array(repeating: true, count: stepCount),
            destination: .slicer(sliceSetID: sliceSet.id, settings: SlicerSettings(gain: -1, transpose: 0, voiceMode: .mono)),
            velocity: 100,
            gateLength: 4
        )
        let generator = makeAlwaysOnGenerator(id: UUID(), trackType: track.trackType)
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let phrase = PhraseModel.default(tracks: [track], layers: layers, generatorPool: [generator], clipPool: [clip])
        let bank = TrackPatternBank(
            trackID: track.id,
            slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .clip(clip.id))]
        )
        let project = makeProject(
            track: track,
            generator: generator,
            phrase: phrase,
            layers: layers,
            clipPool: [clip],
            patternBank: bank,
            sliceSetPool: [sliceSet]
        )
        let controller = EngineController(
            client: nil,
            endpoint: nil,
            sampleEngine: spy,
            sampleAssetCache: cache,
            sampleLibrary: library
        )

        controller.apply(documentModel: project)
        XCTAssertEqual(openedURLs, [expectedURL])

        let tickCount = 128
        let now = ProcessInfo.processInfo.systemUptime
        for step in 0..<tickCount {
            controller.processTick(tickIndex: UInt64(step), now: now + Double(step) * 0.0625)
        }

        XCTAssertEqual(spy.playSliceCalls.count, tickCount)
        XCTAssertEqual(Set(spy.playSliceCalls.map(\.0)), [expectedURL])
        XCTAssertEqual(openedURLs.count, 1, "rapid slicer dispatch should reuse the warmed source sample instead of reopening it per slice")
        XCTAssertEqual(Set(spy.playSliceCalls.map(\.3.voiceMode)), [.mono])
        XCTAssertTrue(spy.playSliceCalls.allSatisfy { $0.7?.choke == true })
        XCTAssertTrue(spy.playSliceCalls.contains { $0.6 }, "stress clip should exercise reverse slice dispatch")
        XCTAssertGreaterThan(Set(spy.playSliceCalls.map(\.1)).count, 1, "stress clip should alternate slice start frames")
    }

    func test_slicerDestination_appliesMicroTimingAtSampleRate() {
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        guard let sample = library.firstSample(in: .kick) else {
            XCTFail("fixture missing"); return
        }
        let spy = SpySamplePlaybackSink()
        let sliceSet = SliceSet(
            sampleID: sample.id,
            markers: [
                SliceMarker(startFrame: 0, endFrame: 4_800),
                SliceMarker(startFrame: 100, endFrame: 4_000, microTimingSteps: 0.5)
            ]
        )
        let clip = ClipPoolEntry(
            id: UUID(),
            name: "Slice Clip",
            trackType: .slice,
            content: .sliceTriggers(stepPattern: [true], sliceIndexes: [1], stepModes: [.single])
        )
        let track = StepSequenceTrack(
            name: "Slice",
            trackType: .slice,
            pitches: [60],
            stepPattern: [true],
            destination: .slicer(sliceSetID: sliceSet.id, settings: .default),
            velocity: 100,
            gateLength: 4
        )
        let generator = makeAlwaysOnGenerator(id: UUID(), trackType: track.trackType)
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let phrase = PhraseModel.default(tracks: [track], layers: layers, generatorPool: [generator], clipPool: [clip])
        let bank = TrackPatternBank(trackID: track.id, slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .clip(clip.id))])
        let project = makeProject(
            track: track,
            generator: generator,
            phrase: phrase,
            layers: layers,
            clipPool: [clip],
            patternBank: bank,
            sliceSetPool: [sliceSet]
        )
        let controller = EngineController(client: nil, endpoint: nil, sampleEngine: spy, sampleLibrary: library)

        controller.apply(documentModel: project)
        controller.processTick(tickIndex: 0, now: ProcessInfo.processInfo.systemUptime)

        XCTAssertEqual(sample.sampleRate, 48_000)
        XCTAssertEqual(spy.playSliceCalls.first?.1, 3_100)
        XCTAssertEqual(spy.playSliceCalls.first?.2, 4_000)
    }

    func test_slicerRunFromHere_extendsToWholeSampleEnd() {
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        guard let sample = library.firstSample(in: .kick) else {
            XCTFail("fixture missing"); return
        }
        let spy = SpySamplePlaybackSink()
        let sliceSet = SliceSet(
            sampleID: sample.id,
            markers: [
                SliceMarker(startFrame: 0, endFrame: 44_100),
                SliceMarker(startFrame: 100, endFrame: 300)
            ]
        )
        let clip = ClipPoolEntry(
            id: UUID(),
            name: "Slice Clip",
            trackType: .slice,
            content: .sliceTriggers(stepPattern: [true], sliceIndexes: [1], stepModes: [.runFromHere])
        )
        let track = StepSequenceTrack(
            name: "Slice",
            trackType: .slice,
            pitches: [60],
            stepPattern: [true],
            destination: .slicer(sliceSetID: sliceSet.id, settings: .default),
            velocity: 100,
            gateLength: 4
        )
        let generator = makeAlwaysOnGenerator(id: UUID(), trackType: track.trackType)
        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let phrase = PhraseModel.default(tracks: [track], layers: layers, generatorPool: [generator], clipPool: [clip])
        let bank = TrackPatternBank(trackID: track.id, slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .clip(clip.id))])
        let project = makeProject(
            track: track,
            generator: generator,
            phrase: phrase,
            layers: layers,
            clipPool: [clip],
            patternBank: bank,
            sliceSetPool: [sliceSet]
        )
        let controller = EngineController(client: nil, endpoint: nil, sampleEngine: spy, sampleLibrary: library)

        controller.apply(documentModel: project)
        controller.processTick(tickIndex: 0, now: ProcessInfo.processInfo.systemUptime)

        XCTAssertEqual(spy.playSliceCalls.first?.1, 100)
        XCTAssertEqual(spy.playSliceCalls.first?.2, 44_100)
    }

}
