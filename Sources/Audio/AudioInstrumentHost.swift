import AVFoundation
import AudioToolbox
import Foundation

protocol TrackPlaybackSink: AnyObject {
    var displayName: String { get }
    var isAvailable: Bool { get }
    var availableInstruments: [AudioInstrumentChoice] { get }
    var selectedInstrument: AudioInstrumentChoice { get }
    var currentAudioUnit: AVAudioUnit? { get }
    func startIfNeeded()
    func stop()
    func setMix(_ mix: TrackMixSettings)
    func setDestination(_ destination: Destination)
    func selectInstrument(_ choice: AudioInstrumentChoice)
    func captureStateBlob() throws -> Data?
    func play(noteEvents: [NoteEvent], bpm: Double, stepsPerBar: Int)
}

final class AudioInstrumentHost: TrackPlaybackSink {
    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "ai.sequencer.SequencerAI.AudioInstrumentHost")
    private let instrumentChoices: [AudioInstrumentChoice]
    private let factory: AUAudioUnitFactory
    private let autoStartEngine: Bool

    private var instrument: AVAudioUnitMIDIInstrument?
    private var shouldBeRunning = false
    private var currentMix = TrackMixSettings.default
    private var currentChoice: AudioInstrumentChoice
    private var currentDestination: Destination
    private var instantiationGeneration: UInt64 = 0
    private var pendingLoadGeneration: UInt64?

    init(
        instrumentChoices: [AudioInstrumentChoice] = AudioInstrumentChoice.defaultChoices,
        initialInstrument: AudioInstrumentChoice = .builtInSynth,
        autoStartEngine: Bool = true,
        instantiateAudioUnit: @escaping AUAudioUnitFactory.AudioUnitLoader = { description, completion in
            AVAudioUnit.instantiate(with: description, options: [.loadOutOfProcess], completionHandler: completion)
        }
    ) {
        let resolvedChoices = instrumentChoices.isEmpty ? [.builtInSynth] : instrumentChoices
        self.instrumentChoices = resolvedChoices
        self.currentChoice = resolvedChoices.first(where: { $0 == initialInstrument }) ?? initialInstrument
        self.currentDestination = .auInstrument(componentID: self.currentChoice.audioComponentID, stateBlob: nil)
        self.autoStartEngine = autoStartEngine
        self.factory = AUAudioUnitFactory(instantiateAudioUnit: instantiateAudioUnit)
    }

    var displayName: String {
        queue.sync { currentChoice.displayName }
    }

    var isAvailable: Bool {
        queue.sync { instrument != nil }
    }

    var availableInstruments: [AudioInstrumentChoice] {
        instrumentChoices
    }

    var selectedInstrument: AudioInstrumentChoice {
        queue.sync { currentChoice }
    }

    var currentAudioUnit: AVAudioUnit? {
        queue.sync { instrument }
    }

    func startIfNeeded() {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            self.shouldBeRunning = true
            self.ensureInstrumentLoadedIfNeeded()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else {
                return
            }

            self.shouldBeRunning = false
            self.stopAllNotes()
            self.engine.stop()
        }
    }

    func setMix(_ mix: TrackMixSettings) {
        queue.async { [weak self] in
            guard let self else {
                return
            }

            self.currentMix = mix
            self.applyCurrentMix()
        }
    }

    func setDestination(_ destination: Destination) {
        queue.async { [weak self] in
            guard let self else {
                return
            }

            guard destination != self.currentDestination else {
                return
            }

            self.currentDestination = destination
            switch destination {
            case let .auInstrument(componentID, _):
                self.currentChoice = self.instrumentChoices.first(where: { $0.audioComponentID == componentID })
                    ?? AudioInstrumentChoice(audioComponentID: componentID)
                self.instantiationGeneration &+= 1
                self.pendingLoadGeneration = nil
                self.disconnectCurrentInstrument()
                if self.shouldBeRunning {
                    self.ensureInstrumentLoadedIfNeeded()
                }
            case .midi, .internalSampler, .inheritGroup, .none:
                self.pendingLoadGeneration = nil
                self.disconnectCurrentInstrument()
            }
        }
    }

    func selectInstrument(_ choice: AudioInstrumentChoice) {
        setDestination(.auInstrument(componentID: choice.audioComponentID, stateBlob: nil))
    }

    func captureStateBlob() throws -> Data? {
        try queue.sync {
            guard let instrument else {
                return nil
            }
            return try factory.captureState(instrument)
        }
    }

    func play(noteEvents: [NoteEvent], bpm: Double, stepsPerBar: Int) {
        guard !noteEvents.isEmpty else {
            return
        }

        queue.async { [weak self] in
            guard let self else {
                return
            }

            guard let instrument = self.instrument else {
                self.ensureInstrumentLoadedIfNeeded()
                return
            }

            self.startEngineIfPossible()

            let tickDuration = 60.0 / max(bpm, 1) / Double(max(stepsPerBar, 1)) * 4.0
            for event in noteEvents where event.gate {
                Task { @MainActor [weak instrument] in
                    instrument?.startNote(event.pitch, withVelocity: event.velocity, onChannel: 0)
                }
                let noteLength = tickDuration * Double(event.length)
                self.queue.asyncAfter(deadline: .now() + noteLength) { [weak instrument] in
                    Task { @MainActor in
                        instrument?.stopNote(event.pitch, onChannel: 0)
                    }
                }
            }
        }
    }

    private func stopAllNotes() {
        guard let instrument else {
            return
        }

        Task { @MainActor [weak instrument] in
            guard let instrument else {
                return
            }
            for pitch in UInt8(0)...UInt8(127) {
                instrument.stopNote(pitch, onChannel: 0)
            }
        }
    }

    private func instantiate(choice: AudioInstrumentChoice, stateBlob: Data?, generation: UInt64) {
        pendingLoadGeneration = generation
        factory.instantiate(choice.audioComponentID, stateBlob: stateBlob) { [weak self] result in
            guard let self else {
                return
            }

            self.queue.async {
                guard generation == self.instantiationGeneration else {
                    return
                }
                guard self.pendingLoadGeneration == generation else {
                    return
                }
                self.pendingLoadGeneration = nil
                guard case let .success(audioUnit) = result,
                      let instrument = audioUnit as? AVAudioUnitMIDIInstrument
                else {
                    self.handleLoadFailure(for: choice, generation: generation)
                    return
                }

                if let attachedEngine = instrument.engine, attachedEngine !== self.engine {
                    self.handleLoadFailure(for: choice, generation: generation)
                    return
                }

                self.connectLoadedInstrument(instrument)
            }
        }
    }

    private func connectLoadedInstrument(_ nextInstrument: AVAudioUnitMIDIInstrument) {
        disconnectCurrentInstrument()
        instrument = nextInstrument
        if nextInstrument.engine == nil {
            engine.attach(nextInstrument)
        }
        if engine.outputConnectionPoints(for: nextInstrument, outputBus: 0).isEmpty {
            engine.connect(nextInstrument, to: engine.mainMixerNode, format: nil)
        }
        engine.prepare()
        applyCurrentMix()
        startEngineIfPossible()
    }

    private func ensureInstrumentLoadedIfNeeded() {
        guard case let .auInstrument(_, stateBlob) = currentDestination else {
            disconnectCurrentInstrument()
            return
        }
        guard instrument == nil else {
            startEngineIfPossible()
            return
        }
        guard pendingLoadGeneration != instantiationGeneration else {
            return
        }

        instantiate(choice: currentChoice, stateBlob: stateBlob, generation: instantiationGeneration)
    }

    private func handleLoadFailure(for choice: AudioInstrumentChoice, generation: UInt64) {
        guard generation == instantiationGeneration else {
            return
        }

        pendingLoadGeneration = nil
        disconnectCurrentInstrument()
        guard choice != .builtInSynth,
              let fallbackChoice = instrumentChoices.first(where: { $0 == .builtInSynth })
        else {
            return
        }

        currentChoice = fallbackChoice
        currentDestination = .auInstrument(componentID: fallbackChoice.audioComponentID, stateBlob: nil)
        instantiationGeneration &+= 1
        instantiate(choice: fallbackChoice, stateBlob: nil, generation: instantiationGeneration)
    }

    private func disconnectCurrentInstrument() {
        stopAllNotes()
        if engine.isRunning {
            engine.stop()
        }

        guard let instrument else {
            return
        }

        engine.disconnectNodeOutput(instrument)
        engine.detach(instrument)
        self.instrument = nil
    }

    private func startEngineIfPossible() {
        guard autoStartEngine, shouldBeRunning, instrument != nil, !engine.isRunning else {
            return
        }

        do {
            try engine.start()
        } catch {
            // A surfaced diagnostics path can own this later; for now we fail soft.
        }
    }

    private func applyCurrentMix() {
        guard let instrument else {
            return
        }

        Task { @MainActor [currentMix] in
            instrument.pan = Float(currentMix.clampedPan)
            instrument.volume = currentMix.isMuted ? 0 : Float(currentMix.clampedLevel)
        }
    }
}
