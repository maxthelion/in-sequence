import AVFoundation
import Foundation

/// Mix/routing synchronization for `EngineController` — scoped mix updates
/// (track/bus faders, sends), effective mixer-state refresh, and the
/// document-driven output/MIDI/sample-mixer sync passes. Mechanically
/// extracted from EngineController.swift (engine carve-up stage: mix/routing
/// sync); statements, ordering, and locking topology are unchanged.
extension EngineController {
    /// Scoped mix update for high-frequency UI such as fader drags. This writes
    /// directly to the live playback sinks without rebuilding the document-driven
    /// engine pipeline.
    func setMix(trackID: UUID, mix: TrackMixSettings) {
        guard let trackIndex = currentDocumentModel.tracks.firstIndex(where: { $0.id == trackID }) else {
            return
        }
        currentDocumentModel.tracks[trackIndex].mix = mix
        if currentDocumentModel.selectedTrackID == trackID {
            currentTrackMix = mix
        }
        refreshEffectiveMixerState(for: currentDocumentModel)
    }

    /// Scoped bus mix update for performance-time bus controls. This stays on the
    /// parameter path: bus fader, pan, mute, solo, and bypass-style insert changes
    /// avoid broad document re-application and do not rebuild the engine pipeline.
    func setMixerBusMix(busID: UUID, mix: BusMixSettings) {
        guard let index = currentDocumentModel.buses.firstIndex(where: { $0.id == busID }) else {
            return
        }
        currentDocumentModel.buses[index].mix = mix.normalized()
        refreshEffectiveMixerState(for: currentDocumentModel)
    }

    func setMixerBusParameters(busID: UUID, bus: MixerBus) {
        guard let index = currentDocumentModel.buses.firstIndex(where: { $0.id == busID }) else {
            return
        }
        let normalized = bus.normalized(fallbackName: currentDocumentModel.buses[index].name)
        currentDocumentModel.buses[index] = normalized
        let effectiveMuteState = Self.effectiveMixerMuteState(for: currentDocumentModel)
        mainAudioGraph.setMixerBusParameters(
            bus: normalized,
            effectiveMute: effectiveMuteState.mutedBusIDs.contains(busID)
        )
    }

    func apply(sendBus: SendBusState) {
        let normalized = sendBus.normalized(expectedID: sendBus.id)
        sendBusStates[normalized.id] = normalized
        sendBusApplyCallCount += 1
        currentDocumentModel.updateSendBus(id: normalized.id) { sendBus in
            sendBus = normalized
        }
        mainAudioGraph.installSendBus(normalized)
    }

    func setTrackOutputBus(trackID: UUID, busID: UUID?, documentModel: Project) {
        guard let track = documentModel.tracks.first(where: { $0.id == trackID }) else {
            return
        }

        if documentModel.selectedTrackID == trackID {
            selectedOutput = Self.effectiveDestination(for: trackID, in: documentModel).destination.kind
        }

        if track.trackType == .audioInput {
            updateAudioInputRoutingParameters(for: documentModel)
        }

        let host = withStateLock { trackRuntime.audioOutputsByTrackID[trackID] }
        host?.setOutputBusID(busID)

        switch Self.effectiveDestination(for: trackID, in: documentModel).destination {
        case .sample, .slicer:
            sampleEngine.setTrackOutputBus(trackID: trackID, busID: busID)
        default:
            break
        }
    }

    func syncTrackParams(for documentModel: Project) {
        // Note injection uses the typed preparedNotesByBlockID path only; no params to sync.
        // Reset generator evaluation state and prepared-tick index so the next prepareTick
        // re-evaluates from the new document model.
        invalidatePreparedPlaybackOutput(resetGeneratedStates: true)
    }

