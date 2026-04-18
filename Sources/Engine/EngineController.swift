import Foundation
import Observation

@Observable
final class EngineController {
    private let midiClient: MIDIClient?
    private let endpoint: MIDIEndpoint?
    private let audioOutput: TrackPlaybackSink?
    private let stepsPerBar: Int

    let registry: BlockRegistry
    let commandQueue: CommandQueue
    let clock: TickClock

    private(set) var isRunning = false
    private(set) var currentBPM: Double
    private(set) var transportPosition = "1:1:1"
    private(set) var executor: Executor?
    private(set) var selectedOutput: TrackOutputDestination

    private var midiOutBlock: MidiOut?

    init(
        client: MIDIClient? = MIDISession.shared.client,
        endpoint: MIDIEndpoint? = MIDISession.shared.appOutput,
        audioOutput: TrackPlaybackSink? = nil,
        stepsPerBar: Int = 16
    ) {
        self.midiClient = client
        self.endpoint = endpoint
        self.audioOutput = audioOutput
        self.stepsPerBar = max(1, stepsPerBar)
        self.registry = BlockRegistry()
        self.commandQueue = CommandQueue(capacity: 256)
        self.clock = TickClock(stepsPerBar: stepsPerBar)
        self.currentBPM = 120
        self.selectedOutput = .midiOut

        do {
            try registerCoreBlocks(registry)
            try buildDefaultPipeline()
        } catch {
            NSLog("EngineController setup failed: \(error)")
        }
    }

    func start() {
        guard !isRunning, executor != nil else {
            return
        }

        if selectedOutput == .auInstrument {
            audioOutput?.startIfNeeded()
        }

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
        audioOutput?.stop()
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
        apply(track: documentModel.selectedTrack)
    }

    func apply(track: StepSequenceTrack) {
        selectedOutput = track.output
        currentTrackMix = track.mix
        midiOutBlock?.endpoint = track.output == .midiOut && !track.mix.isMuted ? endpoint : nil
        audioOutput?.selectInstrument(track.audioInstrument)
        audioOutput?.setMix(track.mix)
        if track.output == .auInstrument {
            audioOutput?.startIfNeeded()
        } else {
            audioOutput?.stop()
        }

        setParam(
            blockID: "gen",
            paramKey: "pitches",
            value: .integers(track.pitches)
        )
        setParam(
            blockID: "gen",
            paramKey: "stepPattern",
            value: .integers(track.stepPattern.map { $0 ? 1 : 0 })
        )
        setParam(
            blockID: "gen",
            paramKey: "accentPattern",
            value: .integers(track.stepAccents.map { $0 ? 1 : 0 })
        )
        setParam(
            blockID: "gen",
            paramKey: "velocity",
            value: .number(Double(track.velocity))
        )
        setParam(
            blockID: "gen",
            paramKey: "gateLength",
            value: .number(Double(track.gateLength))
        )
    }

    var registeredKindIDs: [String] {
        registry.kinds().map(\.id)
    }

    var canStart: Bool {
        executor != nil
    }

    var availableAudioInstruments: [AudioInstrumentChoice] {
        audioOutput?.availableInstruments ?? [.builtInSynth]
    }

    var statusSummary: String {
        guard canStart else {
            return "Engine unavailable"
        }

        switch selectedOutput {
        case .midiOut:
            if documentSelectedTrackIsMuted {
                return "MIDI output muted"
            }
            guard let endpoint else {
                return "Playing without MIDI output"
            }
            return "Output: \(endpoint.displayName)"
        case .auInstrument:
            guard let audioOutput else {
                return "Audio instrument unavailable"
            }
            return audioOutput.isAvailable
                ? "Audio: \(audioOutput.displayName) via Main Mixer\(documentSelectedTrackIsMuted ? " (Muted)" : "")"
                : "Audio instrument unavailable"
        }
    }

    private var documentSelectedTrackIsMuted: Bool {
        currentTrackMix.isMuted
    }

    private var currentTrackMix = TrackMixSettings.default

    private func buildDefaultPipeline() throws {
        guard let generator = registry.make(kindID: "note-generator", blockID: "gen") as? NoteGenerator,
              let midiOut = registry.make(kindID: "midi-out", blockID: "out") as? MidiOut
        else {
            return
        }

        midiOut.client = midiClient
        midiOut.endpoint = endpoint
        self.midiOutBlock = midiOut

        executor = try Executor(
            blocks: [
                "gen": generator,
                "out": midiOut
            ],
            wiring: [
                "out": ["notes": ("gen", "notes")]
            ],
            commandQueue: commandQueue
        )

        apply(track: .default)
    }

    func processTick(tickIndex: UInt64, now: TimeInterval) {
        guard let executor else {
            return
        }

        let outputs = executor.tick(now: now)
        currentBPM = executor.currentBPM
        transportPosition = Self.transportString(for: tickIndex, stepsPerBar: stepsPerBar)

        guard !currentTrackMix.isMuted else {
            return
        }

        guard selectedOutput == .auInstrument,
              case let .notes(events)? = outputs["gen"]?["notes"]
        else {
            return
        }

        audioOutput?.play(noteEvents: events, bpm: executor.currentBPM, stepsPerBar: stepsPerBar)
    }

    private static func transportString(for tickIndex: UInt64, stepsPerBar: Int) -> String {
        let zeroBasedTick = Int(tickIndex)
        let bar = zeroBasedTick / stepsPerBar + 1
        let stepsPerBeat = max(1, stepsPerBar / 4)
        let beat = (zeroBasedTick % stepsPerBar) / stepsPerBeat + 1
        let step = zeroBasedTick % stepsPerBeat + 1
        return "\(bar):\(beat):\(step)"
    }
}
