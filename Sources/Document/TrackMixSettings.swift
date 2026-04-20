import Foundation

struct TrackMixSettings: Codable, Equatable, Sendable {
    var level: Double
    var pan: Double
    var isMuted: Bool

    static let `default` = TrackMixSettings(level: 0.8, pan: 0, isMuted: false)

    var clampedLevel: Double {
        min(max(level, 0), 1)
    }

    var clampedPan: Double {
        min(max(pan, -1), 1)
    }
}
