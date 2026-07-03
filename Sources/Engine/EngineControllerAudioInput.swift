import AVFoundation
import Foundation

/// Audio-input runtime management for `EngineController` — arm/record/capture
/// lifecycle, monitor-mode switching, loop scheduling, capture plans,
/// route-state computation, runtime registry interactions, and capture
/// publication. Mechanically extracted from EngineController.swift (engine
/// carve-up stage: audio input); statements, ordering, and locking topology
/// are unchanged. Tick-path entry points (advanceAudioInputScheduling,
/// scheduleActiveAudioInputLoopPlayback) keep their TickPathMainSyncGuard
/// and stateLock contracts exactly as documented inline.
extension EngineController {
    /// Called after the user grants microphone access so route states and
    /// graph connections reflect the now-usable input device.
    func microphoneAccessChanged() {
        refreshAudioInputRouteStates()
    }

    /// Recompute every audio-input runtime's route state against the current
    /// device's channel count, then resync graph routing.
    func refreshAudioInputRouteStates() {
        let inputTrackIDs = withStateLock { Array(trackRuntime.audioInputRuntimes.keys) }
        for trackID in inputTrackIDs {
            _ = updateAudioInputRuntime(trackID: trackID) { runtime in
                runtime.routeState = audioInputRouteState(for: runtime.selectedInputChannel)
            }
        }
        syncAudioInputRouting(for: currentDocumentModel)
    }

    func audioInputRuntime(for trackID: UUID) -> AudioInputTrackRuntime? {
        _ = audioInputRuntimeRevision
        return withStateLock { trackRuntime.audioInputRuntimes[trackID] }
    }

    /// Stress-test variant of `audioInputRuntime(for:)`: the same
    /// `stateLock` read WITHOUT the `@Observable` registration read. The
    /// churn stress tests call this from worker queues standing in for
    /// main; the observable surface is main-confined in production (every
    /// product caller is SwiftUI), so an off-main registration read would
    /// be a TSan race the product does not have (2026-06-12 lane finding 1).
    func audioInputRuntimeForStressTesting(_ trackID: UUID) -> AudioInputTrackRuntime? {
        withStateLock { trackRuntime.audioInputRuntimes[trackID] }
    }

    /// Stress-test variant of `audioInputRuntimeTrackIDs` (same contract
    /// as `audioInputRuntimeForStressTesting`).
    var audioInputRuntimeTrackIDsForStressTesting: Set<UUID> {
        withStateLock { Set(trackRuntime.audioInputRuntimes.keys) }
    }

    func audioInputRoutingReadoutForTesting(trackID: UUID) -> MainAudioGraph.AudioInputRoutingReadout? {
        mainAudioGraph.audioInputRoutingReadoutForTesting(trackID: trackID)
    }

    func audioInputTrackSendReadoutForTesting(trackID: UUID) -> MainAudioGraph.TrackSendReadout? {
        guard let readout = mainAudioGraph.audioInputRoutingReadoutForTesting(trackID: trackID) else {
            return nil
        }
        return mainAudioGraph.trackSendReadoutForTesting(readout.outputMixer)
    }

    var audioInputRuntimeTrackIDs: Set<UUID> {
        _ = audioInputRuntimeRevision
        return withStateLock { Set(trackRuntime.audioInputRuntimes.keys) }
    }

    enum AudioInputRecordQuantize: String, CaseIterable, Equatable, Sendable {
        case bar
        case phrase
    }

