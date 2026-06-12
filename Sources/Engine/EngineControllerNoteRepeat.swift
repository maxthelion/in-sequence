import Foundation

/// Note-repeat runtime for `EngineController` — engage/release gestures,
/// per-tick repeat scheduling and dispatch, captured-step bookkeeping, and
/// repeat-owned event cleanup. Mechanically extracted from
/// EngineController.swift (engine carve-up stage: note repeat); statements,
/// ordering, and locking topology are unchanged.
extension EngineController {
    func engageNoteRepeat(trackID: UUID) {
        let snapshot = tickState.currentPlaybackSnapshot()
        guard supportsNoteRepeat(trackID: trackID, in: snapshot),
              let track = snapshot.tracks.first(where: { $0.id == trackID })
        else {
            return
        }

        cleanupNoteRepeats(for: [trackID], now: ProcessInfo.processInfo.systemUptime, clearActiveState: true)
        withStateLock {
            activeNoteRepeatsByTrackID[trackID] = ActiveNoteRepeatRuntime(
                trackID: trackID,
                engagedAtTickIndex: currentTransportTick,
                interval: track.noteRepeatInterval,
                capturedStep: currentNoteRepeatCapturesByTrackID[trackID]
            )
        }
        publishNoteRepeatRuntimeUIRevision()
        invalidatePreparedNoteRepeatScheduling()
    }

    func releaseNoteRepeat(trackID: UUID) {
        cleanupNoteRepeats(for: [trackID], now: ProcessInfo.processInfo.systemUptime, clearActiveState: true)
        invalidatePreparedNoteRepeatScheduling()
    }

    func noteRepeatRuntimeSnapshot(for trackID: UUID) -> NoteRepeatRuntimeSnapshot? {
        // Register the narrow revision so SwiftUI bodies calling this update
        // on engage/release (the snapshot's backing dict is intentionally
        // @ObservationIgnored — it mutates on the tick queue).
        _ = noteRepeatRuntimeUIRevision
        return withStateLock { activeNoteRepeatsByTrackID[trackID]?.snapshot }
    }

    func noteRepeatScheduledOutputsForTesting(for trackID: UUID) -> [NoteRepeatScheduledOutput] {
        withStateLock { activeNoteRepeatsByTrackID[trackID]?.scheduledOutputs ?? [] }
    }

    func pendingRepeatOwnedEventCountForTesting(trackID: UUID) -> Int {
        eventQueue.repeatOwnedEventCount(for: trackID)
    }

    var activeNoteRepeatTrackIDsForTesting: Set<UUID> {
        withStateLock { Set(activeNoteRepeatsByTrackID.keys) }
    }

    func clearAllNoteRepeats(now: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        let trackIDs = withStateLock { Set(activeNoteRepeatsByTrackID.keys) }
        cleanupNoteRepeats(for: trackIDs, now: now, clearActiveState: true)
    }

    func clearNoteRepeatCaptureCaches() {
        withStateLock {
            preparedNoteRepeatCapturesByStepIndex.removeAll()
            currentNoteRepeatCapturesByTrackID.removeAll()
        }
    }

    private func invalidatePreparedNoteRepeatScheduling() {
        tickState.invalidatePreparedTick(resetGeneratedStates: false)
        eventQueue.clear()
    }

    func scheduleActiveNoteRepeatsForCurrentTick(tickIndex: UInt64, now: TimeInterval) {
        let (executor, effectiveMutedTrackIDs) = withStateLock {
            (self.executor, self.trackRuntime.effectiveMutedTrackIDs)
        }
        guard let executor else {
            return
        }

        let snapshot = tickState.currentPlaybackSnapshot()
        let playbackPhrase = playbackPhraseForPrepare(upcomingStep: tickIndex, snapshot: snapshot)
        let layerSnapshot = snapshot.layerSnapshot(
            phraseID: playbackPhrase.phraseID,
            stepInPhrase: playbackPhrase.stepInPhrase
        )
        scheduleActiveNoteRepeats(
            anchorTickIndex: tickIndex,
            anchorHostTime: now,
            bpm: executor.currentBPM,
            snapshot: snapshot,
            layerSnapshot: layerSnapshot,
            effectiveMutedTrackIDs: effectiveMutedTrackIDs
        )
    }

