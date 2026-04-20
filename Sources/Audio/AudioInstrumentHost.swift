import AVFoundation
import AudioToolbox
import Foundation

protocol TrackPlaybackSink: AnyObject {
    var displayName: String { get }
    var isAvailable: Bool { get }
    var availableInstruments: [AudioInstrumentChoice] { get }
    var selectedInstrument: AudioInstrumentChoice { get }
    var currentAudioUnit: AVAudioUnit? { get }
    func prepareIfNeeded()
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
    private let snapshotLock = NSLock()
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
    private var snapshotChoice: AudioInstrumentChoice
    private var snapshotAudioUnit: AVAudioUnit?
    private var snapshotAvailable = false

    private func log(_ message: String) {
        NSLog("[AudioInstrumentHost] \(message)")
    }

    private func performOnMain(_ work: @escaping @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated {
                work()
            }
            return
        }

        DispatchQueue.main.sync {
            MainActor.assumeIsolated {
                work()
            }
        }
    }

    private func performOnMainThrowing<T>(_ work: @escaping @MainActor () throws -> T) throws -> T {
        if Thread.isMainThread {
            return try MainActor.assumeIsolated {
                try work()
            }
        }

        var output: T?
        var thrownError: Error?
        DispatchQueue.main.sync {
            do {
                output = try MainActor.assumeIsolated {
                    try work()
                }
            } catch {
                thrownError = error
            }
        }

        if let thrownError {
            throw thrownError
        }
        return output!
    }

    init(
        instrumentChoices: [AudioInstrumentChoice] = AudioInstrumentChoice.defaultChoices,
        initialInstrument: AudioInstrumentChoice = .builtInSynth,
        autoStartEngine: Bool = true,
        instantiateAudioUnit: @escaping AUAudioUnitFactory.AudioUnitLoader = { description, completion in
            AVAudioUnit.instantiate(with: description, options: [], completionHandler: completion)
        }
    ) {
        let resolvedChoices = instrumentChoices.isEmpty ? [.builtInSynth] : instrumentChoices
        self.instrumentChoices = resolvedChoices
        self.currentChoice = resolvedChoices.first(where: { $0 == initialInstrument }) ?? initialInstrument
        self.currentDestination = .auInstrument(componentID: self.currentChoice.audioComponentID, stateBlob: nil)
        self.autoStartEngine = autoStartEngine
        self.factory = AUAudioUnitFactory(instantiateAudioUnit: instantiateAudioUnit)
        self.snapshotChoice = self.currentChoice
    }

    var displayName: String {
        withSnapshot { snapshotChoice.displayName }
    }

    var isAvailable: Bool {
        withSnapshot { snapshotAvailable }
    }

    var availableInstruments: [AudioInstrumentChoice] {
        instrumentChoices
    }

    var selectedInstrument: AudioInstrumentChoice {
        withSnapshot { snapshotChoice }
    }

    var currentAudioUnit: AVAudioUnit? {
        withSnapshot { snapshotAudioUnit }
    }

    func prepareIfNeeded() {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            self.log("prepareIfNeeded destination=\(self.currentDestination.summary) choice=\(self.currentChoice.displayName)")
            self.ensureInstrumentLoadedIfNeeded()
        }
    }

    func startIfNeeded() {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            self.shouldBeRunning = true
            self.log("startIfNeeded destination=\(self.currentDestination.summary)")
            self.ensureInstrumentLoadedIfNeeded()
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else {
                return
            }

            self.shouldBeRunning = false
            self.log("stop")
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
            self.log("setDestination \(destination.summary)")
            switch destination {
            case let .auInstrument(componentID, _):
                self.currentChoice = self.instrumentChoices.first(where: { $0.audioComponentID == componentID })
                    ?? AudioInstrumentChoice(audioComponentID: componentID)
                self.updateSnapshotChoice(self.currentChoice)
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
                self.performOnMain {
                    instrument.startNote(event.pitch, withVelocity: event.velocity, onChannel: 0)
                }
                let noteLength = tickDuration * Double(event.length)
                self.queue.asyncAfter(deadline: .now() + noteLength) { [weak instrument] in
                    guard let instrument else {
                        return
                    }
                    self.performOnMain {
                        instrument.stopNote(event.pitch, onChannel: 0)
                    }
                }
            }
        }
    }

    private func stopAllNotes() {
        guard let instrument else {
            return
        }

        performOnMain {
            for pitch in UInt8(0)...UInt8(127) {
                instrument.stopNote(pitch, onChannel: 0)
            }
        }
    }

    private func instantiate(choice: AudioInstrumentChoice, stateBlob: Data?, generation: UInt64) {
        pendingLoadGeneration = generation
        log("instantiate choice=\(choice.displayName) generation=\(generation) hasState=\(stateBlob != nil)")
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
                    if case let .failure(error) = result {
                        self.log("instantiate failed choice=\(choice.displayName) generation=\(generation) error=\(String(describing: error))")
                    } else {
                        self.log("instantiate returned non-MIDI instrument choice=\(choice.displayName) generation=\(generation)")
                    }
                    self.handleLoadFailure(for: choice, generation: generation)
                    return
                }

                if let attachedEngine = instrument.engine, attachedEngine !== self.engine {
                    self.log("instantiate returned instrument already attached to another engine choice=\(choice.displayName)")
                    self.handleLoadFailure(for: choice, generation: generation)
                    return
                }

                self.log("instantiate success choice=\(choice.displayName) generation=\(generation)")
                self.connectLoadedInstrument(instrument)
            }
        }
    }

    private func connectLoadedInstrument(_ nextInstrument: AVAudioUnitMIDIInstrument) {
        log("connectLoadedInstrument")
        disconnectCurrentInstrument()
        performOnMain {
            self.instrument = nextInstrument
            self.updateSnapshotInstrument(nextInstrument)
            if nextInstrument.engine == nil {
                self.engine.attach(nextInstrument)
            }
            if self.engine.outputConnectionPoints(for: nextInstrument, outputBus: 0).isEmpty {
                self.engine.connect(nextInstrument, to: self.engine.mainMixerNode, format: nil)
            }
            self.engine.prepare()
        }
        applyCurrentMix()
        startEngineIfPossible()
    }

    private func ensureInstrumentLoadedIfNeeded() {
        guard case let .auInstrument(_, stateBlob) = currentDestination else {
            log("ensureInstrumentLoadedIfNeeded no AU destination")
            disconnectCurrentInstrument()
            return
        }
        guard instrument == nil else {
            log("ensureInstrumentLoadedIfNeeded already loaded")
            startEngineIfPossible()
            return
        }
        guard pendingLoadGeneration != instantiationGeneration else {
            log("ensureInstrumentLoadedIfNeeded load already pending generation=\(instantiationGeneration)")
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
        log("handleLoadFailure choice=\(choice.displayName) generation=\(generation)")
        guard choice != .builtInSynth,
              let fallbackChoice = instrumentChoices.first(where: { $0 == .builtInSynth })
        else {
            return
        }

        currentChoice = fallbackChoice
        updateSnapshotChoice(fallbackChoice)
        currentDestination = .auInstrument(componentID: fallbackChoice.audioComponentID, stateBlob: nil)
        instantiationGeneration &+= 1
        instantiate(choice: fallbackChoice, stateBlob: nil, generation: instantiationGeneration)
    }

    private func disconnectCurrentInstrument() {
        stopAllNotes()
        guard let instrument else {
            return
        }

        performOnMain {
            if self.engine.isRunning {
                self.log("disconnectCurrentInstrument stop engine")
                self.engine.stop()
            }

            self.log("disconnectCurrentInstrument detach instrument")
            self.engine.disconnectNodeOutput(instrument)
            self.engine.detach(instrument)
            self.instrument = nil
            self.updateSnapshotInstrument(nil)
        }
    }

    private func startEngineIfPossible() {
        guard autoStartEngine, shouldBeRunning, instrument != nil, !engine.isRunning else {
            return
        }

        do {
            try performOnMainThrowing {
                try self.engine.start()
            }
            log("engine started")
        } catch {
            log("engine start failed error=\(String(describing: error))")
        }
    }

    private func applyCurrentMix() {
        guard let instrument else {
            return
        }

        performOnMain { [currentMix] in
            instrument.pan = Float(currentMix.clampedPan)
            instrument.volume = currentMix.isMuted ? 0 : Float(currentMix.clampedLevel)
        }
    }

    private func withSnapshot<T>(_ body: () -> T) -> T {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        return body()
    }

    private func updateSnapshotChoice(_ choice: AudioInstrumentChoice) {
        snapshotLock.lock()
        snapshotChoice = choice
        snapshotLock.unlock()
    }

    private func updateSnapshotInstrument(_ instrument: AVAudioUnit?) {
        snapshotLock.lock()
        snapshotAudioUnit = instrument
        snapshotAvailable = instrument != nil
        snapshotLock.unlock()
    }
}
