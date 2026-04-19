import Foundation

enum TransportMode: String, Codable, CaseIterable, Equatable, Sendable {
    case song
    case free

    var label: String {
        switch self {
        case .song:
            return "Song"
        case .free:
            return "Free"
        }
    }

    var detail: String {
        switch self {
        case .song:
            return "Transport follows phrase order."
        case .free:
            return "Transport stays on the current phrase."
        }
    }
}
