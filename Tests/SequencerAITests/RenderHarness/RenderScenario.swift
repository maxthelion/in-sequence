import AVFoundation
import Foundation
@testable import SequencerAI

/// Combinatorial scenario DSL for the offline render harness.
///
/// A scenario is a deterministic project (tracks, patterns, buses, sends,
/// FX inserts, phrase structure, BPM) plus a scripted timeline of parameter
/// changes at musical positions ("playing around while it plays"). The
/// harness renders it offline and asserts the output stays on the step grid,
/// renders identically across runs, and contains no dropouts/clipping.
///
/// See docs/testing/render-harness.md for how to add scenarios.
struct RenderScenario {
    /// Deterministic synthesized percussion fixtures (sharp attacks so the
    /// transient detector has unambiguous onsets).
    enum Voice: String, CaseIterable {
        case kick
        case snare
        case hat
        case perc
    }

    enum TrackKind {
        /// One-shot sample track (drum-style).
        case sample(Voice)
        /// Slicer track triggering slice 0 of the slicer source fixture.
        case slicer
    }

    struct TrackSpec {
        var name: String
        var kind: TrackKind
        /// Step indices in 0..<16; the 16-step pattern repeats every bar.
        var steps: [Int]
        var level: Double = 0.8
        var pan: Double = 0
        var sendA: Double = 0
        var sendB: Double = 0
        /// Index into `RenderScenario.buses`, or nil for master.
        var busIndex: Int?

        init(
            name: String,
            kind: TrackKind,
            steps: [Int],
            level: Double = 0.8,
            pan: Double = 0,
            sendA: Double = 0,
            sendB: Double = 0,
            busIndex: Int? = nil
        ) {
            self.name = name
            self.kind = kind
            self.steps = steps
            self.level = level
            self.pan = pan
            self.sendA = sendA
            self.sendB = sendB
            self.busIndex = busIndex
        }
    }

    struct BusSpec {
        var name: String
        var level: Double = 1
        /// Occupied-FX-slot axis: a native filter insert on the bus.
        var withFilterInsert = false

        init(name: String, level: Double = 1, withFilterInsert: Bool = false) {
            self.name = name
            self.level = level
            self.withFilterInsert = withFilterInsert
        }
    }

    enum ActionKind {
        case setBPM(Double)
        case setTrackLevel(trackIndex: Int, level: Double)
        case setTrackPan(trackIndex: Int, pan: Double)
        /// Keep send values nonzero->nonzero: a send crossing zero rewires
        /// the graph topology (production behavior), which restarts the
        /// engine and is not supported mid-render by the offline harness.
        case setTrackSends(trackIndex: Int, sendA: Double, sendB: Double)
        case setBusLevel(busIndex: Int, level: Double)
        case setMasterOutputGain(Double)
    }

    /// A scripted parameter change applied immediately before `tick` is
    /// processed (i.e. it takes effect at that musical step).
    struct Action {
        var tick: Int
        var kind: ActionKind
    }

    var name: String
    var bpm: Double = 120
    var bars: Int = 2
    var tracks: [TrackSpec]
    var buses: [BusSpec] = []
    /// Occupied-FX-slot axis for the global send buses.
    var sendBusAOccupied = false
    var sendBusBOccupied = false
    var actions: [Action] = []
    /// Phrase-structure axis: explicit phrase lengths in bars (the project
    /// cycles through them). Nil uses the single default 8-bar phrase.
    var phraseLengthsBars: [Int]?

    var stepsPerBar: Int { 16 }
    var totalTicks: Int { bars * stepsPerBar }

    init(
        name: String,
        bpm: Double = 120,
        bars: Int = 2,
        tracks: [TrackSpec],
        buses: [BusSpec] = [],
        sendBusAOccupied: Bool = false,
        sendBusBOccupied: Bool = false,
        actions: [Action] = [],
        phraseLengthsBars: [Int]? = nil
    ) {
        self.name = name
        self.bpm = bpm
        self.bars = bars
        self.tracks = tracks
        self.buses = buses
        self.sendBusAOccupied = sendBusAOccupied
        self.sendBusBOccupied = sendBusBOccupied
        self.actions = actions
        self.phraseLengthsBars = phraseLengthsBars
    }

    /// Ticks at which at least one track fires (deduplicated across tracks).
    var expectedOnsetTicks: [Int] {
        var ticks = Set<Int>()
        for bar in 0..<bars {
            for track in tracks {
                for step in track.steps where step >= 0 && step < stepsPerBar {
                    ticks.insert(bar * stepsPerBar + step)
                }
            }
        }
        return ticks.sorted()
    }
}

/// Writes the deterministic audio fixtures and builds the `Project` for a
/// scenario. All fixtures are 48 kHz mono WAVs with instant attacks.
enum RenderScenarioProjectBuilder {
    static let fixtureSampleRate: Double = 48_000

    struct Built {
        var project: Project
        var trackIDs: [UUID]
        var busIDs: [UUID]
    }

