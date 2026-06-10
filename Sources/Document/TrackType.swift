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

/// Which device input feeds an audio-input track: one mono channel, or a
/// stereo pair starting at an even channel offset. Generic over any
/// interface — pickers enumerate the device's reported channel count.
enum AudioInputChannel: Codable, Equatable, Hashable, Sendable {
    case mono(channel: Int)
    case stereo(firstChannel: Int)

    var label: String {
        switch self {
        case let .mono(channel):
            return "Mono \(channel + 1)"
        case let .stereo(firstChannel):
            return "St \(firstChannel + 1)-\(firstChannel + 2)"
        }
    }

    var isStereo: Bool {
        if case .stereo = self { return true }
        return false
    }

    /// Hardware channels the interface must provide for this routing
    /// (selecting device channel N requires N+1 channels to exist).
    var requiredChannelCount: Int {
        switch self {
        case let .mono(channel):
            return channel + 1
        case let .stereo(firstChannel):
            return firstChannel + 2
        }
    }

    /// Zero-based device channel indices this selection taps.
    var deviceChannels: [Int] {
        switch self {
        case let .mono(channel):
            return [channel]
        case let .stereo(firstChannel):
            return [firstChannel, firstChannel + 1]
        }
    }

    var normalized: AudioInputChannel {
        switch self {
        case let .mono(channel):
            return .mono(channel: max(0, channel))
        case let .stereo(firstChannel):
            let clamped = max(0, firstChannel)
            return .stereo(firstChannel: clamped - clamped % 2)
        }
    }

    /// Selections an interface with `channelCount` inputs can satisfy.
    static func monoOptions(channelCount: Int) -> [AudioInputChannel] {
        guard channelCount > 0 else { return [] }
        return (0..<channelCount).map { .mono(channel: $0) }
    }

    static func stereoOptions(channelCount: Int) -> [AudioInputChannel] {
        guard channelCount > 1 else { return [] }
        return stride(from: 0, to: channelCount - 1, by: 2).map { .stereo(firstChannel: $0) }
    }

    // MARK: - Codable (with legacy migration)

    private enum CodingKeys: String, CodingKey {
        case mode
        case channel
    }

    init(from decoder: Decoder) throws {
        // Legacy documents stored a bare string ("mono1" / "mono2" / "stereo").
        if let single = try? decoder.singleValueContainer().decode(String.self) {
            switch single {
            case "mono1":
                self = .mono(channel: 0)
            case "mono2":
                self = .mono(channel: 1)
            case "stereo":
                self = .stereo(firstChannel: 0)
            default:
                throw DecodingError.dataCorrupted(DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Unknown legacy AudioInputChannel value: \(single)"
                ))
            }
            return
        }

        let container = try decoder.container(keyedBy: CodingKeys.self)
        let mode = try container.decode(String.self, forKey: .mode)
        let channel = try container.decodeIfPresent(Int.self, forKey: .channel) ?? 0
        switch mode {
        case "mono":
            self = AudioInputChannel.mono(channel: channel).normalized
        case "stereo":
            self = AudioInputChannel.stereo(firstChannel: channel).normalized
        default:
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Unknown AudioInputChannel mode: \(mode)"
            ))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .mono(channel):
            try container.encode("mono", forKey: .mode)
            try container.encode(channel, forKey: .channel)
        case let .stereo(firstChannel):
            try container.encode("stereo", forKey: .mode)
            try container.encode(firstChannel, forKey: .channel)
        }
    }
}
