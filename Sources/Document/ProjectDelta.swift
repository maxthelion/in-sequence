import Foundation

enum ProjectDelta: Equatable, Hashable {
    case trackMixChanged(trackID: UUID, mix: TrackMixSettings)
    case selectedTrackChanged(trackID: UUID)

    case trackDestinationChanged(trackID: UUID, destination: Destination)
    case trackParameterChanged(trackID: UUID)
    case tracksInsertedOrRemoved
    case trackGroupsChanged
    case routesChanged
    case masterBusChanged
    case patternBanksChanged
    case phrasesChanged
    case clipPoolChanged
    case layersChanged
    case coarseResync

    var isPhaseOneHotPath: Bool {
        switch self {
        case .trackMixChanged,
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
             .layersChanged,
             .coarseResync:
            return false
        }
    }
}