    func syncMidiOutputs(for documentModel: Project) {
        let midiOutBlocks = withStateLock { trackRuntime.midiOutBlocksByTrackID }
        let effectiveMuteState = Self.effectiveMixerMuteState(for: documentModel)
        for track in documentModel.tracks {
            let (destination, pitchOffset) = Self.effectiveDestination(for: track.id, in: documentModel)
            let nextEndpoint: MIDIEndpoint?
            if case let .midi(port, channel, noteOffset) = destination,
               !effectiveMuteState.mutedTrackIDs.contains(track.id)
            {
                nextEndpoint = port.flatMap(resolveEndpoint(named:))
                midiOutBlocks[track.id]?.apply(paramKey: "channel", value: .number(Double(channel)))
                midiOutBlocks[track.id]?.apply(paramKey: "noteOffset", value: .number(Double(noteOffset + pitchOffset)))
            } else {
                nextEndpoint = nil
            }
            if midiOutBlocks[track.id]?.endpoint != nil, nextEndpoint == nil {
                midiOutBlocks[track.id]?.flushPendingNoteOffs(now: ProcessInfo.processInfo.systemUptime)
            }
            midiOutBlocks[track.id]?.endpoint = nextEndpoint
        }
    }

    /// Push every track's authored FX insert chain into the audio graph. The
    /// graph splices each chain between the track's output source node and its
    /// dry/sends destinations. Tracks whose chain is unchanged take the
    /// value-only fast path inside the graph (no engine stop/start).
    ///
    /// Called from the document apply path AFTER `syncAudioOutputs` /
    /// `syncSampleMixers` so each track's output source node is already
    /// registered (the graph resolves the source via the meter-source
    /// registration those passes publish).
    func syncTrackInserts(for documentModel: Project) {
        let liveIDs = withStateLock { trackRuntime.installedTrackInsertChainIDs }
        let nextIDs = Set(documentModel.tracks.map(\.id))
        for removed in liveIDs.subtracting(nextIDs) {
            mainAudioGraph.teardownTrackInserts(trackID: removed)
        }
        for track in documentModel.tracks {
            mainAudioGraph.setTrackInserts(trackID: track.id, inserts: track.fxInserts)
        }
        withStateLock { trackRuntime.installedTrackInsertChainIDs = nextIDs }
    }

    /// Scoped per-track insert-chain update (add/remove/reorder/bypass). Does
    /// NOT rebuild the document-model pipeline. The graph applies a value-only
    /// fast path for bypass-style edits (engine stays running) and only takes
    /// the topology rebuild path when the node chain actually changes —
    /// matching the bus/send scoped-FX shape (Performance-Time Mutation Rule).
    func setTrackInserts(trackID: UUID, inserts: [TrackFXInsert]) {
        if let index = currentDocumentModel.tracks.firstIndex(where: { $0.id == trackID }) {
            currentDocumentModel.tracks[index].fxInserts = inserts
        }
        mainAudioGraph.setTrackInserts(trackID: trackID, inserts: inserts)
    }

    func installMixerBuses(for documentModel: Project) {
        let effectiveMuteState = Self.effectiveMixerMuteState(for: documentModel)
        withStateLock {
            trackRuntime.installMuteState(effectiveMuteState)
        }
        mainAudioGraph.installMixerBuses(
            documentModel.buses,
            effectiveMuteByBusID: Dictionary(
                uniqueKeysWithValues: documentModel.buses.map {
                    ($0.id, effectiveMuteState.mutedBusIDs.contains($0.id))
                }
            )
        )
    }

