import XCTest
import AVFoundation
@testable import SequencerAI

final class EngineControllerSampleTriggerTests: XCTestCase {
    private final class SpySamplePlaybackSink: SamplePlaybackSink {
        var playCalls: [(URL, SamplerSettings, Double)] = []
        func start() throws {}
        func stop() {}
        func play(sampleURL: URL, settings: SamplerSettings, mixLevel: Double, at when: AVAudioTime?) -> VoiceHandle? {
            playCalls.append((sampleURL, settings, mixLevel))
            return nil
        }
        func audition(sampleURL: URL) {}
        func stopAudition() {}
    }

    private var libraryRoot: URL!

    override func setUpWithError() throws {
        libraryRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: libraryRoot.appendingPathComponent("kick"), withIntermediateDirectories: true)
        try Data().write(to: libraryRoot.appendingPathComponent("kick/test-kick.wav"))
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
                step: .manual(pattern: [true]),
                pitch: .manual(pitches: [DrumKitNoteMap.baselineNote], pickMode: .sequential),
                shape: NoteShape(velocity: 100, gateLength: 4, accent: false)
            )
        )
    }

    private func makeProject(
        track: StepSequenceTrack,
        generator: GeneratorPoolEntry,
        phrase: PhraseModel,
        layers: [PhraseLayerDefinition]
    ) -> Project {
        let patternBank = TrackPatternBank(
            trackID: track.id,
            slots: (0..<16).map { TrackPatternSlot(slotIndex: $0, sourceRef: .generator(generator.id)) }
        )
        return Project(
            version: 1,
            tracks: [track],
            generatorPool: [generator],
            clipPool: [],
            layers: layers,
            patternBanks: [patternBank],
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
        controller.start()
        let now = ProcessInfo.processInfo.systemUptime
        for step in 0..<4 {
            controller.processTick(tickIndex: UInt64(step), now: now + Double(step) * 0.125)
        }
        controller.stop()

        // start() pre-queues one tick, then each processTick dispatches-then-prepares.
        // The TickClock may fire one additional background tick before stop(), so the
        // count is at least 4 (the 4 manually-driven ticks) but may be higher.
        XCTAssertGreaterThanOrEqual(spy.playCalls.count, 4, "at least one play per fired tick; 4 ticks driven")
    }

    func test_trackMixLevel_propagatesToSampleEngine() {
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
        track.mix.level = 0.25       // non-default so we can distinguish from level 1.0

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
        controller.processTick(tickIndex: 0, now: now)
        controller.stop()

        XCTAssertFalse(spy.playCalls.isEmpty, "a trigger should have fired")
        for (_, _, mixLevel) in spy.playCalls {
            XCTAssertEqual(mixLevel, 0.25, accuracy: 1e-9, "fader level should arrive at the sample engine as-is")
        }
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
}
