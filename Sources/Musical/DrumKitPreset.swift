import Foundation

enum DrumKitPreset: String, CaseIterable, Sendable {
    case kit808 = "808"
    case acousticBasic = "Acoustic"
    case techno = "Techno"

    struct Member: Equatable, Sendable {
        let tag: VoiceTag
        let trackName: String
        let seedPattern: [Bool]
    }

    var displayName: String {
        switch self {
        case .kit808:
            return "808 Kit"
        case .acousticBasic:
            return "Acoustic Kit"
        case .techno:
            return "Techno Kit"
        }
    }

    var members: [Member] {
        switch self {
        case .kit808:
            return [
                Member(tag: "kick", trackName: "Kick", seedPattern: [true, false, false, false, true, false, false, false, true, false, false, false, true, false, false, false]),
                Member(tag: "snare", trackName: "Snare", seedPattern: [false, false, false, false, true, false, false, false, false, false, false, false, true, false, false, false]),
                Member(tag: "hat-closed", trackName: "Hat", seedPattern: [true, false, true, false, true, false, true, false, true, false, true, false, true, false, true, false]),
                Member(tag: "clap", trackName: "Clap", seedPattern: [false, false, false, false, false, false, false, false, false, false, false, false, true, false, false, false]),
            ]
        case .acousticBasic:
            return [
                Member(tag: "kick", trackName: "Kick", seedPattern: [true, false, false, false, false, false, true, false, true, false, false, false, false, false, true, false]),
                Member(tag: "snare", trackName: "Snare", seedPattern: [false, false, false, false, true, false, false, false, false, false, false, false, true, false, false, false]),
                Member(tag: "hat-closed", trackName: "Hat", seedPattern: [true, true, true, true, true, true, true, true, true, true, true, true, true, true, true, true]),
            ]
        case .techno:
            return [
                Member(tag: "kick", trackName: "Kick", seedPattern: [true, false, false, false, true, false, false, false, true, false, false, false, true, false, true, false]),
                Member(tag: "snare", trackName: "Snare", seedPattern: [false, false, false, false, true, false, false, false, false, false, false, false, true, false, false, false]),
                Member(tag: "hat-closed", trackName: "Hat", seedPattern: [false, true, false, true, false, true, false, true, false, true, false, true, false, true, false, true]),
                Member(tag: "ride", trackName: "Ride", seedPattern: [false, false, false, true, false, false, false, true, false, false, false, true, false, false, false, true]),
            ]
        }
    }

    var suggestedGroupColor: String {
        switch self {
        case .kit808:
            return "#C6A"
        case .acousticBasic:
            return "#8AA"
        case .techno:
            return "#8FC"
        }
    }
}
