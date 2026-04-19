import Foundation

enum WorkspaceSection: String, CaseIterable, Hashable {
    case song
    case phrase
    case tracks
    case track
    case mixer
    case live
    case library

    var title: String {
        switch self {
        case .song:
            return "Song"
        case .phrase:
            return "Phrase"
        case .tracks:
            return "Tracks"
        case .track:
            return "Track"
        case .mixer:
            return "Mixer"
        case .live:
            return "Live"
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
        case .tracks:
            return "square.grid.3x3"
        case .track:
            return "waveform.path"
        case .mixer:
            return "slider.vertical.3"
        case .live:
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
        case .tracks:
            return "track matrix, groups, and creation"
        case .track:
            return "pattern, routing, and voice"
        case .mixer:
            return "levels, pan, and output buses"
        case .live:
            return "live matrix and transport control"
        case .library:
            return "presets, templates, and phrases"
        }
    }
}
