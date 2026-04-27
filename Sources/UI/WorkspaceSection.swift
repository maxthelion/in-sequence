import Foundation

enum WorkspaceSection: String, CaseIterable, Hashable {
    case phrase
    case tracks
    case track
    case mixer
    case scenes
    case library

    var title: String {
        switch self {
        case .phrase:
            return "Phrase"
        case .tracks:
            return "Tracks"
        case .track:
            return "Track"
        case .mixer:
            return "Mixer"
        case .scenes:
            return "Scenes"
        case .library:
            return "Library"
        }
    }

    var systemImage: String {
        switch self {
        case .phrase:
            return "square.split.2x2"
        case .tracks:
            return "square.grid.3x3"
        case .track:
            return "waveform.path"
        case .mixer:
            return "slider.vertical.3"
        case .scenes:
            return "square.stack.3d.up"
        case .library:
            return "books.vertical"
        }
    }
}
