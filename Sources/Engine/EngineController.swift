import Foundation
import Observation

@Observable
final class EngineController {
    private struct PipelineEntry: Equatable {
        let trackID: UUID
        let output: TrackOutputDestination
    }

    private struct AudioTrackRuntime {
        let trackID: UUID
        let generatorBlockID: BlockID
        let mix: TrackMixSettings
        let instrument: AudioInstrumentChoice
    }

    private let midiClient: MIDIClient?
    private let endpoint: MIDIEndpoint?
    private let sharedAudioOutput: TrackPlaybackSink?
    private let audioOutputFactory: (() -> TrackPlaybackSink)?
    private let stepsPerBar: Int
    private let stateLock = NSLock()

    let registry: BlockRegistry
    let commandQueue: CommandQueue
    let clock: TickClock

    private(set) var isRunning = false
    private(set) var currentBPM: Double
    private(set) var transportPosition = "1:1:1"
    private(set) var executor: Executor?
    private(set) var selectedOutput: TrackOutputDestination

    private var currentTrackMix = TrackMixSettings.default
    private var currentDocumentModel: SeqAIDocumentModel = .empty
    private var generatorIDsByTrackID: [UUID: BlockID] = [:]
    private var midiOutBlocksByTrackID: [UUID: MidiOut] = [:]
    private var audioTrackRuntimes: [UUID: AudioTrackRuntime] = [:]
    private var audioOutputsByTrackID: [UUID: TrackPlaybackSink] = [:]
    private var pipelineShape: [PipelineEntry] = []

    init(
        client: MIDIClient? = MIDISession.shared.client,
        endpoint: MIDIEndpoint? = MIDISession.shared.appOutput,
        audioOutput: TrackPlaybackSink? = nil,
        audioOutputFactory: (() -> TrackPlaybackSink)? = nil,
        stepsPerBar: Int = 16
    ) {
        self.midiClient = client
        self.endpoint = endpoint
        self.sharedAudioOutput = audioOutput
        self.audioOutputFactory = audioOutputFactory
        self.stepsPerBar = max(1, stepsPerBar)
        self.registry = BlockRegistry()
        self.commandQueue = CommandQueue(capacity: 256)
        self.clock = TickClock(stepsPerBar: stepsPerBar)
        self.currentBPM = 120
        self.selectedOutput = .midiOut

        do {
            try registerCoreBlocks(registry)
            try buildPipeline(for: .empty)
        } catch {
            NSLog("EngineController setup failed: \(error)")
        }
    }

    func start() {
        guard !isRunning, executor != nil else {
            return
        }

        let hosts = withStateLock { Array(audioOutputsByTrackID.values) }
        hosts.forEach { $0.startIfNeeded() }

        isRunning = true
        clock.start { [weak self] tickIndex, now in
            self?.processTick(tickIndex: tickIndex, now: now)
        }
    }

    func stop() {
        guard isRunning else {
            return
        }

        clock.stop()
        let hosts = withStateLock { Array(audioOutputsByTrackID.values) }
        hosts.forEach { $0.stop() }
        isRunning = false
    }

    func setBPM(_ bpm: Double) {
        let clamped = min(max(bpm, 40), 300)
        currentBPM = clamped
        clock.bpm = clamped
        _ = commandQueue.enqueue(.setBPM(clamped))
    }

    func setParam(blockID: BlockID, paramKey: String, value: ParamValue) {
        _ = commandQueue.enqueue(.setParam(blockID: blockID, paramKey: paramKey, value: value))
    }

    func apply(documentModel: SeqAIDocumentModel) {
        currentDocumentModel = documentModel
        let selectedTrack = documentModel.selectedTrack
        selectedOutput = selectedTrack.output
        currentTrackMix = selectedTrack.mix

        do {
            if withStateLock({ pipelineShape != Self.pipelineShape(for: documentModel) || executor == nil }) {
                try buildPipeline(for: documentModel)
            } else {
                syncTrackParams(for: documentModel)
                syncMidiOutputs(for: documentModel)
                syncAudioOutputs(for: documentModel)
            }
        } catch {
            NSLog("EngineController apply failed: \(error)")
        }
    }

