import Foundation

extension Project {
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

    func destinationWriteTarget(for trackID: UUID) -> DestinationWriteTarget {
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

    func destination(for target: DestinationWriteTarget) -> Destination? {
        switch target {
        case .track(let trackID):
            return tracks.first(where: { $0.id == trackID })?.destination
        case .group(let groupID):
            return trackGroups.first(where: { $0.id == groupID })?.sharedDestination
        }
    }

    func resolvedDestination(for trackID: UUID) -> Destination {
        let target = destinationWriteTarget(for: trackID)
        return destination(for: target)
            ?? tracks.first(where: { $0.id == trackID })?.destination
            ?? .none
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
        if tracks[trackIndex].destination == .inheritGroup {
            NSLog("Track %@ left group %@ while inheriting destination; resetting to .none", tracks[trackIndex].name, trackGroups[groupIndex].name)
            tracks[trackIndex].destination = .none
        }
    }
}
