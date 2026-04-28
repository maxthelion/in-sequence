import Foundation
import AVFoundation

struct VoiceHandle: Equatable, Hashable {
    fileprivate let id: UUID
}

protocol SamplePlaybackSink: AnyObject {
    func start() throws
    func stop()
    /// Ensures `trackID` has a ready mixer, filter, and voice pool attached to
    /// the engine graph. This is safe to call repeatedly and should happen from
    /// the document apply path before transport ticks can dispatch sample events.
    func prepareTrack(trackID: UUID)
    /// Play a sample on a voice routed to `trackID`'s mixer node.
    /// The track mixer's `outputVolume` and `pan` (controlled via `setTrackMix`) are
    /// what the UI fader writes to — this call does not take a mix level.
    func play(sampleURL: URL, settings: SamplerSettings, trackID: UUID, at when: AVAudioTime?) -> VoiceHandle?
    func playSlice(
        sampleURL: URL,
        startFrame: AVAudioFramePosition,
        endFrame: AVAudioFramePosition,
        settings: SlicerSettings,
        trackID: UUID,
        at when: AVAudioTime?,
        reverse: Bool
    ) -> VoiceHandle?
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

extension SamplePlaybackSink {
    func prepareTrack(trackID: UUID) {}

    func playSlice(
        sampleURL: URL,
        startFrame: AVAudioFramePosition,
        endFrame: AVAudioFramePosition,
        settings: SlicerSettings,
        trackID: UUID,
        at when: AVAudioTime?,
        reverse: Bool
    ) -> VoiceHandle? {
        nil
    }
}

/// Hosts sample player nodes with per-track `AVAudioMixerNode`s and static
/// per-track voice pools. `prepareTrack(trackID:)` builds the graph up front, so
/// transport playback only schedules already-connected voices. The mixer's
/// `outputVolume` / `pan` is what the track fader writes to. A separate preview
/// node drives audition and bypasses track mixers entirely.
final class SamplePlaybackEngine: SamplePlaybackSink {
    private struct ReversedSliceCacheKey: Hashable {
        let url: URL
        let startFrame: AVAudioFramePosition
        let endFrame: AVAudioFramePosition
    }

    private struct TrackVoicePool {
        var voices: [AVAudioPlayerNode]
        var handles: [UUID]
        var cursor: Int
    }

    private static let voicesPerTrack = 4
    private static let reversedSliceCacheLimit = 32
    private let audioGraph: MainAudioGraph
    private let previewNode = AVAudioPlayerNode()
    private var fileCache: [URL: AVAudioFile] = [:]
    private var reversedSliceCache: [ReversedSliceCacheKey: AVAudioPCMBuffer] = [:]
    private var reversedSliceCacheOrder: [ReversedSliceCacheKey] = []
    private var isStarted = false
    private var trackVoicePools: [UUID: TrackVoicePool] = [:]
    private var trackMixers: [UUID: AVAudioMixerNode] = [:]
    /// Per-track filter nodes inserted between the track mixer and the main mixer.
    private var trackFilters: [UUID: SamplerFilterNode] = [:]
    /// Per-track, per-kind voice params. Applied at voice scheduling time (next trigger).
    private var voiceParams: [UUID: [BuiltinMacroKind: Double]] = [:]

    var preparedTrackIDs: Set<UUID> {
        Set(trackVoicePools.keys)
    }

    init(audioGraph: MainAudioGraph = MainAudioGraph()) {
        self.audioGraph = audioGraph
        audioGraph.attach(previewNode)
        audioGraph.connect(previewNode, to: audioGraph.preMasterMixer)
    }

    func start() throws {
        guard !isStarted else { return }
        try audioGraph.start()
        isStarted = true
    }

    func stop() {
        guard isStarted else { return }
        for pool in trackVoicePools.values {
            for voice in pool.voices {
                voice.stop()
            }
        }
        previewNode.stop()
        audioGraph.stop()
        isStarted = false
    }

    func prepareTrack(trackID: UUID) {
        guard trackVoicePools[trackID] == nil else { return }

        performOnMain { [self] in
            guard trackVoicePools[trackID] == nil else { return }
            let mixer = trackMixer(for: trackID)
            var voices: [AVAudioPlayerNode] = []
            var handles: [UUID] = []

            for _ in 0..<Self.voicesPerTrack {
                let voice = AVAudioPlayerNode()
                audioGraph.attach(voice)
                audioGraph.connect(voice, to: mixer)
                voices.append(voice)
                handles.append(UUID())
            }

            trackVoicePools[trackID] = TrackVoicePool(
                voices: voices,
                handles: handles,
                cursor: 0
            )
        }
    }

