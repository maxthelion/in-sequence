import Foundation

enum SlicerVoiceMode: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case mono
    case polyphonic
}

struct SlicerSettings: Codable, Equatable, Hashable, Sendable {
    var gain: Double
    var transpose: Int
    var voiceMode: SlicerVoiceMode

    init(gain: Double = 0, transpose: Int = 0, voiceMode: SlicerVoiceMode = .mono) {
        self.gain = gain
        self.transpose = transpose
        self.voiceMode = voiceMode
    }

    static let `default` = SlicerSettings()

    var clamped: SlicerSettings {
        SlicerSettings(
            gain: min(max(gain, -60), 12),
            transpose: min(max(transpose, -48), 48),
            voiceMode: voiceMode
        )
    }
}
