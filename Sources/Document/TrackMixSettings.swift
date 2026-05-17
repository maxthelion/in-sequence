import Foundation

struct TrackMixSettings: Codable, Equatable, Hashable, Sendable {
    static let sendRange: ClosedRange<Double> = 0...1

    var level: Double
    var pan: Double
    var isMuted: Bool
    var isSoloed: Bool
    var sendA: Double {
        didSet {
            sendA = Self.normalizedSend(sendA)
        }
    }
    var sendB: Double {
        didSet {
            sendB = Self.normalizedSend(sendB)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case level
        case pan
        case isMuted
        case isSoloed
        case sendA
        case sendB
    }

    static let `default` = TrackMixSettings(level: 0.8, pan: 0, isMuted: false)

    init(
        level: Double,
        pan: Double,
        isMuted: Bool,
        isSoloed: Bool = false,
        sendA: Double = 0,
        sendB: Double = 0
    ) {
        self.level = level
        self.pan = pan
        self.isMuted = isMuted
        self.isSoloed = isSoloed
        self.sendA = Self.normalizedSend(sendA)
        self.sendB = Self.normalizedSend(sendB)
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        level = try container.decode(Double.self, forKey: .level)
        pan = try container.decode(Double.self, forKey: .pan)
        isMuted = try container.decode(Bool.self, forKey: .isMuted)
        isSoloed = try container.decodeIfPresent(Bool.self, forKey: .isSoloed) ?? false
        sendA = Self.normalizedSend(try container.decodeIfPresent(Double.self, forKey: .sendA) ?? 0)
        sendB = Self.normalizedSend(try container.decodeIfPresent(Double.self, forKey: .sendB) ?? 0)
    }

    var clampedLevel: Double {
        min(max(level, 0), 1)
    }

    var clampedPan: Double {
        min(max(pan, -1), 1)
    }

    func normalized() -> TrackMixSettings {
        TrackMixSettings(
            level: level,
            pan: pan,
            isMuted: isMuted,
            isSoloed: isSoloed,
            sendA: sendA,
            sendB: sendB
        )
    }

    private static func normalizedSend(_ value: Double) -> Double {
        guard value.isFinite else { return 0 }
        return min(max(value, sendRange.lowerBound), sendRange.upperBound)
    }
}
