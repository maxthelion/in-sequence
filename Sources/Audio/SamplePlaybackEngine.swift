import Foundation
import AVFoundation

struct VoiceHandle: Equatable, Hashable {
    fileprivate let id: UUID
}

protocol SamplePlaybackSink: AnyObject {
    func start() throws
    func stop()
    /// Play a sample on a voice routed to `trackID`'s mixer node.
    /// The track mixer's `outputVolume` and `pan` (controlled via `setTrackMix`) are
    /// what the UI fader writes to — this call does not take a mix level.
    func play(sampleURL: URL, settings: SamplerSettings, trackID: UUID, at when: AVAudioTime?) -> VoiceHandle?
    /// Apply the track's fader state to its mixer node. Takes effect live for
    /// in-flight voices as well as subsequent triggers.
    func setTrackMix(trackID: UUID, level: Double, pan: Double)
    /// Tear down the track's mixer node and disconnect any voices still routed to it.
    /// Safe to call for unknown tracks (no-op).
    func removeTrack(trackID: UUID)
    func audition(sampleURL: URL)
    func stopAudition()
}

/// Hosts an AVAudioEngine with per-track `AVAudioMixerNode`s. Voices are
/// dynamically routed to the requesting track's mixer on each `play` call; the
/// mixer's `outputVolume` / `pan` is what the track fader writes to. A separate
/// preview node drives audition and bypasses track mixers entirely.
final class SamplePlaybackEngine: SamplePlaybackSink {
    private static let mainVoiceCount = 16
    private let engine = AVAudioEngine()
    private var mainVoices: [AVAudioPlayerNode] = []
    private var mainVoiceHandles: [UUID] = []
    private var mainVoiceCurrentTrack: [UUID?] = []
    private var nextVoiceIndex = 0
    private let previewNode = AVAudioPlayerNode()
    private var fileCache: [URL: AVAudioFile] = [:]
    private var isStarted = false
    private var trackMixers: [UUID: AVAudioMixerNode] = [:]

    init() {
        for _ in 0..<Self.mainVoiceCount {
            let node = AVAudioPlayerNode()
            engine.attach(node)
            // Voices are connected lazily at first play(), when the target track is known.
            mainVoices.append(node)
            mainVoiceHandles.append(UUID())
            mainVoiceCurrentTrack.append(nil)
        }
        engine.attach(previewNode)
        engine.connect(previewNode, to: engine.mainMixerNode, format: nil)
    }

    func start() throws {
        guard !isStarted else { return }
        try engine.start()
        isStarted = true
    }

    func stop() {
        guard isStarted else { return }
        for voice in mainVoices { voice.stop() }
        previewNode.stop()
        engine.stop()
        isStarted = false
    }

    @discardableResult
    func play(sampleURL: URL, settings: SamplerSettings, trackID: UUID, at when: AVAudioTime? = nil) -> VoiceHandle? {
        guard isStarted else { return nil }
        guard let file = cachedFile(url: sampleURL) else { return nil }

        let voiceIndex = nextVoiceIndex
        let voice = mainVoices[voiceIndex]
        let handleID = UUID()
        mainVoiceHandles[voiceIndex] = handleID
        nextVoiceIndex = (nextVoiceIndex &+ 1) % mainVoices.count

        // Route to this track's mixer; reconnect only when the voice was last used
        // by a different track (first-use on this voice also triggers reconnect).
        let mixer = trackMixer(for: trackID)
        voice.stop()
        if mainVoiceCurrentTrack[voiceIndex] != trackID {
            engine.disconnectNodeOutput(voice)
            engine.connect(voice, to: mixer, format: nil)
            mainVoiceCurrentTrack[voiceIndex] = trackID
        }

        voice.volume = linearGain(dB: settings.gain)
        voice.scheduleFile(file, at: when, completionHandler: nil)
        voice.play()

        return VoiceHandle(id: handleID)
    }

    func stopVoice(_ handle: VoiceHandle) {
        guard let idx = mainVoiceHandles.firstIndex(of: handle.id) else { return }
        mainVoices[idx].stop()
    }

    func stopAllMainVoices() {
        for voice in mainVoices { voice.stop() }
    }

    func setTrackMix(trackID: UUID, level: Double, pan: Double) {
        let mixer = trackMixer(for: trackID)
        mixer.outputVolume = Float(min(max(level, 0), 1))
        mixer.pan = Float(min(max(pan, -1), 1))
    }

    func removeTrack(trackID: UUID) {
        guard let mixer = trackMixers.removeValue(forKey: trackID) else { return }
        for (i, currentTrackID) in mainVoiceCurrentTrack.enumerated() where currentTrackID == trackID {
            mainVoices[i].stop()
            engine.disconnectNodeOutput(mainVoices[i])
            mainVoiceCurrentTrack[i] = nil
        }
        engine.disconnectNodeOutput(mixer)
        engine.detach(mixer)
    }

    func audition(sampleURL: URL) {
        guard isStarted else { return }
        guard let file = cachedFile(url: sampleURL) else { return }
        previewNode.stop()
        previewNode.volume = 1.0
        previewNode.scheduleFile(file, at: nil, completionHandler: nil)
        previewNode.play()
    }

    func stopAudition() {
        previewNode.stop()
    }

    private func trackMixer(for trackID: UUID) -> AVAudioMixerNode {
        if let mixer = trackMixers[trackID] { return mixer }
        let mixer = AVAudioMixerNode()
        engine.attach(mixer)
        engine.connect(mixer, to: engine.mainMixerNode, format: nil)
        trackMixers[trackID] = mixer
        return mixer
    }

    private func cachedFile(url: URL) -> AVAudioFile? {
        if let f = fileCache[url] { return f }
        guard let f = try? AVAudioFile(forReading: url) else { return nil }
        if fileCache.count >= 64 {
            fileCache.removeAll(keepingCapacity: true)
        }
        fileCache[url] = f
        return f
    }

    private func linearGain(dB: Double) -> Float {
        Float(pow(10, dB / 20))
    }
}
