import Foundation

struct TrackMixSettings: Codable, Equatable, Hashable, Sendable {
    var level: Double
    var pan: Double
    var isMuted: Bool
    var isSoloed: Bool

    private enum CodingKeys: String, CodingKey {
        case level
        case pan
        case isMuted
        case isSoloed
    }

    static let `default` = TrackMixSettings(level: 0.8, pan: 0, isMuted: false)

    init(level: Double, pan: Double, isMuted: Bool, isSoloed: Bool = false) {
        self.level = level
        self.pan = pan
        self.isMuted = isMuted
        self.isSoloed = isSoloed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        level = try container.decode(Double.self, forKey: .level)
        pan = try container.decode(Double.self, forKey: .pan)
        isMuted = try container.decode(Bool.self, forKey: .isMuted)
        isSoloed = try container.decodeIfPresent(Bool.self, forKey: .isSoloed) ?? false
    }

    var clampedLevel: Double {
        min(max(level, 0), 1)
    }

    var clampedPan: Double {
        min(max(pan, -1), 1)
    }
}
