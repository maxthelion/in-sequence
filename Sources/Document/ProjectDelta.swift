import Foundation

enum ProjectDelta: Equatable, Hashable {
    case trackMixChanged(trackID: UUID, mix: TrackMixSettings)
    case mixerBusMixChanged(busID: UUID, mix: BusMixSettings)
    case selectedTrackChanged(trackID: UUID)

    case trackDestinationChanged(trackID: UUID, destination: Destination)
    case trackParameterChanged(trackID: UUID)
    case tracksInsertedOrRemoved
    case trackGroupsChanged
    case routesChanged
    case busesChanged
    case masterBusChanged
    case patternBanksChanged
    case phrasesChanged
    case clipPoolChanged
    case layersChanged
    case coarseResync

    var isPhaseOneHotPath: Bool {
        switch self {
        case .trackMixChanged,
             .mixerBusMixChanged,
             .selectedTrackChanged,
             .masterBusChanged,
             .patternBanksChanged,
             .clipPoolChanged,
             .phrasesChanged:
            return true
        case .trackDestinationChanged,
             .trackParameterChanged,
             .tracksInsertedOrRemoved,
             .trackGroupsChanged,
             .routesChanged,
             .busesChanged,
             .layersChanged,
             .coarseResync:
            return false
        }
    }
}
