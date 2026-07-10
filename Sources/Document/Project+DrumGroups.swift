import Foundation

extension Project {
    static func defaultDestination(
        forVoiceTag tag: VoiceTag,
        preferredSampleID: UUID? = nil,
        fallbackPresetName: String,
        library: AudioSampleLibrary = .shared
    ) -> Destination {
        if let preferredSampleID, library.sample(id: preferredSampleID) != nil {
            return .sample(sampleID: preferredSampleID, settings: .default)
        }
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
        library: AudioSampleLibrary = .shared,
        templateLookup: (UUID) -> PatternTemplate? = { DrumAssetLibrary.shared.template(id: $0) }
    ) -> TrackGroupID? {
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
                    preferredSampleID: member.sampleID,
                    fallbackPresetName: plan.name,
                    library: library
                )
            }

            let emptyPattern = Array(repeating: false, count: 16)
            var track = StepSequenceTrack(
                name: member.trackName,
                trackType: .monoMelodic,
                voiceTag: member.tag,
                pitches: [DrumKitNoteMap.baselineNote],
                stepPattern: emptyPattern,
                destination: destination,
                groupID: groupID,
                velocity: StepSequenceTrack.default.velocity,
                gateLength: StepSequenceTrack.default.gateLength
            )
            // Seed the editable per-type default macro template for new drum
            // parts only (M1 sample start, M2 length, M3 filter cutoff).
            // Existing tracks are never retroactively mutated on load.
            track.macros = Self.defaultMacroBindings(forVoiceTag: member.tag, trackID: track.id)
            let clip = ClipPoolEntry(
                id: UUID(),
                name: member.trackName,
                trackType: .monoMelodic,
                content: .stepSequence(
                    stepPattern: emptyPattern,
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

        // By default a drum group routes its members to their own dedicated
        // mixer bus (named after the group), keeping the kit a self-contained
        // mixable unit. `.master` leaves members on the master bus.
        if case .dedicatedBus = plan.busRouting {
            let busID = addMixerBus(name: plan.name, color: plan.color)
            for memberID in memberIDs {
                setTrackOutputBus(trackID: memberID, busID: busID)
            }
        }
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
        // Build phrase layers for the seeded default macro bindings so their
        // live values resolve and they show up in the macros tab.
        syncMacroLayers()

        if let templateID = plan.templateID, let template = templateLookup(templateID) {
            applyPatternTemplate(template, toGroup: groupID, slotIndex: 0)
        }
        return groupID
    }

    @discardableResult
    mutating func addDrumPart(
        groupID: TrackGroupID,
        sampleSourceTrackID: UUID? = nil,
        library: AudioSampleLibrary = .shared
    ) -> UUID? {
        guard let groupIndex = trackGroups.firstIndex(where: { $0.id == groupID }) else {
            return nil
        }

        let group = trackGroups[groupIndex]
        let tag = Self.nextDrumPartTag(for: group, tracks: tracks)
        let memberNumber = group.memberIDs.count + 1
        let destination = Self.drumPartDestination(
            for: tag,
            group: group,
            sampleSourceTrackID: sampleSourceTrackID,
            tracks: tracks,
            library: library
        )
        let emptyPattern = Array(repeating: false, count: 16)
        var track = StepSequenceTrack(
            name: Self.defaultDrumPartName(for: tag, memberNumber: memberNumber),
            trackType: .monoMelodic,
            voiceTag: tag,
            pitches: [DrumKitNoteMap.baselineNote],
            stepPattern: emptyPattern,
            destination: destination,
            groupID: groupID,
            velocity: StepSequenceTrack.default.velocity,
            gateLength: StepSequenceTrack.default.gateLength
        )
        track.macros = Self.defaultMacroBindings(forVoiceTag: tag, trackID: track.id)

        let clip = ClipPoolEntry(
            id: UUID(),
            name: track.name,
            trackType: .monoMelodic,
            content: .stepSequence(
                stepPattern: emptyPattern,
                pitches: [DrumKitNoteMap.baselineNote]
            )
        )

        tracks.append(track)
        clipPool.append(clip)
        patternBanks.append(TrackPatternBank.default(for: track, initialClipID: clip.id))
        trackGroups[groupIndex].memberIDs.append(track.id)

        if case .midi = group.sharedDestination {
            trackGroups[groupIndex].noteMapping[track.id] = Int(DrumKitNoteMap.note(for: tag)) - DrumKitNoteMap.baselineNote
            trackGroups[groupIndex].channelMapping[track.id] = UInt8((memberNumber - 1) % 16)
        }

        if let busID = drumGroupBusID(for: group) {
            setTrackOutputBus(trackID: track.id, busID: busID)
        }

        selectedTrackID = track.id
        syncPhrasesWithTracks()
        syncMacroLayers()
        return track.id
    }

    private static func drumPartDestination(
        for tag: VoiceTag,
        group: TrackGroup,
        sampleSourceTrackID: UUID?,
        tracks: [StepSequenceTrack],
        library: AudioSampleLibrary
    ) -> Destination {
        if let sampleSourceTrackID,
           let source = tracks.first(where: { $0.id == sampleSourceTrackID }),
           case .sample = source.destination {
            return source.destination
        }

        if group.sharedDestination != nil {
            return .inheritGroup
        }

        return defaultDestination(
            forVoiceTag: tag,
            fallbackPresetName: group.name,
            library: library
        )
    }

    private static func nextDrumPartTag(for group: TrackGroup, tracks: [StepSequenceTrack]) -> VoiceTag {
        let preferredTags: [VoiceTag] = ["kick", "snare", "hat-closed", "clap", "tom-low", "tom-mid", "tom-high", "perc"]
        let usedTags = Set(group.memberIDs.compactMap { memberID in
            tracks.first(where: { $0.id == memberID })?.voiceTag
        })
        return preferredTags.first(where: { !usedTags.contains($0) }) ?? "perc"
    }

    private static func defaultDrumPartName(for tag: VoiceTag, memberNumber: Int) -> String {
        switch tag {
        case "kick":
            return "Kick"
        case "snare":
            return "Snare"
        case "hat-closed":
            return "Hat"
        case "clap":
            return "Clap"
        default:
            return "Part \(memberNumber)"
        }
    }

    private func drumGroupBusID(for group: TrackGroup) -> UUID? {
        let routedMemberBusIDs = group.memberIDs.compactMap { memberID in
            tracks.first(where: { $0.id == memberID })?.outputBusID
        }
        if let existingBusID = routedMemberBusIDs.first(where: { busID in
            buses.contains(where: { $0.id == busID })
        }) {
            return existingBusID
        }
        return buses.first(where: { $0.name == group.name })?.id
    }

    /// Applies a pattern template to a drum group by tag matching:
    /// - each member whose tag has a template entry gets a fresh
    ///   `ClipPoolEntry` (named after the member) assigned to the target slot;
    /// - members without a template entry are left untouched;
    /// - template tags absent from the group are ignored;
    /// - members whose target slot holds a generator are skipped;
    /// - duplicate member tags fill the first occurrence only.
    ///
    /// Shared by creation (`addDrumGroup` with a `templateID`) and
    /// post-creation application from the kit matrix.
    mutating func applyPatternTemplate(
        _ template: PatternTemplate,
        toGroup groupID: TrackGroupID,
        slotIndex: Int
    ) {
        applyPatternTemplate(template, toGroup: groupID, slotIndexes: [slotIndex])
    }

    /// Multi-target form used by the kit matrix. Every selected slot is
    /// updated inside the caller's one document/session batch; invalid and
    /// duplicate indexes are ignored. This never changes phrase pattern
    /// selection, so applying to background slots leaves playback untouched.
    mutating func applyPatternTemplate(
        _ template: PatternTemplate,
        toGroup groupID: TrackGroupID,
        slotIndexes: [Int]
    ) {
        guard let group = trackGroups.first(where: { $0.id == groupID }) else {
            return
        }
        let targetSlotIndexes = Set(slotIndexes)
            .filter { (0..<TrackPatternBank.slotCount).contains($0) }
            .sorted()
        guard !targetSlotIndexes.isEmpty else { return }

        var consumedTags = Set<VoiceTag>()
        for memberID in group.memberIDs {
            guard let track = tracks.first(where: { $0.id == memberID }),
                  track.trackType == .monoMelodic,
                  let tag = track.voiceTag,
                  !consumedTags.contains(tag),
                  let stepPattern = template.patterns[tag]
            else {
                continue
            }
            // Duplicate tags fill the first occurrence only — even when that
            // occurrence is skipped because its slot holds a generator.
            consumedTags.insert(tag)

            for slotIndex in targetSlotIndexes {
                guard patternBank(for: memberID).slot(at: slotIndex).sourceRef.mode != .generator else {
                    continue
                }

                let clip = ClipPoolEntry(
                    id: UUID(),
                    name: track.name,
                    trackType: .monoMelodic,
                    content: .stepSequence(
                        stepPattern: stepPattern,
                        pitches: [DrumKitNoteMap.baselineNote]
                    )
                )
                clipPool.append(clip)
                setPatternClipID(clip.id, for: memberID, slotIndex: slotIndex)
            }
        }
    }
}
