import XCTest
import AVFoundation
@testable import SequencerAI

final class EngineControllerSnapshotPlaybackTests: XCTestCase {
    private final class SpySamplePlaybackSink: SamplePlaybackSink {
        var playCalls: [(URL, SamplerSettings, UUID)] = []
        var voiceParamCalls: [(UUID, BuiltinMacroKind, Double)] = []

        func start() throws {}
        func stop() {}
        func play(sampleURL: URL, settings: SamplerSettings, trackID: UUID, at when: AVAudioTime?) -> VoiceHandle? {
            playCalls.append((sampleURL, settings, trackID))
            return nil
        }
        func setTrackMix(trackID: UUID, level: Double, pan: Double) {}
        func removeTrack(trackID: UUID) {}
        func audition(sampleURL: URL) {}
        func stopAudition() {}
        func setVoiceParam(trackID: UUID, kind: BuiltinMacroKind, value: Double) {
            voiceParamCalls.append((trackID, kind, value))
        }
        func applyFilter(_ settings: SamplerFilterSettings, trackID: UUID) {}
        func filterNode(for trackID: UUID) -> SamplerFilterNode? { nil }
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

    func test_snapshot_update_changes_clip_playback_without_document_reapply() {
        let spy = SpySamplePlaybackSink()
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        guard let kick = library.firstSample(in: .kick) else {
            XCTFail("fixture missing")
            return
        }

        var project = makeSampleClipProject(sampleID: kick.id, clipPattern: [true], clipMacroValue: nil)
        let controller = EngineController(client: nil, endpoint: nil, sampleEngine: spy, sampleLibrary: library)
        controller.apply(documentModel: project)
        controller.apply(playbackSnapshot: SequencerSnapshotCompiler.compile(project: project))

        let now = ProcessInfo.processInfo.systemUptime
        controller.processTick(tickIndex: 0, now: now)
        XCTAssertEqual(spy.playCalls.count, 1)

        project.clipPool[0].content = .stepSequence(stepPattern: [false], pitches: [60])
        controller.apply(playbackSnapshot: SequencerSnapshotCompiler.compile(project: project))
        controller.processTick(tickIndex: 1, now: now + 0.125)

        XCTAssertEqual(spy.playCalls.count, 1, "snapshot-only update should suppress the stale clip note without reapplying the document")
    }

    func test_clip_macro_override_wins_over_phrase_macro_value() {
        let spy = SpySamplePlaybackSink()
        let library = AudioSampleLibrary(libraryRoot: libraryRoot)
        guard let kick = library.firstSample(in: .kick) else {
            XCTFail("fixture missing")
            return
        }

        let project = makeSampleClipProject(sampleID: kick.id, clipPattern: [true], clipMacroValue: 0.8)
        let controller = EngineController(client: nil, endpoint: nil, sampleEngine: spy, sampleLibrary: library)
        controller.apply(documentModel: project)
        controller.apply(playbackSnapshot: SequencerSnapshotCompiler.compile(project: project))

        controller.processTick(tickIndex: 0, now: ProcessInfo.processInfo.systemUptime)

        let gainCall = spy.voiceParamCalls.last { $0.1 == .sampleGain }
        XCTAssertNotNil(gainCall)
        XCTAssertEqual(gainCall?.2 ?? 0, 0.8, accuracy: 1e-9)
    }

    private func makeSampleClipProject(sampleID: UUID, clipPattern: [Bool], clipMacroValue: Double?) -> Project {
        let trackID = UUID()
        let gainDescriptor = TrackMacroDescriptor.builtin(trackID: trackID, kind: .sampleGain)
        let binding = TrackMacroBinding(descriptor: gainDescriptor)

        var track = StepSequenceTrack(
            id: trackID,
            name: "Sample Track",
            trackType: .monoMelodic,
            pitches: [60],
            stepPattern: [true],
            destination: .sample(sampleID: sampleID, settings: .default),
            velocity: 100,
            gateLength: 4,
            macros: [binding]
        )
        track.mix.isMuted = false

        let laneValues: [Double?] = [clipMacroValue]
        let clip = ClipPoolEntry(
            id: UUID(),
            name: "Clip",
            trackType: track.trackType,
            content: .stepSequence(stepPattern: clipPattern, pitches: [60]),
            macroLanes: clipMacroValue == nil ? [:] : [binding.id: MacroLane(values: laneValues)]
        )

        let layers = PhraseLayerDefinition.defaultSet(for: [track])
        let macroLayerID = "macro-\(track.id.uuidString)-\(binding.id.uuidString)"
        var phrase = PhraseModel(
            id: UUID(),
            name: "Phrase",
            lengthBars: 1,
            stepsPerBar: 1,
            cells: layers.map { PhraseCellAssignment(trackID: track.id, layerID: $0.id, cell: .inheritDefault) }
        )
        phrase.setCell(.single(.scalar(0.25)), for: macroLayerID, trackID: track.id)

        let bank = TrackPatternBank(
            trackID: track.id,
            slots: (0..<TrackPatternBank.slotCount).map {
                TrackPatternSlot(slotIndex: $0, sourceRef: .clip($0 == 0 ? clip.id : nil))
            }
        )

        return Project(
            version: 1,
            tracks: [track],
            generatorPool: GeneratorPoolEntry.defaultPool,
            clipPool: [clip],
            layers: layers,
            patternBanks: [bank],
            selectedTrackID: track.id,
            phrases: [phrase],
            selectedPhraseID: phrase.id
        )
    }
}