    @discardableResult
    func armAudioInput(
        trackID: UUID,
        quantize: AudioInputRecordQuantize = .bar,
        pendingStartTick: UInt64? = nil
    ) -> Bool {
        let selectedInputChannel = withStateLock { trackRuntime.audioInputRuntimes[trackID]?.selectedInputChannel }
        guard let selectedInputChannel,
              audioInputRouteState(for: selectedInputChannel) == .available
        else {
            syncAudioInputRouting(for: currentDocumentModel)
            return false
        }

        let scheduledStartTick = pendingStartTick ?? {
            switch quantize {
            case .bar:
                return nextAudioInputBarBoundary(after: currentTransportTick)
            case .phrase:
                return nextAudioInputPhraseBoundary(after: currentTransportTick)
            }
        }()
        let didUpdate = updateAudioInputRuntime(trackID: trackID) { runtime in
            runtime.armState = .armed
            runtime.pendingStartTick = scheduledStartTick
            runtime.pendingStopTick = nil
            runtime.pendingLoopStartTick = nil
            runtime.captureStartTick = nil
            runtime.captureEndTick = nil
            runtime.armedRecordBarLength = runtime.recordBarLength
            runtime.scheduledLoopPlaybackID = nil
            runtime.transientFrameCount = 0
            runtime.routeState = audioInputRouteState(for: runtime.selectedInputChannel)
            applyAudioInputCaptureSnapshot(
                readAudioInputCaptureStore {
                    audioInputCaptureStore.prepareCapture(trackID: trackID)
                },
                to: &runtime
            )
        }
        syncAudioInputRouting(for: currentDocumentModel)
        return didUpdate
    }

    @discardableResult
    func cancelAudioInputArm(trackID: UUID) -> Bool {
        let didUpdate = updateAudioInputRuntime(trackID: trackID) { runtime in
            switch runtime.armState {
            case .armed, .recording:
                runtime.armState = runtime.hasRecordedLoop ? .hasLoop : .idle
                runtime.pendingStartTick = nil
                runtime.pendingStopTick = nil
                runtime.pendingLoopStartTick = nil
                runtime.captureStartTick = nil
                runtime.captureEndTick = nil
                runtime.armedRecordBarLength = nil
                runtime.transientFrameCount = 0
                applyAudioInputCaptureSnapshot(
                    readAudioInputCaptureStore {
                        audioInputCaptureStore.cancelCapture(trackID: trackID)
                    },
                    to: &runtime
                )
                audioInputCapturePCMWriterSlot.install(nil)
            case .idle, .hasLoop:
                runtime.pendingStartTick = nil
                runtime.pendingStopTick = nil
                runtime.pendingLoopStartTick = nil
            }
        }
        syncAudioInputRouting(for: currentDocumentModel)
        return didUpdate
    }

    @discardableResult
    func setAudioInputMonitorMode(trackID: UUID, mode: AudioInputMonitorMode) -> Bool {
        let didUpdate = updateAudioInputRuntime(trackID: trackID) { runtime in
            runtime.monitorMode = mode
            switch mode {
            case .input:
                runtime.activeMonitorMode = .input
                runtime.pendingLoopStartTick = nil
                runtime.scheduledLoopPlaybackID = nil
            case .loop:
                if runtime.hasRecordedLoop {
                    if runtime.activeMonitorMode != .loop {
                        runtime.pendingLoopStartTick = nextAudioInputBarBoundary(after: currentTransportTick)
                    }
                } else {
                    runtime.activeMonitorMode = .loop
                    runtime.pendingLoopStartTick = nil
                }
            }
        }
        syncAudioInputRouting(for: currentDocumentModel)
        return didUpdate
    }

    @discardableResult
    func rerouteAudioInput(trackID: UUID, channel: AudioInputChannel) -> Bool {
        let didUpdate = updateAudioInputRuntime(trackID: trackID) { runtime in
            runtime.selectedInputChannel = channel
            runtime.routeState = audioInputRouteState(for: channel)
        }
        syncAudioInputRouting(for: currentDocumentModel)
        return didUpdate
    }

    @discardableResult
    func markAudioInputLoopPlaceholder(trackID: UUID, waveformBuckets: [Float] = []) -> Bool {
        let didUpdate = updateAudioInputRuntime(trackID: trackID) { runtime in
            runtime.armState = .hasLoop
            runtime.pendingStartTick = nil
            runtime.pendingStopTick = nil
            runtime.captureStartTick = nil
            runtime.captureEndTick = nil
            runtime.armedRecordBarLength = nil
            runtime.recordedLoopID = UUID()
            runtime.recordedLoopBarLength = runtime.recordBarLength
            runtime.recordedLibraryAssetID = nil
            runtime.scheduledLoopPlaybackID = nil
            runtime.transientFrameCount = 0
            applyAudioInputCaptureSnapshot(
                readAudioInputCaptureStore {
                    audioInputCaptureStore.replaceCompletedLoop(
                        trackID: trackID,
                        waveformBuckets: waveformBuckets
                    )
                },
                to: &runtime
            )
            audioInputCapturePCMWriterSlot.install(nil)
        }
        syncAudioInputRouting(for: currentDocumentModel)
        return didUpdate
    }

