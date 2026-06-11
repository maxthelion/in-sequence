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
        reverse: Bool,
        stepParameters: SliceTriggerStepParameters?
    ) -> VoiceHandle?
    /// Apply the track's fader state to its mixer node. Takes effect live for
    /// in-flight voices as well as subsequent triggers.
    func setTrackMix(trackID: UUID, level: Double, pan: Double)
    /// Apply the track's post-fader send tap gains. This is a parameter update,
    /// not a topology rebuild.
    func setTrackSends(trackID: UUID, sendA: Double, sendB: Double)
    /// Rewire the prepared track output to a user-created bus, or back to master
    /// when `busID` is nil.
    func setTrackOutputBus(trackID: UUID, busID: UUID?)
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

    func setTrackOutputBus(trackID: UUID, busID: UUID?) {}

    func setTrackSends(trackID: UUID, sendA: Double, sendB: Double) {}

    func playSlice(
        sampleURL: URL,
        startFrame: AVAudioFramePosition,
        endFrame: AVAudioFramePosition,
        settings: SlicerSettings,
        trackID: UUID,
        at when: AVAudioTime?,
        reverse: Bool,
        stepParameters: SliceTriggerStepParameters?
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
    private struct TrackVoicePool {
        var voices: [AVAudioPlayerNode]
        var voiceFilters: [SamplerFilterNode]
        var handles: [UUID]
        var cursor: Int
    }

    private static let voicesPerTrack = 4
    private let audioGraph: MainAudioGraph
    private let previewNode = AVAudioPlayerNode()
    private let lifecycleLock = NSLock()
    private var fileCache: [URL: AVAudioFile] = [:]
    private var isStarted = false
    private var trackVoicePools: [UUID: TrackVoicePool] = [:]
    private var trackMixers: [UUID: AVAudioMixerNode] = [:]
    /// Per-track filter nodes inserted between the track mixer and the main mixer.
    private var trackFilters: [UUID: SamplerFilterNode] = [:]
    private var trackOutputBusIDs: [UUID: UUID] = [:]
    private var trackSendLevels: [UUID: MainAudioGraph.TrackSendLevels] = [:]
    /// Per-track, per-kind voice params. Applied at voice scheduling time (next trigger).
    private var voiceParams: [UUID: [BuiltinMacroKind: Double]] = [:]

    var preparedTrackIDs: Set<UUID> {
        lifecycleLock.withLock {
            Set(trackVoicePools.keys)
        }
    }

    init(audioGraph: MainAudioGraph = MainAudioGraph()) {
        self.audioGraph = audioGraph
        audioGraph.attach(previewNode)
        audioGraph.connect(previewNode, to: audioGraph.preMasterMixer)
    }

    func start() throws {
        guard lifecycleLock.withLock({ !isStarted }) else { return }
        validatePreparedTrackGraphs()
        try audioGraph.start()
        lifecycleLock.withLock {
            isStarted = true
        }
    }

    func stop() {
        let (shouldStop, pools) = lifecycleLock.withLock { () -> (Bool, [TrackVoicePool]) in
            guard isStarted else { return (false, []) }
            isStarted = false
            return (true, Array(trackVoicePools.values))
        }
        guard shouldStop else { return }
        for pool in pools {
            for voice in pool.voices {
                voice.stop()
            }
        }
        previewNode.stop()
        audioGraph.stop()
    }

    func prepareTrack(trackID: UUID) {
        performOnMain { [self] in
            lifecycleLock.withLock {
                if let pool = trackVoicePools[trackID] {
                    repairPreparedTrackGraph(trackID: trackID, pool: pool)
                    return
                }
                let mixer = trackMixer(for: trackID)
                var voices: [AVAudioPlayerNode] = []
                var voiceFilters: [SamplerFilterNode] = []
                var handles: [UUID] = []

                for _ in 0..<Self.voicesPerTrack {
                    let voice = AVAudioPlayerNode()
                    let voiceFilter = SamplerFilterNode()
                    audioGraph.attach(voice)
                    audioGraph.attach(voiceFilter.avNode)
                    audioGraph.connect(voice, to: voiceFilter.avNode)
                    audioGraph.connect(voiceFilter.avNode, to: mixer)
                    voices.append(voice)
                    voiceFilters.append(voiceFilter)
                    handles.append(UUID())
                }

                trackVoicePools[trackID] = TrackVoicePool(
                    voices: voices,
                    voiceFilters: voiceFilters,
                    handles: handles,
                    cursor: 0
                )
            }
        }
    }

    @discardableResult
    func play(sampleURL: URL, settings: SamplerSettings, trackID: UUID, at when: AVAudioTime? = nil) -> VoiceHandle? {
        guard lifecycleLock.withLock({ isStarted }) else { return nil }
        guard let file = cachedFile(url: sampleURL) else { return nil }
        return playWithPreparedVoice(trackID: trackID, voiceMode: .polyphonic) { [self] voice, voiceFilter, params in
            self.scheduleAndStart(
                voice,
                voiceFilter: voiceFilter,
                file: file,
                settings: settings,
                params: params,
                at: when
            )
        }
    }

    @discardableResult
    func playSlice(
        sampleURL: URL,
        startFrame: AVAudioFramePosition,
        endFrame: AVAudioFramePosition,
        settings: SlicerSettings,
        trackID: UUID,
        at when: AVAudioTime? = nil,
        reverse: Bool = false,
        stepParameters: SliceTriggerStepParameters? = nil
    ) -> VoiceHandle? {
        guard lifecycleLock.withLock({ isStarted }) else { return nil }
        guard let file = cachedFile(url: sampleURL) else { return nil }

        let clampedSettings = settings.clamped
        let sliceParameters = (stepParameters ?? .default).clamped
        let resolvedStart = max(0, min(startFrame, max(file.length - 1, 0)))
        let resolvedEnd = max(resolvedStart + 1, min(endFrame, file.length))
        guard resolvedEnd > resolvedStart else { return nil }

        return playWithPreparedVoice(trackID: trackID, voiceMode: clampedSettings.voiceMode) { [self] voice, voiceFilter, params in
            self.scheduleAndStartSlice(
                voice,
                voiceFilter: voiceFilter,
                sampleURL: sampleURL,
                file: file,
                startFrame: resolvedStart,
                endFrame: resolvedEnd,
                settings: clampedSettings,
                params: params,
                at: when,
                reverse: reverse,
                sliceParameters: sliceParameters
            )
        }
    }

    /// AVAudioPlayerNode.play() throws NSException — uncatchable from
    /// Swift — when the engine stopped or the node was detached/disconnected.
    /// The pre-checks close the common cases, but CoreAudio can auto-stop
    /// the engine from its own thread (configuration change) between check
    /// and play, so the ObjC catcher is the only airtight guard: a failed
    /// start drops the trigger instead of killing the app.
    private func startVoiceSafely(_ voice: AVAudioPlayerNode) {
        guard audioGraph.isNodePlayableNow(voice) else { return }
        if let exception = SEQRunCatchingObjCException({ voice.play() }) {
            DevActivity.trace(DevActivity.audioGraph, "dropped sample trigger: play threw \(exception.name.rawValue): \(exception.reason ?? "no reason")")
        }
    }

    private func scheduleAndStart(
        _ voice: AVAudioPlayerNode,
        voiceFilter: SamplerFilterNode?,
        file: AVAudioFile,
        settings: SamplerSettings,
        params: [BuiltinMacroKind: Double]?,
        at when: AVAudioTime?
    ) {
        voice.stop()

        // Apply built-in macro voice params (set by TrackMacroApplier for the current step).
        let gainDB = params?[.sampleGain] ?? settings.gain
        voice.volume = linearGain(dB: gainDB)
        voice.pan = 0
        voice.rate = 1
        voiceFilter?.apply(SamplerFilterSettings())

        // Sample start / length: schedule a segment of the file if set.
        let startNorm = min(max(params?[.sampleStart] ?? settings.start, 0), 1)
        let lengthNorm = min(max(params?[.sampleLength] ?? settings.length, 0), 1)
        let frameCount = Double(file.length)
        let startFrame = AVAudioFramePosition(min(startNorm * frameCount, max(frameCount - 1, 0)))
        let remainingFrames = max(1, Double(file.length) - Double(startFrame))
        let frameLength = AVAudioFrameCount(min(max(1, lengthNorm * frameCount), remainingFrames))
        voice.scheduleSegment(file, startingFrame: startFrame, frameCount: frameLength, at: when, completionHandler: nil)
        startVoiceSafely(voice)
    }

    private func scheduleAndStartSlice(
        _ voice: AVAudioPlayerNode,
        voiceFilter: SamplerFilterNode?,
        sampleURL: URL,
        file: AVAudioFile,
        startFrame: AVAudioFramePosition,
        endFrame: AVAudioFramePosition,
        settings: SlicerSettings,
        params: [BuiltinMacroKind: Double]?,
        at when: AVAudioTime?,
        reverse: Bool,
        sliceParameters: SliceTriggerStepParameters
    ) {
        voice.stop()
        let gainDB = params?[.sampleGain] ?? settings.gain
        voice.volume = linearGain(dB: gainDB)
        voice.pan = Float(sliceParameters.pan)
        voice.rate = Float(playbackRate(forSemitoneOffset: settings.transpose))
        voiceFilter?.setCutoff(hz: cutoffHz(for: sliceParameters.filter))

        let shouldBuffer = reverse || sliceParameters.attackMs > 0 || sliceParameters.releaseMs > 0
        if shouldBuffer,
           let buffer = sliceBuffer(
               sampleURL: sampleURL,
               fileFormat: file.processingFormat,
               playbackFormat: voice.outputFormat(forBus: 0),
               startFrame: startFrame,
               endFrame: endFrame
           )
        {
            if reverse {
                Self.reverse(buffer)
            }
            applyEnvelope(
                to: buffer,
                attackMs: sliceParameters.attackMs,
                releaseMs: sliceParameters.releaseMs
            )
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
        startVoiceSafely(voice)
    }

    func stopVoice(_ handle: VoiceHandle) {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        for pool in trackVoicePools.values {
            guard let index = pool.handles.firstIndex(of: handle.id) else {
                continue
            }
            pool.voices[index].stop()
            return
        }
    }

    func stopAllMainVoices() {
        let pools = lifecycleLock.withLock { Array(trackVoicePools.values) }
        for pool in pools {
            for voice in pool.voices {
                voice.stop()
            }
        }
    }

    func setTrackMix(trackID: UUID, level: Double, pan: Double) {
        prepareTrack(trackID: trackID)
        performOnMain { [self] in
            lifecycleLock.withLock {
                let mixer = trackMixer(for: trackID)
                mixer.outputVolume = Float(min(max(level, 0), 1))
                mixer.pan = Float(min(max(pan, -1), 1))
            }
        }
    }

    func setTrackOutputBus(trackID: UUID, busID: UUID?) {
        performOnMain { [self] in
            lifecycleLock.withLock {
                trackOutputBusIDs[trackID] = busID
                guard let filter = trackFilters[trackID] else { return }
                audioGraph.connectTrackOutput(
                    filter.avNode,
                    to: busID,
                    sends: trackSendLevels[trackID] ?? .zero
                )
            }
        }
    }

    func setTrackSends(trackID: UUID, sendA: Double, sendB: Double) {
        prepareTrack(trackID: trackID)
        performOnMain { [self] in
            lifecycleLock.withLock {
                let levels = MainAudioGraph.TrackSendLevels(sendA: sendA, sendB: sendB)
                trackSendLevels[trackID] = levels
                guard let filter = trackFilters[trackID] else { return }
                audioGraph.setTrackSendLevels(filter.avNode, sendA: levels.sendA, sendB: levels.sendB)
            }
        }
    }

    func removeTrack(trackID: UUID) {
        performOnMain { [self] in
            lifecycleLock.lock()
            defer { lifecycleLock.unlock() }

            if let pool = trackVoicePools.removeValue(forKey: trackID) {
                for voice in pool.voices {
                    voice.stop()
                    audioGraph.disconnectOutput(voice)
                    audioGraph.detach(voice)
                }
                for filter in pool.voiceFilters {
                    audioGraph.disconnectOutput(filter.avNode)
                    audioGraph.detach(filter.avNode)
                }
            }
            voiceParams.removeValue(forKey: trackID)
            trackOutputBusIDs.removeValue(forKey: trackID)
            trackSendLevels.removeValue(forKey: trackID)
            guard let mixer = trackMixers.removeValue(forKey: trackID) else { return }
            audioGraph.disconnectOutput(mixer)
            audioGraph.detach(mixer)
            // Also tear down the filter inserted after this mixer.
            if let filter = trackFilters.removeValue(forKey: trackID) {
                audioGraph.disconnectOutput(filter.avNode)
                audioGraph.detach(filter.avNode)
            }
        }
    }

    func audition(sampleURL: URL) {
        guard lifecycleLock.withLock({ isStarted }) else { return }
        guard let file = cachedFile(url: sampleURL) else { return }
        previewNode.stop()
        previewNode.volume = 1.0
        previewNode.scheduleFile(file, at: nil, completionHandler: nil)
        startVoiceSafely(previewNode)
    }

    func stopAudition() {
        previewNode.stop()
    }

    func setVoiceParam(trackID: UUID, kind: BuiltinMacroKind, value: Double) {
        lifecycleLock.withLock {
            voiceParams[trackID, default: [:]][kind] = value
        }
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
        audioGraph.connectTrackOutput(
            filter.avNode,
            to: trackOutputBusIDs[trackID],
            sends: trackSendLevels[trackID] ?? .zero
        )
        trackFilters[trackID] = filter

        trackMixers[trackID] = mixer
        return mixer
    }

    private func validatePreparedTrackGraphs() {
        performOnMain { [self] in
            lifecycleLock.withLock {
                for (trackID, pool) in trackVoicePools {
                    repairPreparedTrackGraph(trackID: trackID, pool: pool)
                }
            }
        }
    }

    /// Apply filter settings to the filter node for the given track.
    ///
    /// Called from the document layer when the user edits `track.filter` directly
    /// (e.g. via `SamplerDestinationWidget`). Per-step macro dispatch uses
    /// `filterNode(for:)` and the fine-grained setters instead.
    func applyFilter(_ settings: SamplerFilterSettings, trackID: UUID) {
        let filter = lifecycleLock.withLock {
            trackFilters[trackID]
        }
        filter?.apply(settings)
    }

    /// Returns the filter node for the given track, or nil if it doesn't exist.
    ///
    /// Used by `TrackMacroApplier` to dispatch per-step filter macro values.
    func filterNode(for trackID: UUID) -> (any SamplerFilterControlling)? {
        lifecycleLock.withLock {
            trackFilters[trackID]
        }
    }

    private func cachedFile(url: URL) -> AVAudioFile? {
        lifecycleLock.withLock {
            if let f = fileCache[url] { return f }
            guard let f = try? AVAudioFile(forReading: url) else { return nil }
            if fileCache.count >= 64 {
                fileCache.removeAll(keepingCapacity: true)
            }
            fileCache[url] = f
            return f
        }
    }

    private func sliceBuffer(
        sampleURL: URL,
        fileFormat: AVAudioFormat,
        playbackFormat: AVAudioFormat,
        startFrame: AVAudioFramePosition,
        endFrame: AVAudioFramePosition
    ) -> AVAudioPCMBuffer? {
        guard let file = try? AVAudioFile(forReading: sampleURL) else {
            return nil
        }
        let frameCount = AVAudioFrameCount(max(1, endFrame - startFrame))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: fileFormat, frameCapacity: frameCount) else {
            return nil
        }
        do {
            file.framePosition = startFrame
            try file.read(into: buffer, frameCount: frameCount)
        } catch {
            return nil
        }
        return buffer.convertingForPlayback(to: playbackFormat) ?? buffer
    }

    private static func reverse(_ buffer: AVAudioPCMBuffer) {
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

    private func applyEnvelope(to buffer: AVAudioPCMBuffer, attackMs: Double, releaseMs: Double) {
        guard attackMs > 0 || releaseMs > 0 else { return }
        Self.applyEnvelope(to: buffer, attackMs: attackMs, releaseMs: releaseMs)
    }

    static func applyEnvelope(to buffer: AVAudioPCMBuffer, attackMs: Double, releaseMs: Double) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return }

        let sampleRate = buffer.format.sampleRate
        let attackFrames = max(0, Int((max(0, attackMs) / 1000) * sampleRate))
        let releaseFrames = max(0, Int((max(0, releaseMs) / 1000) * sampleRate))
        guard attackFrames > 0 || releaseFrames > 0 else { return }

        let channelCount = Int(buffer.format.channelCount)
        for frame in 0..<frameCount {
            let attackGain: Float
            if attackFrames > 0 {
                attackGain = Float(min(1, Double(frame) / Double(max(attackFrames, 1))))
            } else {
                attackGain = 1
            }

            let releaseGain: Float
            if releaseFrames > 0 {
                let framesFromEnd = max(0, frameCount - 1 - frame)
                releaseGain = Float(min(1, Double(framesFromEnd) / Double(max(releaseFrames, 1))))
            } else {
                releaseGain = 1
            }

            let gain = min(attackGain, releaseGain)
            guard gain < 1 else { continue }
            for channel in 0..<channelCount {
                channelData[channel][frame] *= gain
            }
        }
    }

    private func linearGain(dB: Double) -> Float {
        Float(pow(10, dB / 20))
    }

    private func playbackRate(forSemitoneOffset semitones: Int) -> Double {
        min(max(pow(2, Double(semitones) / 12), 0.25), 4)
    }

    private func cutoffHz(for normalized: Double) -> Double {
        let value = min(max(normalized, 0), 1)
        let minLog = log10(20.0)
        let maxLog = log10(20_000.0)
        return pow(10, minLog + ((maxLog - minLog) * value))
    }

    private func playWithPreparedVoice(
        trackID: UUID,
        voiceMode: SlicerVoiceMode,
        schedule: @escaping (AVAudioPlayerNode, SamplerFilterNode, [BuiltinMacroKind: Double]?) -> Void
    ) -> VoiceHandle? {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                preparedVoicePlaybackOnMain(trackID: trackID, voiceMode: voiceMode, schedule: schedule)
            }
        }

        // Tick/event-queue callers dispatch fire-and-forget: start times ride
        // on the scheduled AVAudioTime, so async preserves timing — and a
        // sync hop here deadlocks against TickClock.stop()'s queue join
        // (main waits for the tick queue, the tick waits for main; observed
        // as a full app hang). Engine callers discard the handle anyway.
        DispatchQueue.main.async { [self] in
            MainActor.assumeIsolated {
                _ = preparedVoicePlaybackOnMain(trackID: trackID, voiceMode: voiceMode, schedule: schedule)
            }
        }
        return nil
    }

    @MainActor
    private func preparedVoicePlaybackOnMain(
        trackID: UUID,
        voiceMode: SlicerVoiceMode,
        schedule: (AVAudioPlayerNode, SamplerFilterNode, [BuiltinMacroKind: Double]?) -> Void
    ) -> VoiceHandle? {
        do {
            var didRepair = false

            while true {
                var selectedVoice: AVAudioPlayerNode?
                var selectedFilter: SamplerFilterNode?
                var selectedParams: [BuiltinMacroKind: Double]?
                var selectedHandleID: UUID?
                var needsRepair = false

                lifecycleLock.withLock {
                    guard var pool = trackVoicePools[trackID],
                          !pool.voices.isEmpty
                    else {
                        return
                    }

                    let voiceIndex: Int
                    switch voiceMode {
                    case .mono:
                        voiceIndex = 0
                    case .polyphonic:
                        voiceIndex = pool.cursor % pool.voices.count
                    }

                    guard voiceIndex < pool.voiceFilters.count,
                          voiceIndex < pool.handles.count
                    else {
                        needsRepair = true
                        return
                    }

                    let voice = pool.voices[voiceIndex]
                    let voiceFilter = pool.voiceFilters[voiceIndex]
                    guard isPreparedTrackRouteReadyForPlayback(
                        trackID: trackID,
                        voice: voice,
                        voiceFilter: voiceFilter
                    ) else {
                        needsRepair = true
                        return
                    }

                    let handleID = UUID()
                    pool.handles[voiceIndex] = handleID
                    if voiceMode == .polyphonic {
                        pool.cursor = (voiceIndex &+ 1) % pool.voices.count
                    }
                    trackVoicePools[trackID] = pool
                    selectedVoice = voice
                    selectedFilter = voiceFilter
                    selectedParams = voiceParams[trackID]
                    selectedHandleID = handleID
                }

                if needsRepair {
                    guard !didRepair else { return nil }
                    didRepair = true
                    lifecycleLock.withLock {
                        guard let pool = trackVoicePools[trackID] else { return }
                        repairPreparedTrackGraph(trackID: trackID, pool: pool)
                    }
                    continue
                }

                guard let voice = selectedVoice,
                      let voiceFilter = selectedFilter,
                      let handleID = selectedHandleID
                else {
                    return nil
                }

                schedule(voice, voiceFilter, selectedParams)
                return VoiceHandle(id: handleID)
            }
        }
    }

    @MainActor
    private func isPreparedTrackRouteReadyForPlayback(
        trackID: UUID,
        voice: AVAudioPlayerNode,
        voiceFilter: SamplerFilterNode
    ) -> Bool {
        guard voice.engine === audioGraph.engine,
              voiceFilter.avNode.engine === audioGraph.engine,
              let mixer = trackMixers[trackID],
              mixer.engine === audioGraph.engine,
              let trackFilter = trackFilters[trackID],
              trackFilter.avNode.engine === audioGraph.engine
        else {
            return false
        }

        return outputConnectionExists(from: voice, to: voiceFilter.avNode) &&
            outputConnectionExists(from: voiceFilter.avNode, to: mixer) &&
            outputConnectionExists(from: mixer, to: trackFilter.avNode) &&
            audioGraph.trackOutputDestinationForTesting(trackFilter.avNode) != nil
    }

    @MainActor
    private func repairPreparedTrackGraph(trackID: UUID, pool: TrackVoicePool) {
        let mixer = trackMixer(for: trackID)
        repairTrackMixerOutput(trackID: trackID, mixer: mixer)

        for index in pool.voices.indices {
            let voice = pool.voices[index]
            guard index < pool.voiceFilters.count else { continue }
            let filter = pool.voiceFilters[index]

            audioGraph.attach(voice)
            audioGraph.attach(filter.avNode)
            connectOutputIfNeeded(voice, to: filter.avNode)
            connectOutputIfNeeded(filter.avNode, to: mixer)
        }
    }

    @MainActor
    private func repairTrackMixerOutput(trackID: UUID, mixer: AVAudioMixerNode) {
        audioGraph.attach(mixer)
        let filter: SamplerFilterNode
        if let existing = trackFilters[trackID] {
            filter = existing
        } else {
            let next = SamplerFilterNode()
            trackFilters[trackID] = next
            filter = next
        }

        audioGraph.attach(filter.avNode)
        connectOutputIfNeeded(mixer, to: filter.avNode)
        if audioGraph.trackOutputDestinationForTesting(filter.avNode) == nil {
            audioGraph.connectTrackOutput(
                filter.avNode,
                to: trackOutputBusIDs[trackID],
                sends: trackSendLevels[trackID] ?? .zero
            )
        }
    }

    private func outputConnectionExists(from source: AVAudioNode, to destination: AVAudioNode) -> Bool {
        audioGraph.engine.outputConnectionPoints(for: source, outputBus: 0).contains { point in
            point.node === destination
        }
    }

    @MainActor
    private func connectOutputIfNeeded(_ source: AVAudioNode, to destination: AVAudioNode) {
        guard source.engine === audioGraph.engine,
              destination.engine === audioGraph.engine,
              !outputConnectionExists(from: source, to: destination)
        else {
            return
        }

        audioGraph.disconnectOutput(source)
        audioGraph.connect(source, to: destination)
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

extension SamplePlaybackEngine {
    func disconnectFirstPreparedVoiceForTesting(trackID: UUID) {
        performOnMain { [self] in
            lifecycleLock.withLock {
                guard let voice = trackVoicePools[trackID]?.voices.first else { return }
                audioGraph.disconnectOutput(voice)
            }
        }
    }

    func isFirstPreparedVoiceConnectedForTesting(trackID: UUID) -> Bool {
        performOnMain { [self] in
            lifecycleLock.withLock {
                guard let pool = trackVoicePools[trackID],
                      let voice = pool.voices.first,
                      let filter = pool.voiceFilters.first
                else {
                    return false
                }
                return outputConnectionExists(from: voice, to: filter.avNode)
            }
        }
    }

    func disconnectPreparedTrackMixerOutputForTesting(trackID: UUID) {
        performOnMain { [self] in
            lifecycleLock.withLock {
                guard let mixer = trackMixers[trackID] else { return }
                audioGraph.disconnectOutput(mixer)
            }
        }
    }

    func isPreparedTrackMixerOutputConnectedForTesting(trackID: UUID) -> Bool {
        performOnMain { [self] in
            lifecycleLock.withLock {
                guard let mixer = trackMixers[trackID],
                      let filter = trackFilters[trackID]
                else {
                    return false
                }
                return outputConnectionExists(from: mixer, to: filter.avNode)
            }
        }
    }
}

private extension NSLock {
    func withLock<T>(_ work: () -> T) -> T {
        lock()
        defer { unlock() }
        return work()
    }
}
