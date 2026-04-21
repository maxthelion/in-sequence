enum AudioSampleCategory: String, Codable, CaseIterable, Equatable, Hashable, Sendable {
    case kick, snare, sidestick, clap
    case hatClosed, hatOpen, hatPedal
    case tomLow, tomMid, tomHi
    case ride, crash, cowbell, tambourine, shaker
    case percussion
    case unknown

    var displayName: String {
        switch self {
        case .kick: return "Kick"
        case .snare: return "Snare"
        case .sidestick: return "Sidestick"
        case .clap: return "Clap"
        case .hatClosed: return "Closed Hat"
        case .hatOpen: return "Open Hat"
        case .hatPedal: return "Pedal Hat"
        case .tomLow: return "Low Tom"
        case .tomMid: return "Mid Tom"
        case .tomHi: return "High Tom"
        case .ride: return "Ride"
        case .crash: return "Crash"
        case .cowbell: return "Cowbell"
        case .tambourine: return "Tambourine"
        case .shaker: return "Shaker"
        case .percussion: return "Percussion"
        case .unknown: return "Unknown"
        }
    }

    var isDrumVoice: Bool {
        switch self {
        case .kick, .snare, .sidestick, .clap,
             .hatClosed, .hatOpen, .hatPedal,
             .tomLow, .tomMid, .tomHi,
             .ride, .crash, .cowbell, .tambourine, .shaker, .percussion:
            return true
        case .unknown:
            return false
        }
    }

    /// Bridge from DrumKitPreset.Member.tag (VoiceTag = String) to a category.
    /// Returns nil for tags not recognised as drum voices.
    init?(voiceTag: VoiceTag) {
        switch voiceTag {
        case "kick": self = .kick
        case "snare": self = .snare
        case "hat-closed": self = .hatClosed
        case "hat-open": self = .hatOpen
        case "hat-pedal": self = .hatPedal
        case "clap": self = .clap
        case "ride": self = .ride
        case "crash": self = .crash
        case "tom-low": self = .tomLow
        case "tom-mid": self = .tomMid
        case "tom-hi": self = .tomHi
        case "sidestick", "rim": self = .sidestick
        case "cowbell": self = .cowbell
        case "tambourine": self = .tambourine
        case "shaker": self = .shaker
        default: return nil
        }
    }
}
