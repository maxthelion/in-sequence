import AVFoundation
import AudioToolbox
import Foundation

protocol TrackPlaybackSink: AnyObject {
    var displayName: String { get }
    var isAvailable: Bool { get }
    func startIfNeeded()
    func stop()
    func play(noteEvents: [NoteEvent], bpm: Double, stepsPerBar: Int)
}

final class AudioInstrumentHost: TrackPlaybackSink {
    let displayName: String

    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "ai.sequencer.SequencerAI.AudioInstrumentHost")
    private var instrument: AVAudioUnitMIDIInstrument?
    private var shouldBeRunning = false

    init(displayName: String = "Apple DLS Synth") {
        self.displayName = displayName
        configureInstrument()
    }

    var isAvailable: Bool {
        queue.sync { instrument != nil }
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

    private func configureInstrument() {
        let description = AudioComponentDescription(
            componentType: kAudioUnitType_MusicDevice,
            componentSubType: kAudioUnitSubType_DLSSynth,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        AVAudioUnit.instantiate(with: description, options: []) { [weak self] audioUnit, _ in
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
}
