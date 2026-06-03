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

            if track.outputBusID != previousTrack.outputBusID {
                deltas.append(.trackOutputBusChanged(trackID: track.id, busID: track.outputBusID))
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

        if buses.map(\.id) != previous.buses.map(\.id) {
            deltas.append(.busesChanged)
        } else {
            var hasStructuralBusChange = false
            for bus in buses {
                guard let previousBus = previous.buses.first(where: { $0.id == bus.id }) else {
                    continue
                }
                if bus.mix != previousBus.mix {
                    deltas.append(.mixerBusMixChanged(busID: bus.id, mix: bus.mix))
                }
                if bus.changedOutsideMix(comparedTo: previousBus) {
                    hasStructuralBusChange = true
                }
            }
            if hasStructuralBusChange {
                deltas.append(.busesChanged)
            }
        }

        if masterBus != previous.masterBus {
            deltas.append(.masterBusChanged)
        }

        if sendBusA != previous.sendBusA {
            deltas.append(.sendBusChanged(busID: .sendA, bus: sendBusA.normalized(expectedID: .sendA)))
        }

        if sendBusB != previous.sendBusB {
            deltas.append(.sendBusChanged(busID: .sendB, bus: sendBusB.normalized(expectedID: .sendB)))
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
        gateLength != previous.gateLength ||
        recordBarLength != previous.recordBarLength ||
        inputChannel != previous.inputChannel
    }
}

private extension MixerBus {
    func changedOutsideMix(comparedTo previous: MixerBus) -> Bool {
        id != previous.id ||
        name != previous.name ||
        color != previous.color ||
        inserts != previous.inserts
    }
}