    func apply(track: StepSequenceTrack) {
        let phrase = PhraseModel.default(tracks: [track])
        apply(
            documentModel: SeqAIDocumentModel(
                version: 1,
                tracks: [track],
                selectedTrackID: track.id,
                phrases: [phrase],
                selectedPhraseID: phrase.id
            )
        )
    }

    var registeredKindIDs: [String] {
        registry.kinds().map(\.id)
    }

    var canStart: Bool {
        executor != nil
    }

    var availableAudioInstruments: [AudioInstrumentChoice] {
        sharedAudioOutput?.availableInstruments ?? AudioInstrumentChoice.defaultChoices
    }

    var statusSummary: String {
        guard canStart else {
            return "Engine unavailable"
        }

        let selectedTrack = currentDocumentModel.selectedTrack
        switch selectedTrack.output {
        case .midiOut:
            if selectedTrack.mix.isMuted {
                return "MIDI output muted"
            }
            guard let endpoint else {
                return "Playing without MIDI output"
            }
            return "Output: \(endpoint.displayName)"
        case .auInstrument:
            let host = withStateLock { audioOutputsByTrackID[selectedTrack.id] }
            guard let host else {
                return "Audio instrument unavailable"
            }
            return host.isAvailable
                ? "Audio: \(host.displayName) via Main Mixer\(selectedTrack.mix.isMuted ? " (Muted)" : "")"
                : "Audio instrument unavailable"
        }
    }

    func processTick(tickIndex: UInt64, now: TimeInterval) {
        let (executor, audioRuntimes, audioOutputs) = withStateLock {
            (self.executor, self.audioTrackRuntimes, self.audioOutputsByTrackID)
        }

        guard let executor else {
            return
        }

        let outputs = executor.tick(now: now)
        currentBPM = executor.currentBPM
        transportPosition = Self.transportString(for: tickIndex, stepsPerBar: stepsPerBar)

        for runtime in audioRuntimes.values where !runtime.mix.isMuted {
            guard case let .notes(events)? = outputs[runtime.generatorBlockID]?["notes"],
                  let host = audioOutputs[runtime.trackID]
            else {
                continue
            }

            host.play(noteEvents: events, bpm: executor.currentBPM, stepsPerBar: stepsPerBar)
        }
    }

    private func buildPipeline(for documentModel: SeqAIDocumentModel) throws {
        var blocks: [BlockID: Block] = [:]
        var wiring: [BlockID: [PortID: (BlockID, PortID)]] = [:]
        var generatorIDs: [UUID: BlockID] = [:]
        var midiOutBlocks: [UUID: MidiOut] = [:]
        var audioRuntimes: [UUID: AudioTrackRuntime] = [:]

        for track in documentModel.tracks {
            let generatorBlockID = Self.generatorBlockID(for: track.id)
            let generator = NoteGenerator(id: generatorBlockID, params: Self.generatorParams(for: track))
            blocks[generatorBlockID] = generator
            generatorIDs[track.id] = generatorBlockID

            switch track.output {
            case .midiOut:
                let midiOutBlockID = Self.midiOutBlockID(for: track.id)
                let midiOut = MidiOut(
                    id: midiOutBlockID,
                    params: ["channel": .number(0)],
                    client: midiClient,
                    endpoint: track.mix.isMuted ? nil : endpoint
                )
                blocks[midiOutBlockID] = midiOut
                wiring[midiOutBlockID] = ["notes": (generatorBlockID, "notes")]
                midiOutBlocks[track.id] = midiOut

            case .auInstrument:
                audioRuntimes[track.id] = AudioTrackRuntime(
                    trackID: track.id,
                    generatorBlockID: generatorBlockID,
                    mix: track.mix,
                    instrument: track.audioInstrument
                )
            }
        }

        let nextExecutor = try Executor(
            blocks: blocks,
            wiring: wiring,
            commandQueue: commandQueue
        )

        withStateLock {
            executor = nextExecutor
            generatorIDsByTrackID = generatorIDs
            midiOutBlocksByTrackID = midiOutBlocks
            audioTrackRuntimes = audioRuntimes
            pipelineShape = Self.pipelineShape(for: documentModel)
        }

        syncAudioOutputs(for: documentModel)
        currentDocumentModel = documentModel
        selectedOutput = documentModel.selectedTrack.output
        currentTrackMix = documentModel.selectedTrack.mix
    }