    private func scheduleActiveNoteRepeats(
        anchorTickIndex: UInt64,
        anchorHostTime: TimeInterval,
        bpm: Double,
        snapshot: PlaybackSnapshot,
        layerSnapshot: LayerSnapshot,
        effectiveMutedTrackIDs: Set<UUID>
    ) {
        let activeRepeats = withStateLock { Array(activeNoteRepeatsByTrackID.values) }
        guard !activeRepeats.isEmpty else {
            return
        }

        let secondsPerStep = Self.secondsPerStep(bpm: bpm, stepsPerBar: stepsPerBar)
        var noteActivityCount = 0
        var latestNoteActivityHostTime = anchorHostTime
        for activeRepeat in activeRepeats {
            guard supportsNoteRepeat(trackID: activeRepeat.trackID, in: snapshot),
                  let capturedStep = activeRepeat.capturedStep,
                  !capturedStep.notes.isEmpty,
                  let track = snapshot.tracks.first(where: { $0.id == activeRepeat.trackID }),
                  !effectiveMutedTrackIDs.contains(activeRepeat.trackID),
                  !layerSnapshot.isMuted(activeRepeat.trackID)
            else {
                continue
            }

            // Slower-than-step rates (1/4, 1/8) fire on every Nth step.
            // Engagement lands between ticks, so the first firing step is the
            // first tick after engagedAtTickIndex; the stride counts from it.
            let stepStride = activeRepeat.interval.v1StepStride
            if stepStride > 1 {
                let firstFiringTick = activeRepeat.engagedAtTickIndex + 1
                guard anchorTickIndex >= firstFiringTick,
                      (anchorTickIndex - firstFiringTick) % UInt64(stepStride) == 0
                else {
                    continue
                }
            }

            let triggerCount = activeRepeat.interval.v1TriggerCountPerStep
            let triggerSpacing = secondsPerStep / Double(max(1, triggerCount))
            var scheduledOutputs: [NoteRepeatScheduledOutput] = []

            for triggerIndex in 0..<triggerCount {
                let scheduledHostTime = anchorHostTime + (Double(triggerIndex) * triggerSpacing)
                dispatchNoteRepeatOutput(
                    notes: capturedStep.notes,
                    for: track,
                    at: scheduledHostTime,
                    anchorTickIndex: anchorTickIndex,
                    bpm: bpm,
                    snapshot: snapshot,
                    layerSnapshot: layerSnapshot,
                    effectiveMutedTrackIDs: effectiveMutedTrackIDs
                )
                scheduledOutputs.append(
                    NoteRepeatScheduledOutput(
                        stepIndex: anchorTickIndex,
                        scheduledHostTime: scheduledHostTime,
                        noteCount: capturedStep.notes.count
                    )
                )
                noteActivityCount += capturedStep.notes.count
                latestNoteActivityHostTime = max(latestNoteActivityHostTime, scheduledHostTime)
            }

            recordScheduledNoteRepeatOutputs(scheduledOutputs, for: activeRepeat.trackID)
        }
        publishNoteActivity(uptime: latestNoteActivityHostTime, count: noteActivityCount)
    }