    func drainAudioInputCapturePublicationForTesting() {
        readAudioInputCaptureStore {}
    }

    func recordAudioInputBufferForTesting(trackID: UUID, buffer: AVAudioPCMBuffer) {
        processAudioInputBuffer(trackID: trackID, buffer: buffer)
    }

    func processAudioInputBuffer(trackID: UUID, buffer: AVAudioPCMBuffer) {
        let summary = AudioInputCaptureStore.summarize(buffer: buffer)
        let copyReceipt = audioInputCapturePCMWriterSlot.copy(trackID: trackID, from: buffer)
        audioInputCaptureTransport.write(
            trackID: trackID,
            packet: AudioInputCaptureBufferPacket(
                summary: summary,
                captureWriterID: copyReceipt?.writerID,
                copiedFrameCount: copyReceipt?.frameCount ?? 0
            )
        )
    }

    func startAudioInputCaptureDrainTimer() {
        guard audioInputCaptureDrainTimer == nil else { return }

        let timer = DispatchSource.makeTimerSource(queue: audioInputCapturePublicationQueue)
        timer.schedule(
            deadline: .now() + .milliseconds(33),
            repeating: .milliseconds(33),
            leeway: .milliseconds(5)
        )
        timer.setEventHandler { [weak self] in
            self?.drainAudioInputCaptureTransport()
        }
        timer.resume()
        audioInputCaptureDrainTimer = timer
    }

    private func drainAudioInputCaptureTransport() {
        audioInputCaptureTransport.drain { trackID, packet in
            let snapshot = audioInputCaptureStore.process(packet: packet, trackID: trackID)
            publishAudioInputCaptureSnapshot(trackID: trackID, snapshot: snapshot)
        }
    }

    private func publishAudioInputCaptureSnapshot(trackID: UUID, snapshot: AudioInputCaptureSnapshot) {
        publishToMain { [weak self] in
            guard let self else { return }
            _ = self.updateAudioInputRuntime(trackID: trackID) { runtime in
                self.applyAudioInputCaptureSnapshot(snapshot, to: &runtime)
            }
        }
    }

    private func applyAudioInputCaptureSnapshot(
        _ snapshot: AudioInputCaptureSnapshot,
        to runtime: inout AudioInputTrackRuntime
    ) {
        guard snapshot.revision >= runtime.captureSnapshotRevision else {
            return
        }
        runtime.captureSnapshotRevision = snapshot.revision
        runtime.liveLevel = snapshot.liveLevel
        runtime.recordingProgress = snapshot.recordingProgress
        runtime.captureWaveformBuckets = snapshot.streamedWaveformBuckets
        runtime.waveformBuckets = snapshot.completedWaveformBuckets
    }

    private func readAudioInputCaptureStore<T>(_ body: () -> T) -> T {
        if DispatchQueue.getSpecific(key: audioInputCapturePublicationQueueKey) != nil {
            drainAudioInputCaptureTransport()
            return body()
        }
        return audioInputCapturePublicationQueue.sync {
            self.drainAudioInputCaptureTransport()
            return body()
        }
    }