    private func refreshEffectiveMixerState(for documentModel: Project) {
        let effectiveMuteState = Self.effectiveMixerMuteState(for: documentModel)
        let audioOutputs = withStateLock { self.trackRuntime.audioOutputsByTrackID }
        withStateLock {
            trackRuntime.installMuteState(effectiveMuteState)
            for (trackID, runtime) in trackRuntime.audioTrackRuntimes {
                guard let track = documentModel.tracks.first(where: { $0.id == trackID }) else { continue }
                trackRuntime.audioTrackRuntimes[trackID] = AudioTrackRuntime(
                    trackID: runtime.trackID,
                    generatorBlockID: runtime.generatorBlockID,
                    mix: Self.effectiveMix(for: track.mix, isMuted: effectiveMuteState.mutedTrackIDs.contains(trackID)),
                    destination: runtime.destination,
                    pitchOffset: runtime.pitchOffset
                )
            }
        }

        for track in documentModel.tracks {
            let effectiveMix = Self.effectiveMix(
                for: track.mix,
                isMuted: effectiveMuteState.mutedTrackIDs.contains(track.id)
            )
            let mixerMuted = effectiveMuteState.mutedTrackIDs.contains(track.id)
            audioOutputs[track.id]?.setMix(effectiveMix)
            switch Self.effectiveDestination(for: track.id, in: documentModel).destination {
            case .sample, .slicer:
                // Fader level is the raw user value; mute is applied as a
                // ramped gain via setTrackMuteGain so unmute restores it.
                sampleEngine.setTrackMix(
                    trackID: track.id,
                    level: track.mix.clampedLevel,
                    pan: effectiveMix.clampedPan
                )
                sampleEngine.setTrackMuteGain(trackID: track.id, muted: mixerMuted)
                sampleEngine.setTrackSends(trackID: track.id, sendA: effectiveMix.sendA, sendB: effectiveMix.sendB)
            default:
                continue
            }
        }
        syncMidiOutputs(for: documentModel)
        updateAudioInputRoutingParameters(for: documentModel)

        for bus in documentModel.buses {
            mainAudioGraph.setMixerBusMix(
                busID: bus.id,
                mix: bus.mix,
                effectiveMute: effectiveMuteState.mutedBusIDs.contains(bus.id)
            )
        }
    }

    func syncAudioOutputs(for documentModel: Project) {
        let effectiveMuteState = Self.effectiveMixerMuteState(for: documentModel)
        let desiredAudioTracks = documentModel.tracks.compactMap { track -> (StepSequenceTrack, Destination, Int, AudioOutputKey)? in
            let (destination, pitchOffset) = Self.effectiveDestination(for: track.id, in: documentModel)
            guard case .auInstrument = destination,
                  let key = Self.audioOutputKey(for: track, in: documentModel)
            else {
                return nil
            }
            return (track, destination, pitchOffset, key)
        }

        let previousOutputs = withStateLock { trackRuntime.audioOutputsByTrackID }
        let previousKeys = withStateLock { trackRuntime.audioOutputKeysByTrackID }
        let previousDestinations = withStateLock { trackRuntime.lastDestinationByOutputKey }
        var hostsByKey: [AudioOutputKey: TrackPlaybackSink] = [:]
        var nextOutputs: [UUID: TrackPlaybackSink] = [:]
        var nextKeys: [UUID: AudioOutputKey] = [:]
        var nextDestinations: [AudioOutputKey: Destination] = [:]

        for (track, destination, _, key) in desiredAudioTracks {
            let host = hostsByKey[key] ?? {
                if let existingTrackID = previousKeys.first(where: { $0.value == key })?.key,
                   let existing = previousOutputs[existingTrackID]
                {
                    hostsByKey[key] = existing
                    return existing
                }

                let created = audioOutputFactory?() ?? sharedAudioOutput
                if let created {
                    hostsByKey[key] = created
                }
                return created
            }()

            guard let host else {
                continue
            }

            nextOutputs[track.id] = host
            nextKeys[track.id] = key
            log("syncAudioOutputs track=\(track.name) key=\(String(describing: key)) destination=\(destination.summary)")
            if previousDestinations[key] != destination {
                host.setDestination(destination)
            }
            nextDestinations[key] = destination
            host.setOutputBusID(track.outputBusID)
            host.setMix(Self.effectiveMix(for: track.mix, isMuted: effectiveMuteState.mutedTrackIDs.contains(track.id)))
            host.prepareIfNeeded()
            if isRunning {
                host.startIfNeeded()
            }
        }

        // Meter registration (roadmap 29): each host meters the set of
        // tracks it currently plays — shared hosts publish one stream to
        // every strip they back.
        var meterTrackIDsByHost: [ObjectIdentifier: (host: TrackPlaybackSink, trackIDs: Set<UUID>)] = [:]
        for (trackID, host) in nextOutputs {
            meterTrackIDsByHost[ObjectIdentifier(host), default: (host, [])].trackIDs.insert(trackID)
        }
        for entry in meterTrackIDsByHost.values {
            entry.host.setMeterTrackIDs(entry.trackIDs)
        }

        let previousUniqueHosts = Self.uniqueHosts(Array(previousOutputs.values))
        let nextUniqueHosts = Self.uniqueHosts(Array(nextOutputs.values))
        let nextHostIDs = Set(nextUniqueHosts.map { ObjectIdentifier($0) })
        let removedHosts = previousUniqueHosts.filter { !nextHostIDs.contains(ObjectIdentifier($0)) }

        withStateLock {
            trackRuntime.installAudioOutputs(
                outputs: nextOutputs,
                outputKeys: nextKeys,
                destinationsByOutputKey: nextDestinations,
                audioRuntimes: Dictionary(
                uniqueKeysWithValues: desiredAudioTracks.map {
                    (
                        $0.0.id,
                        AudioTrackRuntime(
                            trackID: $0.0.id,
                            generatorBlockID: trackRuntime.generatorIDsByTrackID[$0.0.id] ?? Self.generatorBlockID(for: $0.0.id),
                            mix: Self.effectiveMix(
                                for: $0.0.mix,
                                isMuted: effectiveMuteState.mutedTrackIDs.contains($0.0.id)
                            ),
                            destination: $0.1,
                            pitchOffset: $0.2
                        )
                    )
                }
                )
            )
        }

        removedHosts.forEach { $0.stop() }

        syncSampleMixers(for: documentModel)
    }

