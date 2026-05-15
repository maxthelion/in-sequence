import Foundation

extension EngineController {
    enum AudioOutputKey: Hashable {
        case track(UUID)
        case group(TrackGroupID, UUID?)
    }

    struct EffectiveMixerMuteState: Equatable {
        var isSoloActive: Bool
        var mutedTrackIDs: Set<UUID>
        var mutedBusIDs: Set<UUID>
    }

    static func noteEvent(from generated: GeneratedNote) -> NoteEvent {
        NoteEvent(
            pitch: UInt8(min(max(generated.pitch, 0), 127)),
            velocity: UInt8(min(max(generated.velocity, 0), 127)),
            length: UInt16(min(max(generated.length, 0), Int(UInt16.max))),
            gate: true,
            voiceTag: generated.voiceTag,
            sliceParameters: generated.sliceParameters
        )
    }

    static func generatorBlockID(for trackID: UUID) -> BlockID {
        "gen-\(trackID.uuidString.lowercased())"
    }

    static func midiOutBlockID(for trackID: UUID) -> BlockID {
        "out-\(trackID.uuidString.lowercased())"
    }

    static func pipelineShape(for documentModel: Project) -> [PipelineEntry] {
        documentModel.tracks.map {
            PipelineEntry(
                trackID: $0.id,
                output: Self.effectiveDestination(for: $0.id, in: documentModel).destination.kind
            )
        }
    }

    static func routedMIDIDestination(from route: Route) -> Destination? {
        guard case let .midi(port, channel, noteOffset) = route.destination else {
            return nil
        }

        return .midi(port: port, channel: channel, noteOffset: noteOffset)
    }

    static func transportString(for tickIndex: UInt64, stepsPerBar: Int) -> String {
        let zeroBasedTick = Int(tickIndex)
        let bar = zeroBasedTick / stepsPerBar + 1
        let stepsPerBeat = max(1, stepsPerBar / 4)
        let beat = (zeroBasedTick % stepsPerBar) / stepsPerBeat + 1
        let step = zeroBasedTick % stepsPerBeat + 1
        return "\(bar):\(beat):\(step)"
    }

    static func effectiveDestination(for trackID: UUID, in documentModel: Project) -> (destination: Destination, pitchOffset: Int) {
        guard let track = documentModel.tracks.first(where: { $0.id == trackID }) else {
            return (.none, 0)
        }

        if case .inheritGroup = track.destination {
            guard let groupID = track.groupID,
                  let group = documentModel.trackGroups.first(where: { $0.id == groupID }),
                  let sharedDestination = group.sharedDestination
            else {
                return (.none, 0)
            }

            return (sharedDestination, group.noteMapping[trackID] ?? 0)
        }

        return (track.destination, 0)
    }

    static func audioOutputKey(for track: StepSequenceTrack, in documentModel: Project) -> AudioOutputKey? {
        let (destination, _) = effectiveDestination(for: track.id, in: documentModel)
        guard case .auInstrument = destination else {
            return nil
        }
        if case .inheritGroup = track.destination,
           let groupID = track.groupID
        {
            return .group(groupID, track.outputBusID)
        }
        return .track(track.id)
    }

    static func effectiveMixerMuteState(for documentModel: Project) -> EffectiveMixerMuteState {
        let validBusIDs = Set(documentModel.buses.map(\.id))
        let soloedBusIDs = Set(documentModel.buses.filter { $0.mix.isSoloed }.map(\.id))
        let soloedTrackIDs = Set(documentModel.tracks.filter { $0.mix.isSoloed }.map(\.id))
        let isSoloActive = !soloedBusIDs.isEmpty || !soloedTrackIDs.isEmpty

        var mutedBusIDs = Set(documentModel.buses.filter { $0.mix.isMuted }.map(\.id))
        var mutedTrackIDs = Set(documentModel.tracks.filter { $0.mix.isMuted }.map(\.id))

        guard isSoloActive else {
            return EffectiveMixerMuteState(
                isSoloActive: false,
                mutedTrackIDs: mutedTrackIDs,
                mutedBusIDs: mutedBusIDs
            )
        }

        let soloedTrackIDsByBus = Dictionary(grouping: documentModel.tracks.filter { track in
            guard soloedTrackIDs.contains(track.id),
                  let outputBusID = track.outputBusID,
                  validBusIDs.contains(outputBusID)
            else {
                return false
            }
            return true
        }, by: { $0.outputBusID! })

        for bus in documentModel.buses {
            if !bus.mix.isSoloed && soloedTrackIDsByBus[bus.id, default: []].isEmpty {
                mutedBusIDs.insert(bus.id)
            }
        }

        for track in documentModel.tracks {
            if track.mix.isMuted {
                mutedTrackIDs.insert(track.id)
                continue
            }
            if track.mix.isSoloed {
                continue
            }
            if let outputBusID = track.outputBusID,
               soloedBusIDs.contains(outputBusID)
            {
                continue
            }
            mutedTrackIDs.insert(track.id)
        }

        return EffectiveMixerMuteState(
            isSoloActive: true,
            mutedTrackIDs: mutedTrackIDs,
            mutedBusIDs: mutedBusIDs
        )
    }

    static func effectiveMix(for mix: TrackMixSettings, isMuted: Bool) -> TrackMixSettings {
        TrackMixSettings(
            level: mix.level,
            pan: mix.pan,
            isMuted: isMuted,
            isSoloed: mix.isSoloed
        )
    }

    static func shifted(_ notes: [NoteEvent], by semitones: Int) -> [NoteEvent] {
        guard semitones != 0 else {
            return notes
        }

        return notes.map { note in
            let shiftedPitch = min(max(Int(note.pitch) + semitones, 0), 127)
            return NoteEvent(
                pitch: UInt8(shiftedPitch),
                velocity: note.velocity,
                length: note.length,
                gate: note.gate,
                voiceTag: note.voiceTag,
                sliceParameters: note.sliceParameters
            )
        }
    }

    static func uniqueHosts(_ hosts: [TrackPlaybackSink]) -> [TrackPlaybackSink] {
        var seen: Set<ObjectIdentifier> = []
        return hosts.filter { host in
            seen.insert(ObjectIdentifier(host)).inserted
        }
    }
}
