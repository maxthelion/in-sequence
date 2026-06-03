import Foundation

enum TrackType: String, Codable, CaseIterable, Equatable, Sendable {
    case monoMelodic
    case polyMelodic
    case slice
    case audioInput

    var label: String {
        switch self {
        case .monoMelodic:
            return "Mono"
        case .polyMelodic:
            return "Poly"
        case .slice:
            return "Slice"
        case .audioInput:
            return "Audio Input"
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
        case .audioInput:
            return "Input"
        }
    }
}

enum AudioInputChannel: String, Codable, CaseIterable, Equatable, Sendable {
    case mono1
    case mono2
    case stereo

    var label: String {
        switch self {
        case .mono1:
            return "Mono 1"
        case .mono2:
            return "Mono 2"
        case .stereo:
            return "Stereo"
        }
    }
}
