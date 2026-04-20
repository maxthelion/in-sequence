import Foundation

enum TrackType: String, Codable, CaseIterable, Equatable, Sendable {
    case monoMelodic
    case polyMelodic
    case slice

    var label: String {
        switch self {
        case .monoMelodic:
            return "Mono"
        case .polyMelodic:
            return "Poly"
        case .slice:
            return "Slice"
        }
    }

    var shortLabel: String {
        switch self {
        case .monoMelodic:
            return "Mono"
        case .polyMelodic:
            return "Poly"
        case .slice:
            return "Slice"
        }
    }
}
