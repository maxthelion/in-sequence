import XCTest
import AVFoundation
@testable import SequencerAI

final class EngineControllerSampleTriggerTests: XCTestCase {
    private final class SpySamplePlaybackSink: SamplePlaybackSink {
        var playCalls: [(URL, SamplerSettings, UUID, AVAudioTime?)] = []
        var playSliceCalls: [(URL, AVAudioFramePosition, AVAudioFramePosition, SlicerSettings, UUID, AVAudioTime?, Bool, SliceTriggerStepParameters?)] = []
        var prepareTrackCalls: [UUID] = []
        var setTrackMixCalls: [(UUID, Double, Double)] = []
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

    func test_sampleDestination_schedulesPreparedNextStepAtNextTickTime() throws {
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
        controller.processTick(tickIndex: 0, now: 100)
        controller.processTick(tickIndex: 1, now: 100.125)

        let scheduledSeconds = spy.playCalls.compactMap { call in
            call.3.map { AVAudioTime.seconds(forHostTime: $0.hostTime) }
        }
        XCTAssertEqual(scheduledSeconds.count, 2)
        XCTAssertEqual(scheduledSeconds[0], 100, accuracy: 0.000001)
        XCTAssertEqual(scheduledSeconds[1], 100.125, accuracy: 0.000001)
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

        let repeatTimes = spy.playCalls.map(\.3)
        XCTAssertEqual(repeatTimes.count, 4)
        XCTAssertTrue(repeatTimes.allSatisfy { $0 != nil })
        let scheduledSeconds = repeatTimes.compactMap { when in
            when.map { AVAudioTime.seconds(forHostTime: $0.hostTime) }
        }
        XCTAssertEqual(scheduledSeconds.count, 4)
        zip(scheduledSeconds, [1.0, 1.03125, 1.0625, 1.09375]).forEach { actual, expected in
            XCTAssertEqual(actual, expected, accuracy: 0.000001)
        }
        XCTAssertEqual(Set(scheduledSeconds).count, 4, "1/64 repeats must not collapse into one dispatch time")
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

    func test_muteCell_suppressesSampleDispatch() {
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

        XCTAssertEqual(spy.playCalls.count, 0, "muted track should not dispatch sample triggers")
    }

    func test_mixMute_suppressesSampleDispatch() {
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

        XCTAssertEqual(spy.playCalls.count, 0, "mix-muted track should not dispatch sample triggers")
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
