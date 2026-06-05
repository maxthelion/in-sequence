import Foundation

extension Project {
    static func defaultDestination(
        forVoiceTag tag: VoiceTag,
        fallbackPresetName: String,
        library: AudioSampleLibrary = .shared
    ) -> Destination {
        guard let category = AudioSampleCategory(voiceTag: tag),
              let sample = library.firstSample(in: category)
        else {
            return .internalSampler(bankID: .drumKitDefault, preset: fallbackPresetName)
        }
        return .sample(sampleID: sample.id, settings: .default)
    }

    @discardableResult
    mutating func addDrumGroup(
        plan: DrumGroupPlan,
        library: AudioSampleLibrary = .shared
    ) -> TrackGroupID? {
        guard !plan.members.isEmpty else {
            return nil
        }

        let groupID = TrackGroupID()
        var newTracks: [StepSequenceTrack] = []
        var newBanks: [TrackPatternBank] = []

        for member in plan.members {
            let destination: Destination
            if plan.sharedDestination != nil, member.routesToShared {
                destination = .inheritGroup
            } else {
                destination = Self.defaultDestination(
                    forVoiceTag: member.tag,
                    fallbackPresetName: plan.name,
                    library: library
                )
            }

            let effectiveSeedPattern = plan.prepopulateClips
                ? member.seedPattern
                : Array(repeating: false, count: member.seedPattern.count)

            let track = StepSequenceTrack(
                name: member.trackName,
                trackType: .monoMelodic,
                pitches: [DrumKitNoteMap.baselineNote],
                stepPattern: effectiveSeedPattern,
                destination: destination,
                groupID: groupID,
                velocity: StepSequenceTrack.default.velocity,
                gateLength: StepSequenceTrack.default.gateLength
            )
            let clip = ClipPoolEntry(
                id: UUID(),
                name: member.trackName,
                trackType: .monoMelodic,
                content: .stepSequence(
                    stepPattern: effectiveSeedPattern,
                    pitches: [DrumKitNoteMap.baselineNote]
                )
            )
            clipPool.append(clip)
            newTracks.append(track)
            newBanks.append(TrackPatternBank.default(for: track, initialClipID: clip.id))
        }

        tracks.append(contentsOf: newTracks)
        patternBanks.append(contentsOf: newBanks)
        let memberIDs = newTracks.map(\.id)
        let usesSharedMIDI: Bool = {
            guard case .some(.midi) = plan.sharedDestination else {
                return false
            }
            return true
        }()
        let noteMapping: [UUID: Int] = usesSharedMIDI
            ? Dictionary(uniqueKeysWithValues: zip(memberIDs, plan.members).map { memberID, member in
                (memberID, Int(DrumKitNoteMap.note(for: member.tag)) - DrumKitNoteMap.baselineNote)
            })
            : [:]
        let channelMapping: [UUID: UInt8] = usesSharedMIDI
            ? Dictionary(uniqueKeysWithValues: memberIDs.enumerated().map { index, memberID in
                (memberID, UInt8(index % 16))
            })
            : [:]
        trackGroups.append(
            TrackGroup(
                id: groupID,
                name: plan.name,
                color: plan.color,
                memberIDs: memberIDs,
                sharedDestination: plan.sharedDestination,
                noteMapping: noteMapping,
                channelMapping: channelMapping
            )
        )
        selectedTrackID = newTracks.first?.id ?? selectedTrackID
        syncPhrasesWithTracks()
        return groupID
    }
}