    private func syncTrackParams(for documentModel: SeqAIDocumentModel) {
        let generatorIDs = withStateLock { generatorIDsByTrackID }
        for track in documentModel.tracks {
            guard let generatorBlockID = generatorIDs[track.id] else {
                continue
            }

            for (paramKey, value) in Self.generatorParams(for: track) {
                setParam(blockID: generatorBlockID, paramKey: paramKey, value: value)
            }
        }
    }

    private func syncMidiOutputs(for documentModel: SeqAIDocumentModel) {
        let midiOutBlocks = withStateLock { midiOutBlocksByTrackID }
        for track in documentModel.tracks {
            midiOutBlocks[track.id]?.endpoint = track.output == .midiOut && !track.mix.isMuted ? endpoint : nil
        }
    }

    private func syncAudioOutputs(for documentModel: SeqAIDocumentModel) {
        let desiredAudioTracks = documentModel.tracks.filter { $0.output == .auInstrument }
        let desiredTrackIDs = Set(desiredAudioTracks.map(\.id))

        let removedHosts = withStateLock { () -> [TrackPlaybackSink] in
            let removedIDs = Set(audioOutputsByTrackID.keys).subtracting(desiredTrackIDs)
            let hosts = removedIDs.compactMap { audioOutputsByTrackID.removeValue(forKey: $0) }
            return hosts
        }
        removedHosts.forEach { $0.stop() }

        for track in desiredAudioTracks {
            let host = withStateLock { () -> TrackPlaybackSink? in
                if let existing = audioOutputsByTrackID[track.id] {
                    return existing
                }

                let created = audioOutputFactory?() ?? sharedAudioOutput
                if let created {
                    audioOutputsByTrackID[track.id] = created
                }
                return created
            }

            host?.selectInstrument(track.audioInstrument)
            host?.setMix(track.mix)
            if isRunning {
                host?.startIfNeeded()
            }
        }

        withStateLock {
            audioTrackRuntimes = Dictionary(
                uniqueKeysWithValues: desiredAudioTracks.map {
                    (
                        $0.id,
                        AudioTrackRuntime(
                            trackID: $0.id,
                            generatorBlockID: generatorIDsByTrackID[$0.id] ?? Self.generatorBlockID(for: $0.id),
                            mix: $0.mix,
                            instrument: $0.audioInstrument
                        )
                    )
                }
            )
        }
    }

    private static func generatorParams(for track: StepSequenceTrack) -> [String: ParamValue] {
        [
            "pitches": .integers(track.pitches),
            "stepPattern": .integers(track.stepPattern.map { $0 ? 1 : 0 }),
            "accentPattern": .integers(track.stepAccents.map { $0 ? 1 : 0 }),
            "velocity": .number(Double(track.velocity)),
            "gateLength": .number(Double(track.gateLength))
        ]
    }

    private static func generatorBlockID(for trackID: UUID) -> BlockID {
        "gen-\(trackID.uuidString.lowercased())"
    }

    private static func midiOutBlockID(for trackID: UUID) -> BlockID {
        "out-\(trackID.uuidString.lowercased())"
    }

    private static func pipelineShape(for documentModel: SeqAIDocumentModel) -> [PipelineEntry] {
        documentModel.tracks.map { PipelineEntry(trackID: $0.id, output: $0.output) }
    }

    private static func transportString(for tickIndex: UInt64, stepsPerBar: Int) -> String {
        let zeroBasedTick = Int(tickIndex)
        let bar = zeroBasedTick / stepsPerBar + 1
        let stepsPerBeat = max(1, stepsPerBar / 4)
        let beat = (zeroBasedTick % stepsPerBar) / stepsPerBeat + 1
        let step = zeroBasedTick % stepsPerBeat + 1
        return "\(bar):\(beat):\(step)"
    }

    private func withStateLock<T>(_ body: () -> T) -> T {
        stateLock.lock()
        defer { stateLock.unlock() }
        return body()
    }
}