    /// Push per-track fader state to `sampleEngine`. Called from `syncAudioOutputs`
    /// every time the document model changes, which includes fader moves via the
    /// mixer UI. The engine prepares per-track mixers and voice pools here so
    /// tick-time sample dispatch never mutates the AVAudioEngine graph.
    private func syncSampleMixers(for documentModel: Project) {
        let effectiveMuteState = Self.effectiveMixerMuteState(for: documentModel)
        var sampleTrackIDs: Set<UUID> = []
        var sampleIDsToWarm: Set<UUID> = []
        for track in documentModel.tracks {
            switch Self.effectiveDestination(for: track.id, in: documentModel).destination {
            case let .sample(sampleID, _):
                sampleIDsToWarm.insert(sampleID)
            case let .slicer(sliceSetID, _):
                if let sampleID = documentModel.sliceSet(id: sliceSetID)?.sampleID {
                    sampleIDsToWarm.insert(sampleID)
                }
            default:
                continue
            }
            sampleTrackIDs.insert(track.id)
            sampleEngine.setTrackOutputBus(trackID: track.id, busID: track.outputBusID)
            sampleEngine.prepareTrack(trackID: track.id)
            let mixerMuted = effectiveMuteState.mutedTrackIDs.contains(track.id)
            // Fader level stays raw; mute is a ramped gain via setTrackMuteGain.
            sampleEngine.setTrackMix(
                trackID: track.id,
                level: track.mix.clampedLevel,
                pan: track.mix.clampedPan
            )
            sampleEngine.setTrackMuteGain(trackID: track.id, muted: mixerMuted)
            sampleEngine.setTrackSends(trackID: track.id, sendA: track.mix.sendA, sendB: track.mix.sendB)
        }

        warmSampleAssets(sampleIDs: sampleIDsToWarm)

        let previouslyLiveTrackIDs = withStateLock { trackRuntime.liveSampleTrackIDs }
        for removed in previouslyLiveTrackIDs.subtracting(sampleTrackIDs) {
            sampleEngine.removeTrack(trackID: removed)
        }

        withStateLock { trackRuntime.liveSampleTrackIDs = sampleTrackIDs }
    }

    private func warmSampleAssets(sampleIDs: Set<UUID>) {
        let samples = sampleIDs.compactMap { sampleLibrary.sample(id: $0) }
        sampleAssetCache.retain(sampleIDs: sampleIDs)
        if isRunning {
            sampleAssetCache.warmAsync(samples: samples, libraryRoot: sampleLibraryRoot, pinnedSampleIDs: sampleIDs)
        } else {
            sampleAssetCache.warm(samples: samples, libraryRoot: sampleLibraryRoot)
        }
        sampleAssetCache.retain(sampleIDs: sampleIDs)
    }
}
