import Foundation
import Observation

@Observable
final class EngineController {
    private let midiClient: MIDIClient?
    private let endpoint: MIDIEndpoint?
    private let stepsPerBar: Int

    let registry: BlockRegistry
    let commandQueue: CommandQueue
    let clock: TickClock

    private(set) var isRunning = false
    private(set) var currentBPM: Double
    private(set) var transportPosition = "1:1:1"
    private(set) var executor: Executor?

    init(
        client: MIDIClient? = MIDISession.shared.client,
        endpoint: MIDIEndpoint? = MIDISession.shared.appOutput,
        stepsPerBar: Int = 16
    ) {
        self.midiClient = client
        self.endpoint = endpoint
        self.stepsPerBar = max(1, stepsPerBar)
        self.registry = BlockRegistry()
        self.commandQueue = CommandQueue(capacity: 256)
        self.clock = TickClock(stepsPerBar: stepsPerBar)
        self.currentBPM = 120

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

        isRunning = true
        clock.start { [weak self] tickIndex, now in
            self?.handleTick(tickIndex: tickIndex, now: now)
        }
    }

    func stop() {
        guard isRunning else {
            return
        }

        clock.stop()
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

    var statusSummary: String {
        guard canStart else {
            return "Engine unavailable"
        }
        guard let endpoint else {
            return "Playing without MIDI output"
        }
        return "Output: \(endpoint.displayName)"
    }

    private func buildDefaultPipeline() throws {
        guard let generator = registry.make(kindID: "note-generator", blockID: "gen") as? NoteGenerator,
              let midiOut = registry.make(kindID: "midi-out", blockID: "out") as? MidiOut
        else {
            return
        }

        midiOut.client = midiClient
        midiOut.endpoint = endpoint

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

    private func handleTick(tickIndex: UInt64, now: TimeInterval) {
        guard let executor else {
            return
        }

        _ = executor.tick(now: now)
        currentBPM = executor.currentBPM
        transportPosition = Self.transportString(for: tickIndex, stepsPerBar: stepsPerBar)
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
