import Foundation

extension Project {
    struct ResolvedPlaybackDestination: Equatable, Sendable {
        var destination: Destination
        var pitchOffset: Int
    }

    struct DrumGroupRoutingDraft: Equatable, Sendable {
        struct MemberRoute: Equatable, Sendable {
            var memberID: UUID
            var inheritsGroupDestination: Bool
            var ownDestination: Destination?
            var noteOffset: Int
            var midiChannel: UInt8

            init(
                memberID: UUID,
                inheritsGroupDestination: Bool,
                ownDestination: Destination? = nil,
                noteOffset: Int,
                midiChannel: UInt8
            ) {
                self.memberID = memberID
                self.inheritsGroupDestination = inheritsGroupDestination
                self.ownDestination = ownDestination
                self.noteOffset = noteOffset
                self.midiChannel = midiChannel
            }
        }

        var groupID: TrackGroupID
        var sharedDestination: Destination?
        var triggerMappingMode: DrumTriggerMappingMode
        var members: [MemberRoute]

        init(
            groupID: TrackGroupID,
            sharedDestination: Destination?,
            triggerMappingMode: DrumTriggerMappingMode,
            members: [MemberRoute]
        ) {
            self.groupID = groupID
            self.sharedDestination = sharedDestination
            self.triggerMappingMode = triggerMappingMode
            self.members = members
        }
    }

    func routesSourced(from trackID: UUID) -> [Route] {
        routes.filter { route in
            switch route.source {
            case let .track(sourceTrackID), let .chordGenerator(sourceTrackID):
                return sourceTrackID == trackID
            }
        }
    }

    func routesTargeting(_ trackID: UUID) -> [Route] {
        routes.filter { $0.destination.targetTrackID == trackID }
    }

    func group(for trackID: UUID) -> TrackGroup? {
        guard let groupID = tracks.first(where: { $0.id == trackID })?.groupID else {
            return nil
        }
        return trackGroups.first(where: { $0.id == groupID })
    }

    // MARK: - Destination resolution (single home)
    //
    // The static overloads are the one implementation of write-target and
    // destination resolution; the instance methods and
    // LiveSequencerStore's accessors both delegate here so the logic cannot
    // drift between the document and the live store.

    static func destinationWriteTarget(
        for trackID: UUID,
        tracks: [StepSequenceTrack],
        trackGroups: [TrackGroup]
    ) -> DestinationWriteTarget {
        guard let track = tracks.first(where: { $0.id == trackID }) else {
            return .track(trackID)
        }
        if case .inheritGroup = track.destination,
           let groupID = track.groupID,
           trackGroups.contains(where: { $0.id == groupID })
        {
            return .group(groupID)
        }
        return .track(trackID)
    }

    static func destination(
        for target: DestinationWriteTarget,
        tracks: [StepSequenceTrack],
        trackGroups: [TrackGroup]
    ) -> Destination? {
        switch target {
        case .track(let trackID):
            return tracks.first(where: { $0.id == trackID })?.destination
        case .group(let groupID):
            return trackGroups.first(where: { $0.id == groupID })?.sharedDestination
        }
    }

    static func resolvedDestination(
        for trackID: UUID,
        tracks: [StepSequenceTrack],
        trackGroups: [TrackGroup]
    ) -> Destination {
        let target = destinationWriteTarget(for: trackID, tracks: tracks, trackGroups: trackGroups)
        return destination(for: target, tracks: tracks, trackGroups: trackGroups)
            ?? tracks.first(where: { $0.id == trackID })?.destination
            ?? .none
    }

    static func resolvedPlaybackDestination(
        for trackID: UUID,
        tracks: [StepSequenceTrack],
        trackGroups: [TrackGroup]
    ) -> ResolvedPlaybackDestination {
        guard let track = tracks.first(where: { $0.id == trackID }) else {
            return ResolvedPlaybackDestination(destination: .none, pitchOffset: 0)
        }

        guard case .inheritGroup = track.destination else {
            return ResolvedPlaybackDestination(destination: track.destination, pitchOffset: 0)
        }

        guard let groupID = track.groupID,
              let group = trackGroups.first(where: { $0.id == groupID })
        else {
            return ResolvedPlaybackDestination(destination: .none, pitchOffset: 0)
        }

        return resolveInheritedPlaybackDestination(trackID: trackID, group: group)
    }

    func destinationWriteTarget(for trackID: UUID) -> DestinationWriteTarget {
        Self.destinationWriteTarget(for: trackID, tracks: tracks, trackGroups: trackGroups)
    }

    func destination(for target: DestinationWriteTarget) -> Destination? {
        Self.destination(for: target, tracks: tracks, trackGroups: trackGroups)
    }

    func resolvedDestination(for trackID: UUID) -> Destination {
        Self.resolvedDestination(for: trackID, tracks: tracks, trackGroups: trackGroups)
    }