    func syncAudioInputRuntimes(for documentModel: Project) {
        let desiredTracks = Array(documentModel.tracks.filter { $0.trackType == .audioInput }.prefix(1))
        let desiredIDs = Set(desiredTracks.map(\.id))
        if desiredIDs.isEmpty {
            audioInputCapturePCMWriterSlot.install(nil)
        }
        readAudioInputCaptureStore {
            audioInputCaptureStore.keepOnly(trackIDs: desiredIDs)
        }

        let changed = withStateLock {
            var next = trackRuntime.audioInputRuntimes.filter { desiredIDs.contains($0.key) }
            for track in desiredTracks {
                var runtime = next[track.id]
                    ?? AudioInputTrackRuntime(
                        trackID: track.id,
                        recordBarLength: track.recordBarLength,
                        selectedInputChannel: track.inputChannel,
                        routeState: audioInputRouteState(for: track.inputChannel)
                    )
                runtime.recordBarLength = StepSequenceTrack.normalizedRecordBarLength(track.recordBarLength)
                runtime.selectedInputChannel = track.inputChannel
                runtime.routeState = audioInputRouteState(for: track.inputChannel)
                next[track.id] = runtime
            }

            if next != trackRuntime.audioInputRuntimes {
                trackRuntime.audioInputRuntimes = next
                return true
            }
            return false
        }
        if changed {
            // @Observable bump outside stateLock and on main
            // (see updateAudioInputRuntime).
            publishToMain { [weak self] in
                self?.audioInputRuntimeRevision &+= 1
            }
        }
    }

    func syncAudioInputRouting(for documentModel: Project) {
        guard !bypassAudioInputRoutingSyncForTesting else { return }
        mainAudioGraph.syncAudioInputRoutings(audioInputRoutingRequests(for: documentModel))
    }

    func updateAudioInputRoutingParameters(for documentModel: Project) {
        guard !bypassAudioInputRoutingSyncForTesting else { return }
        mainAudioGraph.updateAudioInputRoutingParameters(audioInputRoutingRequests(for: documentModel))
    }

    private func audioInputRoutingRequests(for documentModel: Project) -> [MainAudioGraph.AudioInputRoutingRequest] {
        let effectiveMuteState = Self.effectiveMixerMuteState(for: documentModel)
        let crossfader = masterBusPerformanceOverlay.crossfaderOverride
            ?? documentModel.masterBus.abSelection?.crossfader
        let runtimes = withStateLock { trackRuntime.audioInputRuntimes }
        return documentModel.tracks.compactMap { track -> MainAudioGraph.AudioInputRoutingRequest? in
            guard let runtime = runtimes[track.id] else { return nil }
            let mix = Self.effectiveMix(
                for: track.mix,
                isMuted: effectiveMuteState.mutedTrackIDs.contains(track.id),
                sceneGain: track.mix.sceneMembership.gain(crossfader: crossfader)
            )
            return MainAudioGraph.AudioInputRoutingRequest(
                trackID: track.id,
                source: Self.audioInputMonitorSource(for: runtime),
                selectedChannel: runtime.selectedInputChannel,
                outputBusID: track.outputBusID,
                mix: mix
            )
        }
    }

    /// Cheap tick-side probe: true when some recorded loop still needs a
    /// playback schedule. The actual scheduling work hops to main (it talks
    /// to the audio graph), so the tick queue only pays the hop when there
    /// is something to do.
    var hasPendingAudioInputLoopSchedule: Bool {
        withStateLock {
            trackRuntime.audioInputRuntimes.values.contains { runtime in
                runtime.activeMonitorMode == .loop
                    && runtime.recordedLoopID != nil
                    && runtime.scheduledLoopPlaybackID != runtime.recordedLoopID
            }
        }
    }

    /// Returns false when any pending loop schedule attempt failed (the
    /// caller rebuilds routing so the next tick's retry finds a wired
    /// player); true when nothing was pending or all attempts succeeded.
    @discardableResult
    func scheduleActiveAudioInputLoopPlayback() -> Bool {
        var allSucceeded = true
        let candidates = withStateLock {
            trackRuntime.audioInputRuntimes.values.compactMap { runtime -> (UUID, UUID)? in
                guard runtime.activeMonitorMode == .loop,
                      let recordedLoopID = runtime.recordedLoopID,
                      runtime.scheduledLoopPlaybackID != recordedLoopID
                else {
                    return nil
                }
                return (runtime.trackID, recordedLoopID)
            }
        }

        for (trackID, loopID) in candidates {
            guard let buffer = readAudioInputCaptureStore({
                audioInputCaptureStore.completedLoopPlaybackBuffer(trackID: trackID)
            }) else {
                continue
            }
            guard mainAudioGraph.scheduleAudioInputLoopPlayback(trackID: trackID, buffer: buffer) else {
                allSucceeded = false
                continue
            }
            _ = updateAudioInputRuntime(trackID: trackID) { runtime in
                guard runtime.recordedLoopID == loopID else { return }
                runtime.scheduledLoopPlaybackID = loopID
            }
        }
        return allSucceeded
    }

