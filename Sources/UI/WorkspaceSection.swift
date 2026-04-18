import Foundation

enum WorkspaceSection: String, CaseIterable, Hashable {
    case song
    case phrase
    case track
    case mixer
    case perform
    case library

    var title: String {
        switch self {
        case .song:
            return "Song"
        case .phrase:
            return "Phrase"
        case .track:
            return "Track"
        case .mixer:
            return "Mixer"
        case .perform:
            return "Perform"
        case .library:
            return "Library"
        }
    }

    var systemImage: String {
        switch self {
        case .song:
            return "rectangle.stack"
        case .phrase:
            return "square.split.2x2"
        case .track:
            return "waveform.path"
        case .mixer:
            return "slider.vertical.3"
        case .perform:
            return "sparkles"
        case .library:
            return "books.vertical"
        }
    }

    var subtitle: String {
        switch self {
        case .song:
            return "phrase refs and arrangement flow"
        case .phrase:
            return "macro grid and pipeline graph"
        case .track:
            return "pattern, routing, and voice"
        case .mixer:
            return "levels, pan, and output buses"
        case .perform:
            return "live overlays and punch-ins"
        case .library:
            return "presets, templates, and phrases"
        }
    }
}
