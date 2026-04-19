import Foundation

struct Voicing: Codable, Equatable, Sendable {
    static let defaultTag: VoiceTag = "default"

    var destinations: [VoiceTag: Destination]

    init(destinations: [VoiceTag: Destination] = [:]) {
        self.destinations = destinations
    }

    static func single(_ destination: Destination) -> Voicing {
        Voicing(destinations: [defaultTag: destination])
    }

    var defaultDestination: Destination {
        destinations[Self.defaultTag] ?? .none
    }

    mutating func setDefault(_ destination: Destination) {
        destinations[Self.defaultTag] = destination
    }

    func destination(for tag: VoiceTag) -> Destination {
        destinations[tag] ?? .none
    }

    static func defaults(forType trackType: TrackType) -> Voicing {
        switch trackType {
        case .instrument:
            return .single(.none)
        case .drumRack:
            return Voicing(destinations: [
                "kick": .internalSampler(bankID: .drumKitDefault, preset: "kick-909"),
                "snare": .internalSampler(bankID: .drumKitDefault, preset: "snare-909"),
                "hat-closed": .internalSampler(bankID: .drumKitDefault, preset: "hat-closed-909"),
                "hat-open": .internalSampler(bankID: .drumKitDefault, preset: "hat-open-909"),
                "clap": .internalSampler(bankID: .drumKitDefault, preset: "clap-909"),
                "tom-low": .internalSampler(bankID: .drumKitDefault, preset: "tom-low-909"),
                "tom-mid": .internalSampler(bankID: .drumKitDefault, preset: "tom-mid-909"),
                "tom-hi": .internalSampler(bankID: .drumKitDefault, preset: "tom-hi-909"),
                "ride": .internalSampler(bankID: .drumKitDefault, preset: "ride-909"),
                "crash": .internalSampler(bankID: .drumKitDefault, preset: "crash-909"),
            ])
        case .sliceLoop:
            return .single(.internalSampler(bankID: .sliceDefault, preset: "empty-slice"))
        }
    }
}