    @discardableResult
    func play(sampleURL: URL, settings: SamplerSettings, trackID: UUID, at when: AVAudioTime? = nil) -> VoiceHandle? {
        guard isStarted else { return nil }
        guard let file = cachedFile(url: sampleURL) else { return nil }
        guard var pool = trackVoicePools[trackID],
              !pool.voices.isEmpty
        else {
            return nil
        }

        let voiceIndex = pool.cursor % pool.voices.count
        let voice = pool.voices[voiceIndex]
        let handleID = UUID()
        pool.handles[voiceIndex] = handleID
        pool.cursor = (voiceIndex &+ 1) % pool.voices.count
        trackVoicePools[trackID] = pool
        let params = voiceParams[trackID]

        scheduleAndStart(voice, file: file, settings: settings, params: params, at: when)
        return VoiceHandle(id: handleID)
    }

    @discardableResult
    func playSlice(
        sampleURL: URL,
        startFrame: AVAudioFramePosition,
        endFrame: AVAudioFramePosition,
        settings: SlicerSettings,
        trackID: UUID,
        at when: AVAudioTime? = nil,
        reverse: Bool = false
    ) -> VoiceHandle? {
        guard isStarted else { return nil }
        guard let file = cachedFile(url: sampleURL) else { return nil }

        let clampedSettings = settings.clamped
        let resolvedStart = max(0, min(startFrame, max(file.length - 1, 0)))
        let resolvedEnd = max(resolvedStart + 1, min(endFrame, file.length))
        guard resolvedEnd > resolvedStart else { return nil }

        guard var pool = trackVoicePools[trackID],
              !pool.voices.isEmpty
        else {
            return nil
        }

        let voiceIndex: Int
        switch clampedSettings.voiceMode {
        case .mono:
            voiceIndex = 0
        case .polyphonic:
            voiceIndex = pool.cursor % pool.voices.count
            pool.cursor = (voiceIndex &+ 1) % pool.voices.count
        }

        let voice = pool.voices[voiceIndex]
        let handleID = UUID()
        pool.handles[voiceIndex] = handleID
        trackVoicePools[trackID] = pool
        let params = voiceParams[trackID]

        scheduleAndStartSlice(
            voice,
            sampleURL: sampleURL,
            file: file,
            startFrame: resolvedStart,
            endFrame: resolvedEnd,
            settings: clampedSettings,
            params: params,
            at: when,
            reverse: reverse
        )
        return VoiceHandle(id: handleID)
    }

    private func scheduleAndStart(
        _ voice: AVAudioPlayerNode,
        file: AVAudioFile,
        settings: SamplerSettings,
        params: [BuiltinMacroKind: Double]?,
        at when: AVAudioTime?
    ) {
        voice.stop()

        // Apply built-in macro voice params (set by TrackMacroApplier for the current step).
        let gainDB = params?[.sampleGain] ?? settings.gain
        voice.volume = linearGain(dB: gainDB)

        // Sample start / length: schedule a segment of the file if set.
        let startNorm = min(max(params?[.sampleStart] ?? settings.start, 0), 1)
        let lengthNorm = min(max(params?[.sampleLength] ?? settings.length, 0), 1)
        let frameCount = Double(file.length)
        let startFrame = AVAudioFramePosition(min(startNorm * frameCount, max(frameCount - 1, 0)))
        let remainingFrames = max(1, Double(file.length) - Double(startFrame))
        let frameLength = AVAudioFrameCount(min(max(1, lengthNorm * frameCount), remainingFrames))
        voice.scheduleSegment(file, startingFrame: startFrame, frameCount: frameLength, at: when, completionHandler: nil)
        voice.play()
    }

    private func scheduleAndStartSlice(
        _ voice: AVAudioPlayerNode,
        sampleURL: URL,
        file: AVAudioFile,
        startFrame: AVAudioFramePosition,
        endFrame: AVAudioFramePosition,
        settings: SlicerSettings,
        params: [BuiltinMacroKind: Double]?,
        at when: AVAudioTime?,
        reverse: Bool
    ) {
        voice.stop()
        let gainDB = params?[.sampleGain] ?? settings.gain
        voice.volume = linearGain(dB: gainDB)

        if reverse,
           let buffer = reversedSliceBuffer(
               sampleURL: sampleURL,
               format: file.processingFormat,
               startFrame: startFrame,
               endFrame: endFrame
           )
        {
            voice.scheduleBuffer(buffer, at: when, options: [], completionHandler: nil)
        } else {
            voice.scheduleSegment(
                file,
                startingFrame: startFrame,
                frameCount: AVAudioFrameCount(endFrame - startFrame),
                at: when,
                completionHandler: nil
            )
        }
        voice.play()
    }