    private func dispatchNoteRepeatOutput(
        notes: [NoteEvent],
        for track: StepSequenceTrack,
        at scheduledHostTime: TimeInterval,
        anchorTickIndex: UInt64,
        bpm: Double,
        snapshot: PlaybackSnapshot,
        layerSnapshot: LayerSnapshot,
        effectiveMutedTrackIDs: Set<UUID>
    ) {
        let resolved = snapshot.resolvedDestination(for: track.id)
        switch resolved.destination {
        case let .midi(port, channel, noteOffset):
            guard port != nil,
                  let midiOut = withStateLock({ trackRuntime.midiOutBlocksByTrackID[track.id] })
            else {
                break
            }
            midiOut.apply(paramKey: "channel", value: .number(Double(channel)))
            midiOut.apply(paramKey: "noteOffset", value: .number(Double(noteOffset + resolved.pitchOffset)))
            _ = midiOut.tick(
                context: TickContext(
                    tickIndex: anchorTickIndex,
                    bpm: bpm,
                    inputs: ["notes": .notes(notes)],
                    now: scheduledHostTime,
                    preparedNotesByBlockID: [:]
                )
            )

        case .auInstrument:
            let audioOutputs = withStateLock { trackRuntime.audioOutputsByTrackID }
            guard audioOutputs[track.id] != nil else {
                break
            }
            eventQueue.enqueue(
                ScheduledEvent(
                    scheduledHostTime: scheduledHostTime,
                    payload: .trackAU(
                        trackID: track.id,
                        destination: resolved.destination,
                        notes: Self.shifted(notes, by: resolved.pitchOffset),
                        bpm: bpm,
                        stepsPerBar: stepsPerBar
                    ),
                    repeatOwnerTrackID: track.id
                )
            )

        case let .sample(sampleID, settings):
            for _ in notes {
                eventQueue.enqueue(
                    ScheduledEvent(
                        scheduledHostTime: scheduledHostTime,
                        payload: .sampleTrigger(
                            trackID: track.id,
                            sampleID: sampleID,
                            settings: settings,
                            scheduledHostTime: scheduledHostTime
                        ),
                        repeatOwnerTrackID: track.id
                    )
                )
            }

        case let .slicer(sliceSetID, settings):
            EngineSlicerDispatcher.enqueueSliceTriggers(
                for: notes,
                trackID: track.id,
                sliceSetID: sliceSetID,
                settings: settings,
                snapshot: snapshot,
                sampleLibrary: sampleLibrary,
                sampleLibraryRoot: sampleLibraryRoot,
                stepsPerBar: stepsPerBar,
                bpm: bpm,
                now: scheduledHostTime,
                eventQueue: eventQueue,
                repeatOwnerTrackID: track.id
            )

        case .internalSampler, .inheritGroup, .none:
            break
        }

        routerDispatch.beginTick(now: scheduledHostTime)
        router.tick([RouterTickInput(sourceTrack: track.id, notes: notes, chordContext: nil)])
        flushRoutedEvents(
            bpm: bpm,
            snapshot: snapshot,
            layerSnapshot: layerSnapshot,
            effectiveMutedTrackIDs: effectiveMutedTrackIDs,
            repeatOwnerTrackID: track.id
        )
    }

    private func recordScheduledNoteRepeatOutputs(
        _ outputs: [NoteRepeatScheduledOutput],
        for trackID: UUID
    ) {
        guard !outputs.isEmpty else {
            return
        }

        withStateLock {
            guard var activeRepeat = activeNoteRepeatsByTrackID[trackID] else {
                return
            }
            activeRepeat.scheduledOutputs.append(contentsOf: outputs)
            if activeRepeat.scheduledOutputs.count > 64 {
                activeRepeat.scheduledOutputs = Array(activeRepeat.scheduledOutputs.suffix(64))
            }
            activeNoteRepeatsByTrackID[trackID] = activeRepeat
        }
    }

    private func cleanupNoteRepeats(
        for trackIDs: Set<UUID>,
        now: TimeInterval,
        clearActiveState: Bool
    ) {
        guard !trackIDs.isEmpty else {
            return
        }

        eventQueue.cancelRepeatOwnedEvents(for: trackIDs)
        flushRepeatPendingOutput(for: trackIDs, now: now)

        let didClearActiveState = withStateLock {
            var didRemove = false
            for trackID in trackIDs {
                if clearActiveState {
                    didRemove = activeNoteRepeatsByTrackID.removeValue(forKey: trackID) != nil || didRemove
                } else if var activeRepeat = activeNoteRepeatsByTrackID[trackID] {
                    activeRepeat.scheduledOutputs.removeAll()
                    activeNoteRepeatsByTrackID[trackID] = activeRepeat
                }
            }
            return didRemove
        }
        if didClearActiveState {
            publishNoteRepeatRuntimeUIRevision()
        }
    }

    /// Bump the narrow note-repeat UI publisher. Outside stateLock and on
    /// main, same contract as `audioInputRuntimeRevision` (Observation's
    /// willSet can synchronously re-enter SwiftUI bodies that read engine
    /// state through the same lock).
    private func publishNoteRepeatRuntimeUIRevision() {
        publishToMain { [weak self] in
            self?.noteRepeatRuntimeUIRevision &+= 1
        }
    }