    func resolvedPlaybackDestination(for trackID: UUID) -> ResolvedPlaybackDestination {
        Self.resolvedPlaybackDestination(for: trackID, tracks: tracks, trackGroups: trackGroups)
    }

    mutating func setDestination(_ destination: Destination, for target: DestinationWriteTarget) {
        switch target {
        case .track(let trackID):
            guard let trackIndex = tracks.firstIndex(where: { $0.id == trackID }) else {
                return
            }
            tracks[trackIndex].destination = destination
        case .group(let groupID):
            guard let groupIndex = trackGroups.firstIndex(where: { $0.id == groupID }) else {
                return
            }
            trackGroups[groupIndex].sharedDestination = destination
        }
    }

    mutating func setEditedDestination(_ destination: Destination, for trackID: UUID) {
        setDestination(destination, for: destinationWriteTarget(for: trackID))
    }

    func voiceSnapshotDestination(for trackID: UUID) -> Destination? {
        let target = destinationWriteTarget(for: trackID)
        return destination(for: target)?.withoutTransientState
    }

    mutating func setEditedMIDIPort(_ port: MIDIEndpointName?, for trackID: UUID) {
        let target = destinationWriteTarget(for: trackID)
        let updated = (destination(for: target) ?? .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0))
            .settingMIDIPort(port)
        setDestination(updated, for: target)
    }

    mutating func setEditedMIDIChannel(_ channel: UInt8, for trackID: UUID) {
        let target = destinationWriteTarget(for: trackID)
        let updated = (destination(for: target) ?? .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0))
            .settingMIDIChannel(channel)
        setDestination(updated, for: target)
    }

    mutating func setEditedMIDINoteOffset(_ noteOffset: Int, for trackID: UUID) {
        let target = destinationWriteTarget(for: trackID)
        let updated = (destination(for: target) ?? .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0))
            .settingMIDINoteOffset(noteOffset)
        setDestination(updated, for: target)
    }

    mutating func setGroupSharedDestinationWithMacros(_ destination: Destination?, groupID: TrackGroupID) {
        guard let groupIndex = trackGroups.firstIndex(where: { $0.id == groupID }) else {
            return
        }

        if let destination {
            setDestination(destination, for: .group(groupID))
        } else {
            trackGroups[groupIndex].sharedDestination = nil
        }

        let inheritedMemberIDs = trackGroups[groupIndex].memberIDs.filter { memberID in
            tracks.first(where: { $0.id == memberID })?.destination == .inheritGroup
        }
        let destinationForMacros = destination ?? .none
        for memberID in inheritedMemberIDs {
            syncBuiltinMacrosForResolvedDestination(destinationForMacros, for: memberID)
        }
    }

    mutating func setDrumGroupMemberInheritsDestination(
        _ inheritsGroupDestination: Bool,
        trackID: UUID,
        ownDestination: Destination = .none
    ) {
        guard let trackIndex = tracks.firstIndex(where: { $0.id == trackID }),
              let groupID = tracks[trackIndex].groupID,
              let group = trackGroups.first(where: { $0.id == groupID }),
              group.memberIDs.contains(trackID)
        else {
            return
        }

        if inheritsGroupDestination {
            tracks[trackIndex].destination = .inheritGroup
            syncBuiltinMacrosForResolvedDestination(group.sharedDestination ?? .none, for: trackID)
        } else {
            setTrackDestinationWithMacros(ownDestination, for: trackID)
        }
    }

    mutating func setDrumGroupTriggerMappingMode(_ mode: DrumTriggerMappingMode, groupID: TrackGroupID) {
        guard let groupIndex = trackGroups.firstIndex(where: { $0.id == groupID }) else {
            return
        }
        trackGroups[groupIndex].triggerMappingMode = mode
    }

    mutating func setDrumGroupMemberNoteOffset(_ offset: Int, trackID: UUID) {
        guard let groupIndex = drumGroupIndex(containing: trackID) else {
            return
        }
        trackGroups[groupIndex].noteMapping[trackID] = offset
    }

    mutating func setDrumGroupMemberMIDIChannel(_ channel: UInt8, trackID: UUID) {
        guard let groupIndex = drumGroupIndex(containing: trackID) else {
            return
        }
        trackGroups[groupIndex].channelMapping[trackID] = min(channel, 15)
    }

    mutating func applyDrumGroupRoutingDraft(_ draft: DrumGroupRoutingDraft) {
        guard trackGroups.contains(where: { $0.id == draft.groupID }) else {
            return
        }

        setGroupSharedDestinationWithMacros(draft.sharedDestination, groupID: draft.groupID)
        setDrumGroupTriggerMappingMode(draft.triggerMappingMode, groupID: draft.groupID)

        for member in draft.members {
            guard drumGroupIndex(containing: member.memberID, in: draft.groupID) != nil else {
                continue
            }
            setDrumGroupMemberInheritsDestination(
                member.inheritsGroupDestination,
                trackID: member.memberID,
                ownDestination: member.ownDestination ?? .none
            )
            setDrumGroupMemberNoteOffset(member.noteOffset, trackID: member.memberID)
            setDrumGroupMemberMIDIChannel(member.midiChannel, trackID: member.memberID)
        }
    }

    func tracksInGroup(_ groupID: TrackGroupID) -> [StepSequenceTrack] {
        guard let group = trackGroups.first(where: { $0.id == groupID }) else {
            return []
        }
        return group.memberIDs.compactMap { memberID in
            tracks.first(where: { $0.id == memberID })
        }
    }

    func makeDefaultRoute(from trackID: UUID) -> Route {
        if let targetTrack = tracks.first(where: { $0.id != trackID }) {
            return Route(source: .track(trackID), destination: .voicing(targetTrack.id))
        }

        return Route(
            source: .track(trackID),
            destination: .midi(port: .sequencerAIOut, channel: 0, noteOffset: 0)
        )
    }

    mutating func upsertRoute(_ route: Route) {
        if let index = routes.firstIndex(where: { $0.id == route.id }) {
            routes[index] = route
        } else {
            routes.append(route)
        }
    }

    mutating func removeRoute(id: UUID) {
        routes.removeAll { $0.id == id }
    }

    mutating func addGroup(name: String, color: String = "#8AA") -> TrackGroupID {
        let group = TrackGroup(name: name, color: color)
        trackGroups.append(group)
        return group.id
    }

    mutating func addToGroup(trackID: UUID, groupID: TrackGroupID) {
        guard let trackIndex = tracks.firstIndex(where: { $0.id == trackID }),
              let groupIndex = trackGroups.firstIndex(where: { $0.id == groupID })
        else {
            return
        }

        if tracks[trackIndex].groupID == groupID,
           trackGroups[groupIndex].memberIDs.contains(trackID)
        {
            return
        }

        if let previousGroupID = tracks[trackIndex].groupID,
           let previousGroupIndex = trackGroups.firstIndex(where: { $0.id == previousGroupID })
        {
            trackGroups[previousGroupIndex].memberIDs.removeAll { $0 == trackID }
            trackGroups[previousGroupIndex].noteMapping.removeValue(forKey: trackID)
            trackGroups[previousGroupIndex].channelMapping.removeValue(forKey: trackID)
        }

        tracks[trackIndex].groupID = groupID
        if !trackGroups[groupIndex].memberIDs.contains(trackID) {
            trackGroups[groupIndex].memberIDs.append(trackID)
        }
    }

    mutating func removeFromGroup(trackID: UUID) {
        guard let trackIndex = tracks.firstIndex(where: { $0.id == trackID }) else {
            return
        }
        guard let groupID = tracks[trackIndex].groupID,
              let groupIndex = trackGroups.firstIndex(where: { $0.id == groupID })
        else {
            tracks[trackIndex].groupID = nil
            return
        }

        tracks[trackIndex].groupID = nil
        trackGroups[groupIndex].memberIDs.removeAll { $0 == trackID }
        trackGroups[groupIndex].noteMapping.removeValue(forKey: trackID)
        trackGroups[groupIndex].channelMapping.removeValue(forKey: trackID)
        if tracks[trackIndex].destination == .inheritGroup {
            NSLog("Track %@ left group %@ while inheriting destination; resetting to .none", tracks[trackIndex].name, trackGroups[groupIndex].name)
            tracks[trackIndex].destination = .none
        }
    }

    static func resolveInheritedPlaybackDestination(
        trackID: UUID,
        group: TrackGroup
    ) -> ResolvedPlaybackDestination {
        switch group.triggerMappingMode {
        case .perNote:
            guard let sharedDestination = group.sharedDestination else {
                return ResolvedPlaybackDestination(destination: .none, pitchOffset: 0)
            }
            return ResolvedPlaybackDestination(
                destination: sharedDestination,
                pitchOffset: group.noteMapping[trackID] ?? 0
            )

        case .perChannel:
            guard case let .midi(port, _, _) = group.sharedDestination else {
                return ResolvedPlaybackDestination(destination: .none, pitchOffset: 0)
            }
            return ResolvedPlaybackDestination(
                destination: .midi(port: port, channel: group.channelMapping[trackID] ?? 0, noteOffset: 0),
                pitchOffset: 0
            )

        case .individual:
            return ResolvedPlaybackDestination(destination: .none, pitchOffset: 0)
        }
    }

    private func drumGroupIndex(containing trackID: UUID) -> Int? {
        guard let groupID = tracks.first(where: { $0.id == trackID })?.groupID else {
            return nil
        }
        return drumGroupIndex(containing: trackID, in: groupID)
    }

    private func drumGroupIndex(containing trackID: UUID, in groupID: TrackGroupID) -> Int? {
        trackGroups.firstIndex { group in
            group.id == groupID && group.memberIDs.contains(trackID)
        }
    }
}