    private static func audioInputMonitorSource(for runtime: AudioInputTrackRuntime) -> MainAudioGraph.AudioInputMonitorSource {
        guard runtime.routeState == .available else { return .silent }
        switch runtime.activeMonitorMode {
        case .input:
            return .input
        case .loop:
            return runtime.hasRecordedLoop ? .loop : .silent
        }
    }

    func advanceAudioInputScheduling(at tickIndex: UInt64) -> Bool {
        // Capture plans resolve before stateLock is taken. The format read
        // is a lock-free snapshot now (no main hop), but plan resolution
        // still allocates and reads a foreign lock — keeping it outside the
        // tick-critical stateLock section is cheap hygiene.
        let capturePlans = resolveAudioInputCapturePlans(at: tickIndex)
        let didChange = advanceAudioInputSchedulingLocked(at: tickIndex, capturePlans: capturePlans)
        if didChange {
            // @Observable bump outside stateLock (see updateAudioInputRuntime),
            // and on main because this runs from the tick queue.
            publishToMain { [weak self] in
                self?.audioInputRuntimeRevision &+= 1
            }
        }
        return didChange
    }

    /// Pre-resolves the capture plan for every track whose recording would
    /// begin at this tick, BEFORE `stateLock` is taken (see note above).
    /// The runtime is re-validated under the lock; a plan resolved for a
    /// track whose state moved on in the meantime is simply unused.
    private func resolveAudioInputCapturePlans(at tickIndex: UInt64) -> [UUID: AudioInputCapturePlan] {
        guard isAudioInputBarBoundary(tickIndex) else { return [:] }
        let beginCandidates: [(trackID: UUID, bars: Int)] = withStateLock {
            trackRuntime.audioInputRuntimes.values.compactMap { runtime in
                guard runtime.armState == .armed,
                      let startTick = runtime.pendingStartTick,
                      tickIndex >= startTick
                else {
                    return nil
                }
                let bars = StepSequenceTrack.normalizedRecordBarLength(
                    runtime.armedRecordBarLength ?? runtime.recordBarLength
                )
                return (runtime.trackID, bars)
            }
        }

        var plans: [UUID: AudioInputCapturePlan] = [:]
        for candidate in beginCandidates {
            plans[candidate.trackID] = audioInputCapturePlan(trackID: candidate.trackID, bars: candidate.bars)
        }
        return plans
    }

    private func advanceAudioInputSchedulingLocked(
        at tickIndex: UInt64,
        capturePlans: [UUID: AudioInputCapturePlan]
    ) -> Bool {
        withStateLock {
            var didChange = false
            for trackID in trackRuntime.audioInputRuntimes.keys {
                guard var runtime = trackRuntime.audioInputRuntimes[trackID] else {
                    continue
                }
                let original = runtime

                if runtime.armState == .recording,
                   let endTick = runtime.captureEndTick,
                   tickIndex >= endTick,
                   isAudioInputBarBoundary(tickIndex)
                {
                    completeAudioInputCapture(&runtime, at: tickIndex)
                }

                if runtime.armState == .armed,
                   let startTick = runtime.pendingStartTick,
                   tickIndex >= startTick,
                   isAudioInputBarBoundary(tickIndex)
                {
                    beginAudioInputCapture(&runtime, at: tickIndex, capturePlan: capturePlans[trackID])
                }

                if runtime.armState == .recording,
                   let startTick = runtime.captureStartTick,
                   let endTick = runtime.captureEndTick,
                   tickIndex < endTick
                {
                    let span = max(1, endTick &- startTick)
                    let elapsed = min(tickIndex &- startTick, span)
                    applyAudioInputCaptureSnapshot(
                        readAudioInputCaptureStore {
                            audioInputCaptureStore.updateProgress(
                                trackID: runtime.trackID,
                                progress: Double(elapsed) / Double(span)
                            )
                        },
                        to: &runtime
                    )
                }

                if let loopStartTick = runtime.pendingLoopStartTick,
                   tickIndex >= loopStartTick,
                   isAudioInputBarBoundary(tickIndex)
                {
                    runtime.activeMonitorMode = .loop
                    runtime.pendingLoopStartTick = nil
                }

                if runtime != original {
                    trackRuntime.audioInputRuntimes[trackID] = runtime
                    didChange = true
                }
            }

            return didChange
        }
    }

