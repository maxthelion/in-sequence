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
        libraryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: libraryRoot.appendingPathComponent("kick"), withIntermediateDirectories: true)
        try writeSilentWAV(to: libraryRoot.appendingPathComponent("kick/test-kick.wav"), sampleRate: 48_000)
    }

    override func tearDownWithError() throws {
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