    // MARK: - Fixtures

    /// Creates a temp sample-library root with one fixture per voice plus the
    /// slicer source. Callers should remove the directory in tearDown.
    static func makeFixtureLibraryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("render-harness-fixtures-\(UUID().uuidString)", isDirectory: true)
        try writeFixture(category: "kick", file: "rh-kick.wav", root: root) { i, n in
            // Click-dominant "kick": broadband 5 ms attack louder than the
            // 80 Hz tail. The autoslice detector localizes broadband attacks
            // to ~1 ms, but a low-frequency-dominant onset mislocates by up
            // to ~±15 ms (the 80 Hz body's own cycles read as attack edges
            // at the detector's 2 ms analysis lag) — measured empirically;
            // the autoslice product tolerance is 30 ms, so that is by
            // design. Timing fixtures therefore keep their global peak in
            // the attack click.
            let click = i < 240
                ? seededNoise(UInt64(i) &* 0x9E37_79B9_7F4A_7C15 &+ 11) * (1 - Float(i) / 240) * 0.75
                : 0
            let body = sinf(Float(i) * Float(2 * Double.pi * 80 / fixtureSampleRate)) * expf(-9 * Float(i) / Float(n)) * 0.3
            return click + body
        }
        try writeFixture(category: "snare", file: "rh-snare.wav", root: root, frames: 1_920) { i, n in
            // Seeded noise burst.
            (seededNoise(UInt64(i) &* 6_364_136_223_846_793_005 &+ 1)) * expf(-7 * Float(i) / Float(n)) * 0.6
        }
        try writeFixture(category: "hatClosed", file: "rh-hat.wav", root: root, frames: 960) { i, n in
            // Short bright noise tick.
            (seededNoise(UInt64(i) &* 2_862_933_555_777_941_757 &+ 3)) * expf(-9 * Float(i) / Float(n)) * 0.45
        }
        try writeFixture(category: "percussion", file: "rh-perc.wav", root: root, frames: 1_200) { i, n in
            sinf(Float(i) * Float(2 * Double.pi * 1_800 / fixtureSampleRate)) * expf(-8 * Float(i) / Float(n)) * 0.55
        }
        try writeFixture(category: "breaks", file: "rh-slicer-source.wav", root: root, frames: 24_000) { i, _ in
            // Slicer source: a click in the first 50 ms, silence afterwards.
            i < 2_400
                ? sinf(Float(i) * Float(2 * Double.pi * 600 / fixtureSampleRate)) * expf(-8 * Float(i) / 2_400) * 0.7
                : 0
        }
        return root
    }

    static func slicerSourceSampleID(libraryRoot: URL) -> UUID {
        AudioSampleLibrary.stableID(forRelativePath: "breaks/rh-slicer-source.wav")
    }

    private static func seededNoise(_ seed: UInt64) -> Float {
        // Deterministic pseudo-noise in [-1, 1] (splitmix64 finalizer).
        var z = seed &+ 0x9E37_79B9_7F4A_7C15
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Float(Double(z) / Double(UInt64.max)) * 2 - 1
    }

    private static func writeFixture(
        category: String,
        file: String,
        root: URL,
        frames: Int = 2_880,
        sample: (Int, Int) -> Float
    ) throws {
        let directory = root.appendingPathComponent(category, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let format = AVAudioFormat(standardFormatWithSampleRate: fixtureSampleRate, channels: 1)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(frames))!
        buffer.frameLength = AVAudioFrameCount(frames)
        let samples = buffer.floatChannelData![0]
        for index in 0..<frames {
            samples[index] = sample(index, frames)
        }
        let audioFile = try AVAudioFile(forWriting: directory.appendingPathComponent(file), settings: format.settings)
        try audioFile.write(from: buffer)
    }

    // MARK: - Project assembly

    static func build(scenario: RenderScenario, library: AudioSampleLibrary) throws -> Built {
        var tracks: [StepSequenceTrack] = []
        var clips: [ClipPoolEntry] = []
        var sliceSets: [SliceSet] = []
        var patternBanks: [TrackPatternBank] = []

        let buses = scenario.buses.map { spec in
            MixerBus(
                name: spec.name,
                mix: BusMixSettings(level: spec.level, pan: 0, isMuted: false, isSoloed: false),
                inserts: spec.withFilterInsert ? [MixerBusInsert.filter()] : []
            )
        }

        for (index, spec) in scenario.tracks.enumerated() {
            let stepFlags = (0..<scenario.stepsPerBar).map { spec.steps.contains($0) }
            var track: StepSequenceTrack
            let clip: ClipPoolEntry

            switch spec.kind {
            case let .sample(voice):
                guard let sample = library.firstSample(in: voice.sampleCategory) else {
                    throw RenderHarnessError.missingFixture(voice.rawValue)
                }
                track = StepSequenceTrack(
                    name: spec.name,
                    pitches: [DrumKitNoteMap.baselineNote],
                    stepPattern: [true],
                    destination: .sample(sampleID: sample.id, settings: .default),
                    velocity: 100,
                    gateLength: 1
                )
                clip = ClipPoolEntry(
                    id: deterministicUUID(index: index),
                    name: "\(spec.name) Pattern",
                    trackType: track.trackType,
                    content: .noteGrid(
                        lengthSteps: scenario.stepsPerBar,
                        steps: stepFlags.map { isOn in
                            isOn
                                ? ClipStep(
                                    main: ClipLane(
                                        chance: 1,
                                        notes: [ClipStepNote(pitch: DrumKitNoteMap.baselineNote, velocity: 100, lengthSteps: 1)]
                                    ),
                                    fill: nil
                                )
                                : .empty
                        }
                    )
                )

            case .slicer:
                guard let source = library.sample(id: slicerSourceSampleID(libraryRoot: library.libraryRoot)) else {
                    throw RenderHarnessError.missingFixture("slicer source")
                }
                let sliceSet = SliceSet(
                    sampleID: source.id,
                    markers: [SliceMarker(startFrame: 0, endFrame: 2_400)]
                )
                sliceSets.append(sliceSet)
                track = StepSequenceTrack(
                    name: spec.name,
                    trackType: .slice,
                    pitches: [60],
                    stepPattern: [true],
                    destination: .slicer(sliceSetID: sliceSet.id, settings: .default),
                    velocity: 100,
                    gateLength: 1
                )
                clip = ClipPoolEntry(
                    id: deterministicUUID(index: index),
                    name: "\(spec.name) Slices",
                    trackType: .slice,
                    content: .sliceTriggers(
                        stepPattern: stepFlags,
                        sliceIndexes: stepFlags.map { _ in 0 },
                        stepModes: stepFlags.map { _ in .single }
                    )
                )
            }

            track.mix = TrackMixSettings(
                level: spec.level,
                pan: spec.pan,
                isMuted: false,
                sendA: spec.sendA,
                sendB: spec.sendB
            )
            if let busIndex = spec.busIndex, busIndex >= 0, busIndex < buses.count {
                track.outputBusID = buses[busIndex].id
            }

            tracks.append(track)
            clips.append(clip)
            patternBanks.append(
                TrackPatternBank(
                    trackID: track.id,
                    slots: [TrackPatternSlot(slotIndex: 0, sourceRef: .clip(clip.id))]
                )
            )
        }

        let layers = PhraseLayerDefinition.defaultSet(for: tracks)
        let phrases: [PhraseModel]
        if let lengths = scenario.phraseLengthsBars, !lengths.isEmpty {
            phrases = lengths.enumerated().map { index, lengthBars in
                PhraseModel(
                    id: deterministicUUID(index: 1_000 + index),
                    name: "Phrase \(index + 1)",
                    lengthBars: lengthBars,
                    stepsPerBar: scenario.stepsPerBar,
                    cells: layers.flatMap { layer in
                        tracks.map { track in
                            PhraseCellAssignment(trackID: track.id, layerID: layer.id, cell: .inheritDefault)
                        }
                    }
                )
            }
        } else {
            phrases = [PhraseModel.default(tracks: tracks, layers: layers, clipPool: clips)]
        }

        let project = Project(
            version: 1,
            tracks: tracks,
            clipPool: clips,
            layers: layers,
            buses: buses,
            sendBusA: SendBusState(id: .sendA, inserts: scenario.sendBusAOccupied ? [SendBusInsert.filter()] : []),
            sendBusB: SendBusState(id: .sendB, inserts: scenario.sendBusBOccupied ? [SendBusInsert.filter()] : []),
            patternBanks: patternBanks,
            sliceSetPool: sliceSets,
            selectedTrackID: tracks[0].id,
            phrases: phrases,
            selectedPhraseID: phrases[0].id
        )

        // Project normalization can reassign duplicate IDs; read back the
        // authoritative IDs from the normalized model.
        return Built(
            project: project,
            trackIDs: project.tracks.map(\.id),
            busIDs: project.buses.map(\.id)
        )
    }

    private static func deterministicUUID(index: Int) -> UUID {
        let suffix = String(format: "%012d", index)
        return UUID(uuidString: "0c0ffee0-1111-4222-8333-\(suffix)") ?? UUID()
    }
}

enum RenderHarnessError: Error, CustomStringConvertible {
    case missingFixture(String)
    case manualRenderingUnavailable(String)
    case renderFailed(String)

    var description: String {
        switch self {
        case let .missingFixture(name):
            return "Render harness fixture missing: \(name)"
        case let .manualRenderingUnavailable(reason):
            return "Manual rendering unavailable: \(reason)"
        case let .renderFailed(reason):
            return "Offline render failed: \(reason)"
        }
    }
}

private extension RenderScenario.Voice {
    var sampleCategory: AudioSampleCategory {
        switch self {
        case .kick: return .kick
        case .snare: return .snare
        case .hat: return .hatClosed
        case .perc: return .percussion
        }
    }
}