    func stopVoice(_ handle: VoiceHandle) {
        for pool in trackVoicePools.values {
            guard let index = pool.handles.firstIndex(of: handle.id) else {
                continue
            }
            pool.voices[index].stop()
            return
        }
    }

    func stopAllMainVoices() {
        for pool in trackVoicePools.values {
            for voice in pool.voices {
                voice.stop()
            }
        }
    }

    func setTrackMix(trackID: UUID, level: Double, pan: Double) {
        prepareTrack(trackID: trackID)
        let mixer = trackMixer(for: trackID)
        mixer.outputVolume = Float(min(max(level, 0), 1))
        mixer.pan = Float(min(max(pan, -1), 1))
    }

    func removeTrack(trackID: UUID) {
        if let pool = trackVoicePools.removeValue(forKey: trackID) {
            for voice in pool.voices {
                voice.stop()
                audioGraph.disconnectOutput(voice)
                audioGraph.detach(voice)
            }
        }
        voiceParams.removeValue(forKey: trackID)
        guard let mixer = trackMixers.removeValue(forKey: trackID) else { return }
        audioGraph.disconnectOutput(mixer)
        audioGraph.detach(mixer)
        // Also tear down the filter inserted after this mixer.
        if let filter = trackFilters.removeValue(forKey: trackID) {
            audioGraph.disconnectOutput(filter.avNode)
            audioGraph.detach(filter.avNode)
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
        audioGraph.attach(mixer)

        // Insert a filter between the track mixer and the main mixer.
        // Graph: voices -> mixer -> filter.avNode -> shared pre-master mixer
        let filter = SamplerFilterNode()
        audioGraph.attach(filter.avNode)
        audioGraph.connect(mixer, to: filter.avNode)
        audioGraph.connect(filter.avNode, to: audioGraph.preMasterMixer)
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

    private func reversedSliceBuffer(
        sampleURL: URL,
        format: AVAudioFormat,
        startFrame: AVAudioFramePosition,
        endFrame: AVAudioFramePosition
    ) -> AVAudioPCMBuffer? {
        let key = ReversedSliceCacheKey(url: sampleURL, startFrame: startFrame, endFrame: endFrame)
        if let cached = reversedSliceCache[key] {
            return cached
        }
        guard let file = try? AVAudioFile(forReading: sampleURL) else {
            return nil
        }
        let frameCount = AVAudioFrameCount(max(1, endFrame - startFrame))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount) else {
            return nil
        }
        do {
            file.framePosition = startFrame
            try file.read(into: buffer, frameCount: frameCount)
        } catch {
            return nil
        }
        reverse(buffer)
        cacheReversedSlice(buffer, for: key)
        return buffer
    }

    private func reverse(_ buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        let channelCount = Int(buffer.format.channelCount)
        guard frameCount > 1 else { return }
        for channel in 0..<channelCount {
            let samples = channelData[channel]
            var left = 0
            var right = frameCount - 1
            while left < right {
                let temp = samples[left]
                samples[left] = samples[right]
                samples[right] = temp
                left += 1
                right -= 1
            }
        }
    }

    private func cacheReversedSlice(_ buffer: AVAudioPCMBuffer, for key: ReversedSliceCacheKey) {
        reversedSliceCache[key] = buffer
        reversedSliceCacheOrder.removeAll { $0 == key }
        reversedSliceCacheOrder.append(key)
        while reversedSliceCacheOrder.count > Self.reversedSliceCacheLimit {
            let removed = reversedSliceCacheOrder.removeFirst()
            reversedSliceCache.removeValue(forKey: removed)
        }
    }

    private func linearGain(dB: Double) -> Float {
        Float(pow(10, dB / 20))
    }

    private func performOnMain<T>(_ work: @escaping @MainActor () -> T) -> T {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                work()
            }
        }

        var result: T?
        DispatchQueue.main.sync {
            result = MainActor.assumeIsolated {
                work()
            }
        }
        return result!
    }
}