    /// `capturePlan` is resolved by the caller OUTSIDE `stateLock`
    /// (`resolveAudioInputCapturePlans`): the plan reads the graph's
    /// capture-format snapshot and allocates — kept out of the
    /// tick-critical stateLock section.
    private func beginAudioInputCapture(
        _ runtime: inout AudioInputTrackRuntime,
        at tickIndex: UInt64,
        capturePlan: AudioInputCapturePlan?
    ) {
        let bars = StepSequenceTrack.normalizedRecordBarLength(runtime.armedRecordBarLength ?? runtime.recordBarLength)
        let endTick = tickIndex &+ UInt64(bars * stepsPerBar)
        runtime.armState = .recording
        runtime.pendingStartTick = nil
        runtime.pendingStopTick = endTick
        runtime.captureStartTick = tickIndex
        runtime.captureEndTick = endTick
        runtime.armedRecordBarLength = bars
        runtime.transientFrameCount = 0
        runtime.activeMonitorMode = .input
        runtime.pendingLoopStartTick = nil
        let captureWriter = capturePlan.flatMap {
            AudioInputCapturePCMWriter(trackID: runtime.trackID, plan: $0)
        }
        audioInputCapturePCMWriterSlot.install(captureWriter)
        let captureStart = readAudioInputCaptureStore {
            audioInputCaptureStore.beginCapture(trackID: runtime.trackID, writer: captureWriter)
        }
        applyAudioInputCaptureSnapshot(
            captureStart,
            to: &runtime
        )
    }

    private func audioInputCapturePlan(trackID: UUID, bars: Int) -> AudioInputCapturePlan? {
        if let override = audioInputCapturePlanOverrideForTesting {
            return override(trackID, bars)
        }

        // The capture-format read is a lock-protected snapshot lookup —
        // main publishes it at every graph reconfiguration point
        // (MainAudioGraph.publishAudioInputCaptureFormatsOnMain). No main
        // hop: this was the last waived TickPathMainSyncGuard hop, and the
        // guard now traps. A snapshot miss (mid-reconfigure race) returns
        // nil and the capture proceeds without a PCM writer — degraded, but
        // never blocking the tick queue.
        guard let format = mainAudioGraph.audioInputCaptureFormat(trackID: trackID) else {
            return nil
        }

        let beatsPerBar = 4.0
        let durationSeconds = (Double(bars) * beatsPerBar * 60.0) / max(currentBPM, 1)
        let expectedFrameCount = Int((durationSeconds * format.sampleRate).rounded(.up))
        let tapSlackFrameCount = 4096
        return AudioInputCapturePlan(
            sampleRate: format.sampleRate,
            channelCount: Int(format.channelCount),
            maximumFrameCount: max(1, expectedFrameCount + tapSlackFrameCount)
        )
    }

