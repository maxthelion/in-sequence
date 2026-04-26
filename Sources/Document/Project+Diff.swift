import Foundation

extension Project {
    func deltas(from previous: Project) -> [ProjectDelta] {
        guard version == previous.version else {
            return [.coarseResync]
        }

        var deltas: [ProjectDelta] = []

        let previousTrackIDs = Set(previous.tracks.map(\.id))
        let currentTrackIDs = Set(tracks.map(\.id))
        if previousTrackIDs != currentTrackIDs {
            deltas.append(.tracksInsertedOrRemoved)
        }

        for track in tracks {
            guard let previousTrack = previous.tracks.first(where: { $0.id == track.id }) else {
                continue
            }

            if track.mix != previousTrack.mix {
                deltas.append(.trackMixChanged(trackID: track.id, mix: track.mix))
            }

            if track.destination != previousTrack.destination {
                deltas.append(.trackDestinationChanged(trackID: track.id, destination: track.destination))
            }

            if track.changedOutsideMixAndDestination(comparedTo: previousTrack) {
                deltas.append(.trackParameterChanged(trackID: track.id))
            }
        }

        if selectedTrackID != previous.selectedTrackID {
            deltas.append(.selectedTrackChanged(trackID: selectedTrackID))
        }

        if trackGroups != previous.trackGroups {
            deltas.append(.trackGroupsChanged)
        }

        if routes != previous.routes {
            deltas.append(.routesChanged)
        }

        if masterBus != previous.masterBus {
            deltas.append(.masterBusChanged)
        }

        if patternBanks != previous.patternBanks {
            deltas.append(.patternBanksChanged)
        }

        if phrases != previous.phrases {
            deltas.append(.phrasesChanged)
        }

        if clipPool != previous.clipPool {
            deltas.append(.clipPoolChanged)
        }

        if layers != previous.layers {
            deltas.append(.layersChanged)
        }

        return deltas
    }
}

private extension StepSequenceTrack {
    func changedOutsideMixAndDestination(comparedTo previous: StepSequenceTrack) -> Bool {
        id != previous.id ||
        name != previous.name ||
        trackType != previous.trackType ||
        pitches != previous.pitches ||
        stepPattern != previous.stepPattern ||
        stepAccents != previous.stepAccents ||
        groupID != previous.groupID ||
        velocity != previous.velocity ||
        gateLength != previous.gateLength
    }
}
