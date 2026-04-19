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
        case .monoMelodic, .polyMelodic:
            return .single(.none)
        case .slice:
            return .single(.internalSampler(bankID: .sliceDefault, preset: "empty-slice"))
        }
    }
}
