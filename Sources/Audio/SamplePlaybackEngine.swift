import Foundation
import AVFoundation

struct VoiceHandle: Equatable, Hashable {
    fileprivate let id: UUID
}

/// The two independent mute sources that can gain-mute a track. They are
/// tracked separately and OR-combined so neither clobbers the other.
enum TrackMuteSource: Equatable {
    /// Mixer / channel-strip mute (rides in the document mix state).
    case mixer
    /// Perform-layer mute (toggled by the performance layer overlay).
    case layer
}

protocol SamplePlaybackSink: AnyObject {
    func start() throws
    func stop()
    /// Phase-1 warm engine: stop all sounding voices for a transport STOP without
    /// tearing the underlying audio engine down. The engine keeps running
    /// (outputting silence) so the next transport start is not a cold start and
    /// the render origin stays valid for look-ahead. Only `stop()` (driven by
    /// shutdown / device change / explicit rebuild) stops the engine.
    func stopVoicesKeepingEngineWarm()
    /// Ensures `trackID` has a ready mixer, filter, and voice pool attached to
    /// the engine graph. This is safe to call repeatedly and should happen from
    /// the document apply path before transport ticks can dispatch sample events.
    func prepareTrack(trackID: UUID)
    /// Play a sample on a voice routed to `trackID`'s mixer node.
    /// The track mixer's `outputVolume` and `pan` (controlled via `setTrackMix`) are
    /// what the UI fader writes to — this call does not take a mix level.
    func play(sampleURL: URL, settings: SamplerSettings, trackID: UUID, at when: AVAudioTime?) -> VoiceHandle?
    func play(sampleAsset: PreparedSampleAsset, settings: SamplerSettings, trackID: UUID, at when: AVAudioTime?) -> VoiceHandle?
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
    func playSlice(
        sampleAsset: PreparedSampleAsset,
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
    /// Apply track mute as a ramped GAIN change (voices keep playing). Mixer
    /// mute and perform-layer mute both route here so they share one gain
    /// mechanism, but they are tracked as SEPARATE sources and OR-combined so
    /// one cannot clobber the other. Safe off-main (only writes `outputVolume`).
    func setTrackMuteGain(trackID: UUID, muted: Bool, source: TrackMuteSource)
    /// Apply the track's scene-membership crossfade gain (selective scene
    /// inputs, roadmap 25) as a ramped GAIN change on the same per-track gain
    /// stage mute rides — never a hard-cut (Hard Rule 5). Multiplies with the
    /// fader level; the configured Send A/B levels are untouched.
    func setTrackSceneGain(trackID: UUID, gain: Double)
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
    /// Default: a sink with no separate warm-stop path falls back to a full
    /// `stop()`. Sinks that own a real audio engine (`SamplePlaybackEngine`)
    /// override this to stop voices while leaving the engine running.
    func stopVoicesKeepingEngineWarm() {
        stop()
    }

    func prepareTrack(trackID: UUID) {}

    func setTrackOutputBus(trackID: UUID, busID: UUID?) {}

    func setTrackSends(trackID: UUID, sendA: Double, sendB: Double) {}

    func setTrackMuteGain(trackID: UUID, muted: Bool, source: TrackMuteSource) {}

    func setTrackSceneGain(trackID: UUID, gain: Double) {}

    /// Convenience for callers (e.g. tests) that exercise a single mute source.
    func setTrackMuteGain(trackID: UUID, muted: Bool) {
        setTrackMuteGain(trackID: trackID, muted: muted, source: .mixer)
    }

    func play(sampleAsset: PreparedSampleAsset, settings: SamplerSettings, trackID: UUID, at when: AVAudioTime?) -> VoiceHandle? {
        play(sampleURL: sampleAsset.url, settings: settings, trackID: trackID, at: when)
    }

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

    func playSlice(
        sampleAsset: PreparedSampleAsset,
        startFrame: AVAudioFramePosition,
        endFrame: AVAudioFramePosition,
        settings: SlicerSettings,
        trackID: UUID,
        at when: AVAudioTime?,
        reverse: Bool,
        stepParameters: SliceTriggerStepParameters?
    ) -> VoiceHandle? {
        playSlice(
            sampleURL: sampleAsset.url,
            startFrame: startFrame,
            endFrame: endFrame,
            settings: settings,
            trackID: trackID,
            at: when,
            reverse: reverse,
            stepParameters: stepParameters
        )
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

    private struct BusVoicePool {
        var voices: [AVAudioPlayerNode]
        var voiceMixers: [AVAudioMixerNode]
        /// Per-track summing node: every voice mixer feeds this single node,
        /// which is the track's OWN output (pre-bus). It connects to the bus
        /// input mixer (one input per track, not one per voice — also avoids the
        /// per-voice bus-input collision), and it is registered as the track's
        /// meter source so the SOURCE track keeps metering its own level even
        /// when routed to a bus (#62). The bus meters the sum of these.
        var trackSumMixer: AVAudioMixerNode
        var handles: [UUID]
        var cursor: Int
    }

    private final class SamplerFilterFanout: SamplerFilterControlling {
        private let lock = NSLock()
        private var targets: [SamplerFilterNode] = []

        func setTargets(_ targets: [SamplerFilterNode]) {
            lock.withLock {
                self.targets = targets
            }
        }

        func apply(_ settings: SamplerFilterSettings) {
            for target in snapshotTargets() {
                target.apply(settings)
            }
        }

        func setType(_ type: SamplerFilterType) {
            for target in snapshotTargets() {
                target.setType(type)
            }
        }

        func setPoles(_ poles: SamplerFilterPoles) {
            for target in snapshotTargets() {
                target.setPoles(poles)
            }
        }

        func setCutoff(hz: Double) {
            for target in snapshotTargets() {
                target.setCutoff(hz: hz)
            }
        }

        func setResonance(_ normalized: Double) {
            for target in snapshotTargets() {
                target.setResonance(normalized)
            }
        }

        func setDrive(_ normalized: Double) {
            for target in snapshotTargets() {
                target.setDrive(normalized)
            }
        }

        private func snapshotTargets() -> [SamplerFilterNode] {
            lock.withLock { targets }
        }
    }

    private static let voicesPerTrack = 4
    private let audioGraph: MainAudioGraph
    private let previewNode = AVAudioPlayerNode()
    private let lifecycleLock = NSLock()
    /// Serializes player scheduling with stop/disconnect/detach. Readiness flags
    /// prevent new selections during a rebuild, but a tick may already have
    /// selected a voice before the flag is withdrawn. This lock closes that
    /// final command-lifetime window; it is never taken by the render callback.
    private let playerCommandLock = NSRecursiveLock()
    private let residentTriggerBufferCacheLock = NSLock()
    private static let residentTriggerBufferCacheBudgetBytes = 32 * 1_024 * 1_024
    private static let residentTriggerBufferCacheEntryLimit = 256
    private struct ResidentTriggerBufferKey: Hashable {
        let sourceID: ObjectIdentifier
        let startFrame: AVAudioFramePosition
        let frameCount: AVAudioFrameCount
        let sampleRateBits: UInt64
        let channelCount: AVAudioChannelCount
        let commonFormat: UInt
        let interleaved: Bool
        let reverse: Bool
        let attackBits: UInt64
        let releaseBits: UInt64
    }
    private struct ResidentTriggerBufferCacheEntry {
        let source: AVAudioPCMBuffer
        let buffer: AVAudioPCMBuffer
        let byteSize: Int
    }
    private var residentTriggerBufferCache: [ResidentTriggerBufferKey: ResidentTriggerBufferCacheEntry] = [:]
    private var residentTriggerBufferCacheOrder: [ResidentTriggerBufferKey] = []
    private var residentTriggerBufferCacheBytes = 0
    private var fileCache: [URL: AVAudioFile] = [:]
    private var isStarted = false
    private var trackVoicePools: [UUID: TrackVoicePool] = [:]
    private var busVoicePools: [UUID: BusVoicePool] = [:]
    private var trackMixers: [UUID: AVAudioMixerNode] = [:]
    /// Per-track filter nodes inserted between the track mixer and the main mixer.
    private var trackFilters: [UUID: SamplerFilterNode] = [:]
    private var trackFilterFanouts: [UUID: SamplerFilterFanout] = [:]
    private var trackMixValues: [UUID: (level: Float, pan: Float)] = [:]
    /// Per-track mute applied as GAIN (ramped), separate from the fader level so
    /// unmute restores the user's level. `effectiveLevel` = muted ? 0 : level.
    ///
    /// Mixer-mute and perform-layer mute are INDEPENDENT sources tracked
    /// SEPARATELY (`mixerMutedTrackIDs` + `layerMutedTrackIDs`) and OR-combined:
    /// a track is gain-muted while EITHER source mutes it. A single shared flag
    /// would let one source clobber the other (last-writer-wins), so e.g.
    /// mixer-mute then layer-mute+unmute would un-silence a mixer-muted track.
    private var mixerMutedTrackIDs: Set<UUID> = []
    private var layerMutedTrackIDs: Set<UUID> = []
    /// Per-track scene-membership crossfade gain (selective scene inputs,
    /// roadmap 25), multiplied with the fader level on the same gain stage
    /// mute rides. Absent = 1 (member of both scenes / no A/B crossfade).
    /// Effective volume = muted ? 0 : level * sceneGain.
    private var trackSceneGains: [UUID: Float] = [:]
    private var trackOutputBusIDs: [UUID: UUID] = [:]
    private var trackSendLevels: [UUID: MainAudioGraph.TrackSendLevels] = [:]
    private var fastPathReadyTrackIDs: Set<UUID> = []
    private var deferredPreparedTrackRepairIDs: Set<UUID> = []
    /// Per-track count of how many times the bounded last-resort self-heal
    /// backstop (`deferPreparedTrackRepair` → `repairDeferredPreparedTrackIfNeeded`)
    /// has fired for the track's CURRENT deferral episode. Reset to 0 whenever a
    /// track is successfully (re)published fast-path-ready (a healthy prepare /
    /// repair / route), so a normal track never accumulates. Capped at
    /// `maxDeferredRepairAttempts`: a genuinely-unconnectable track logs once and
    /// STOPS scheduling heals so it can never oscillate and pin the main thread.
    private var deferredPreparedTrackRepairAttempts: [UUID: Int] = [:]
    /// Hard cap on the bounded self-heal backstop (see
    /// `deferredPreparedTrackRepairAttempts`). After the gate fix the steady
    /// state is ~0 defers, so this only ever trips for a genuinely-broken track.
    private static let maxDeferredRepairAttempts = 3
    /// Per-track, per-kind voice params. Applied at voice scheduling time (next trigger).
    private var voiceParams: [UUID: [BuiltinMacroKind: Double]] = [:]
    #if DEBUG
    private(set) var voiceSelectionsForTesting: [(trackID: UUID, voiceMode: SlicerVoiceMode, voiceIndex: Int, stoppedPriorVoice: Bool)] = []
    /// Number of times a sample-track teardown took the ramp-to-silence path
    /// (one or more sounding chokepoint mixers faded out before detach). Mirrors
    /// `MainAudioGraph.rampedReconnectCountForTesting` — lets a test assert that
    /// `removeTrack` / route-switch teardown of a sounding track does NOT
    /// hard-cut (Hard Rule 5).
    private(set) var sampleTeardownRampCountForTesting = 0
    /// Number of times a sample-track ROUTE SWITCH (bus↔master) ramped the
    /// OUTGOING route's sounding chokepoint to silence before tearing it down and
    /// building the incoming route. Lets a test assert that a route switch of a
    /// sounding track crossfades (Hard Rule 5) rather than hard-cutting.
    private(set) var sampleRouteCrossfadeCountForTesting = 0
    /// Number of triggered voices scheduled via a RESIDENT `AVAudioPCMBuffer`
    /// (`scheduleBuffer`) — the warm-from-RAM path that Hard Rule 4 mandates for
    /// every trigger. A default forward slice / one-shot MUST land here.
    private(set) var residentBufferScheduleCountForTesting = 0
    /// Number of triggered voices that fell back to streaming a file segment
    /// (`scheduleSegment(file:)`) because no resident buffer was available.
    /// This is reserved for legacy URL playback and assets that exceed the
    /// resident working-set budget. Lets tests assert the resident path remains
    /// the default for normal prepared samples.
    private(set) var fileSegmentScheduleCountForTesting = 0
    private(set) var residentTriggerBufferBuildCountForTesting = 0
    #endif

    var preparedTrackIDs: Set<UUID> {
        withLifecycleLock {
            Set(trackVoicePools.keys).union(busVoicePools.keys)
        }
    }

    #if DEBUG
    var deferredPreparedTrackRepairIDsForTesting: Set<UUID> {
        withLifecycleLock { deferredPreparedTrackRepairIDs }
    }
    #endif

    init(audioGraph: MainAudioGraph = MainAudioGraph()) {
        self.audioGraph = audioGraph
        // realtime-allow-graph-mutation: constructor preview wiring only, not tick dispatch. Test: RealtimePathLintTests.
        audioGraph.attach(previewNode)
        // realtime-allow-graph-mutation: constructor preview wiring only, not tick dispatch. Test: RealtimePathLintTests.
        audioGraph.connect(previewNode, to: audioGraph.preMasterMixer)
        // realtime-allow-graph-mutation: constructor graph preparation only, not tick dispatch. Test: RealtimePathLintTests.
        audioGraph.engine.prepare()
    }

    func start() throws {
        guard withLifecycleLock({ !isStarted }) else { return }
        validatePreparedTrackGraphs()
        withLifecycleLock {
            isStarted = true
        }
    }

    func stop() {
        let (shouldStop, pools, busPools) = withLifecycleLock { () -> (Bool, [TrackVoicePool], [BusVoicePool]) in
            guard isStarted else { return (false, [], []) }
            isStarted = false
            return (true, Array(trackVoicePools.values), Array(busVoicePools.values))
        }
        guard shouldStop else { return }
        withPlayerCommandLock {
            for pool in pools {
                for voice in pool.voices {
                    voice.stop()
                }
            }
            for pool in busPools {
                for voice in pool.voices {
                    voice.stop()
                }
            }
            previewNode.stop()
        }
    }

    /// Phase-1 warm engine: silence all voices for a transport stop but leave the
    /// underlying `AVAudioEngine` running. `isStarted` stays true so the engine
    /// is treated as warm and the next transport start reuses the live graph (no
    /// cold-start render-origin gap). The engine is only torn down by `stop()`
    /// (shutdown / device change / explicit rebuild).
    func stopVoicesKeepingEngineWarm() {
        let (pools, busPools) = withLifecycleLock { () -> ([TrackVoicePool], [BusVoicePool]) in
            guard isStarted else { return ([], []) }
            return (Array(trackVoicePools.values), Array(busVoicePools.values))
        }
        withPlayerCommandLock {
            for pool in pools {
                for voice in pool.voices {
                    voice.stop()
                }
            }
            for pool in busPools {
                for voice in pool.voices {
                    voice.stop()
                }
            }
            previewNode.stop()
        }
    }

    func prepareTrack(trackID: UUID) {
        performOnMain { [self] in
            // Snapshot the routing decision + existing pool under the lock;
            // the heavy graph construction below runs WITHOUT the lock (the
            // setup/repair helpers take it internally for their dictionary
            // touches). This is the deadlock-class fix: the tick path, which
            // takes lifecycleLock every tick, never contends with a live
            // engine reconfiguration.
            let (busID, existingPool): (UUID?, TrackVoicePool?) = withLifecycleLock {
                (trackOutputBusIDs[trackID], trackVoicePools[trackID])
            }

            if let busID, audioGraph.mixerBusReadoutForTesting(busID: busID) != nil {
                prepareBusVoicePool(trackID: trackID, busID: busID)
                // Fast-path gate: publish only after the bus chain is validated.
                if let pool = withLifecycleLock({ busVoicePools[trackID] }) {
                    publishBusTrackFastPathIfConnected(trackID: trackID, busID: busID, pool: pool)
                }
                return
            }
            if let existingPool {
                if !isPreparedTrackPoolReadyForPlayback(trackID: trackID, pool: existingPool) {
                    // repairPreparedTrackGraph republishes through the gate itself.
                    repairPreparedTrackGraph(trackID: trackID, pool: existingPool)
                } else {
                    // Already fully connected — publish through the gate.
                    publishPreparedTrackFastPathIfConnected(trackID: trackID, pool: existingPool)
                }
                return
            }

            _ = trackMixer(for: trackID)
            var voices: [AVAudioPlayerNode] = []
            var voiceFilters: [SamplerFilterNode] = []
            var handles: [UUID] = []

            for _ in 0..<Self.voicesPerTrack {
                let voice = AVAudioPlayerNode()
                let voiceFilter = SamplerFilterNode()
                // realtime-allow-graph-mutation: prepared track setup occurs during document apply/setup, not tick dispatch. Test: RealtimePathLintTests.
                audioGraph.attach(voice)
                // realtime-allow-graph-mutation: prepared track setup occurs during document apply/setup, not tick dispatch. Test: RealtimePathLintTests.
                audioGraph.attach(voiceFilter.avNode)
                voices.append(voice)
                voiceFilters.append(voiceFilter)
                handles.append(UUID())
            }

            let pool = TrackVoicePool(
                voices: voices,
                voiceFilters: voiceFilters,
                handles: handles,
                cursor: 0
            )
            withLifecycleLock {
                trackVoicePools[trackID] = pool
            }
            // repairPreparedTrackGraph wires the chain and republishes through the
            // fast-path gate (validated-connected) itself.
            repairPreparedTrackGraph(trackID: trackID, pool: pool)
        }
    }

    @discardableResult
    func play(sampleURL: URL, settings: SamplerSettings, trackID: UUID, at when: AVAudioTime? = nil) -> VoiceHandle? {
        guard withLifecycleLock({ isStarted }) else { return nil }
        guard let file = cachedFile(url: sampleURL) else { return nil }
        // URL-only path (audition / tests) has no resident PCM buffer; the live
        // trigger path always routes through `play(sampleAsset:)` below, which
        // carries the warmed buffer.
        return playPreparedSample(file: file, pcmBuffer: nil, sampleURL: sampleURL, settings: settings, trackID: trackID, at: when)
    }

    @discardableResult
    func play(sampleAsset: PreparedSampleAsset, settings: SamplerSettings, trackID: UUID, at when: AVAudioTime? = nil) -> VoiceHandle? {
        guard withLifecycleLock({ isStarted }) else { return nil }
        return playPreparedSample(
            file: sampleAsset.file,
            pcmBuffer: sampleAsset.pcmBuffer,
            sampleURL: sampleAsset.url,
            settings: settings,
            trackID: trackID,
            at: when
        )
    }

    private func playPreparedSample(
        file: AVAudioFile,
        pcmBuffer: AVAudioPCMBuffer?,
        sampleURL: URL,
        settings: SamplerSettings,
        trackID: UUID,
        at when: AVAudioTime?
    ) -> VoiceHandle? {
        if withLifecycleLock({ busVoicePools[trackID] != nil }) {
            return playPreparedBusSample(
                file: file,
                pcmBuffer: pcmBuffer,
                sampleURL: sampleURL,
                settings: settings,
                trackID: trackID,
                at: when
            )
        }
        let scheduled = when.map { AVAudioTime.seconds(forHostTime: $0.hostTime) }
        return playWithPreparedVoice(trackID: trackID, voiceMode: .polyphonic, scheduled: scheduled) { [self] voice, voiceFilter, params in
            let effectiveWhen = Self.effectivePlaybackTime(for: when)
            let actual = ProcessInfo.processInfo.systemUptime
            let frameRange = Self.sampleFrameRange(file: file, settings: settings, params: params)
            SequencerTimingProbe.sampleSchedule(
                trackID: trackID,
                file: sampleURL.lastPathComponent,
                scheduled: scheduled,
                actual: actual,
                mode: effectiveWhen == nil ? "immediate" : "scheduled",
                start: params?[.sampleStart] ?? settings.start,
                length: params?[.sampleLength] ?? settings.length,
                gain: params?[.sampleGain] ?? settings.gain,
                startFrame: Int64(frameRange.startFrame),
                endFrame: Int64(frameRange.startFrame + AVAudioFramePosition(frameRange.frameLength))
            )
            SampleTriggerTrace.schedule(
                trackID: trackID,
                sampleURL: sampleURL,
                scheduledHostTime: when.map { AVAudioTime.seconds(forHostTime: $0.hostTime) },
                mode: effectiveWhen == nil ? "immediate" : "scheduled"
            )
            return self.scheduleAndStart(
                voice,
                voiceFilter: self.trackOutputBusIDs[trackID] == nil ? voiceFilter : nil,
                file: file,
                pcmBuffer: pcmBuffer,
                settings: settings,
                params: params,
                at: effectiveWhen
            )
        }
    }

    private func playPreparedBusSample(
        file: AVAudioFile,
        pcmBuffer: AVAudioPCMBuffer?,
        sampleURL: URL,
        settings: SamplerSettings,
        trackID: UUID,
        at when: AVAudioTime?
    ) -> VoiceHandle? {
        let scheduled = when.map { AVAudioTime.seconds(forHostTime: $0.hostTime) }
        let effectiveWhen = Self.effectivePlaybackTime(for: when)
        let actual = ProcessInfo.processInfo.systemUptime
        let frameRange = Self.sampleFrameRange(file: file, settings: settings, params: nil)
        SequencerTimingProbe.sampleSchedule(
            trackID: trackID,
            file: sampleURL.lastPathComponent,
            scheduled: scheduled,
            actual: actual,
            mode: effectiveWhen == nil ? "immediate" : "scheduled",
            start: settings.start,
            length: settings.length,
            gain: settings.gain,
            startFrame: Int64(frameRange.startFrame),
            endFrame: Int64(frameRange.startFrame + AVAudioFramePosition(frameRange.frameLength))
        )
        SampleTriggerTrace.schedule(
            trackID: trackID,
            sampleURL: sampleURL,
            scheduledHostTime: scheduled,
            mode: effectiveWhen == nil ? "immediate" : "scheduled"
        )

        var selectedVoice: AVAudioPlayerNode?
        var handleID: UUID?
        withLifecycleLock {
            guard var pool = busVoicePools[trackID],
                  !pool.voices.isEmpty
            else {
                return
            }
            let index = pool.cursor % pool.voices.count
            selectedVoice = pool.voices[index]
            let nextHandle = UUID()
            pool.handles[index] = nextHandle
            pool.cursor = (index &+ 1) % pool.voices.count
            busVoicePools[trackID] = pool
            handleID = nextHandle
            #if DEBUG
            voiceSelectionsForTesting.append((
                trackID: trackID,
                voiceMode: .polyphonic,
                voiceIndex: index,
                stoppedPriorVoice: false
            ))
            #endif
            SequencerTimingProbe.voiceSelected(
                trackID: trackID,
                voiceMode: SlicerVoiceMode.polyphonic.rawValue,
                voiceIndex: index,
                stoppedPriorVoice: false
            )
        }

        guard let voice = selectedVoice,
              let handleID
        else {
            SequencerTimingProbe.sampleFastPath(
                trackID: trackID,
                scheduled: scheduled,
                actual: ProcessInfo.processInfo.systemUptime,
                result: "unprepared"
            )
            return nil
        }

        let didSchedule = withPlayerCommandLock {
            guard scheduleResidentOrFileSegment(
                voice,
                file: file,
                pcmBuffer: pcmBuffer,
                startFrame: frameRange.startFrame,
                frameCount: frameRange.frameLength,
                transforms: nil,
                playbackFormat: voice.outputFormat(forBus: 0),
                at: effectiveWhen
            ) else {
                return false
            }
            return ensureVoiceStartedSafely(voice)
        }
        guard didSchedule else {
            deferPreparedTrackRepair(trackID: trackID, scheduled: scheduled)
            SequencerTimingProbe.sampleFastPath(
                trackID: trackID,
                scheduled: scheduled,
                actual: ProcessInfo.processInfo.systemUptime,
                result: "schedule-failed"
            )
            return nil
        }
        SequencerTimingProbe.sampleFastPath(
            trackID: trackID,
            scheduled: scheduled,
            actual: ProcessInfo.processInfo.systemUptime,
            result: "scheduled"
        )
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
        reverse: Bool = false,
        stepParameters: SliceTriggerStepParameters? = nil
    ) -> VoiceHandle? {
        guard withLifecycleLock({ isStarted }) else { return nil }
        guard let file = cachedFile(url: sampleURL) else { return nil }
        return playPreparedSlice(
            file: file,
            pcmBuffer: nil,
            sampleURL: sampleURL,
            startFrame: startFrame,
            endFrame: endFrame,
            settings: settings,
            trackID: trackID,
            at: when,
            reverse: reverse,
            stepParameters: stepParameters
        )
    }

    @discardableResult
    func playSlice(
        sampleAsset: PreparedSampleAsset,
        startFrame: AVAudioFramePosition,
        endFrame: AVAudioFramePosition,
        settings: SlicerSettings,
        trackID: UUID,
        at when: AVAudioTime? = nil,
        reverse: Bool = false,
        stepParameters: SliceTriggerStepParameters? = nil
    ) -> VoiceHandle? {
        guard withLifecycleLock({ isStarted }) else { return nil }
        return playPreparedSlice(
            file: sampleAsset.file,
            pcmBuffer: sampleAsset.pcmBuffer,
            sampleURL: sampleAsset.url,
            startFrame: startFrame,
            endFrame: endFrame,
            settings: settings,
            trackID: trackID,
            at: when,
            reverse: reverse,
            stepParameters: stepParameters
        )
    }

    private func playPreparedSlice(
        file: AVAudioFile,
        pcmBuffer: AVAudioPCMBuffer?,
        sampleURL: URL,
        startFrame: AVAudioFramePosition,
        endFrame: AVAudioFramePosition,
        settings: SlicerSettings,
        trackID: UUID,
        at when: AVAudioTime?,
        reverse: Bool,
        stepParameters: SliceTriggerStepParameters?
    ) -> VoiceHandle? {
        let clampedSettings = settings.clamped
        let sliceParameters = (stepParameters ?? .default).clamped
        let resolvedStart = max(0, min(startFrame, max(file.length - 1, 0)))
        let resolvedEnd = max(resolvedStart + 1, min(endFrame, file.length))
        guard resolvedEnd > resolvedStart else { return nil }

        let scheduled = when.map { AVAudioTime.seconds(forHostTime: $0.hostTime) }
        return playWithPreparedVoice(trackID: trackID, voiceMode: clampedSettings.voiceMode, scheduled: scheduled) { [self] voice, voiceFilter, params in
            let effectiveWhen = Self.effectivePlaybackTime(for: when)
            let actual = ProcessInfo.processInfo.systemUptime
            SequencerTimingProbe.sliceSchedule(
                trackID: trackID,
                file: sampleURL.lastPathComponent,
                scheduled: scheduled,
                actual: actual,
                mode: effectiveWhen == nil ? "immediate" : "scheduled",
                startFrame: Int64(resolvedStart),
                endFrame: Int64(resolvedEnd),
                voiceMode: clampedSettings.voiceMode.rawValue,
                reverse: reverse,
                choke: sliceParameters.choke
            )
            SampleTriggerTrace.schedule(
                trackID: trackID,
                sampleURL: sampleURL,
                scheduledHostTime: when.map { AVAudioTime.seconds(forHostTime: $0.hostTime) },
                mode: effectiveWhen == nil ? "immediate" : "scheduled"
            )
            return self.scheduleAndStartSlice(
                voice,
                voiceFilter: self.trackOutputBusIDs[trackID] == nil ? voiceFilter : nil,
                sampleURL: sampleURL,
                file: file,
                pcmBuffer: pcmBuffer,
                startFrame: resolvedStart,
                endFrame: resolvedEnd,
                settings: clampedSettings,
                params: params,
                at: effectiveWhen,
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
    private func startVoiceSafely(_ voice: AVAudioPlayerNode, at when: AVAudioTime? = nil) -> Bool {
        guard canIssuePlayerNodeCommand(voice, operation: "play") else { return false }
        if let exception = SEQRunCatchingObjCException({
            if let when {
                voice.play(at: when)
            } else {
                voice.play()
            }
        }) {
            DevActivity.trace(DevActivity.audioGraph, "dropped sample trigger: play threw \(exception.name.rawValue): \(exception.reason ?? "no reason")")
            return false
        }
        return true
    }

    private func ensureVoiceStartedSafely(_ voice: AVAudioPlayerNode) -> Bool {
        voice.isPlaying || startVoiceSafely(voice)
    }

    private func withPlayerCommandLock<T>(_ body: () throws -> T) rethrows -> T {
        playerCommandLock.lock()
        defer { playerCommandLock.unlock() }
        return try body()
    }

    private func canIssuePlayerNodeCommand(_ voice: AVAudioPlayerNode, operation: String) -> Bool {
        guard audioGraph.isNodePlayableNow(voice) else { return false }
        guard audioGraph.renderPosition != nil else {
            DevActivity.trace(DevActivity.audioGraph, "dropped sample trigger: \(operation) before valid render position")
            return false
        }
        return true
    }

    /// Per-trigger transforms applied to the resident sub-range buffer (reverse,
    /// attack/release envelope). Run on the RAM buffer copy, never on a streamed
    /// file. `nil` means "no transform" (the common forward, no-envelope case).
    private struct SliceBufferTransforms {
        var reverse: Bool
        var attackMs: Double
        var releaseMs: Double

        var isIdentity: Bool {
            !reverse && attackMs <= 0 && releaseMs <= 0
        }
    }

    private func scheduleAndStart(
        _ voice: AVAudioPlayerNode,
        voiceFilter: SamplerFilterNode?,
        file: AVAudioFile,
        pcmBuffer: AVAudioPCMBuffer?,
        settings: SamplerSettings,
        params: [BuiltinMacroKind: Double]?,
        at when: AVAudioTime?
    ) -> Bool {
        withPlayerCommandLock {
            if let voiceFilter {
                // Apply built-in macro voice params (set by TrackMacroApplier for the current step).
                let gainDB = params?[.sampleGain] ?? settings.gain
                voice.volume = linearGain(dB: gainDB)
                voice.pan = 0
                voice.rate = 1
                voiceFilter.apply(SamplerFilterSettings())
            }

            // Hard Rule 4: triggered playback reads the RESIDENT PCM buffer.
            let frameRange = Self.sampleFrameRange(file: file, settings: settings, params: params)
            guard scheduleResidentOrFileSegment(
                voice,
                file: file,
                pcmBuffer: pcmBuffer,
                startFrame: frameRange.startFrame,
                frameCount: frameRange.frameLength,
                transforms: nil,
                playbackFormat: voice.outputFormat(forBus: 0),
                at: when
            ) else {
                return false
            }
            return ensureVoiceStartedSafely(voice)
        }
    }

    private func scheduleAndStartSlice(
        _ voice: AVAudioPlayerNode,
        voiceFilter: SamplerFilterNode?,
        sampleURL: URL,
        file: AVAudioFile,
        pcmBuffer: AVAudioPCMBuffer?,
        startFrame: AVAudioFramePosition,
        endFrame: AVAudioFramePosition,
        settings: SlicerSettings,
        params: [BuiltinMacroKind: Double]?,
        at when: AVAudioTime?,
        reverse: Bool,
        sliceParameters: SliceTriggerStepParameters
    ) -> Bool {
        withPlayerCommandLock {
            if let voiceFilter {
                let gainDB = params?[.sampleGain] ?? settings.gain
                voice.volume = linearGain(dB: gainDB)
                voice.pan = Float(sliceParameters.pan)
                voice.rate = Float(playbackRate(forSemitoneOffset: settings.transpose))
                voiceFilter.setCutoff(hz: cutoffHz(for: sliceParameters.filter))
            }

            // Hard Rule 4: all slice triggers use the resident sub-range buffer.
            let transforms = SliceBufferTransforms(
                reverse: reverse,
                attackMs: sliceParameters.attackMs,
                releaseMs: sliceParameters.releaseMs
            )
            guard scheduleResidentOrFileSegment(
                voice,
                file: file,
                pcmBuffer: pcmBuffer,
                startFrame: startFrame,
                frameCount: AVAudioFrameCount(max(1, endFrame - startFrame)),
                transforms: transforms,
                playbackFormat: voice.outputFormat(forBus: 0),
                at: when
            ) else {
                return false
            }
            return ensureVoiceStartedSafely(voice)
        }
    }

    /// The single trigger-scheduling site. Schedules a RESIDENT `AVAudioPCMBuffer`
    /// (`scheduleBuffer`) for the requested sub-range whenever a warmed
    /// `pcmBuffer` is available — Hard Rule 4's warm-from-RAM default for every
    /// slice / one-shot / drum hit. Per-trigger transforms (reverse, envelope)
    /// are applied to that RAM copy.
    ///
    /// The `scheduleSegment(file:)` branch is the bounded, explicit exception for
    /// a trigger whose source has NO resident buffer: today only the legacy
    /// URL/audition path (`play(sampleURL:)`, `playSlice(sampleURL:)`) and any
    /// asset whose PCM load was skipped or demoted because the audio exceeds the
    /// bounded resident working set — i.e. large/long audio, the case the rule
    /// reserves streaming for.
    private func scheduleResidentOrFileSegment(
        _ voice: AVAudioPlayerNode,
        file: AVAudioFile,
        pcmBuffer: AVAudioPCMBuffer?,
        startFrame: AVAudioFramePosition,
        frameCount: AVAudioFrameCount,
        transforms: SliceBufferTransforms?,
        playbackFormat: AVAudioFormat,
        at when: AVAudioTime?
    ) -> Bool {
        guard canIssuePlayerNodeCommand(voice, operation: "schedule") else { return false }
        if let buffer = residentTriggerBuffer(
            pcmBuffer: pcmBuffer,
            fileFormat: file.processingFormat,
            playbackFormat: playbackFormat,
            startFrame: startFrame,
            frameCount: frameCount,
            transforms: transforms
        ) {
            if let exception = SEQRunCatchingObjCException({
                voice.scheduleBuffer(buffer, at: when, options: .interrupts, completionHandler: nil)
            }) {
                DevActivity.trace(DevActivity.audioGraph, "dropped sample trigger: scheduleBuffer threw \(exception.name.rawValue): \(exception.reason ?? "no reason")")
                return false
            }
            #if DEBUG
            residentBufferScheduleCountForTesting += 1
            #endif
            return true
        }

        voice.stop()
        if let exception = SEQRunCatchingObjCException({
            // realtime-allow-file-stream: bounded large/over-budget or legacy URL fallback only; normal prepared samples take the resident scheduleBuffer branch above. Test: SamplePlaybackEngineResidentBufferTests.
            voice.scheduleSegment(
                file,
                startingFrame: startFrame,
                frameCount: frameCount,
                at: when,
                completionHandler: nil
            )
        }) {
            DevActivity.trace(DevActivity.audioGraph, "dropped sample trigger: scheduleSegment threw \(exception.name.rawValue): \(exception.reason ?? "no reason")")
            return false
        }
        #if DEBUG
        fileSegmentScheduleCountForTesting += 1
        #endif
        return true
    }

    /// Build the resident sub-range buffer for a trigger from the warmed
    /// `pcmBuffer`, applying any per-trigger transforms on the RAM copy. Returns
    /// nil only when there is no resident buffer (forcing the file fallback).
    private func residentTriggerBuffer(
        pcmBuffer: AVAudioPCMBuffer?,
        fileFormat: AVAudioFormat,
        playbackFormat: AVAudioFormat,
        startFrame: AVAudioFramePosition,
        frameCount: AVAudioFrameCount,
        transforms: SliceBufferTransforms?
    ) -> AVAudioPCMBuffer? {
        guard let source = pcmBuffer else { return nil }
        guard startFrame >= 0,
              startFrame < AVAudioFramePosition(source.frameLength)
        else {
            return nil
        }
        let available = AVAudioFrameCount(
            AVAudioFramePosition(source.frameLength) - startFrame
        )
        let clampedCount = max(1, min(frameCount, available))
        let effectiveTransforms = transforms ?? SliceBufferTransforms(
            reverse: false,
            attackMs: 0,
            releaseMs: 0
        )

        // The common one-shot path can schedule the warmed source buffer
        // directly. No sub-range allocation, copy, or format conversion occurs
        // on a trigger.
        if startFrame == 0,
           clampedCount == source.frameLength,
           effectiveTransforms.isIdentity,
           source.format == playbackFormat
        {
            return source
        }

        let key = ResidentTriggerBufferKey(
            sourceID: ObjectIdentifier(source),
            startFrame: startFrame,
            frameCount: clampedCount,
            sampleRateBits: playbackFormat.sampleRate.bitPattern,
            channelCount: playbackFormat.channelCount,
            commonFormat: playbackFormat.commonFormat.rawValue,
            interleaved: playbackFormat.isInterleaved,
            reverse: effectiveTransforms.reverse,
            attackBits: effectiveTransforms.attackMs.bitPattern,
            releaseBits: effectiveTransforms.releaseMs.bitPattern
        )
        if let cached = residentTriggerBufferCacheLock.withLock({
            residentTriggerBufferCache[key]?.buffer
        }) {
            return cached
        }

        guard let buffer = sliceBuffer(
            pcmBuffer: pcmBuffer,
            fileFormat: fileFormat,
            playbackFormat: playbackFormat,
            startFrame: startFrame,
            frameCount: clampedCount
        ) else {
            return nil
        }
        if !effectiveTransforms.isIdentity {
            if effectiveTransforms.reverse {
                Self.reverse(buffer)
            }
            applyEnvelope(
                to: buffer,
                attackMs: effectiveTransforms.attackMs,
                releaseMs: effectiveTransforms.releaseMs
            )
        }
        #if DEBUG
        residentTriggerBufferBuildCountForTesting += 1
        #endif
        cacheResidentTriggerBuffer(buffer, source: source, key: key)
        return buffer
    }

    private func cacheResidentTriggerBuffer(
        _ buffer: AVAudioPCMBuffer,
        source: AVAudioPCMBuffer,
        key: ResidentTriggerBufferKey
    ) {
        let bytesPerFrame = Int(buffer.format.streamDescription.pointee.mBytesPerFrame)
        let channels = buffer.format.isInterleaved ? 1 : Int(buffer.format.channelCount)
        let byteSize = Int(buffer.frameLength) * max(1, bytesPerFrame) * max(1, channels)
        guard byteSize <= Self.residentTriggerBufferCacheBudgetBytes else { return }
        residentTriggerBufferCacheLock.withLock {
            if residentTriggerBufferCache[key] == nil {
                residentTriggerBufferCache[key] = ResidentTriggerBufferCacheEntry(
                    source: source,
                    buffer: buffer,
                    byteSize: byteSize
                )
                residentTriggerBufferCacheOrder.append(key)
                residentTriggerBufferCacheBytes += byteSize
            }
            while (residentTriggerBufferCacheBytes > Self.residentTriggerBufferCacheBudgetBytes ||
                   residentTriggerBufferCache.count > Self.residentTriggerBufferCacheEntryLimit),
                  let oldest = residentTriggerBufferCacheOrder.first
            {
                residentTriggerBufferCacheOrder.removeFirst()
                if let removed = residentTriggerBufferCache.removeValue(forKey: oldest) {
                    residentTriggerBufferCacheBytes -= removed.byteSize
                }
            }
        }
    }

    func stopVoice(_ handle: VoiceHandle) {
        let voice: AVAudioPlayerNode? = withLifecycleLock {
            for pool in trackVoicePools.values {
                guard let index = pool.handles.firstIndex(of: handle.id) else {
                    continue
                }
                return pool.voices[index]
            }
            for pool in busVoicePools.values {
                guard let index = pool.handles.firstIndex(of: handle.id) else {
                    continue
                }
                return pool.voices[index]
            }
            return nil
        }
        if let voice {
            withPlayerCommandLock { voice.stop() }
        }
    }

    func stopAllMainVoices() {
        let (pools, busPools) = withLifecycleLock { (Array(trackVoicePools.values), Array(busVoicePools.values)) }
        withPlayerCommandLock {
            for pool in pools {
                for voice in pool.voices {
                    voice.stop()
                }
            }
            for pool in busPools {
                for voice in pool.voices {
                    voice.stop()
                }
            }
        }
    }

    /// Effective gain-mute for a track: muted while EITHER the mixer source or
    /// the perform-layer source mutes it. Caller MUST hold `lifecycleLock`
    /// (reads the two mute-source sets).
    private func effectiveMuteLocked(_ trackID: UUID) -> Bool {
        mixerMutedTrackIDs.contains(trackID) || layerMutedTrackIDs.contains(trackID)
    }

    /// The track's scene-membership gain (1 when never set). Caller MUST hold
    /// `lifecycleLock`.
    private func sceneGainLocked(_ trackID: UUID) -> Float {
        trackSceneGains[trackID] ?? 1
    }

    /// Set the per-track fader level/pan. `level` is the user's fader value
    /// (NOT pre-zeroed for mute) — mute is applied separately as a ramped gain
    /// via `setTrackMuteGain`, so unmute restores this level. The effective
    /// output volume is `muted ? 0 : level`, applied through a short ramp.
    func setTrackMix(trackID: UUID, level: Double, pan: Double) {
        prepareTrack(trackID: trackID)
        performOnMain { [self] in
            let clampedLevel = Float(min(max(level, 0), 1))
            let clampedPan = Float(min(max(pan, -1), 1))
            // Publish the new mix value and read the target node + mute under
            // the lock; the mixer parameter writes below are node-parameter
            // updates (not graph mutations) and run without the lock.
            let (busPool, mixer, muted, sceneGain): (BusVoicePool?, AVAudioMixerNode?, Bool, Float) = withLifecycleLock {
                trackMixValues[trackID] = (level: clampedLevel, pan: clampedPan)
                let muted = effectiveMuteLocked(trackID)
                let sceneGain = sceneGainLocked(trackID)
                if let pool = busVoicePools[trackID] {
                    return (pool, nil, muted, sceneGain)
                }
                return (nil, trackMixers[trackID], muted, sceneGain)
            }
            let effectiveLevel = muted ? 0 : clampedLevel * sceneGain
            if let busPool {
                applyBusVoiceMix(trackID: trackID, pool: busPool)
                return
            }
            // prepareTrack(trackID:) above guarantees the mixer exists.
            let resolvedMixer = mixer ?? trackMixer(for: trackID)
            // Fader moves snap (no ramp); mute transitions ramp via
            // setTrackMuteGain. Snapping here keeps drag latency-free.
            MixerGainRamp.shared.setImmediate(resolvedMixer, to: effectiveLevel)
            resolvedMixer.pan = clampedPan
        }
    }

    /// Apply track mute/unmute as a ramped GAIN change on the per-track mixer's
    /// `outputVolume` — voices keep playing; a ringing sound is cut/restored
    /// instantly without waiting for the next trigger. Mirrors the bus-mute
    /// shape (`MixerBusHost.applyMix`). Mixer-mute and perform-layer mute both
    /// call this, so they resolve to the same gain mechanism.
    ///
    /// Safe to call from any thread (including the tick path): it only kicks a
    /// ramp that writes `outputVolume` (a node-parameter write, not a graph
    /// mutation) and never holds `lifecycleLock` across engine work.
    func setTrackMuteGain(trackID: UUID, muted: Bool, source: TrackMuteSource) {
        let (busPool, mixer, filter, sendLevels, level, effectiveMuted): (
            BusVoicePool?, AVAudioMixerNode?, SamplerFilterNode?, MainAudioGraph.TrackSendLevels, Float, Bool
        ) = withLifecycleLock {
            // Record THIS source independently; effective mute is mixer || layer
            // so neither source clobbers the other (last-writer-wins bug).
            switch source {
            case .mixer:
                if muted { mixerMutedTrackIDs.insert(trackID) } else { mixerMutedTrackIDs.remove(trackID) }
            case .layer:
                if muted { layerMutedTrackIDs.insert(trackID) } else { layerMutedTrackIDs.remove(trackID) }
            }
            let effective = effectiveMuteLocked(trackID)
            let level = (trackMixValues[trackID]?.level ?? 1) * sceneGainLocked(trackID)
            let configuredSends = trackSendLevels[trackID] ?? .zero
            if let pool = busVoicePools[trackID] {
                return (pool, nil, nil, configuredSends, level, effective)
            }
            return (nil, trackMixers[trackID], trackFilters[trackID], configuredSends, level, effective)
        }
        let target: Float = effectiveMuted ? 0 : level
        if let busPool {
            // The track fader/mute lives on the per-track sum node (the track's
            // own output); ramp it, not the unity voice mixers. Bus-routed tracks
            // have no per-track send fanout (sends come from the bus), so muting
            // the sum node already silences everything the track feeds the bus.
            MixerGainRamp.shared.ramp(busPool.trackSumMixer, to: target)
            return
        }
        guard let mixer else { return }
        MixerGainRamp.shared.ramp(mixer, to: target)
        // #58: a master-routed track's Send A/B legs tap the fanout (downstream
        // of `mixer` but carrying their own configured gain). Re-ramp the
        // send-leg gains gated by effective mute so a muted track sends 0 to
        // both send buses; unmute restores the configured send levels. This uses
        // the TICK-SAFE ramp (no main hop, no graph mutation) — setTrackMuteGain
        // is called from the tick path by the perform-layer mute, so it must NOT
        // go through setTrackSendLevels (which synchronously hops to main).
        if let filter {
            let effective = effectiveMuted ? MainAudioGraph.TrackSendLevels.zero : sendLevels
            audioGraph.rampExistingTrackSendLegsForMute(
                filter.avNode,
                sendA: effective.sendA,
                sendB: effective.sendB
            )
        }
    }

    /// Apply the track's scene-membership crossfade gain as a ramped GAIN
    /// change on the same per-track gain stage mute rides (selective scene
    /// inputs, roadmap 25). Membership flips while the track is sounding are
    /// full-scale jumps (e.g. 1 -> 0 at a crossfader extreme), so they must
    /// ramp — never ride the snapping fader path (Hard Rule 5). Mirrors the
    /// `setTrackMuteGain` shape: publish under the lock, ramp without it.
    /// Send A/B configured levels are deliberately untouched (the Send A/B
    /// contract is byte-identical with scenes — 353829be).
    func setTrackSceneGain(trackID: UUID, gain: Double) {
        let clamped: Float = gain.isFinite ? Float(min(max(gain, 0), 1)) : 1
        let (busPool, mixer, level, effectiveMuted, changed): (
            BusVoicePool?, AVAudioMixerNode?, Float, Bool, Bool
        ) = withLifecycleLock {
            let previous = sceneGainLocked(trackID)
            trackSceneGains[trackID] = clamped
            let changed = previous != clamped
            let level = trackMixValues[trackID]?.level ?? 1
            let muted = effectiveMuteLocked(trackID)
            if let pool = busVoicePools[trackID] {
                return (pool, nil, level, muted, changed)
            }
            return (nil, trackMixers[trackID], level, muted, changed)
        }
        guard changed else { return }
        let target: Float = effectiveMuted ? 0 : level * clamped
        if let busPool {
            // Same node the fader/mute own for bus-routed tracks: the per-track
            // sum mixer (the track's output into the bus).
            MixerGainRamp.shared.ramp(busPool.trackSumMixer, to: target)
            return
        }
        guard let mixer else { return }
        MixerGainRamp.shared.ramp(mixer, to: target)
    }

    func setTrackOutputBus(trackID: UUID, busID: UUID?) {
        performOnMain { [self] in
            // Decide the branch and capture references under the lock; the
            // chosen graph mutation runs WITHOUT the lock so it can't stall
            // the tick path (which takes lifecycleLock each tick).
            enum Branch {
                case prepareBus(UUID)
                case teardownBus(BusVoicePool)
                case repairTrack(TrackVoicePool)
                case wireFilterOutput(SamplerFilterNode, UUID?, MainAudioGraph.TrackSendLevels)
                case none
            }
            let useBus = busID != nil && audioGraph.mixerBusReadoutForTesting(busID: busID!) != nil
            let branch: Branch = withLifecycleLock {
                trackOutputBusIDs[trackID] = busID
                // Fast-path GATE: drop the track from fast-path-ready BEFORE the
                // teardown/disconnect/reconnect window of EVERY rebuild branch, so
                // a concurrent tick-thread `play()` can never select a voice while
                // its output chain is mid-rebuild. Each branch re-publishes only
                // after validating the new connection (publish*FastPathIfConnected).
                if useBus, let busID {
                    _ = fastPathReadyTrackIDs.remove(trackID)
                    return .prepareBus(busID)
                } else if let pool = busVoicePools.removeValue(forKey: trackID) {
                    _ = fastPathReadyTrackIDs.remove(trackID)
                    return .teardownBus(pool)
                } else if let pool = trackVoicePools[trackID] {
                    _ = fastPathReadyTrackIDs.remove(trackID)
                    return .repairTrack(pool)
                } else if let filter = trackFilters[trackID] {
                    _ = fastPathReadyTrackIDs.remove(trackID)
                    return .wireFilterOutput(filter, busID, trackSendLevels[trackID] ?? .zero)
                }
                return .none
            }

            switch branch {
            case let .prepareBus(busID):
                prepareBusVoicePool(trackID: trackID, busID: busID, liveRouteSwitch: true)
                if let pool = withLifecycleLock({ busVoicePools[trackID] }) {
                    publishBusTrackFastPathIfConnected(trackID: trackID, busID: busID, pool: pool)
                }
            case let .teardownBus(pool):
                // Routing a bus-routed track back to master: tear down the bus
                // voice pool, then re-establish the track's MASTER voice pool so
                // it keeps sounding on the new destination. Without this rebuild
                // the track is left with no playable voices on either path and
                // goes permanently silent. `prepareTrack` runs the heavy graph
                // construction without holding `lifecycleLock` (it captures refs
                // under the lock, mutates after — same leaf-lock invariant), and
                // because `trackOutputBusIDs[trackID]` was just set to nil above,
                // it rebuilds the prepared master pool rather than a bus pool.
                // `prepareTrack` republishes fast-path through the gate itself.
                //
                // CLICK FIX (Hard Rule 5): the OUTGOING bus route's chokepoint is
                // `pool.trackSumMixer` — the single node every bus voice sums
                // through, and it may still be sounding (mid-decay). Ramp IT to
                // silence FIRST, then run the teardown→rebuild block. The
                // teardown→rebuild stays SYNCHRONOUS and in the SAME order inside
                // the closure (teardown then prepareTrack), so the master rebuild
                // still sees the bus pool already torn down — the naïve
                // "defer only the teardown, rebuild now" regression
                // (route-to-master → silence) is avoided.
                DevActivity.trace(DevActivity.audioGraph, "route-to-master teardownBus start track=\(trackID.uuidString)")
                rampOutgoingThenSwitch(outgoing: [pool.trackSumMixer], liveRouteSwitch: true) { [self] in
                    teardownBusVoicePool(pool)
                    prepareTrack(trackID: trackID)
                    // Bring the new MASTER route's chokepoint (the track mixer) up
                    // from silence to its configured level — the incoming side of
                    // the crossfade. `prepareTrack` builds/repairs the master pool
                    // and (via setTrackMix elsewhere) has the configured level in
                    // `trackMixValues`; respect effective mute so a muted track
                    // stays silent.
                    let (mixer, target): (AVAudioMixerNode?, Float) = withLifecycleLock {
                        let muted = effectiveMuteLocked(trackID)
                        let level = (trackMixValues[trackID]?.level ?? 1) * sceneGainLocked(trackID)
                        return (trackMixers[trackID], muted ? 0 : level)
                    }
                    if let mixer {
                        rampIncomingChokepointUp(mixer, to: target)
                    }
                    DevActivity.trace(DevActivity.audioGraph, "route-to-master teardownBus done track=\(trackID.uuidString)")
                }
            case let .repairTrack(pool):
                // repairPreparedTrackGraph republishes through the gate itself.
                repairPreparedTrackGraph(trackID: trackID, pool: pool)
            case let .wireFilterOutput(filter, busID, sends):
                audioGraph.connectTrackOutput(filter.avNode, to: busID, sends: sends)
                if let pool = withLifecycleLock({ trackVoicePools[trackID] }) {
                    publishPreparedTrackFastPathIfConnected(trackID: trackID, pool: pool)
                }
            case .none:
                // No pool/filter to (re)wire yet — nothing to publish. The track
                // becomes fast-path-ready when prepareTrack later builds its pool.
                break
            }
        }
    }

    func setTrackSends(trackID: UUID, sendA: Double, sendB: Double) {
        prepareTrack(trackID: trackID)
        performOnMain { [self] in
            let levels = MainAudioGraph.TrackSendLevels(sendA: sendA, sendB: sendB)
            // Publish the CONFIGURED levels + read the terminal node and the
            // effective mute under the lock; the send-level apply (which may
            // rewire send geometry the first time) runs without the lock.
            // #58: the APPLIED send-leg gains are gated by effective mute — a
            // muted track sends 0 to both send buses (its fanout sends bleed
            // through to the FX/aux bus → master otherwise). The configured
            // levels stay in `trackSendLevels` so unmute restores them.
            let (filter, muted): (SamplerFilterNode?, Bool) = withLifecycleLock {
                trackSendLevels[trackID] = levels
                return (trackFilters[trackID], effectiveMuteLocked(trackID))
            }
            guard let filter else { return }
            let effective = muted ? MainAudioGraph.TrackSendLevels.zero : levels
            audioGraph.setTrackSendLevels(filter.avNode, sendA: effective.sendA, sendB: effective.sendB)
        }
    }

    func removeTrack(trackID: UUID) {
        performOnMain { [self] in
            // Under-lock section: publish the removal (drop the track from
            // every dictionary the tick path reads) and CAPTURE the node
            // references to tear down. Once `trackVoicePools`/`busVoicePools`/
            // `fastPathReadyTrackIDs` no longer name this track, the tick path
            // can never select its voices again, so the captured nodes are
            // safe to detach after the lock is released. The engine mutations
            // (disconnect/detach) run OUTSIDE the lock so a live HAL reconfig
            // can't stall the tick thread that takes lifecycleLock each tick.
            let removedTrackPool: TrackVoicePool?
            let removedBusPool: BusVoicePool?
            let removedMixer: AVAudioMixerNode?
            let removedFilter: SamplerFilterNode?
            (removedTrackPool, removedBusPool, removedMixer, removedFilter) = withLifecycleLock {
                let trackPool = trackVoicePools.removeValue(forKey: trackID)
                let busPool = busVoicePools.removeValue(forKey: trackID)
                voiceParams.removeValue(forKey: trackID)
                trackOutputBusIDs.removeValue(forKey: trackID)
                trackSendLevels.removeValue(forKey: trackID)
                trackMixValues.removeValue(forKey: trackID)
                mixerMutedTrackIDs.remove(trackID)
                layerMutedTrackIDs.remove(trackID)
                trackSceneGains.removeValue(forKey: trackID)
                trackFilterFanouts.removeValue(forKey: trackID)
                _ = fastPathReadyTrackIDs.remove(trackID)
                _ = deferredPreparedTrackRepairIDs.remove(trackID)
                deferredPreparedTrackRepairAttempts.removeValue(forKey: trackID)
                let mixer = trackMixers.removeValue(forKey: trackID)
                let filter = trackFilters.removeValue(forKey: trackID)
                return (trackPool, busPool, mixer, filter)
            }

            // Post-lock section: tear down the captured graph nodes — but RAMP
            // the track's output chokepoint(s) to silence FIRST, then detach
            // only once the fade completes. Hard Rule 5: "never disconnect a
            // sounding node; ramp to silence first." A removed part's voices may
            // still be mid-decay; detaching them live is the exact click the
            // 2026-06-25 hard-disconnect bug is about. The tick path has already
            // stopped selecting these voices (their dictionary entries were
            // removed under the lock above), so nothing re-triggers through them
            // while they fade out.
            let detachCapturedNodes: @MainActor () -> Void = { [self] in
                if let removedTrackPool {
                    teardownTrackVoicePool(removedTrackPool)
                }
                if let removedBusPool {
                    teardownBusVoicePool(removedBusPool)
                }
                if let removedMixer {
                    // realtime-allow-graph-mutation: track teardown is document/routing cleanup, not tick dispatch. Test: RealtimePathLintTests.
                    audioGraph.disconnectOutput(removedMixer)
                    // realtime-allow-graph-mutation: track teardown is document/routing cleanup, not tick dispatch. Test: RealtimePathLintTests.
                    audioGraph.detach(removedMixer)
                }
                // Also tear down the filter inserted after this mixer.
                if let removedFilter {
                    // realtime-allow-graph-mutation: track teardown is document/routing cleanup, not tick dispatch. Test: RealtimePathLintTests.
                    audioGraph.disconnectOutput(removedFilter.avNode)
                    // realtime-allow-graph-mutation: track teardown is document/routing cleanup, not tick dispatch. Test: RealtimePathLintTests.
                    audioGraph.detach(removedFilter.avNode)
                }
            }

            // The track's signal chokepoint: the track mixer (non-bus track) or
            // the per-track sum node (bus-routed track) — the single node the
            // whole track flows through. Ramping it to 0 fades the whole track to
            // silence before any node leaves the graph.
            var chokepoints: [AVAudioMixerNode] = []
            if let removedMixer { chokepoints.append(removedMixer) }
            if let removedBusPool { chokepoints.append(removedBusPool.trackSumMixer) }
            rampMixersToSilenceThenDetach(chokepoints, detach: detachCapturedNodes)
        }
    }

    /// Ramp each chokepoint mixer's output to silence, then run `detach` on the
    /// main actor once ALL ramps finish (or right away if there is nothing to
    /// ramp). `detach` ALWAYS runs — even if a ramp is superseded — because the
    /// captured nodes were already removed from the tick-path dictionaries and
    /// MUST be freed (never leaked). Uses `MixerGainRamp` (writes `outputVolume`
    /// only — no graph mutation, no `lifecycleLock`), so it cannot stall the
    /// tick thread, and the detach is deferred ~12 ms, not blocked on.
    private func rampMixersToSilenceThenDetach(
        _ mixers: [AVAudioMixerNode],
        detach: @escaping @MainActor () -> Void
    ) {
        guard !mixers.isEmpty else {
            // Nothing to fade (e.g. a track with no resident output nodes);
            // detach right away on the main actor.
            // realtime-allow-main-async: deferred node teardown hop to main, off the tick path (control/teardown only). Test: RealtimePathLintTests.
            DispatchQueue.main.async { MainActor.assumeIsolated { detach() } }
            return
        }
        #if DEBUG
        sampleTeardownRampCountForTesting += 1
        #endif
        let group = DispatchGroup()
        for mixer in mixers {
            group.enter()
            MixerGainRamp.shared.ramp(mixer, to: 0) { _ in group.leave() }
        }
        group.notify(queue: .main) {
            MainActor.assumeIsolated { detach() }
        }
    }

    /// Click-free route switch (bus↔master) for a SOUNDING sample track.
    ///
    /// Hard Rule 5 forbids hard-disconnecting a sounding node; a route switch
    /// tears the OLD route's chokepoint out of the graph and builds a NEW route
    /// in its place. To avoid the click we ramp the OUTGOING chokepoint(s) to
    /// silence FIRST, and only once the fade reaches 0 do we run
    /// `switchAndBringUp` — which performs the teardown→rebuild **synchronously,
    /// in the original order** and brings the new route's gain up from 0.
    ///
    /// CRITICAL ordering invariant (the prior failure this avoids): a naïve
    /// "defer the teardown, rebuild immediately" regressed route-to-master to
    /// SILENCE — the rebuild (`prepareTrack` / new bus pool) depends on the old
    /// pool being torn down *before* it runs, so deferring only the teardown left
    /// the rebuilt voices not sounding
    /// (docs/bugs/20260626-route-switch-teardown-hard-cut). Here the ENTIRE
    /// teardown→rebuild block runs together inside `switchAndBringUp` with its
    /// internal order unchanged; only the whole block is deferred behind the
    /// down-ramp. If there is no sounding outgoing chokepoint we run it
    /// immediately (no ramp needed — nothing is being cut).
    ///
    /// `MixerGainRamp.ramp` writes `outputVolume` only (no graph mutation, no
    /// `lifecycleLock`), so the down-ramp cannot stall the tick path, and the
    /// switch is deferred ~12 ms rather than blocked on. The down-ramp uses
    /// `markSettled: false` so it does not overwrite any node's intended rest
    /// level — the outgoing chokepoint is torn down anyway, and any surviving
    /// node keeps its true settled target.
    @MainActor
    private func rampOutgoingThenSwitch(
        outgoing chokepoints: [AVAudioMixerNode],
        liveRouteSwitch: Bool = false,
        switchAndBringUp: @escaping @MainActor () -> Void
    ) {
        // Mirror MainAudioGraph.connectTrackOutput's gate: a chokepoint can only
        // be HARD-CUT-clicking if it is genuinely PASSING audio right now — the
        // engine is running AND the node has BOTH a live input edge (something
        // feeds it) and a live output edge (it reaches downstream). A fresh build
        // / setup / repair (no input or no output edge yet) is silent, so the
        // switch runs synchronously (no dip, deterministic post-state) — that
        // keeps pure-setup paths and offline render unchanged.
        let playbackStarted = withLifecycleLock { isStarted }
        let sounding = chokepoints.filter { node in
            liveRouteSwitch
                && node.engine === audioGraph.engine
                && playbackStarted
                && (nodeHasAnyInputConnection(node) || node.outputVolume > 0.001)
        }
        guard !sounding.isEmpty else {
            // Nothing currently passing audio to fade — run the switch now.
            switchAndBringUp()
            return
        }
        #if DEBUG
        sampleRouteCrossfadeCountForTesting += 1
        #endif
        let group = DispatchGroup()
        for mixer in sounding {
            group.enter()
            MixerGainRamp.shared.ramp(mixer, to: 0, markSettled: false) { _ in group.leave() }
        }
        group.notify(queue: .main) {
            MainActor.assumeIsolated { switchAndBringUp() }
        }
    }

    @MainActor
    private func nodeHasAnyInputConnection(_ node: AVAudioNode) -> Bool {
        for bus in AVAudioNodeBus(0)..<AVAudioNodeBus(32) {
            if audioGraph.engine.inputConnectionPoint(for: node, inputBus: bus) != nil {
                return true
            }
        }
        return false
    }

    /// Bring a freshly-built route's chokepoint up from silence to its configured
    /// level via a short ramp (the INCOMING side of a route crossfade). The new
    /// voices only sound on their next trigger envelope, so the up-ramp is belt-
    /// and-suspenders against any residual transient on the fresh gain stage.
    private func rampIncomingChokepointUp(_ node: AVAudioMixerNode, to level: Float) {
        node.outputVolume = 0
        MixerGainRamp.shared.ramp(node, to: level)
    }

    func audition(sampleURL: URL) {
        guard withLifecycleLock({ isStarted }) else { return }
        guard let file = cachedFile(url: sampleURL) else { return }
        previewNode.stop()
        previewNode.volume = 1.0
        previewNode.scheduleFile(file, at: nil, completionHandler: nil)
        _ = startVoiceSafely(previewNode)
    }

    func stopAudition() {
        previewNode.stop()
    }

    func setVoiceParam(trackID: UUID, kind: BuiltinMacroKind, value: Double) {
        withLifecycleLock {
            voiceParams[trackID, default: [:]][kind] = value
        }
    }

    /// Lock contract: callers MUST NOT hold `lifecycleLock`. This method runs
    /// on `@MainActor` (writers are main-serialized) and takes the lock
    /// internally only for the brief dictionary read/publish points — never
    /// across the `audioGraph` graph mutation below.
    @MainActor
    private func trackMixer(for trackID: UUID) -> AVAudioMixerNode {
        let (existingMixer, busID, sends) = withLifecycleLock {
            (trackMixers[trackID], trackOutputBusIDs[trackID], trackSendLevels[trackID] ?? .zero)
        }
        if let existingMixer { return existingMixer }
        let mixer = AVAudioMixerNode()
        // realtime-allow-graph-mutation: prepared track output setup occurs during setup/repair, not tick dispatch. Test: RealtimePathLintTests.
        audioGraph.attach(mixer)

        // Insert a filter between the track mixer and the main mixer.
        // Graph: voices -> mixer -> filter.avNode -> shared pre-master mixer
        let filter = SamplerFilterNode()
        // realtime-allow-graph-mutation: prepared track output setup occurs during setup/repair, not tick dispatch. Test: RealtimePathLintTests.
        audioGraph.attach(filter.avNode)
        // realtime-allow-graph-mutation: prepared track output setup occurs during setup/repair, not tick dispatch. Test: RealtimePathLintTests.
        audioGraph.connect(mixer, to: filter.avNode)
        // Setup/rebuild: splice synchronously (no ramp dip). The new voices are
        // not sounding through this graph yet, and a rebuild issues several of
        // these in quick succession — overlapping deferred dips on the same
        // fanout race and can leave the filter disconnected (the intermittent
        // drum-part-add / route-to-master silence).
        audioGraph.connectTrackOutput(
            filter.avNode,
            to: busID,
            sends: sends,
            ramped: false
        )
        // The filter node is the track's terminal point (post level/pan,
        // post filter) — register it as the strip's meter source.
        audioGraph.setTrackMeterSources(trackIDs: [trackID], node: filter.avNode)
        let fanout = withLifecycleLock { () -> SamplerFilterFanout in
            trackFilters[trackID] = filter
            trackMixers[trackID] = mixer
            return filterFanoutLocked(for: trackID)
        }
        fanout.setTargets([filter])
        return mixer
    }

    /// Lock contract: callers MUST NOT hold `lifecycleLock`. Runs on
    /// `@MainActor`; takes the lock internally only for the dictionary
    /// snapshot/publish points, never across the graph mutation.
    @MainActor
    private func prepareBusVoicePool(trackID: UUID, busID: UUID, liveRouteSwitch: Bool = false) {
        // Snapshot existing state and tear down any stale track-route nodes
        // under the lock; drop the track from the fast-path so the tick path
        // can't touch the pool while we rebuild it.
        let (existingBusPool, staleTrackPool, staleMixer, staleFilter) = withLifecycleLock {
            () -> (BusVoicePool?, TrackVoicePool?, AVAudioMixerNode?, SamplerFilterNode?) in
            let busPool = busVoicePools[trackID]
            if busPool != nil { return (busPool, nil, nil, nil) }
            _ = fastPathReadyTrackIDs.remove(trackID)
            let trackPool = trackVoicePools.removeValue(forKey: trackID)
            let mixer = trackMixers.removeValue(forKey: trackID)
            let filter = trackFilters.removeValue(forKey: trackID)
            return (nil, trackPool, mixer, filter)
        }

        if let existingBusPool, isBusVoicePoolReadyForPlayback(pool: existingBusPool, busID: busID) {
            // Already a healthy bus pool — no route switch, no teardown. Just
            // re-apply the mix (this path is not a sounding-node disconnect).
            applyBusVoiceMix(trackID: trackID, pool: existingBusPool)
            return
        }

        // OUTGOING route chokepoint(s) that may currently be SOUNDING and are
        // about to be torn down — ramp these to silence BEFORE the disconnect
        // (Hard Rule 5). For master→bus the outgoing chokepoint is the track
        // mixer (`staleMixer`); for a stale bus rebuild it is the old bus pool's
        // `trackSumMixer`. The teardown of these (and the build of the new bus
        // route) all run SYNCHRONOUSLY in `buildBusRoute` below, in the original
        // order, so the new route is fully built before publish — we never
        // "defer the teardown while rebuilding now" (that regressed the sibling
        // route-to-master path to silence).
        var outgoingChokepoints: [AVAudioMixerNode] = []
        if let staleMixer { outgoingChokepoints.append(staleMixer) }
        if let existingBusPool { outgoingChokepoints.append(existingBusPool.trackSumMixer) }

        let buildBusRoute: @MainActor () -> Void = { [self] in
            if let existingBusPool {
                // Stale bus pool: drop it (under lock) and rebuild below.
                withLifecycleLock {
                    _ = fastPathReadyTrackIDs.remove(trackID)
                    _ = busVoicePools.removeValue(forKey: trackID)
                }
                teardownBusVoicePool(existingBusPool)
            }

            if let staleTrackPool {
                teardownTrackVoicePool(staleTrackPool)
            }
            if let staleMixer {
                // realtime-allow-graph-mutation: prepared route switch setup only, not tick dispatch. Test: RealtimePathLintTests.
                audioGraph.disconnectOutput(staleMixer)
                // realtime-allow-graph-mutation: prepared route switch setup only, not tick dispatch. Test: RealtimePathLintTests.
                audioGraph.detach(staleMixer)
            }
            if let staleFilter {
                // realtime-allow-graph-mutation: prepared route switch setup only, not tick dispatch. Test: RealtimePathLintTests.
                audioGraph.disconnectOutput(staleFilter.avNode)
                // realtime-allow-graph-mutation: prepared route switch setup only, not tick dispatch. Test: RealtimePathLintTests.
                audioGraph.detach(staleFilter.avNode)
            }

            // The track's OWN output node when routed to a bus: every voice mixer
            // sums into this single node, which then feeds the bus. It is the track's
            // meter source (so the source meters regardless of routing, #62) and the
            // single per-track input on the bus (so per-track inputs cannot collide).
            let trackSumMixer = AVAudioMixerNode()
            // realtime-allow-graph-mutation: prepared bus voice setup occurs during document apply/setup, not tick dispatch. Test: RealtimePathLintTests.
            audioGraph.attach(trackSumMixer)

            var voices: [AVAudioPlayerNode] = []
            var mixers: [AVAudioMixerNode] = []
            var handles: [UUID] = []
            for index in 0..<Self.voicesPerTrack {
                let voice = AVAudioPlayerNode()
                let mixer = AVAudioMixerNode()
                // realtime-allow-graph-mutation: prepared bus voice setup occurs during document apply/setup, not tick dispatch. Test: RealtimePathLintTests.
                audioGraph.attach(voice)
                // realtime-allow-graph-mutation: prepared bus voice setup occurs during document apply/setup, not tick dispatch. Test: RealtimePathLintTests.
                audioGraph.attach(mixer)
                // realtime-allow-graph-mutation: prepared bus voice setup occurs during document apply/setup, not tick dispatch. Test: RealtimePathLintTests.
                audioGraph.engine.connect(voice, to: mixer, fromBus: 0, toBus: 0, format: nil)
                // Each voice mixer feeds a distinct input on the per-track sum mixer.
                // realtime-allow-graph-mutation: prepared bus voice setup occurs during document apply/setup, not tick dispatch. Test: RealtimePathLintTests.
                audioGraph.engine.connect(mixer, to: trackSumMixer, fromBus: 0, toBus: index, format: nil)
                voices.append(voice)
                mixers.append(mixer)
                handles.append(UUID())
            }

            // realtime-allow-graph-mutation: prepared bus voice setup occurs during document apply/setup, not tick dispatch. Test: RealtimePathLintTests.
            // One connection per track to the shared bus input mixer (a unique free
            // input bus allocated inside connectPreparedSampleVoiceOutput), so tracks
            // routed to the same bus cannot collide. The bus input mixer SUMS these
            // per-track outputs — the bus meters that sum (#59).
            audioGraph.connectPreparedSampleVoiceOutput(
                trackID: trackID,
                trackSumMixer,
                toMixerBus: busID
            )
            // The per-track sum node is the track's terminal point when bus-routed —
            // register it as the strip's meter source so the SOURCE track keeps
            // metering its own level even though its output goes to a bus (#62).
            audioGraph.setTrackMeterSources(trackIDs: [trackID], node: trackSumMixer)

            let pool = BusVoicePool(voices: voices, voiceMixers: mixers, trackSumMixer: trackSumMixer, handles: handles, cursor: 0)
            let fanout = withLifecycleLock { () -> SamplerFilterFanout in
                busVoicePools[trackID] = pool
                _ = deferredPreparedTrackRepairIDs.remove(trackID)
                return filterFanoutLocked(for: trackID)
            }
            fanout.setTargets([])
            // INCOMING side of the crossfade: bring the new sum-node chokepoint up
            // from silence rather than snapping it on. `applyBusVoiceMix` sets the
            // configured fader level immediately; override the sum node to a ramp
            // from 0 to that level (mute-respecting). Voice mixers stay at unity.
            applyBusVoiceMix(trackID: trackID, pool: pool)
            let target: Float = withLifecycleLock {
                let mix = trackMixValues[trackID] ?? (level: 1, pan: 0)
                return effectiveMuteLocked(trackID) ? 0 : mix.level * sceneGainLocked(trackID)
            }
            rampIncomingChokepointUp(trackSumMixer, to: target)
            // realtime-allow-graph-mutation: prepared bus voice setup occurs during document apply/setup, not tick dispatch. Test: RealtimePathLintTests.
            audioGraph.engine.prepare()
            // Republish fast-path here: when the build is DEFERRED behind the
            // outgoing down-ramp, the caller's synchronous post-call read of
            // `busVoicePools[trackID]` is still nil, so the gate must be set from
            // inside the deferred block. Idempotent with the caller's own publish.
            publishBusTrackFastPathIfConnected(trackID: trackID, busID: busID, pool: pool)
        }

        rampOutgoingThenSwitch(
            outgoing: outgoingChokepoints,
            liveRouteSwitch: liveRouteSwitch,
            switchAndBringUp: buildBusRoute
        )
    }

    @MainActor
    private func isBusVoicePoolReadyForPlayback(pool: BusVoicePool, busID: UUID) -> Bool {
        guard audioGraph.mixerBusReadoutForTesting(busID: busID) != nil,
              !pool.voices.isEmpty,
              pool.voices.count == pool.voiceMixers.count
        else {
            return false
        }
        guard pool.trackSumMixer.engine === audioGraph.engine,
              // The per-track sum node is the track's output — verify it reaches
              // the bus (voices -> voiceMixers -> sumMixer -> bus input mixer).
              outputConnectionExists(from: pool.trackSumMixer)
        else {
            return false
        }
        for index in pool.voices.indices {
            let voice = pool.voices[index]
            let mixer = pool.voiceMixers[index]
            guard voice.engine === audioGraph.engine,
                  mixer.engine === audioGraph.engine,
                  outputConnectionExists(from: voice, to: mixer),
                  outputConnectionExists(from: mixer, to: pool.trackSumMixer)
            else {
                return false
            }
        }
        // The voices reaching the bus input mixer is not enough — the bus's
        // OWN output edge to preMaster can be silently dropped (a mixer with no
        // inputs has no resolvable output format), leaving a live-looking voice
        // chain that dead-ends at the bus. Verify the bus->master leg too, so a
        // broken bus output can't pass the gate and play silently.
        guard audioGraph.mixerBusTerminalReachesPreMaster(busID: busID) else {
            return false
        }
        return true
    }

    /// Lock contract: callers MUST NOT hold `lifecycleLock`. Reads
    /// `trackMixValues` under the lock, then applies the mixer params (a
    /// node-parameter write, not a graph mutation) without it.
    private func applyBusVoiceMix(trackID: UUID, pool: BusVoicePool) {
        let (mix, muted, sceneGain) = withLifecycleLock {
            (trackMixValues[trackID] ?? (level: 1, pan: 0), effectiveMuteLocked(trackID), sceneGainLocked(trackID))
        }
        let effectiveLevel = muted ? 0 : mix.level * sceneGain
        // Apply the track fader/pan on the per-track sum node (the track's own
        // output); voice mixers stay at unity. This keeps the meter source (the
        // sum node) reading the post-fader track level.
        MixerGainRamp.shared.setImmediate(pool.trackSumMixer, to: effectiveLevel)
        pool.trackSumMixer.pan = mix.pan
        for mixer in pool.voiceMixers {
            MixerGainRamp.shared.setImmediate(mixer, to: 1)
            mixer.pan = 0
        }
    }

    @MainActor
    private func teardownTrackVoicePool(_ pool: TrackVoicePool) {
        playerCommandLock.lock()
        defer { playerCommandLock.unlock() }
        for voice in pool.voices {
            voice.stop()
            voice.reset()
            // realtime-allow-graph-mutation: prepared route switch setup only, not tick dispatch. Test: RealtimePathLintTests.
            audioGraph.disconnectOutput(voice)
            // realtime-allow-graph-mutation: prepared route switch setup only, not tick dispatch. Test: RealtimePathLintTests.
            audioGraph.detach(voice)
        }
        for filter in pool.voiceFilters {
            // realtime-allow-graph-mutation: prepared route switch setup only, not tick dispatch. Test: RealtimePathLintTests.
            audioGraph.disconnectOutput(filter.avNode)
            // realtime-allow-graph-mutation: prepared route switch setup only, not tick dispatch. Test: RealtimePathLintTests.
            audioGraph.detach(filter.avNode)
        }
    }

    @MainActor
    private func teardownBusVoicePool(_ pool: BusVoicePool) {
        playerCommandLock.lock()
        defer { playerCommandLock.unlock() }
        for voice in pool.voices {
            voice.stop()
            voice.reset()
            // realtime-allow-graph-mutation: prepared route switch setup only, not tick dispatch. Test: RealtimePathLintTests.
            audioGraph.disconnectOutput(voice)
            // realtime-allow-graph-mutation: prepared route switch setup only, not tick dispatch. Test: RealtimePathLintTests.
            audioGraph.detach(voice)
        }
        for mixer in pool.voiceMixers {
            // realtime-allow-graph-mutation: prepared route switch setup only, not tick dispatch. Test: RealtimePathLintTests.
            audioGraph.disconnectOutput(mixer)
            // realtime-allow-graph-mutation: prepared route switch setup only, not tick dispatch. Test: RealtimePathLintTests.
            audioGraph.detach(mixer)
        }
        // realtime-allow-graph-mutation: prepared route switch setup only, not tick dispatch. Test: RealtimePathLintTests.
        audioGraph.disconnectOutput(pool.trackSumMixer)
        // The per-track sum node was the track's meter source — detach clears
        // its meter tap + meter-source registration (MainAudioGraph.detach).
        // realtime-allow-graph-mutation: prepared route switch setup only, not tick dispatch. Test: RealtimePathLintTests.
        audioGraph.detach(pool.trackSumMixer)
    }

    private func validatePreparedTrackGraphs() {
        performOnMain { [self] in
            // Snapshot the pools + bus routing under the lock, then validate /
            // repair WITHOUT holding it (the repair helpers take the lock
            // internally for their dictionary touches). Writers are
            // main-serialized, so the snapshot can't be invalidated mid-pass.
            let (trackPools, busPools, busRouting): (
                [UUID: TrackVoicePool],
                [UUID: BusVoicePool],
                [UUID: UUID]
            ) = withLifecycleLock {
                (trackVoicePools, busVoicePools, trackOutputBusIDs)
            }

            for (trackID, pool) in trackPools {
                guard !isPreparedTrackPoolReadyForPlayback(trackID: trackID, pool: pool) else {
                    // Healthy — (re)publish through the gate (clears deferred +
                    // resets the backstop attempt count for a recovered track).
                    publishPreparedTrackFastPathIfConnected(trackID: trackID, pool: pool)
                    continue
                }
                repairPreparedTrackGraph(trackID: trackID, pool: pool)
            }
            for (trackID, pool) in busPools {
                guard let busID = busRouting[trackID],
                      isBusVoicePoolReadyForPlayback(pool: pool, busID: busID)
                else {
                    if let busID = busRouting[trackID] {
                        prepareBusVoicePool(trackID: trackID, busID: busID)
                        if let rebuilt = withLifecycleLock({ busVoicePools[trackID] }) {
                            publishBusTrackFastPathIfConnected(trackID: trackID, busID: busID, pool: rebuilt)
                        }
                    }
                    continue
                }
                applyBusVoiceMix(trackID: trackID, pool: pool)
                publishBusTrackFastPathIfConnected(trackID: trackID, busID: busID, pool: pool)
            }
        }
    }

    /// Apply filter settings to the filter node for the given track.
    ///
    /// Called from the document layer when the user edits `track.filter` directly
    /// (e.g. via `SamplerDestinationWidget`). Per-step macro dispatch uses
    /// `filterNode(for:)` and the fine-grained setters instead.
    func applyFilter(_ settings: SamplerFilterSettings, trackID: UUID) {
        let filter: (any SamplerFilterControlling)? = withLifecycleLock {
            if let fanout = trackFilterFanouts[trackID] {
                return fanout
            }
            return trackFilters[trackID]
        }
        filter?.apply(settings)
    }

    /// Returns the filter node for the given track, or nil if it doesn't exist.
    ///
    /// Used by `TrackMacroApplier` to dispatch per-step filter macro values.
    func filterNode(for trackID: UUID) -> (any SamplerFilterControlling)? {
        withLifecycleLock {
            if let fanout = trackFilterFanouts[trackID] {
                return fanout
            }
            return trackFilters[trackID]
        }
    }

    private func cachedFile(url: URL) -> AVAudioFile? {
        withLifecycleLock {
            if let f = fileCache[url] { return f }
            // realtime-allow-file-open: legacy audition/URL fallback; tick dispatch must use PreparedSampleAsset. Test: RealtimePathLintTests.
            guard let f = try? AVAudioFile(forReading: url) else { return nil }
            if fileCache.count >= 64 {
                fileCache.removeAll(keepingCapacity: true)
            }
            fileCache[url] = f
            return f
        }
    }

    /// Copy `frameCount` frames starting at `startFrame` out of the resident
    /// `pcmBuffer` into a fresh playback-format buffer — purely an in-RAM
    /// sub-range copy, no file I/O. Returns nil when there is no resident source
    /// or the range is out of bounds. `frameCount` is clamped to the frames
    /// actually available from `startFrame` so a slightly-overlong request
    /// (e.g. last slice) still produces a resident buffer instead of falling
    /// through to file streaming.
    private func sliceBuffer(
        pcmBuffer: AVAudioPCMBuffer?,
        fileFormat: AVAudioFormat,
        playbackFormat: AVAudioFormat,
        startFrame: AVAudioFramePosition,
        frameCount: AVAudioFrameCount
    ) -> AVAudioPCMBuffer? {
        guard let source = pcmBuffer,
              startFrame >= 0,
              startFrame < AVAudioFramePosition(source.frameLength)
        else {
            return nil
        }
        let available = AVAudioFrameCount(AVAudioFramePosition(source.frameLength) - startFrame)
        let clampedCount = max(1, min(frameCount, available))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: fileFormat, frameCapacity: clampedCount),
              Self.copyFrames(from: source, startFrame: startFrame, frameCount: clampedCount, into: buffer)
        else {
            return nil
        }
        return buffer.convertingForPlayback(to: playbackFormat) ?? buffer
    }

    private static func copyFrames(
        from source: AVAudioPCMBuffer,
        startFrame: AVAudioFramePosition,
        frameCount: AVAudioFrameCount,
        into destination: AVAudioPCMBuffer
    ) -> Bool {
        let offset = Int(startFrame)
        let count = Int(frameCount)
        guard offset >= 0,
              count > 0,
              offset + count <= Int(source.frameLength),
              let sourceChannels = source.floatChannelData,
              let destinationChannels = destination.floatChannelData
        else {
            return false
        }

        let channelCount = min(Int(source.format.channelCount), Int(destination.format.channelCount))
        for channel in 0..<channelCount {
            destinationChannels[channel].update(from: sourceChannels[channel] + offset, count: count)
        }
        destination.frameLength = frameCount
        return true
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

    static func effectivePlaybackTime(for when: AVAudioTime?, now: Double = ProcessInfo.processInfo.systemUptime) -> AVAudioTime? {
        guard let when else { return nil }
        guard when.isHostTimeValid else { return when }
        let scheduled = AVAudioTime.seconds(forHostTime: when.hostTime)
        return scheduled > now ? when : nil
    }

    private static func sampleFrameRange(
        file: AVAudioFile,
        settings: SamplerSettings,
        params: [BuiltinMacroKind: Double]?
    ) -> (startFrame: AVAudioFramePosition, frameLength: AVAudioFrameCount) {
        let startNorm = min(max(params?[.sampleStart] ?? settings.start, 0), 1)
        let lengthNorm = min(max(params?[.sampleLength] ?? settings.length, 0), 1)
        let frameCount = Double(file.length)
        let startFrame = AVAudioFramePosition(min(startNorm * frameCount, max(frameCount - 1, 0)))
        let remainingFrames = max(1, Double(file.length) - Double(startFrame))
        let frameLength = AVAudioFrameCount(min(max(1, lengthNorm * frameCount), remainingFrames))
        return (startFrame, frameLength)
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
        scheduled: TimeInterval?,
        schedule: @escaping (AVAudioPlayerNode, SamplerFilterNode, [BuiltinMacroKind: Double]?) -> Bool
    ) -> VoiceHandle? {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                preparedVoicePlaybackOnMain(trackID: trackID, voiceMode: voiceMode, schedule: schedule)
            }
        }

        if preparedVoicePlaybackFastPath(
            trackID: trackID,
            voiceMode: voiceMode,
            scheduled: scheduled,
            schedule: schedule
        ) {
            return nil
        }

        guard !isPreparedTrackRepairDeferred(trackID: trackID) else {
            SequencerTimingProbe.sampleFastPath(
                trackID: trackID,
                scheduled: scheduled,
                actual: ProcessInfo.processInfo.systemUptime,
                result: "repair-deferred"
            )
            return nil
        }

        // Broken/missing graph state still repairs on main. The normal
        // prepared path above schedules directly from the tick/event queue,
        // so tab rendering no longer sits between the tick and sample start.
        let enqueued = ProcessInfo.processInfo.systemUptime
        SequencerTimingProbe.sampleMainHopQueued(
            trackID: trackID,
            scheduled: scheduled,
            enqueued: enqueued,
            reason: "repair"
        )
        // realtime-allow-main-async: exceptional graph repair only; normal prepared playback uses fast path. Test: RealtimePathLintTests.
        DispatchQueue.main.async { [self] in
            SequencerTimingProbe.sampleMainHopStarted(
                trackID: trackID,
                scheduled: scheduled,
                enqueued: enqueued,
                actual: ProcessInfo.processInfo.systemUptime,
                reason: "repair"
            )
            MainActor.assumeIsolated {
                _ = preparedVoicePlaybackOnMain(trackID: trackID, voiceMode: voiceMode, schedule: schedule)
            }
        }
        return nil
    }

    private func preparedVoicePlaybackFastPath(
        trackID: UUID,
        voiceMode: SlicerVoiceMode,
        scheduled: TimeInterval?,
        schedule: (AVAudioPlayerNode, SamplerFilterNode, [BuiltinMacroKind: Double]?) -> Bool
    ) -> Bool {
        var selectedVoice: AVAudioPlayerNode?
        var selectedFilter: SamplerFilterNode?
        var selectedParams: [BuiltinMacroKind: Double]?

        withLifecycleLock {
            guard fastPathReadyTrackIDs.contains(trackID),
                  var pool = trackVoicePools[trackID],
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
                _ = fastPathReadyTrackIDs.remove(trackID)
                return
            }

            selectedVoice = pool.voices[voiceIndex]
            selectedFilter = pool.voiceFilters[voiceIndex]
            selectedParams = voiceParams[trackID]
            pool.handles[voiceIndex] = UUID()
            if voiceMode == .polyphonic {
                pool.cursor = (voiceIndex &+ 1) % pool.voices.count
            }
            trackVoicePools[trackID] = pool
            #if DEBUG
            voiceSelectionsForTesting.append((
                trackID: trackID,
                voiceMode: voiceMode,
                voiceIndex: voiceIndex,
                stoppedPriorVoice: voiceMode == .mono
            ))
            #endif
            SequencerTimingProbe.voiceSelected(
                trackID: trackID,
                voiceMode: voiceMode.rawValue,
                voiceIndex: voiceIndex,
                stoppedPriorVoice: voiceMode == .mono
            )
        }

        guard let voice = selectedVoice,
              let filter = selectedFilter
        else {
            SequencerTimingProbe.sampleFastPath(
                trackID: trackID,
                scheduled: scheduled,
                actual: ProcessInfo.processInfo.systemUptime,
                result: "unprepared"
            )
            return false
        }

        if schedule(voice, filter, selectedParams) {
            SequencerTimingProbe.sampleFastPath(
                trackID: trackID,
                scheduled: scheduled,
                actual: ProcessInfo.processInfo.systemUptime,
                result: "scheduled"
            )
            return true
        }

        deferPreparedTrackRepair(trackID: trackID, scheduled: scheduled)
        SequencerTimingProbe.sampleFastPath(
            trackID: trackID,
            scheduled: scheduled,
            actual: ProcessInfo.processInfo.systemUptime,
            result: "schedule-failed"
        )
        return true
    }

    @MainActor
    private func preparedVoicePlaybackOnMain(
        trackID: UUID,
        voiceMode: SlicerVoiceMode,
        schedule: (AVAudioPlayerNode, SamplerFilterNode, [BuiltinMacroKind: Double]?) -> Bool
    ) -> VoiceHandle? {
        do {
            var didRepair = false

            while true {
                // Select the voice + advance the cursor under the lock (pure
                // in-memory). The route-readiness check and any repair run
                // OUTSIDE the lock so a live engine reconfiguration never
                // stalls the tick thread that takes lifecycleLock each tick.
                var selectedVoice: AVAudioPlayerNode?
                var selectedFilter: SamplerFilterNode?
                var selectedParams: [BuiltinMacroKind: Double]?
                var selectedHandleID: UUID?
                var needsRepair = false

                withLifecycleLock {
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
                    let handleID = UUID()
                    pool.handles[voiceIndex] = handleID
                    if voiceMode == .polyphonic {
                        pool.cursor = (voiceIndex &+ 1) % pool.voices.count
                    }
                    trackVoicePools[trackID] = pool
                    #if DEBUG
                    voiceSelectionsForTesting.append((
                        trackID: trackID,
                        voiceMode: voiceMode,
                        voiceIndex: voiceIndex,
                        stoppedPriorVoice: voiceMode == .mono
                    ))
                    #endif
                    SequencerTimingProbe.voiceSelected(
                        trackID: trackID,
                        voiceMode: voiceMode.rawValue,
                        voiceIndex: voiceIndex,
                        stoppedPriorVoice: voiceMode == .mono
                    )
                    selectedVoice = voice
                    selectedFilter = voiceFilter
                    selectedParams = voiceParams[trackID]
                    selectedHandleID = handleID
                }

                // Route-readiness check OUTSIDE the lock (it reads the engine
                // graph and queries dictionaries under its own short lock).
                if !needsRepair,
                   let voice = selectedVoice,
                   let voiceFilter = selectedFilter,
                   !isPreparedTrackRouteReadyForPlayback(
                       trackID: trackID,
                       voice: voice,
                       voiceFilter: voiceFilter
                   ) {
                    needsRepair = true
                }

                if needsRepair {
                    guard !didRepair else { return nil }
                    didRepair = true
                    repairSelectedTrackIfPresent(trackID: trackID)
                    continue
                }

                guard let voice = selectedVoice,
                      let voiceFilter = selectedFilter,
                      let handleID = selectedHandleID
                else {
                    return nil
                }

                if schedule(voice, voiceFilter, selectedParams) {
                    withLifecycleLock {
                        _ = fastPathReadyTrackIDs.insert(trackID)
                        _ = deferredPreparedTrackRepairIDs.remove(trackID)
                    }
                    return VoiceHandle(id: handleID)
                }

                withLifecycleLock {
                    markPreparedTrackRepairDeferredLocked(trackID: trackID)
                }
                guard !didRepair else { return nil }
                didRepair = true
                repairSelectedTrackIfPresent(trackID: trackID)
            }
        }
    }

    /// Repair the prepared track graph for `trackID` if a pool exists. Reads
    /// the pool under the lock, then runs the repair WITHOUT the lock (the
    /// repair helper takes the lock internally for its dictionary touches).
    @MainActor
    private func repairSelectedTrackIfPresent(trackID: UUID) {
        guard let pool = withLifecycleLock({ trackVoicePools[trackID] }) else { return }
        repairPreparedTrackGraph(trackID: trackID, pool: pool)
    }

    @MainActor
    private func isPreparedTrackRouteReadyForPlayback(
        trackID: UUID,
        voice: AVAudioPlayerNode,
        voiceFilter: SamplerFilterNode
    ) -> Bool {
        let (mixer, trackFilter) = withLifecycleLock { (trackMixers[trackID], trackFilters[trackID]) }
        guard voice.engine === audioGraph.engine,
              voiceFilter.avNode.engine === audioGraph.engine,
              let mixer,
              mixer.engine === audioGraph.engine,
              let trackFilter,
              trackFilter.avNode.engine === audioGraph.engine
        else {
            return false
        }
        return outputConnectionExists(from: voice, to: voiceFilter.avNode) &&
            outputConnectionExists(from: voiceFilter.avNode, to: mixer) &&
            outputConnectionExists(from: mixer, to: trackFilter.avNode) &&
            outputConnectionExists(from: trackFilter.avNode)
    }

    @MainActor
    private func isPreparedTrackPoolReadyForPlayback(trackID: UUID, pool: TrackVoicePool) -> Bool {
        guard !pool.voices.isEmpty,
              pool.voices.count == pool.voiceFilters.count
        else {
            return false
        }

        for index in pool.voices.indices {
            guard isPreparedTrackRouteReadyForPlayback(
                trackID: trackID,
                voice: pool.voices[index],
                voiceFilter: pool.voiceFilters[index]
            ) else {
                return false
            }
        }
        return true
    }

    /// The fast-path-ready GATE (watertight prevention of the disconnect-window
    /// race). Re-publish a prepared-MASTER track as fast-path-ready ONLY after
    /// VALIDATING that its full output chain (voice→voiceFilter→mixer→trackFilter
    /// →output) is actually connected in the live graph — the same
    /// `outputConnectionExists`-backed predicate `repairTrackMixerOutput` uses.
    ///
    /// Every prepare/repair/route path drops the track from `fastPathReadyTrackIDs`
    /// BEFORE its teardown/disconnect/reconnect window (under the lock), does the
    /// synchronous topology edit on main, and then calls this. Because the whole
    /// disconnect→reconnect window is synchronous on main and we only re-add the
    /// track after the new connection is proven present, the concurrent
    /// tick-thread `play()` can NEVER select a voice whose chain is mid-rebuild →
    /// it never lands a `play()` in the disconnected window → no
    /// "player started when in a disconnected state" → no defer. Steady-state
    /// defers drop to ~0 (the disconnect is PREVENTED, not recovered from).
    ///
    /// If validation fails (the rebuild did not produce a complete chain — should
    /// be rare), the track is left OUT of fast-path and marked repair-deferred so
    /// the bounded backstop can have one more bounded attempt rather than
    /// publishing a half-connected track the tick path would trip on.
    /// - Returns: `true` if the track was published fast-path-ready.
    @MainActor
    @discardableResult
    private func publishPreparedTrackFastPathIfConnected(trackID: UUID, pool: TrackVoicePool) -> Bool {
        guard isPreparedTrackPoolReadyForPlayback(trackID: trackID, pool: pool) else {
            DevActivity.trace(
                DevActivity.audioGraph,
                "fast-path gate WITHHELD (chain not fully connected) track=\(trackID.uuidString)"
            )
            // Leave the track OUT of fast-path and route it through the BOUNDED
            // backstop so it gets one more capped+backed-off repair attempt rather
            // than silently staying dropped. `deferPreparedTrackRepair` removes
            // fast-path under the lock and schedules the heal (subject to the cap).
            deferPreparedTrackRepair(trackID: trackID, scheduled: nil)
            return false
        }
        withLifecycleLock {
            trackVoicePools[trackID] = pool
            _ = fastPathReadyTrackIDs.insert(trackID)
            _ = deferredPreparedTrackRepairIDs.remove(trackID)
            deferredPreparedTrackRepairAttempts.removeValue(forKey: trackID)
        }
        return true
    }

    /// Bus-pool counterpart of `publishPreparedTrackFastPathIfConnected`:
    /// re-publish a bus-routed track as fast-path-ready ONLY after validating the
    /// bus voice pool's full chain (each voice→voiceMixer→bus) is live.
    @MainActor
    @discardableResult
    private func publishBusTrackFastPathIfConnected(trackID: UUID, busID: UUID, pool: BusVoicePool) -> Bool {
        guard isBusVoicePoolReadyForPlayback(pool: pool, busID: busID) else {
            DevActivity.trace(
                DevActivity.audioGraph,
                "fast-path gate WITHHELD (bus chain not fully connected) track=\(trackID.uuidString)"
            )
            // Bounded backstop (capped + backed off) for the rare unconnected case.
            deferPreparedTrackRepair(trackID: trackID, scheduled: nil)
            return false
        }
        withLifecycleLock {
            _ = fastPathReadyTrackIDs.insert(trackID)
            _ = deferredPreparedTrackRepairIDs.remove(trackID)
            deferredPreparedTrackRepairAttempts.removeValue(forKey: trackID)
        }
        return true
    }

    /// Lock contract: callers MUST NOT hold `lifecycleLock`. Runs on
    /// `@MainActor`; drops the track from the fast-path (under the lock) before
    /// the rewire so the tick path can't select a half-rebuilt pool, performs
    /// the graph mutation WITHOUT the lock, then republishes the pool + ready
    /// flag under the lock.
    @MainActor
    private func repairPreparedTrackGraph(trackID: UUID, pool: TrackVoicePool) {
        playerCommandLock.lock()
        defer { playerCommandLock.unlock() }
        let started = ProcessInfo.processInfo.systemUptime
        var mutationCount = 0
        defer {
            SequencerTimingProbe.graphRepair(
                subsystem: "sample",
                trackID: trackID,
                cause: "prepared-track",
                duration: ProcessInfo.processInfo.systemUptime - started,
                mutationCount: mutationCount
            )
        }
        let pool = pool
        withLifecycleLock {
            _ = fastPathReadyTrackIDs.remove(trackID)
        }
        let mixer = trackMixer(for: trackID)
        repairTrackMixerOutput(trackID: trackID, mixer: mixer)

        var disconnectedMixerInputs = false
        for index in pool.voices.indices {
            let voice = pool.voices[index]
            guard index < pool.voiceFilters.count else { continue }
            let filter = pool.voiceFilters[index]
            voice.stop()
            voice.reset()
            if outputConnectionExists(from: voice) {
                // realtime-allow-graph-mutation: exceptional prepared graph repair only; normal playback uses fast path and logs repair. Test: RealtimePathLintTests.
                audioGraph.disconnectOutput(voice)
                mutationCount += 1
                // realtime-allow-graph-mutation: exceptional prepared graph repair only; normal playback uses fast path and logs repair. Test: RealtimePathLintTests.
                audioGraph.disconnectInput(filter.avNode)
                mutationCount += 1
            }
            if outputConnectionExists(from: filter.avNode) {
                // realtime-allow-graph-mutation: exceptional prepared graph repair only; normal playback uses fast path and logs repair. Test: RealtimePathLintTests.
                audioGraph.disconnectOutput(filter.avNode)
                mutationCount += 1
                disconnectedMixerInputs = true
            }
        }
        if disconnectedMixerInputs {
            // realtime-allow-graph-mutation: exceptional prepared graph repair only; normal playback uses fast path and logs repair. Test: RealtimePathLintTests.
            audioGraph.disconnectInput(mixer)
            mutationCount += 1
        }
        // `disconnectNodeOutput` removes these sources from the mixer, but
        // `nextAvailableInputBus` can still advance after repeated repair
        // passes. Rebuild the fan-in deterministically from bus 0 once all
        // prepared voice-filter outputs are clear.
        var mixerInputBus: AVAudioNodeBus = 0

        for index in pool.voices.indices {
            let voice = pool.voices[index]
            guard index < pool.voiceFilters.count else { continue }
            let filter = pool.voiceFilters[index]

            // realtime-allow-graph-mutation: exceptional prepared graph repair only; normal playback uses fast path and logs repair. Test: RealtimePathLintTests.
            audioGraph.attach(voice)
            mutationCount += 1
            // realtime-allow-graph-mutation: exceptional prepared graph repair only; normal playback uses fast path and logs repair. Test: RealtimePathLintTests.
            audioGraph.attach(filter.avNode)
            mutationCount += 1
            // realtime-allow-graph-mutation: exceptional prepared graph repair only; normal playback uses fast path and logs repair. Test: RealtimePathLintTests.
            audioGraph.engine.connect(
                voice,
                to: filter.avNode,
                fromBus: 0,
                toBus: 0,
                format: nil
            )
            mutationCount += 1
            // realtime-allow-graph-mutation: exceptional prepared graph repair only; normal playback uses fast path and logs repair. Test: RealtimePathLintTests.
            audioGraph.engine.connect(
                filter.avNode,
                to: mixer,
                fromBus: 0,
                toBus: mixerInputBus,
                format: nil
            )
            mutationCount += 1
            mixerInputBus += 1
        }
        // Fast-path gate: publish the rebuilt pool as ready ONLY after validating
        // the chain is fully connected (prevents the tick-thread disconnect race).
        publishPreparedTrackFastPathIfConnected(trackID: trackID, pool: pool)
    }

    private func deferPreparedTrackRepair(trackID: UUID, scheduled: TimeInterval?) {
        // The fast-path GATE (publish*FastPathIfConnected) now prevents the
        // disconnect-window race that caused this defer: a track is never
        // published fast-path-ready while its output chain is mid-rebuild, so the
        // tick `play()` never lands in the disconnected window. Steady-state
        // defers should therefore be ~0. This path remains ONLY as a bounded
        // last-resort BACKSTOP for any residual edge (e.g. an unforeseen
        // engine-level disconnect): it schedules a SINGLE main-hop repair per
        // deferral episode with a HARD PER-TRACK ATTEMPT CAP + linear backoff, so
        // a genuinely-unconnectable track can NEVER oscillate forever and pin the
        // main thread (the prior band-aid had no cap → ~100+ heals/run).
        let (didInsert, attempt): (Bool, Int) = withLifecycleLock {
            let inserted = markPreparedTrackRepairDeferredLocked(trackID: trackID)
            // Count attempts only on the transition INTO the deferred set so a
            // storm of re-defers within one episode does not inflate the count.
            if inserted {
                let next = (deferredPreparedTrackRepairAttempts[trackID] ?? 0) + 1
                deferredPreparedTrackRepairAttempts[trackID] = next
                return (true, next)
            }
            return (false, deferredPreparedTrackRepairAttempts[trackID] ?? 0)
        }
        if didInsert {
            guard attempt <= Self.maxDeferredRepairAttempts else {
                // Cap hit: stop scheduling. Log ONCE and leave the track deferred
                // (the tick path keeps dropping its triggers rather than throwing)
                // until a user-driven prepare/route/validate sweep heals it. This
                // bounds the backstop so it can never pin main.
                DevActivity.trace(
                    DevActivity.audioGraph,
                    "prepared sample graph repair backstop CAPPED (attempts=\(attempt)) track=\(trackID.uuidString) — leaving deferred until next prepare/validate"
                )
                SequencerTimingProbe.sampleFastPath(
                    trackID: trackID,
                    scheduled: scheduled,
                    actual: ProcessInfo.processInfo.systemUptime,
                    result: "repair-deferred-capped"
                )
                return
            }
            DevActivity.trace(
                DevActivity.audioGraph,
                "deferred prepared sample graph repair track=\(trackID.uuidString) attempt=\(attempt) reason=post-failure"
            )
            // Linear backoff: attempt N waits N * base. Keeps the backstop off the
            // main queue's hot path even in the (now unexpected) repeat case.
            let backoff = Double(attempt) * 0.02
            // realtime-allow-main-async: bounded last-resort self-heal off the tick path (capped + backed off, not event scheduling). Test: RealtimePathLintTests.
            DispatchQueue.main.asyncAfter(deadline: .now() + backoff) { [weak self] in
                guard let self else { return }
                MainActor.assumeIsolated {
                    self.repairDeferredPreparedTrackIfNeeded(trackID: trackID)
                }
            }
        }
        SequencerTimingProbe.sampleFastPath(
            trackID: trackID,
            scheduled: scheduled,
            actual: ProcessInfo.processInfo.systemUptime,
            result: didInsert ? "repair-deferred" : "repair-deferred-pending"
        )
    }

    /// Bounded last-resort self-heal for a track marked repair-deferred by a
    /// tick-path schedule failure. Re-prepares/repairs the prepared graph; the
    /// gated republish (publish*FastPathIfConnected) clears the deferred flag +
    /// resets the attempt count only if the chain validates as connected. Capped
    /// + backed-off by `deferPreparedTrackRepair`.
    @MainActor
    private func repairDeferredPreparedTrackIfNeeded(trackID: UUID) {
        // Still deferred? A concurrent prepare/route may already have healed it.
        guard withLifecycleLock({ deferredPreparedTrackRepairIDs.contains(trackID) }) else { return }
        // `prepareTrack` resolves the right branch (bus pool vs prepared master
        // pool), repairs the graph, and re-publishes through the fast-path gate
        // (which clears the deferred flag + attempt count on a validated chain).
        prepareTrack(trackID: trackID)
    }

    @discardableResult
    private func markPreparedTrackRepairDeferredLocked(trackID: UUID) -> Bool {
        _ = fastPathReadyTrackIDs.remove(trackID)
        return deferredPreparedTrackRepairIDs.insert(trackID).inserted
    }

    private func isPreparedTrackRepairDeferred(trackID: UUID) -> Bool {
        withLifecycleLock {
            deferredPreparedTrackRepairIDs.contains(trackID)
        }
    }

    /// Lock contract: callers MUST NOT hold `lifecycleLock`. Reads/publishes
    /// `trackFilters` / route levels under the lock; graph mutation runs
    /// without it.
    @MainActor
    private func repairTrackMixerOutput(trackID: UUID, mixer: AVAudioMixerNode) {
        // realtime-allow-graph-mutation: prepared track output setup/repair only, not event scheduling. Test: RealtimePathLintTests.
        audioGraph.attach(mixer)
        let (filter, busID, sends) = withLifecycleLock {
            () -> (SamplerFilterNode, UUID?, MainAudioGraph.TrackSendLevels) in
            let filter: SamplerFilterNode
            if let existing = trackFilters[trackID] {
                filter = existing
            } else {
                let next = SamplerFilterNode()
                trackFilters[trackID] = next
                filter = next
            }
            return (filter, trackOutputBusIDs[trackID], trackSendLevels[trackID] ?? .zero)
        }

        // realtime-allow-graph-mutation: prepared track output setup/repair only, not event scheduling. Test: RealtimePathLintTests.
        audioGraph.attach(filter.avNode)
        connectOutputIfNeeded(mixer, to: filter.avNode)
        if audioGraph.trackOutputDestinationForTesting(filter.avNode) == nil ||
            !outputConnectionExists(from: filter.avNode)
        {
            // Repair path: splice synchronously (no ramp dip). Repairs run
            // repeatedly during a rebuild/validate pass; overlapping deferred
            // dips on the same fanout race and can leave the filter
            // disconnected (the intermittent silence). The track's voices are
            // (re)wired here, not sounding through a stale path, so no click.
            audioGraph.connectTrackOutput(
                filter.avNode,
                to: busID,
                sends: sends,
                ramped: false
            )
        }
        audioGraph.setTrackMeterSources(trackIDs: [trackID], node: filter.avNode)
    }

    private func outputConnectionExists(from source: AVAudioNode, to destination: AVAudioNode) -> Bool {
        audioGraph.engine.outputConnectionPoints(for: source, outputBus: 0).contains { point in
            point.node === destination
        }
    }

    private func outputConnectionExists(from source: AVAudioNode) -> Bool {
        !audioGraph.engine.outputConnectionPoints(for: source, outputBus: 0).isEmpty
    }

    /// Caller must hold `lifecycleLock` (mutates `trackFilterFanouts`).
    private func filterFanoutLocked(for trackID: UUID) -> SamplerFilterFanout {
        if let fanout = trackFilterFanouts[trackID] {
            return fanout
        }
        let fanout = SamplerFilterFanout()
        trackFilterFanouts[trackID] = fanout
        return fanout
    }

    @MainActor
    private func connectOutputIfNeeded(_ source: AVAudioNode, to destination: AVAudioNode) {
        guard source.engine === audioGraph.engine,
              destination.engine === audioGraph.engine,
              !outputConnectionExists(from: source, to: destination)
        else {
            return
        }

        // realtime-allow-graph-mutation: prepared graph setup/repair connection only, not tick dispatch. Test: RealtimePathLintTests.
        audioGraph.disconnectOutput(source)
        // realtime-allow-graph-mutation: prepared graph setup/repair connection only, not tick dispatch. Test: RealtimePathLintTests.
        audioGraph.connect(source, to: destination)
    }

    /// Acquire `lifecycleLock` for the small in-memory critical section only.
    ///
    /// In DEBUG this maintains `TickPathMainSyncGuard.lifecycleLockDepthForCurrentThread`,
    /// so the `MainAudioGraph` graph-mutation entry points can trap if a live
    /// `AVAudioEngine.connect/disconnect` is attempted while this lock is held.
    /// That coupling is the mixer-mute / add-FX deadlock class: an unbounded
    /// HAL reconfig under `lifecycleLock` starves the tick path, which takes
    /// `lifecycleLock` every `prepareTick`. Control paths therefore read/swap
    /// the dictionaries here, RELEASE, then mutate the engine.
    @discardableResult
    private func withLifecycleLock<T>(_ work: () -> T) -> T {
        lifecycleLock.lock()
        #if DEBUG
        TickPathMainSyncGuard.lifecycleLockDepthForCurrentThread += 1
        #endif
        defer {
            #if DEBUG
            TickPathMainSyncGuard.lifecycleLockDepthForCurrentThread -= 1
            #endif
            lifecycleLock.unlock()
        }
        return work()
    }

    private func performOnMain<T>(_ work: @escaping @MainActor () -> T) -> T {
        if Thread.isMainThread {
            return MainActor.assumeIsolated {
                work()
            }
        }

        TickPathMainSyncGuard.assertNotSyncingToMainFromTickPath("SamplePlaybackEngine.performOnMain")
        var result: T?
        // realtime-allow-main-sync: document apply/setup path guarded against tick-thread use. Test: RealtimePathLintTests.
        DispatchQueue.main.sync {
            result = MainActor.assumeIsolated {
                work()
            }
        }
        return result!
    }
}

extension SamplePlaybackEngine {
    /// The bus voice pool's voice mixers for a track, in voice order. Lets a
    /// test inspect the live voice-mixer → bus-input-mixer → preMaster chain
    /// for a bus-routed sample track (the route-to-bus silence repro).
    func busVoiceMixersForTesting(trackID: UUID) -> [AVAudioMixerNode] {
        performOnMain { [self] in
            withLifecycleLock { busVoicePools[trackID]?.voiceMixers ?? [] }
        }
    }

    /// The per-track sum node for a bus-routed track: the single node every voice
    /// mixer feeds, which connects to the bus input mixer (one input per track)
    /// and is the track's meter source. Lets a test inspect the
    /// voiceMixers → trackSumMixer → bus-input-mixer → preMaster chain.
    func busTrackSumMixerForTesting(trackID: UUID) -> AVAudioMixerNode? {
        performOnMain { [self] in
            withLifecycleLock { busVoicePools[trackID]?.trackSumMixer }
        }
    }

    func disconnectFirstPreparedVoiceForTesting(trackID: UUID) {
        performOnMain { [self] in
            let voice: AVAudioPlayerNode? = withLifecycleLock {
                guard let voice = trackVoicePools[trackID]?.voices.first else { return nil }
                _ = fastPathReadyTrackIDs.remove(trackID)
                return voice
            }
            guard let voice else { return }
            // realtime-allow-graph-mutation: test hook deliberately breaks prepared graph. Test: RealtimePathLintTests.
            audioGraph.disconnectOutput(voice)
        }
    }

    func disconnectFirstPreparedVoiceForFastPathFailureForTesting(trackID: UUID) {
        performOnMain { [self] in
            let voice: AVAudioPlayerNode? = withLifecycleLock {
                guard let voice = trackVoicePools[trackID]?.voices.first else { return nil }
                _ = fastPathReadyTrackIDs.insert(trackID)
                return voice
            }
            guard let voice else { return }
            // realtime-allow-graph-mutation: test hook deliberately breaks prepared fast path. Test: RealtimePathLintTests.
            audioGraph.disconnectOutput(voice)
        }
    }

    func isFirstPreparedVoiceConnectedForTesting(trackID: UUID) -> Bool {
        performOnMain { [self] in
            withLifecycleLock {
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
            let mixer: AVAudioMixerNode? = withLifecycleLock {
                guard let mixer = trackMixers[trackID] else { return nil }
                _ = fastPathReadyTrackIDs.remove(trackID)
                return mixer
            }
            guard let mixer else { return }
            // realtime-allow-graph-mutation: test hook deliberately breaks prepared graph. Test: RealtimePathLintTests.
            audioGraph.disconnectOutput(mixer)
        }
    }

    func isPreparedTrackMixerOutputConnectedForTesting(trackID: UUID) -> Bool {
        performOnMain { [self] in
            withLifecycleLock {
                guard let mixer = trackMixers[trackID],
                      let filter = trackFilters[trackID]
                else {
                    return false
                }
                return outputConnectionExists(from: mixer, to: filter.avNode)
            }
        }
    }

    func disconnectPreparedTrackTerminalOutputForTesting(trackID: UUID) {
        performOnMain { [self] in
            let filter: SamplerFilterNode? = withLifecycleLock {
                guard let filter = trackFilters[trackID] else { return nil }
                _ = fastPathReadyTrackIDs.remove(trackID)
                return filter
            }
            guard let filter else { return }
            // realtime-allow-graph-mutation: test hook deliberately breaks prepared graph. Test: RealtimePathLintTests.
            audioGraph.disconnectOutput(filter.avNode)
        }
    }

    func isPreparedTrackTerminalOutputConnectedForTesting(trackID: UUID) -> Bool {
        performOnMain { [self] in
            withLifecycleLock {
                guard let filter = trackFilters[trackID] else {
                    return false
                }
                return outputConnectionExists(from: filter.avNode)
            }
        }
    }

    /// The per-track mixer's current `outputVolume` — the gain that mute
    /// ramps. Tests assert this (not the meter) for mute-as-gain behaviour.
    /// Returns nil if the track has no prepared mixer. Allows a brief settle so
    /// an in-flight ramp can reach its target.
    func trackOutputGainForTesting(trackID: UUID) -> Float? {
        performOnMain { [self] in
            withLifecycleLock {
                if let pool = busVoicePools[trackID] {
                    // The fader/mute gain lives on the per-track sum node (the
                    // track's own output); voice mixers stay at unity.
                    return pool.trackSumMixer.outputVolume
                }
                return trackMixers[trackID]?.outputVolume
            }
        }
    }

    /// ENGINE-TRUTH per-track send gains read from the live send-mixer nodes in
    /// `MainAudioGraph` (the value `setTrackSendLevels` ramps), keyed by the
    /// track's filter source node — the same node `setTrackSends` passes to the
    /// graph. Returns nil when no filter / send geometry exists yet. Used by the
    /// R4 scene-send rig to assert the applied preset gains exactly (A ⇒ sendB=0,
    /// B ⇒ sendA=0). NOTE: reads the node's current outputVolume, so callers must
    /// poll past the ~12 ms gain ramp for the settled value.
    func trackAppliedSendLevelsForTesting(trackID: UUID) -> (sendA: Float, sendB: Float)? {
        let filter: SamplerFilterNode? = performOnMain { [self] in
            withLifecycleLock { trackFilters[trackID] }
        }
        guard let filter else { return nil }
        guard let readout = audioGraph.trackSendReadoutForTesting(filter.avNode) else { return nil }
        return (readout.sendAGain, readout.sendBGain)
    }

    /// The track's output chokepoint mixer node (track mixer, or first bus-voice
    /// mixer) — captured BEFORE a teardown so a test can watch its `outputVolume`
    /// fade to 0 across the ramp-before-detach. Returns nil once the track's
    /// dictionary entries are gone (after the synchronous under-lock removal).
    func trackOutputChokepointNodeForTesting(trackID: UUID) -> AVAudioMixerNode? {
        performOnMain { [self] in
            withLifecycleLock {
                if let pool = busVoicePools[trackID] {
                    // Chokepoint is the per-track sum node (the single node the
                    // whole bus-routed track flows through).
                    return pool.trackSumMixer
                }
                return trackMixers[trackID]
            }
        }
    }

    /// The bus ID the engine has ACTUALLY routed this sample track's output to
    /// (nil = master). Engine-truth: set inside `setTrackOutputBus` when the
    /// graph reconnects, not read from the document. The routing-stress gate
    /// asserts this against the requested destination so a parse-only no-op is
    /// caught. Returns ("n/a", nil) marker via Optional<Optional> collapse:
    /// outer nil = no engine record for this track (not a sample track).
    func trackOutputBusIDForTesting(trackID: UUID) -> UUID?? {
        performOnMain { [self] in
            withLifecycleLock {
                guard trackMixers[trackID] != nil || trackVoicePools[trackID] != nil || busVoicePools[trackID] != nil else {
                    return UUID??.none
                }
                return .some(trackOutputBusIDs[trackID])
            }
        }
    }

    func preparedTrackRouteReadoutForTesting(trackID: UUID) -> [String: Bool] {
        performOnMain { [self] in
            withLifecycleLock {
                if let pool = busVoicePools[trackID],
                   let voice = pool.voices.first,
                   let mixer = pool.voiceMixers.first
                {
                    return [
                        "prepared": true,
                        "busSafeRoute": true,
                        "voiceToVoiceFilter": false,
                        "voiceFilterToMixer": outputConnectionExists(from: voice, to: mixer),
                        "mixerToTrackFilter": false,
                        "trackFilterHasOutput": outputConnectionExists(from: mixer),
                        "voicePlayable": audioGraph.isNodePlayableNow(voice),
                    ]
                }
                guard let pool = trackVoicePools[trackID],
                      let voice = pool.voices.first,
                      let voiceFilter = pool.voiceFilters.first
                else {
                    return ["prepared": false]
                }
                guard let mixer = trackMixers[trackID],
                      let trackFilter = trackFilters[trackID]
                else {
                    return ["prepared": false]
                }
                return [
                    "prepared": true,
                    "busSafeRoute": false,
                    "voiceToVoiceFilter": outputConnectionExists(from: voice, to: voiceFilter.avNode),
                    "voiceFilterToMixer": outputConnectionExists(from: voiceFilter.avNode, to: mixer),
                    "mixerToTrackFilter": outputConnectionExists(from: mixer, to: trackFilter.avNode),
                    "trackFilterHasOutput": outputConnectionExists(from: trackFilter.avNode),
                    "voicePlayable": audioGraph.isNodePlayableNow(voice),
                ]
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