    private func completeAudioInputCapture(_ runtime: inout AudioInputTrackRuntime, at tickIndex: UInt64) {
        let bars = StepSequenceTrack.normalizedRecordBarLength(runtime.armedRecordBarLength ?? runtime.recordBarLength)
        let startTick = runtime.captureStartTick ?? tickIndex
        runtime.armState = .hasLoop
        runtime.pendingStartTick = nil
        runtime.pendingStopTick = nil
        runtime.captureStartTick = nil
        runtime.captureEndTick = nil
        runtime.armedRecordBarLength = nil
        runtime.recordedLoopID = UUID()
        runtime.recordedLoopBarLength = bars
        runtime.recordedLibraryAssetID = nil
        runtime.scheduledLoopPlaybackID = nil
        runtime.transientFrameCount = Int(tickIndex &- startTick)
        let completedPCM = readAudioInputCaptureStore { () -> AudioInputCapturedPCM? in
            applyAudioInputCaptureSnapshot(
                audioInputCaptureStore.completeCapture(trackID: runtime.trackID),
                to: &runtime
            )
            return audioInputCaptureStore.completedLoopPCM(trackID: runtime.trackID)
        }
        audioInputCapturePCMWriterSlot.install(nil)
        // Persist the take into the global recording library. We only capture
        // the PCM reference here (value type, COW); the file write happens on
        // the persistence queue — never on this tick path and never on main.
        schedulePersistCapturedRecording(pcm: completedPCM, trackID: runtime.trackID, barCount: bars)
        // Auto-switch to Buffer the moment the take completes (owner
        // direction): the captured loop becomes what you hear; Live is one
        // toggle away. Completion lands on a bar boundary, so entry is
        // immediate.
        runtime.monitorMode = .loop
        runtime.pendingLoopStartTick = nil
        runtime.activeMonitorMode = .loop
    }

    /// Write a completed capture into the recording library. Name/BPM are
    /// main-published state, so they resolve on main; the blocking file IO
    /// runs on `recordingPersistenceQueue`. A write failure traces to the
    /// activity log and leaves the in-memory loop untouched — the session
    /// keeps playing from memory.
    private func schedulePersistCapturedRecording(
        pcm: AudioInputCapturedPCM?,
        trackID: UUID,
        barCount: Int
    ) {
        guard let recordingLibrary else { return }
        guard let pcm, pcm.frameCount > 0 else {
            DevActivity.trace(DevActivity.library, "recording persist skipped: no PCM for track \(trackID)")
            return
        }

        publishToMain { [weak self] in
            guard let self else { return }
            let trackName = self.currentDocumentModel.tracks.first(where: { $0.id == trackID })?.name ?? "Audio Input"
            let bpm = self.currentBPM
            self.recordingPersistenceQueue.async { [weak self] in
                guard let self else { return }
                do {
                    let asset = try recordingLibrary.storeRecording(
                        pcm: pcm,
                        sourceTrackName: trackName,
                        barCount: barCount,
                        bpm: bpm
                    )
                    DevActivity.trace(DevActivity.library, "recording persisted: \(asset.fileName)")
                    self.publishToMain { [weak self] in
                        guard let self else { return }
                        _ = self.updateAudioInputRuntime(trackID: trackID) { runtime in
                            runtime.recordedLibraryAssetID = asset.id
                        }
                        // Recordings double as samples; rescan so pickers see
                        // the new take without an app restart.
                        self.sampleLibrary.reload()
                        self.recordingPersistenceObserverForTesting?(.success(asset))
                    }
                } catch {
                    NSLog("[EngineController] recording persist failed (loop keeps playing from memory): \(error)")
                    DevActivity.trace(DevActivity.library, "recording persist FAILED: \(error)")
                    self.publishToMain { [weak self] in
                        self?.recordingPersistenceObserverForTesting?(.failure(error))
                    }
                }
            }
        }
    }

