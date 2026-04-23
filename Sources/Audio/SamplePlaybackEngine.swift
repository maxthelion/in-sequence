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

    /// Set a built-in voice parameter for subsequent triggers on the given track.
    /// Applied per step; does NOT retroactively modify currently-playing voices
    /// (which would cause clicks).
    func setVoiceParam(trackID: UUID, kind: BuiltinMacroKind, value: Double)

    /// Apply complete filter settings to the filter node for a track.
    /// Called from the document layer on track-level changes (e.g. UI control edits).
    func applyFilter(_ settings: SamplerFilterSettings, trackID: UUID)

    /// Returns the filter node for a track, or nil if the track is unknown.
    /// Used by `TrackMacroApplier` for fine-grained per-step macro dispatch.
    func filterNode(for trackID: UUID) -> (any SamplerFilterControlling)?
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
    /// Per-track filter nodes inserted between the track mixer and the main mixer.
    private var trackFilters: [UUID: SamplerFilterNode] = [:]
    /// Per-track, per-kind voice params. Applied at voice scheduling time (next trigger).
    private var voiceParams: [UUID: [BuiltinMacroKind: Double]] = [:]

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

        // Apply built-in macro voice params (set by TrackMacroApplier for the current step).
        let params = voiceParams[trackID]
        let gainDB = params?[.sampleGain] ?? settings.gain
        voice.volume = linearGain(dB: gainDB)

        // Sample start / length: schedule a segment of the file if set.
        let startNorm = params?[.sampleStart] ?? 0
        let lengthNorm = params?[.sampleLength] ?? 1
        let frameCount = Double(file.length)
        let startFrame = AVAudioFramePosition(startNorm * frameCount)
        let frameLength = AVAudioFrameCount(max(1, lengthNorm * frameCount))
        voice.scheduleSegment(file, startingFrame: startFrame, frameCount: frameLength, at: when, completionHandler: nil)
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
        // Also tear down the filter inserted after this mixer.
        if let filter = trackFilters.removeValue(forKey: trackID) {
            engine.disconnectNodeOutput(filter.avNode)
            engine.detach(filter.avNode)
        }
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

    func setVoiceParam(trackID: UUID, kind: BuiltinMacroKind, value: Double) {
        voiceParams[trackID, default: [:]][kind] = value
    }

    private func trackMixer(for trackID: UUID) -> AVAudioMixerNode {
        if let mixer = trackMixers[trackID] { return mixer }
        let mixer = AVAudioMixerNode()
        engine.attach(mixer)

        // Insert a filter between the track mixer and the main mixer.
        // Graph: voices -> mixer -> filter.avNode -> mainMixerNode
        let filter = SamplerFilterNode()
        engine.attach(filter.avNode)
        engine.connect(mixer, to: filter.avNode, format: nil)
        engine.connect(filter.avNode, to: engine.mainMixerNode, format: nil)
        trackFilters[trackID] = filter

        trackMixers[trackID] = mixer
        return mixer
    }

    /// Apply filter settings to the filter node for the given track.
    ///
    /// Called from the document layer when the user edits `track.filter` directly
    /// (e.g. via `SamplerDestinationWidget`). Per-step macro dispatch uses
    /// `filterNode(for:)` and the fine-grained setters instead.
    func applyFilter(_ settings: SamplerFilterSettings, trackID: UUID) {
        trackFilters[trackID]?.apply(settings)
    }

    /// Returns the filter node for the given track, or nil if it doesn't exist.
    ///
    /// Used by `TrackMacroApplier` to dispatch per-step filter macro values.
    func filterNode(for trackID: UUID) -> (any SamplerFilterControlling)? {
        trackFilters[trackID]
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