    private func flushRepeatPendingOutput(for trackIDs: Set<UUID>, now: TimeInterval) {
        let (midiOutBlocks, routedOutputs) = withStateLock {
            (
                trackRuntime.midiOutBlocksByTrackID,
                routerDispatch.midiOutputs
            )
        }

        for trackID in trackIDs {
            midiOutBlocks[trackID]?.flushPendingNoteOffs(now: now)
        }

        // Routed MIDI outputs are destination-owned rather than source-track-owned today.
        // Repeats therefore use a conservative no-leak cleanup contract for routed note-offs.
        routedOutputs.values.forEach { $0.flushPendingNoteOffs(now: now) }
    }

    func recordPreparedNoteRepeatCaptures(
        stepIndex: UInt64,
        generatorIDsByTrackID: [UUID: BlockID],
        preparedNotesByBlockID: [BlockID: [NoteEvent]]
    ) {
        let captures: [UUID: NoteRepeatCapturedStep] = Dictionary(
            uniqueKeysWithValues: generatorIDsByTrackID.compactMap { trackID, blockID -> (UUID, NoteRepeatCapturedStep)? in
                guard let notes = preparedNotesByBlockID[blockID] else {
                    return nil
                }
                return (trackID, NoteRepeatCapturedStep(stepIndex: stepIndex, notes: notes))
            }
        )
        withStateLock {
            preparedNoteRepeatCapturesByStepIndex[stepIndex] = captures
            let oldestRetainedStep = stepIndex > 4 ? stepIndex - 4 : 0
            preparedNoteRepeatCapturesByStepIndex = preparedNoteRepeatCapturesByStepIndex.filter {
                $0.key >= oldestRetainedStep
            }
        }
    }

    func promotePreparedNoteRepeatCapture(for stepIndex: UInt64) {
        withStateLock {
            currentNoteRepeatCapturesByTrackID = preparedNoteRepeatCapturesByStepIndex[stepIndex] ?? [:]
            preparedNoteRepeatCapturesByStepIndex = preparedNoteRepeatCapturesByStepIndex.filter { $0.key >= stepIndex }
        }
    }

    func reconcileNoteRepeats(with snapshot: PlaybackSnapshot) {
        // Copy the keys out first: supportsNoteRepeat acquires
        // phraseNavigationLock, and holding stateLock across it would pin a
        // stateLock → phraseNavigationLock ordering for the whole codebase.
        let activeTrackIDs = withStateLock { Set(activeNoteRepeatsByTrackID.keys) }
        let unsupportedTrackIDs = activeTrackIDs.filter { trackID in
            !supportsNoteRepeat(trackID: trackID, in: snapshot)
        }
        if !unsupportedTrackIDs.isEmpty {
            cleanupNoteRepeats(
                for: unsupportedTrackIDs,
                now: ProcessInfo.processInfo.systemUptime,
                clearActiveState: true
            )
        }
    }

    private func supportsNoteRepeat(trackID: UUID, in snapshot: PlaybackSnapshot) -> Bool {
        guard snapshot.tracks.contains(where: { $0.id == trackID }),
              let position = noteRepeatPlaybackPosition(in: snapshot),
              let resolved = snapshot.resolvedStep(
                  phraseID: position.phraseID,
                  trackID: trackID,
                  stepInPhrase: position.stepInPhrase
              ),
              let program = snapshot.sourceProgram(for: trackID)
        else {
            return false
        }

        switch program.slotProgram(at: resolved.slotIndex) {
        case let .clip(clipID, _, _):
            return snapshot.clipEntry(id: clipID) != nil
        case .generator, .empty:
            return false
        }
    }

    private func noteRepeatPlaybackPosition(in snapshot: PlaybackSnapshot) -> (phraseID: UUID, stepInPhrase: Int)? {
        phraseNavigationLock.lock()
        let currentPhraseID = phraseNavigationState.currentPhraseID
        phraseNavigationLock.unlock()

        let phraseID = validPhraseID(currentPhraseID, in: snapshot) ?? firstValidPhraseID(in: snapshot) ?? snapshot.selectedPhraseID
        guard let phraseBuffer = snapshot.phraseBuffer(for: phraseID) else {
            return nil
        }

        let stepCount = max(1, phraseBuffer.stepCount)
        return (phraseID, Int(currentTransportTick % UInt64(stepCount)))
    }
}