    private func updateAudioInputRuntime(
        trackID: UUID,
        update: (inout AudioInputTrackRuntime) -> Void
    ) -> Bool {
        let updated = withStateLock {
            guard var runtime = trackRuntime.audioInputRuntimes[trackID] else {
                return false
            }
            update(&runtime)
            trackRuntime.audioInputRuntimes[trackID] = runtime
            return true
        }
        if updated {
            // The @Observable revision bump must happen OUTSIDE stateLock:
            // Observation's willSet can synchronously re-evaluate SwiftUI
            // bodies, and those bodies read engine state through the same
            // lock — observed as a main-thread deadlock the moment live
            // input levels started publishing at 60Hz.
            //
            // AND it must happen ON MAIN (D4): this is called from the tick
            // queue (loop-playback bookkeeping), and an off-main write to
            // @Observable storage runs observer callbacks on the tick thread
            // — the runtime-confirmed deadlock class when main is parked in
            // clock.stop()'s queue.sync. publishToMain runs inline when
            // already on main, preserving synchronous test drivers.
            publishToMain { [weak self] in
                self?.audioInputRuntimeRevision &+= 1
            }
        }
        return updated
    }

    private func audioInputRouteState(for channel: AudioInputChannel) -> AudioInputRouteState {
        Self.audioInputRouteState(for: channel, availableChannelCount: availableAudioInputChannelCount)
    }

    /// Device input channel count for UI affordances (input selector,
    /// arm-availability messaging).
    var audioInputAvailableChannels: Int {
        availableAudioInputChannelCount
    }

    private var availableAudioInputChannelCount: Int {
        if let audioInputAvailableChannelCountOverrideForTesting {
            return max(0, audioInputAvailableChannelCountOverrideForTesting)
        }
        return mainAudioGraph.availableInputChannelCount
    }

    private func isAudioInputBarBoundary(_ tickIndex: UInt64) -> Bool {
        tickIndex % UInt64(stepsPerBar) == 0
    }

    /// Next phrase-cycle boundary for quantized record starts. Uses the live
    /// phrase navigation state (cycle start tick + current phrase length);
    /// falls back to the next bar when no phrase is playing. A queued phrase
    /// switch after arming can move the actual boundary — v1 records at the
    /// boundary scheduled at arm time.
    private func nextAudioInputPhraseBoundary(after tickIndex: UInt64) -> UInt64 {
        let (cycleStart, phraseID): (UInt64, UUID?) = {
            phraseNavigationLock.lock()
            defer { phraseNavigationLock.unlock() }
            return (phraseNavigationState.phraseCycleStartTick, phraseNavigationState.currentPhraseID)
        }()

        let snapshot = tickState.currentPlaybackSnapshot()
        guard let phraseID,
              let buffer = snapshot.phraseBuffer(for: phraseID),
              buffer.stepCount > 0
        else {
            return nextAudioInputBarBoundary(after: tickIndex)
        }

        let phraseLength = UInt64(buffer.stepCount)
        let sinceCycleStart = tickIndex >= cycleStart ? tickIndex &- cycleStart : 0
        let intoPhrase = sinceCycleStart % phraseLength
        let ticksUntilBoundary = intoPhrase == 0 ? phraseLength : phraseLength - intoPhrase
        return tickIndex &+ ticksUntilBoundary
    }

    /// Push the document's record length into the live runtime so the next
    /// arm uses it without waiting for a full document apply.
    @discardableResult
    func setAudioInputRecordBarLength(trackID: UUID, bars: Int) -> Bool {
        DevActivity.trace(DevActivity.engine, "setAudioInputRecordBarLength bars=\(bars)")
        return updateAudioInputRuntime(trackID: trackID) { runtime in
            runtime.recordBarLength = StepSequenceTrack.normalizedRecordBarLength(bars)
        }
    }

    private func nextAudioInputBarBoundary(after tickIndex: UInt64) -> UInt64 {
        let barLength = UInt64(stepsPerBar)
        let ticksIntoBar = tickIndex % barLength
        let ticksUntilNextBar = ticksIntoBar == 0 ? barLength : barLength - ticksIntoBar
        return tickIndex &+ ticksUntilNextBar
    }

    static func audioInputRouteState(
        for channel: AudioInputChannel,
        availableChannelCount: Int
    ) -> AudioInputRouteState {
        // Any input at all is routable: mono/stereo is a property of the
        // track's content, never a hardware requirement. A stereo selection
        // on a mono device duplicates; a mono selection beyond the device's
        // channels clamps. The meters reveal one-sided signals.
        availableChannelCount >= 1 ? .available : .silentUnavailable
    }
}
