import AVFoundation
import AudioToolbox
import Foundation

protocol TrackPlaybackSink: AnyObject {
    var displayName: String { get }
    var isAvailable: Bool { get }
    var availableInstruments: [AudioInstrumentChoice] { get }
    var selectedInstrument: AudioInstrumentChoice { get }
    func startIfNeeded()
    func stop()
    func setMix(_ mix: TrackMixSettings)
    func selectInstrument(_ choice: AudioInstrumentChoice)
    func play(noteEvents: [NoteEvent], bpm: Double, stepsPerBar: Int)
}

final class AudioInstrumentHost: TrackPlaybackSink {
    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "ai.sequencer.SequencerAI.AudioInstrumentHost")
    private let instrumentChoices: [AudioInstrumentChoice]

    private var instrument: AVAudioUnitMIDIInstrument?
    private var shouldBeRunning = false
    private var currentMix = TrackMixSettings.default
    private var currentChoice: AudioInstrumentChoice

    init(
        instrumentChoices: [AudioInstrumentChoice] = AudioInstrumentChoice.defaultChoices,
        initialInstrument: AudioInstrumentChoice = .builtInSynth
    ) {
        let resolvedChoices = instrumentChoices.isEmpty ? [.builtInSynth] : instrumentChoices
        self.instrumentChoices = resolvedChoices
        self.currentChoice = resolvedChoices.first(where: { $0 == initialInstrument }) ?? initialInstrument
        instantiate(choice: currentChoice)
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

    func startIfNeeded() {
        queue.async { [weak self] in
            guard let self else {
                return
            }
            self.shouldBeRunning = true
            self.startEngineIfPossible()
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

    func selectInstrument(_ choice: AudioInstrumentChoice) {
        queue.async { [weak self] in
            guard let self else {
                return
            }

            let resolvedChoice = self.instrumentChoices.first(where: { $0 == choice }) ?? choice
            guard resolvedChoice != self.currentChoice else {
                return
            }

            self.stopAllNotes()
            if self.engine.isRunning {
                self.engine.stop()
            }
            if let instrument = self.instrument {
                self.engine.disconnectNodeInput(self.engine.mainMixerNode)
                self.engine.detach(instrument)
                self.instrument = nil
            }

            self.currentChoice = resolvedChoice
            self.instantiate(choice: resolvedChoice)
        }
    }

    func play(noteEvents: [NoteEvent], bpm: Double, stepsPerBar: Int) {
        guard !noteEvents.isEmpty else {
            return
        }

        queue.async { [weak self] in
            guard let self, let instrument = self.instrument else {
                return
            }

            self.startEngineIfPossible()

            let tickDuration = 60.0 / max(bpm, 1) / Double(max(stepsPerBar, 1)) * 4.0
            for event in noteEvents where event.gate {
                instrument.startNote(event.pitch, withVelocity: event.velocity, onChannel: 0)
                let noteLength = tickDuration * Double(event.length)
                self.queue.asyncAfter(deadline: .now() + noteLength) { [weak instrument] in
                    instrument?.stopNote(event.pitch, onChannel: 0)
                }
            }
        }
    }

    private func stopAllNotes() {
        guard let instrument else {
            return
        }

        for pitch in UInt8(0)...UInt8(127) {
            instrument.stopNote(pitch, onChannel: 0)
        }
    }

    private func instantiate(choice: AudioInstrumentChoice) {
        AVAudioUnit.instantiate(with: choice.componentDescription, options: []) { [weak self] audioUnit, _ in
            guard let self else {
                return
            }

            self.queue.async {
                guard let instrument = audioUnit as? AVAudioUnitMIDIInstrument else {
                    return
                }

                self.instrument = instrument
                self.engine.attach(instrument)
                self.engine.connect(instrument, to: self.engine.mainMixerNode, format: nil)
                self.engine.prepare()
                self.applyCurrentMix()
                self.startEngineIfPossible()
            }
        }
    }

    private func startEngineIfPossible() {
        guard shouldBeRunning, instrument != nil, !engine.isRunning else {
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

        instrument.pan = Float(currentMix.clampedPan)
        instrument.volume = currentMix.isMuted ? 0 : Float(currentMix.clampedLevel)
    }
}
